#!/bin/bash
#
# Build a release .zip suitable for attaching to a GitHub Release.
#
# Output: build/release/VoxKey-<version>.zip
#
# Version is read from CFBundleShortVersionString in VoxKey/Resources/Info.plist.
# Bump it there before running this script.
#
# Signing identity defaults to the local "VoxKey Dev" persistent identity. To use
# a real Developer ID Application certificate once you have one:
#
#     SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
#
# This produces an UNNOTARIZED build. End users will see Gatekeeper's "developer
# cannot be verified" dialog and must allow the app in System Settings → Privacy
# & Security on first install. See README.md "Installing on macOS" for the user-
# facing steps. To produce a notarized build, see scripts/notarize.sh (not yet
# implemented).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$PROJECT_DIR/VoxKey/Resources/Info.plist"
ENTITLEMENTS="$PROJECT_DIR/VoxKey/Resources/VoxKey.entitlements"
RELEASE_DIR="$PROJECT_DIR/build/release"
APP_BUNDLE="$RELEASE_DIR/VoxKey.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-VoxKey Dev}"

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "ERROR: $INFO_PLIST not found." >&2
    exit 1
fi
if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "ERROR: $ENTITLEMENTS not found." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null)" || {
    echo "ERROR: CFBundleShortVersionString not found in $INFO_PLIST" >&2
    exit 1
}
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null)" || {
    echo "ERROR: CFBundleVersion not found in $INFO_PLIST" >&2
    exit 1
}

# Clean staging before building so a failed build can't leave a stale .app behind
# that a subsequent rerun would otherwise re-ship.
echo "Building VoxKey $VERSION (build $BUILD_NUMBER)..."
rm -rf "$RELEASE_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cd "$PROJECT_DIR"
swift build -c release

echo "Assembling app bundle at $APP_BUNDLE..."
cp "$PROJECT_DIR/.build/release/VoxKey" "$APP_BUNDLE/Contents/MacOS/VoxKey"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

echo "Signing with identity: $SIGNING_IDENTITY"
# --options runtime enables the hardened runtime, which is required for notarized
# Developer ID distribution. The self-signed "VoxKey Dev" identity accepts the
# flag silently, so we set it now and the only diff for notarized builds later is
# swapping SIGNING_IDENTITY and adding --timestamp.
# Note: no --deep — that's an anti-pattern for new signing per Apple, and this
# bundle has no nested helpers anyway.
codesign --force \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --strict --deep "$APP_BUNDLE"
# Informational Gatekeeper assessment. A self-signed identity is `rejected` —
# this is the expected and intentional state for unnotarized builds (it's what
# triggers the "developer cannot be verified" dialog the README walks through).
# codesign --verify above already catches a structurally broken signature, so
# this call is purely diagnostic.
echo "Gatekeeper assessment (rejection is expected for unnotarized self-signed builds):"
spctl --assess --type execute --verbose "$APP_BUNDLE" 2>&1 || true

ZIP_NAME="VoxKey-$VERSION.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"

echo "Packaging $ZIP_NAME..."
# ditto preserves macOS metadata (extended attributes, resource forks) and the
# bundle structure properly — plain `zip` is known to break .app bundles.
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

ZIP_SIZE="$(du -h "$ZIP_PATH" | cut -f1)"

echo ""
echo "Done."
echo ""
echo "Built:    $ZIP_PATH ($ZIP_SIZE)"
echo "Version:  $VERSION (build $BUILD_NUMBER)"
echo "Signed:   $SIGNING_IDENTITY (unnotarized)"
echo ""
echo "Next steps for cutting a GitHub release:"
echo "  git tag v$VERSION"
echo "  git push origin v$VERSION"
echo "  gh release create v$VERSION \"$ZIP_PATH\" --notes 'Release notes here'"
