# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

VoxKey is a macOS menu bar push-to-talk dictation app. Hold an activation key → capture mic audio → transcribe locally with WhisperKit → paste at cursor. Apple Silicon + macOS 14+ only.

## Build & Run

The project is a Swift Package (`Package.swift`) and also has an Xcode project (`VoxKey.xcodeproj`) generated from `project.yml` via XcodeGen.

```bash
swift build                          # SwiftPM debug build
swift build -c release               # release binary at .build/release/VoxKey
swift test                           # run all XCTest tests
swift test --filter HotkeyManagerTests/testFullKeyDownUpCycle  # single test
./scripts/build.sh                   # release build + bundle + install to /Applications + codesign
xcodegen generate                    # regenerate VoxKey.xcodeproj from project.yml
```

`scripts/build.sh` is the canonical install flow. It signs with a **persistent local identity called "VoxKey Dev"**, not ad-hoc. This is intentional: ad-hoc signing produces a new cdhash on every build, which invalidates the macOS TCC database entries (Accessibility / Input Monitoring), forcing the user to re-grant permissions every rebuild. If you change the signing identity, expect to re-grant permissions.

`scripts/notarize.sh` is a stub — notarization is not implemented.

## Architecture

The app is a single executable target whose lifecycle is split between SwiftUI (`VoxKeyApp`) and an `AppDelegate`. SwiftUI owns `MenuBarExtra` and `Settings` scenes; `AppDelegate` owns everything that needs AppKit-level access (event taps, audio engine, text insertion). The delegate is the integration point — managers are independent objects wired together in `AppDelegate.startDictationPipeline()`.

**State machine** lives in `AppState.DictationState` (`.idle` / `.recording` / `.processing`). `AppDelegate` is the only writer. The menu bar icon and content view observe it via `@EnvironmentObject`. Key-down/key-up callbacks are no-ops unless state matches the expected value, so re-entrancy and out-of-order events are safe.

**Dictation pipeline** (one full cycle):

1. `HotkeyManager` (CGEventTap on `.flagsChanged`) fires `onKeyDown`.
2. `AppDelegate.handleKeyDown` sets state to `.recording` and calls `AudioCaptureManager.startRecording()`.
3. `AudioCaptureManager` taps the input node in **hardware format** (not 16kHz) and accumulates `AVAudioPCMBuffer` copies. Sample-rate conversion happens at stop time, not during capture — this avoids losing audio if the converter stalls.
4. On `onKeyUp`, `stopRecording()` concatenates buffers and converts to 16 kHz mono Float32 via `AVAudioConverter`.
5. `TranscriptionService.transcribe(audioSamples:)` runs WhisperKit with `DecodingOptions.promptTokens` seeded from the custom dictionary (see below).
6. `TextInsertionManager.insertText(_:)` saves the full pasteboard (all items, all types), writes the transcription, synthesizes ⌘V, then restores the original pasteboard after `Constants.clipboardRestoreDelay`. There is no AX-API path — we always use clipboard + ⌘V.

### Hotkey: the threading invariant

`HotkeyManager.start()` creates the `CGEventTap` and runs its `CFRunLoop` on a **dedicated background thread** (`com.voxkey.eventtap`, QoS `.userInteractive`), not on the main run loop. This is load-bearing: SwiftUI's main run loop can starve the tap of events when the app is launched via `open` (vs. double-click in Finder), causing the hotkey to silently stop working. Callbacks hop back to `@MainActor` inside `AppDelegate`.

The tap also handles `.tapDisabledByTimeout` / `.tapDisabledByUserInput` by re-enabling itself — macOS disables event taps that block too long.

### Activation key

`Constants.activationKeyCode` is the single source of truth. Currently `62` (Right Control); set to `61` for Right Option. `HotkeyManager.handleFlagsChanged` reads the matching `CGEventFlags` mask (`.maskControl` for 62, `.maskAlternate` for 61) based on which keycode is configured. If you add a third option, update both the keycode constant and the mask-selection logic.

### Custom dictionary

Stored in `UserDefaults` under `customDictionaryTerms`, edited via Settings, defaulted from `Constants.defaultDictionaryTerms`. `TranscriptionService.buildDecodingOptions()` joins them with `", "`, tokenizes via WhisperKit's tokenizer, and **filters out tokens >= `specialTokens.specialTokenBegin`** before passing as `promptTokens`. Do not skip the filter — special tokens in the prompt corrupt decoding.

### Permissions

Three are required: Accessibility, Microphone, Input Monitoring. `PermissionManager.checkAccessibility()` does not trust `AXIsProcessTrusted()` alone — for unsigned/dev builds it returns false even when granted, so the manager falls back to attempting a real `CGEvent.tapCreate`. `OnboardingView` is shown only when `HotkeyManager.start()` fails on launch. The entitlements file disables app sandbox (`com.apple.security.app-sandbox = false`) — required for global event tap and clipboard manipulation. Do not re-enable sandbox.

## Testing

Tests live in `VoxKeyTests/` and target the executable's internal symbols via `@testable import VoxKey`. `HotkeyManager.handleFlagsChanged` and `TextInsertionManager.savePasteboard`/`restorePasteboard` are exposed at internal access specifically for tests — keep them internal, not private. `CGEventTap` itself cannot be exercised in CI (no Accessibility grant), so tests construct synthetic `CGEvent`s and feed them directly into `handleFlagsChanged`.

## Spec

`specs/voxkey.spec.md` is the original product spec. Treat it as design intent, not current state — implementation has diverged in places (e.g., activation key is configurable; custom-dictionary terms live in `UserDefaults`, not just `Constants`).
