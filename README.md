# VoxKey

A macOS menu bar app for push-to-talk voice dictation, powered by on-device transcription with [WhisperKit](https://github.com/argmaxinc/WhisperKit).

Hold **Right Ctrl** to record, release to transcribe, and text is inserted at your cursor — all processed locally on your Mac.

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1 or later)
- Xcode 15+

## Setup

```bash
git clone git@github.com:BrandonABarringer/VoxKey.git
cd VoxKey
swift build
```

Or open `VoxKey.xcodeproj` in Xcode.

## Usage

1. Launch VoxKey — it appears in the menu bar (no Dock icon).
2. On first launch, grant the required permissions:
   - **Accessibility** — for hotkey detection and text insertion
   - **Microphone** — for audio recording
   - **Input Monitoring** — for global key event capture
3. Hold **Right Ctrl** (keycode 62) to record.
4. Release to transcribe and insert text at the cursor position.

## Features

- **On-device transcription** — no data leaves your Mac
- **Push-to-talk** — hold Right Ctrl to record, release to transcribe
- **Cursor insertion** — transcribed text is pasted at the active cursor via clipboard
- **Model selection** — choose from Tiny, Base, Small, Medium, or Large v3 Turbo models in Settings
- **Custom dictionary** — configurable terms to improve recognition of specific words (e.g., proper nouns, technical terms)
- **Launch at Login** — optional auto-start via Settings
- **Silent operation** — no audio feedback

## Architecture

```
VoxKey/
├── App/
│   ├── VoxKeyApp.swift          # @main entry point
│   └── AppDelegate.swift        # Lifecycle, permissions, hotkey wiring
├── Managers/
│   ├── HotkeyManager.swift      # CGEventTap for Right Ctrl detection
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

## Build & Distribution

Build a release binary:

```bash
swift build --configuration release
```

For notarized DMG distribution:

```bash
./scripts/notarize.sh
```

## License

Private — all rights reserved.
