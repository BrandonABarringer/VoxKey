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

1. `HotkeyManager` (CGEventTap on `.flagsChanged`) fires `onActivate`.
2. `AppDelegate.handleKeyDown` sets state to `.recording` and calls `AudioCaptureManager.startRecording()`.
3. `AudioCaptureManager` taps the input node in **hardware format** (not 16kHz) and accumulates `AVAudioPCMBuffer` copies. Sample-rate conversion happens at stop time, not during capture — this avoids losing audio if the converter stalls.
4. On `onDeactivate`, `stopRecording()` concatenates buffers and converts to 16 kHz mono Float32 via `AVAudioConverter`.
5. `TranscriptionService.transcribe(audioSamples:)` runs WhisperKit with `DecodingOptions.promptTokens` seeded from the custom dictionary (see below).
6. `TextInsertionManager.insertText(_:)` saves the full pasteboard (all items, all types), writes the transcription, synthesizes ⌘V, then restores the original pasteboard after `Constants.clipboardRestoreDelay`. There is no AX-API path — we always use clipboard + ⌘V.

### Hotkey: the threading invariant

`HotkeyManager.start()` creates the `CGEventTap` and runs its `CFRunLoop` on a **dedicated background thread** (`com.voxkey.eventtap`, QoS `.userInteractive`), not on the main run loop. This is load-bearing: SwiftUI's main run loop can starve the tap of events when the app is launched via `open` (vs. double-click in Finder), causing the hotkey to silently stop working. Callbacks hop back to `@MainActor` inside `AppDelegate`.

The tap also handles `.tapDisabledByTimeout` / `.tapDisabledByUserInput` by re-enabling itself — macOS disables event taps that block too long.

### Activation key and mode

User-configurable at runtime via Settings; persisted in `UserDefaults` under `"activationKeyCode"` (Int) and `"activationMode"` (String: `"hold"` / `"singleTap"` / `"doubleTap"`). Defaults live in `Constants` (`defaultActivationKeyCode = 62`, `defaultActivationMode = .hold`).

Supported keys are enumerated in `ActivationKey` (Models/), which maps each keycode to its `CGEventFlags` mask and human-readable label. To add a new supported key, add a case to `ActivationKey` — no other code changes required.

Hold mode is the original push-to-talk behavior. Single tap / double tap modes route events through `TapStateMachine`, which converts raw key events into semantic `.start` / `.stop` actions. `HotkeyManager` exposes `onActivate` / `onDeactivate` as the unified callback surface — Hold maps keyDown→activate / keyUp→deactivate; tap modes map `.start`→activate / `.stop`→deactivate.

`AppDelegate` observes `UserDefaults.didChangeNotification` and calls `HotkeyManager.restart(keyCode:mode:doubleTapWindowMs:)` when either setting changes. Restart tears down the existing CGEventTap and spawns a fresh `com.voxkey.eventtap` background thread — the threading invariant above must be preserved through restart.

### Custom dictionary

Stored in `UserDefaults` under `customDictionaryTerms`, edited via Settings, defaulted from `Constants.defaultDictionaryTerms`. `TranscriptionService.buildDecodingOptions()` joins them with `", "`, tokenizes via WhisperKit's tokenizer, and **filters out tokens >= `specialTokens.specialTokenBegin`** before passing as `promptTokens`. Do not skip the filter — special tokens in the prompt corrupt decoding.

### Permissions

Three are required: Accessibility, Microphone, Input Monitoring. `PermissionManager.checkAccessibility()` does not trust `AXIsProcessTrusted()` alone — for unsigned/dev builds it returns false even when granted, so the manager falls back to attempting a real `CGEvent.tapCreate`. `OnboardingView` is shown only when `HotkeyManager.start()` fails on launch. The entitlements file disables app sandbox (`com.apple.security.app-sandbox = false`) — required for global event tap and clipboard manipulation. Do not re-enable sandbox.

## Testing

Tests live in `VoxKeyTests/` and target the executable's internal symbols via `@testable import VoxKey`. `HotkeyManager.handleFlagsChanged` and `TextInsertionManager.savePasteboard`/`restorePasteboard` are exposed at internal access specifically for tests — keep them internal, not private. `CGEventTap` itself cannot be exercised in CI (no Accessibility grant), so tests construct synthetic `CGEvent`s and feed them directly into `handleFlagsChanged`.

## Spec

`specs/voxkey.spec.md` is the original product spec. Treat it as design intent, not current state — implementation has diverged in places (e.g., activation key is configurable; custom-dictionary terms live in `UserDefaults`, not just `Constants`).
