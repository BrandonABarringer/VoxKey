#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/VoxKey.app"
INSTALL_PATH="/Applications/VoxKey.app"

echo "Building VoxKey..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

echo "Assembling app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$PROJECT_DIR/.build/release/VoxKey" "$APP_BUNDLE/Contents/MacOS/VoxKey"

# Deploy to /Applications
echo "Installing to $INSTALL_PATH..."
pkill -f VoxKey 2>/dev/null || true
sleep 1
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

# Sign with persistent "VoxKey Dev" identity so TCC permissions survive rebuilds.
# (Ad-hoc signing changes the cdhash each build, invalidating TCC entries.)
echo "Signing..."
codesign --force --deep --sign "VoxKey Dev" "$INSTALL_PATH"

echo "Done!"
echo ""
echo "To run:  open $INSTALL_PATH"
echo "To quit: Click menu bar icon > Quit VoxKey"
