# VoxKey

A macOS menu bar app for push-to-talk voice dictation, powered by on-device transcription with [WhisperKit](https://github.com/argmaxinc/WhisperKit).

Hold **Right Ctrl** to record, release to transcribe, and text is inserted at your cursor — all processed locally on your Mac.

## Installing on macOS

**Requires macOS 14.0 (Sonoma) or later on Apple Silicon (M1+).** VoxKey does not support Intel Macs.

1. Go to the [Releases page](https://github.com/BrandonABarringer/VoxKey/releases) and download the latest `VoxKey-<version>.zip`.
2. Unzip and drag `VoxKey.app` into `/Applications`.
3. Double-click `VoxKey.app`. macOS will refuse to open it the first time and show a dialog that says **"VoxKey can't be opened because the developer cannot be verified."** This is expected — the app is not yet signed with an Apple-issued certificate. Click **Cancel** on this dialog (clicking Cancel is the right answer, not a mistake). **Do not click "Move to Trash"** — that removes the app entirely and you'll have to start over.
4. Within a few minutes of step 3, open **System Settings → Privacy & Security**. Scroll to the bottom of the page. You'll see a message like **"VoxKey was blocked to protect your Mac."** Click **Open Anyway** next to it. (If you waited too long and the message is gone, see "If you don't see Open Anyway" below.)
5. macOS will prompt for your password to confirm, then show one more "Are you sure you want to open it?" dialog. Click **Open**.
6. VoxKey is now installed. From here on, it launches normally.

On first launch, VoxKey will guide you through granting three permissions in System Settings:

- **Accessibility** — required to detect the global hotkey and paste transcribed text
- **Microphone** — required to record your voice
- **Input Monitoring** — required to receive the activation key press from outside the app. VoxKey only listens for the specific activation key — it does not record or log any other keystrokes or what you type.

Each permission opens its own panel in System Settings → Privacy & Security. Toggle VoxKey on in each one, then return to the app.

> **Note:** Steps 3–5 repeat any time you install a new version. This is a macOS behavior for apps that aren't notarized by Apple. We may add notarized releases in the future, which would remove this step. If you receive `VoxKey.app` directly via AirDrop or a Slack file share from a trusted sender (instead of downloading from GitHub), steps 3–5 may not be required because the quarantine flag isn't applied.

<details>
<summary>If you don't see "Open Anyway"</summary>

If the System Settings → Privacy & Security panel no longer shows the "VoxKey was blocked..." message (it expires after a short window), you can clear the quarantine flag manually from Terminal:

```bash
xattr -d com.apple.quarantine /Applications/VoxKey.app
```

Then double-click VoxKey.app again — it will launch normally.

</details>

## Usage

1. VoxKey lives in the menu bar — there is no Dock icon. Look for the small microphone icon at the top of your screen.
2. Hold the activation key (default: **Right Ctrl**) to start recording. The activation key can be changed in Settings — currently Right Ctrl or Right Option.
3. Speak normally.
4. Release the activation key to stop recording. VoxKey transcribes the audio on-device and pastes the text at your cursor's current position.
5. Click the menu bar icon for Settings (activation key, model selection, custom dictionary, launch-at-login) and Quit.

## Features

- **On-device transcription** — no audio or text ever leaves your Mac
- **Push-to-talk** — hold Right Ctrl to record, release to transcribe
- **Cursor insertion** — transcribed text is pasted at the active cursor via clipboard
- **Model selection** — choose from Tiny, Base, Small, Medium, or Large v3 Turbo models in Settings
- **Custom dictionary** — configurable terms to improve recognition of specific words (e.g., proper nouns, technical jargon)
- **Launch at Login** — optional auto-start via Settings
- **Silent operation** — no audio feedback

## Developing

Requires macOS 14.0+, Apple Silicon, and Xcode 15+ (or the Command Line Tools for SwiftPM-only builds).

```bash
git clone git@github.com:BrandonABarringer/VoxKey.git
cd VoxKey
swift build
```

Or open `VoxKey.xcodeproj` in Xcode. The `.xcodeproj` is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is committed to the repo. If you edit `project.yml`, regenerate the project with `xcodegen generate` before opening Xcode.

For a local install of your in-development build to `/Applications`, use `./scripts/build.sh` — it builds, signs with a persistent local identity (so TCC permission grants survive rebuilds), and installs.

## Architecture

```
VoxKey/
├── App/
│   ├── VoxKeyApp.swift          # @main entry point
│   └── AppDelegate.swift        # Lifecycle, permissions, hotkey wiring
├── Managers/
│   ├── HotkeyManager.swift      # CGEventTap for activation key detection
│   ├── AudioCaptureManager.swift # AVAudioEngine, 16kHz mono PCM
│   ├── MenuBarManager.swift     # NSStatusItem, icon states
│   ├── TextInsertionManager.swift # Clipboard save/restore, Cmd+V simulation
│   └── PermissionManager.swift  # Accessibility, Mic, Input Monitoring checks
├── Models/
│   └── AppState.swift           # Observable state (idle/recording/processing)
├── Services/
│   └── TranscriptionService.swift # WhisperKit integration
├── Views/
│   ├── SettingsView.swift       # Model picker, launch at login, permissions
│   └── OnboardingView.swift     # First-launch permission setup
├── Utilities/
│   └── Constants.swift          # Keycodes, model names, dictionary terms
└── Resources/
    ├── Info.plist
    └── VoxKey.entitlements
```

## Custom Dictionary

VoxKey supports custom dictionary terms to bias WhisperKit toward recognizing specific words. Edit the `customDictionaryTerms` array in `Constants.swift`:

```swift
static let customDictionaryTerms = ["Claude", "CLAUDE.md", "Vercel", "git", "GitHub"]
```

These terms are passed as prompt tokens to WhisperKit's decoder, improving recognition accuracy for proper nouns and technical jargon.

## Building a Release

To produce a `.zip` suitable for attaching to a GitHub Release:

```bash
./scripts/release.sh
```

This builds a release configuration, assembles the `.app` bundle, signs with the local "VoxKey Dev" identity, and writes `build/release/VoxKey-<version>.zip`. The script prints the next steps for tagging and creating the release.

The version is read from `CFBundleShortVersionString` in `VoxKey/Resources/Info.plist`. Bump it there before running `release.sh`.

Notarized distribution (which would skip the Privacy & Security dance for users) is not yet implemented — see `scripts/notarize.sh`.

## License

Private — all rights reserved.
