# Implementation Spec: Configurable Activation Key and Activation Mode

**Created:** 2026-05-22
**Status:** Draft
**Last Updated:** 2026-05-22

## Problem Statement

VoxKey's activation key is a compile-time constant (`Constants.activationKeyCode = 62`, Right Control). MacBook keyboards ship without a right Control key, making the app unusable for a significant share of the target audience without recompiling from source. Additionally, the app supports only one activation mode (hold-to-talk), excluding users who prefer a hands-free toggle workflow. Both the activation key and activation mode must become runtime settings, persisted to `UserDefaults` and configurable through the existing Settings window, with changes taking effect immediately without restarting the app.

Success: Any user can open Settings, choose their preferred modifier key from a picker, choose Hold or Single/Double Tap as their activation mode, and have the change applied live — all without recompiling or restarting.

## Deliverables

- [ ] `/Users/austingregersen/Developer/VoxKey/VoxKey/Models/ActivationKey.swift` — New file: `ActivationKey` enum listing all 10 supported modifier keycodes with their `CGEventFlags` masks and human-readable labels (create)
- [ ] `/Users/austingregersen/Developer/VoxKey/VoxKey/Models/ActivationMode.swift` — New file: `ActivationMode` enum with three cases (`hold`, `singleTap`, `doubleTap`) and `UserDefaults` raw string values (create)
- [ ] `/Users/austingregersen/Developer/VoxKey/VoxKey/Models/TapStateMachine.swift` — New file: deterministic state machine that consumes `(timestamp: TimeInterval, isKeyDown: Bool)` events and produces `TapAction` (`.start`, `.stop`, `.noop`); injectable clock closure for deterministic testing (create)
- [ ] `/Users/austingregersen/Developer/VoxKey/VoxKey/Utilities/Constants.swift` — Modify: add `defaultActivationKeyCode`, `defaultActivationMode`, `defaultDoubleTapWindowMs`; retain `activationKeyCode` as a deprecated alias pointing to `defaultActivationKeyCode` to avoid breaking any direct read that may exist (modify)
- [ ] `/Users/austingregersen/Developer/VoxKey/VoxKey/Managers/HotkeyManager.swift` — Modify: replace hardcoded `if keyCode == Constants.rightCtrlKeyCode` flag-mask selection with table-driven `ActivationKey` lookup; add `onActivate`/`onDeactivate` semantic callbacks; add `restart(keyCode:mode:doubleTapWindowMs:)` method; integrate `TapStateMachine` for tap modes (modify)
- [ ] `/Users/austingregersen/Developer/VoxKey/VoxKey/App/AppDelegate.swift` — Modify: wire `onActivate`/`onDeactivate` instead of `onKeyDown`/`onKeyUp`; observe `UserDefaults` changes for `activationKeyCode` and `activationMode` via `NotificationCenter` (`didChangeNotification`) and call `hotkeyManager.restart(...)` on the main actor (modify)
- [ ] `/Users/austingregersen/Developer/VoxKey/VoxKey/Views/SettingsView.swift` — Modify: add a new "Activation" `Section` with an Activation Key `Picker` and an Activation Mode `Picker`; show an inline `HStack` warning when Caps Lock is paired with Hold mode (modify)
- [ ] `/Users/austingregersen/Developer/VoxKey/VoxKeyTests/HotkeyManagerTests.swift` — Modify: update existing tests for refactored callback names (`onActivate`/`onDeactivate`); add parametrized keycode→mask tests; add `TapStateMachine` tests; add `UserDefaults` persistence tests (modify)

## Requirements

### REQ-1: Activation Mode Enum and Persistence

**Description:** An `ActivationMode` enum with cases `hold`, `singleTap`, and `doubleTap` must be readable from and writable to `UserDefaults.standard` under the key `"activationMode"` (raw string values `"hold"`, `"singleTap"`, `"doubleTap"`), defaulting to `.hold` when the key is absent.

**Acceptance Criteria:**
- Given `UserDefaults.standard` has no value for `"activationMode"`
- When `ActivationMode.current` (or equivalent read accessor) is called
- Then the result is `.hold`

- Given `UserDefaults.standard.set("doubleTap", forKey: "activationMode")` has been called
- When `ActivationMode.current` is read
- Then the result is `.doubleTap`

- Given `ActivationMode.singleTap` is persisted via its write accessor
- When the app is re-initialized and reads `"activationMode"` from `UserDefaults`
- Then the result is `.singleTap`

**Verification:**
- Command: `swift test --filter HotkeyManagerTests/testActivationModePersistence`
- Expected: Test exits 0; all three cases round-trip through `UserDefaults` and the missing-key default returns `.hold`

**Priority:** Must
**Status:** Pending

---

### REQ-2: Activation Key Enum and Keycode-to-Mask Table

**Description:** An `ActivationKey` enum must enumerate all 10 supported modifier keycodes (62, 59, 61, 58, 54, 55, 60, 56, 57, 63), expose a `cgKeyCode: CGKeyCode` property, a `flagsMask: CGEventFlags` property, and a `label: String` property with human-readable names; a static function `activationKey(forKeyCode:) -> ActivationKey?` must cover all 10 codes with no fallback to hardcoded conditionals.

**Acceptance Criteria:**
- Given keycode `62`
- When `ActivationKey.activationKey(forKeyCode: 62)` is called
- Then the result is non-nil and `.flagsMask` is `.maskControl`

- Given keycode `57` (Caps Lock)
- When `ActivationKey.activationKey(forKeyCode: 57)` is called
- Then the result is non-nil and `.flagsMask` is `.maskAlphaShift`

- Given keycode `63` (Fn)
- When `ActivationKey.activationKey(forKeyCode: 63)` is called
- Then the result is non-nil and `.flagsMask` is `.maskSecondaryFn`

- Given an unknown keycode (e.g., `0`)
- When `ActivationKey.activationKey(forKeyCode: 0)` is called
- Then the result is `nil`

**Verification:**
- Command: `swift test --filter HotkeyManagerTests/testActivationKeyMappingAllKeycodes`
- Expected: Test iterates all 10 (keycode, expectedMask) pairs and asserts non-nil with correct mask; exits 0

**Priority:** Must
**Status:** Pending

---

### REQ-3: HotkeyManager Table-Driven Flag Lookup

**Description:** `HotkeyManager.handleFlagsChanged` must use `ActivationKey.activationKey(forKeyCode:)` to resolve the correct `CGEventFlags` mask for the active keycode, eliminating the existing `if Constants.activationKeyCode == Constants.rightCtrlKeyCode` conditional entirely; `handleFlagsChanged` must remain `internal` (not `private`).

**Acceptance Criteria:**
- Given `HotkeyManager` is initialized with keycode `55` (Left Command)
- When a `flagsChanged` event arrives with `keyboardEventKeycode = 55` and `flags = [.maskCommand]`
- Then `onActivate` fires

- Given `HotkeyManager` is initialized with keycode `55`
- When a `flagsChanged` event arrives with `keyboardEventKeycode = 59` and `flags = [.maskControl]`
- Then neither `onActivate` nor `onDeactivate` fires

- Given the source of `HotkeyManager.swift`
- When grepped for `rightCtrlKeyCode` or `maskAlternate` in `handleFlagsChanged`
- Then no match is found (the old conditional is gone)

**Verification:**
- Command: `swift test --filter HotkeyManagerTests` (full suite)
- Expected: All existing and new tests pass; exit 0
- Command: `grep -n "rightCtrlKeyCode\|maskAlternate" /Users/austingregersen/Developer/VoxKey/VoxKey/Managers/HotkeyManager.swift`
- Expected: No output (zero matches in `handleFlagsChanged`)

**Priority:** Must
**Status:** Pending

---

### REQ-4: Semantic Callbacks `onActivate` / `onDeactivate`

**Description:** `HotkeyManager` must expose `var onActivate: (() -> Void)?` and `var onDeactivate: (() -> Void)?` as the primary callback surface; in Hold mode `onActivate` maps to key-down and `onDeactivate` maps to key-up; `AppDelegate` must be updated to assign these callbacks instead of `onKeyDown`/`onKeyUp`; the old `onKeyDown`/`onKeyUp` properties must be removed to prevent stale callsites.

**Acceptance Criteria:**
- Given `HotkeyManager` is in Hold mode with `onActivate` and `onDeactivate` set
- When a key-down event for the configured keycode arrives
- Then `onActivate` fires and `onDeactivate` does not

- Given `HotkeyManager` is in Hold mode
- When a key-up event for the configured keycode arrives
- Then `onDeactivate` fires and `onActivate` does not

- Given the source of `AppDelegate.swift`
- When grepped for `onKeyDown` or `onKeyUp`
- Then no match is found

**Verification:**
- Command: `grep -rn "onKeyDown\|onKeyUp" /Users/austingregersen/Developer/VoxKey/VoxKey/`
- Expected: No output (zero matches across all source files)
- Command: `swift test --filter HotkeyManagerTests/testFullKeyDownUpCycle`
- Expected: Test passes (updated to use `onActivate`/`onDeactivate`)

**Priority:** Must
**Status:** Pending

---

### REQ-5: TapStateMachine — Single Tap Mode

**Description:** `TapStateMachine` in `.singleTap` mode must emit `.start` on the first key-up (complete tap) when recording is inactive, and emit `.stop` on the next key-up when recording is active; the machine must accept an injectable `clock: () -> TimeInterval` closure so tests can drive it without `sleep`.

**Acceptance Criteria:**
- Given the machine is in idle state
- When key-down then key-up events arrive
- Then `.start` is returned on the key-up event

- Given the machine has previously emitted `.start` (recording is active)
- When key-down then key-up events arrive again
- Then `.stop` is returned on the key-up event

- Given a key-down event with no subsequent key-up
- When `process(timestamp:isKeyDown:)` is called with `isKeyDown = true`
- Then `.noop` is returned

- Given recording is active
- When only a key-down arrives (no key-up yet)
- Then `.noop` is returned (stop requires a complete tap)

**Verification:**
- Command: `swift test --filter HotkeyManagerTests/testSingleTapStartStop`
- Expected: Test passes; `.start` then `.stop` emitted on successive complete taps; exit 0

**Priority:** Must
**Status:** Pending

---

### REQ-6: TapStateMachine — Double Tap Mode

**Description:** `TapStateMachine` in `.doubleTap` mode must emit `.start` only when two complete taps (key-down, key-up, key-down, key-up) occur with the second key-down arriving within `doubleTapWindowMs` milliseconds of the first key-up; a single tap must not emit `.start`; once recording is active, a single complete tap must emit `.stop` (making stopping easier than requiring another double tap).

**Acceptance Criteria:**
- Given two taps where the second key-down is within `doubleTapWindowMs` (400ms default)
- When the second key-up arrives
- Then `.start` is emitted

- Given two taps where the second key-down is more than `doubleTapWindowMs` after the first key-up
- When the second key-up arrives
- Then `.noop` is emitted (window expired; first tap is discarded)

- Given machine is at the exact window boundary (second key-down at exactly `doubleTapWindowMs`)
- When the second key-up arrives
- Then `.noop` is emitted (boundary is exclusive: `<`, not `<=`)

- Given recording is active (machine emitted `.start`)
- When one complete tap arrives
- Then `.stop` is emitted

**Verification:**
- Command: `swift test --filter HotkeyManagerTests/testDoubleTapStartStop`
- Expected: All within-window, outside-window, boundary, and stop-via-single-tap cases pass; exit 0

**Priority:** Must
**Status:** Pending

---

### REQ-7: HotkeyManager Routes Events to TapStateMachine in Tap Modes

**Description:** When `HotkeyManager` is configured in `.singleTap` or `.doubleTap` mode, `handleFlagsChanged` must forward key-press events to the `TapStateMachine` and call `onActivate` or `onDeactivate` based on the machine's output (`.start` → `onActivate`, `.stop` → `onDeactivate`, `.noop` → neither); in Hold mode the tap state machine must not be consulted.

**Acceptance Criteria:**
- Given `HotkeyManager` is in `.singleTap` mode
- When a complete tap of the configured key arrives
- Then `onActivate` fires exactly once

- Given `HotkeyManager` is in `.doubleTap` mode
- When a double tap within the window arrives
- Then `onActivate` fires exactly once

- Given `HotkeyManager` is in `.hold` mode
- When the configured key is held down
- Then `onActivate` fires on key-down (not on key-up)

**Verification:**
- Command: `swift test --filter HotkeyManagerTests/testHoldModeActivation`
- Command: `swift test --filter HotkeyManagerTests/testSingleTapModeActivation`
- Command: `swift test --filter HotkeyManagerTests/testDoubleTapModeActivation`
- Expected: All three tests pass; exit 0

**Priority:** Must
**Status:** Pending

---

### REQ-8: `restart(keyCode:mode:doubleTapWindowMs:)` Method

**Description:** `HotkeyManager` must expose a `restart(keyCode: CGKeyCode, mode: ActivationMode, doubleTapWindowMs: Int)` method that stops the existing CGEventTap and CFRunLoop, deallocates the tap resources, and starts a fresh tap on a new dedicated background thread named `"com.voxkey.eventtap"` with QoS `.userInteractive`; the method must be callable on the `@MainActor` and must complete synchronously from the caller's perspective (i.e., the new thread is started before `restart` returns, though CFRunLoopRun executes on the background thread).

**Acceptance Criteria:**
- Given `HotkeyManager` is running with keycode `62`
- When `restart(keyCode: 61, mode: .hold, doubleTapWindowMs: 400)` is called
- Then the old tap is stopped and a new tap is started; subsequent events are filtered against keycode `61`

- Given `restart` is called
- When the new thread is inspected (`Thread.name`)
- Then the name is `"com.voxkey.eventtap"` and `qualityOfService` is `.userInteractive`

- Given `restart` is called while a recording is in progress (state is `.recording`)
- When `AppDelegate`'s `onDeactivate` observer is triggered by the restart
- Then the existing recording is not silently abandoned (the spec does not require aborting in-flight recordings but does require that `restart` itself does not call `onDeactivate`; `AppDelegate` must guard against spurious deactivation during restart)

**Verification:**
- Command: `grep -n "com.voxkey.eventtap" /Users/austingregersen/Developer/VoxKey/VoxKey/Managers/HotkeyManager.swift`
- Expected: Exactly one occurrence (in the `restart` / `start` implementation)
- Command: `swift test --filter HotkeyManagerTests/testRestartChangesKeyCode`
- Expected: Test synthesizes events for old and new keycode before and after restart and verifies correct filtering; exit 0

**Priority:** Must
**Status:** Pending

---

### REQ-9: Live Apply via UserDefaults Observation in AppDelegate

**Description:** `AppDelegate` must observe `UserDefaults.didChangeNotification` and, when `"activationKeyCode"` or `"activationMode"` has changed, read the new values and call `hotkeyManager.restart(keyCode:mode:doubleTapWindowMs:)` on the main actor; the observation must be set up once during `applicationDidFinishLaunching` and torn down in `applicationWillTerminate`.

**Acceptance Criteria:**
- Given `AppDelegate` is running with Right Control active
- When `UserDefaults.standard.set(61, forKey: "activationKeyCode")` is called externally (simulating a Settings picker change)
- Then within one run-loop cycle on the main actor, `hotkeyManager.restart` is called with keycode `61`

- Given a `UserDefaults` change to an unrelated key (e.g., `"selectedModel"`)
- When the notification fires
- Then `hotkeyManager.restart` is NOT called

**Verification:**
- Command: `swift test --filter HotkeyManagerTests/testUserDefaultsObservationTriggersRestart`
- Expected: Test uses a mock/subclass of `HotkeyManager` to count `restart` calls; exactly 1 call for each relevant key change, 0 calls for unrelated changes; exit 0
- Command: `grep -n "didChangeNotification" /Users/austingregersen/Developer/VoxKey/VoxKey/App/AppDelegate.swift`
- Expected: At least one match

**Priority:** Must
**Status:** Pending

---

### REQ-10: Activation Key Persistence in UserDefaults

**Description:** The active `CGKeyCode` must be read from `UserDefaults.standard` under key `"activationKeyCode"` (type `Int`) on every call to `HotkeyManager.start()` and `restart()`; when the key is absent, the value from `Constants.defaultActivationKeyCode` (62) must be used; writing a new keycode to `"activationKeyCode"` must persist across app restarts.

**Acceptance Criteria:**
- Given `UserDefaults.standard` has no value for `"activationKeyCode"`
- When `HotkeyManager` reads the configured keycode
- Then it uses `62`

- Given `UserDefaults.standard.set(55, forKey: "activationKeyCode")` has been called
- When `HotkeyManager.restart(...)` is called with keycode `55`
- Then events for keycode `55` activate the callback and events for keycode `62` do not

**Verification:**
- Command: `swift test --filter HotkeyManagerTests/testActivationKeyCodePersistence`
- Expected: Round-trip write/read of each of the 10 supported keycodes returns the correct value; missing-key default is `62`; exit 0

**Priority:** Must
**Status:** Pending

---

### REQ-11: Double Tap Window Persistence in UserDefaults

**Description:** The double-tap detection window must be read from `UserDefaults.standard` under key `"doubleTapWindowMs"` (type `Int`); when absent, the default is `400`; the value is passed as `doubleTapWindowMs` to `TapStateMachine` and to `restart(keyCode:mode:doubleTapWindowMs:)`.

**Acceptance Criteria:**
- Given `UserDefaults.standard` has no value for `"doubleTapWindowMs"`
- When `TapStateMachine` is initialized from stored settings
- Then it uses a window of 400 ms

- Given `UserDefaults.standard.set(250, forKey: "doubleTapWindowMs")`
- When `TapStateMachine` is initialized
- Then two taps 300 ms apart emit `.start` and two taps 260 ms apart also emit `.start`, but two taps 251 ms apart emit `.noop` only if the value were 250 ms (verify via injected clock in tests)

**Verification:**
- Command: `swift test --filter HotkeyManagerTests/testDoubleTapWindowFromUserDefaults`
- Expected: Test writes `250` to UserDefaults, builds machine, confirms window is `250` ms; exit 0

**Priority:** Should
**Status:** Pending

---

### REQ-12: Settings UI — Activation Section

**Description:** `SettingsView` must contain a new `Section("Activation")` with two pickers: (1) an Activation Key `Picker` using `@AppStorage("activationKeyCode")` bound via `Int` that lists all 10 supported keys with their human-readable labels from `ActivationKey`; (2) an Activation Mode `Picker` using `@AppStorage("activationMode")` bound via `String` that lists "Hold", "Single Tap", and "Double Tap" with a one-line description for each.

**Acceptance Criteria:**
- Given the Settings window is open
- When the user inspects the "Activation" section
- Then both pickers are visible

- Given the user selects "Left Command" in the Activation Key picker
- When the selection is confirmed (picker closes)
- Then `UserDefaults.standard.integer(forKey: "activationKeyCode")` equals `55`

- Given the user selects "Double Tap" in the Activation Mode picker
- When the selection is confirmed
- Then `UserDefaults.standard.string(forKey: "activationMode")` equals `"doubleTap"`

**Verification:**
- Command: `grep -n "Section.*Activation" /Users/austingregersen/Developer/VoxKey/VoxKey/Views/SettingsView.swift`
- Expected: At least one match
- Command: `grep -n "activationKeyCode\|activationMode" /Users/austingregersen/Developer/VoxKey/VoxKey/Views/SettingsView.swift`
- Expected: At least two matches (one per picker binding)
- Command: `swift build`
- Expected: Exit 0 (UI compiles without errors)

**Priority:** Must
**Status:** Pending

---

### REQ-13: Caps Lock + Hold Mode Warning in Settings UI

**Description:** When the user has selected "Caps Lock" (keycode `57`) as the activation key AND "Hold" as the activation mode simultaneously, `SettingsView` must display an inline warning text explaining that Caps Lock toggles on press rather than indicating held state, making Hold mode unreliable with this key.

**Acceptance Criteria:**
- Given `activationKeyCode = 57` and `activationMode = "hold"` in `UserDefaults`
- When `SettingsView` renders
- Then a warning message is visible within the Activation section (e.g., "Caps Lock toggles on press and is not compatible with Hold mode. Use Single Tap or Double Tap instead.")

- Given `activationKeyCode = 57` and `activationMode = "singleTap"`
- When `SettingsView` renders
- Then no warning is shown

- Given `activationKeyCode = 62` and `activationMode = "hold"`
- When `SettingsView` renders
- Then no warning is shown

**Verification:**
- Command: `grep -n "Caps Lock\|capsLock\|maskAlphaShift\|57.*Hold\|Hold.*57" /Users/austingregersen/Developer/VoxKey/VoxKey/Views/SettingsView.swift`
- Expected: At least one match indicating the warning condition is implemented
- Command: `swift build`
- Expected: Exit 0

**Priority:** Must
**Status:** Pending

---

### REQ-14: Backward Compatibility — Default Values for Existing Users

**Description:** Users with no `"activationKeyCode"` or `"activationMode"` values in `UserDefaults` must experience identical behavior to the pre-feature app: Right Control (keycode `62`) in Hold mode; `Constants.defaultActivationKeyCode` must equal `62` and `Constants.defaultActivationMode` must equal `ActivationMode.hold`.

**Acceptance Criteria:**
- Given a fresh `UserDefaults.standard` with no activation keys set
- When `AppDelegate` starts the hotkey pipeline
- Then `HotkeyManager` is initialized with keycode `62` in `.hold` mode

- Given the existing `HotkeyManagerTests` suite (all tests written against keycode `62`)
- When run after the refactor
- Then all tests continue to pass without modification to their keycode values

**Verification:**
- Command: `swift test --filter HotkeyManagerTests/testRightCtrlKeyDownTriggersCallback`
- Command: `swift test --filter HotkeyManagerTests/testRightCtrlKeyUpTriggersCallback`
- Command: `swift test --filter HotkeyManagerTests/testFullKeyDownUpCycle`
- Expected: All three pass without modification to the test keycode values; exit 0
- Command: `grep -n "defaultActivationKeyCode" /Users/austingregersen/Developer/VoxKey/VoxKey/Utilities/Constants.swift`
- Expected: Match with value `62`

**Priority:** Must
**Status:** Pending

---

### REQ-15: Background Thread Invariant Preserved After Restart

**Description:** After every call to `HotkeyManager.restart(...)`, the new CFRunLoop must run on a background thread named `"com.voxkey.eventtap"` with QoS `.userInteractive`; the CFRunLoop must never be added to the main run loop; the tap must re-enable itself on `.tapDisabledByTimeout` and `.tapDisabledByUserInput`.

**Acceptance Criteria:**
- Given `HotkeyManager.restart(...)` is called
- When the new tap is running
- Then `Thread.current.name` within the CFRunLoop callback is `"com.voxkey.eventtap"`

- Given `HotkeyManager.restart(...)` is called
- When the new tap is running
- Then `Thread.isMainThread` within the CFRunLoop callback is `false`

- Given the new tap receives a `.tapDisabledByTimeout` event
- When `handleFlagsChanged` processes it
- Then `CGEvent.tapEnable(tap:enable:true)` is called (existing behavior preserved)

**Verification:**
- Command: `grep -n "CFRunLoopGetMain\|RunLoop.main\|DispatchQueue.main.*CFRunLoop" /Users/austingregersen/Developer/VoxKey/VoxKey/Managers/HotkeyManager.swift`
- Expected: No output (main run loop must not be used for the event tap)
- Command: `grep -n "com.voxkey.eventtap" /Users/austingregersen/Developer/VoxKey/VoxKey/Managers/HotkeyManager.swift`
- Expected: Exactly one occurrence
- Command: `swift test --filter HotkeyManagerTests/testTapDisabledByTimeoutDoesNotTriggerCallbacks`
- Expected: Test passes after refactor; exit 0

**Priority:** Must
**Status:** Pending

---

### REQ-16: All Existing Tests Pass After Refactor

**Description:** The complete `swift test` suite must exit 0 after all refactoring changes; no existing test may be deleted; tests that reference `onKeyDown`/`onKeyUp` must be updated to use `onActivate`/`onDeactivate` but their behavioral assertions must remain unchanged.

**Acceptance Criteria:**
- Given all source changes are applied
- When `swift test` is run
- Then exit code is 0 and no tests are skipped or marked as expected failures

**Verification:**
- Command: `swift test`
- Expected: Exit 0, output contains "Test Suite 'All tests' passed"

**Priority:** Must
**Status:** Pending

---

### REQ-17: Full Build and Install Succeeds

**Description:** `swift build` (debug) and `./scripts/build.sh` (release, signed) must both succeed after all changes; the installed app at `/Applications/VoxKey.app` must be signed with the "VoxKey Dev" identity.

**Acceptance Criteria:**
- Given all source changes are applied
- When `swift build` is run
- Then exit code is 0 with no errors

- Given `./scripts/build.sh` is run
- When it completes
- Then exit code is 0 and `/Applications/VoxKey.app` exists

- Given `/Applications/VoxKey.app` exists
- When `codesign -dv /Applications/VoxKey.app` is run
- Then output contains `VoxKey Dev`

**Verification:**
- Command: `swift build`
- Expected: Exit 0
- Command: `./scripts/build.sh`
- Expected: Exit 0
- Command: `codesign -dv /Applications/VoxKey.app 2>&1 | grep "VoxKey Dev"`
- Expected: Non-empty output

**Priority:** Must
**Status:** Pending

---

## Technical Context

### Technologies

- Language: Swift 5.9 (swift-tools-version: 5.9, `Package.swift` line 1)
- Minimum OS: macOS 14.0 (`Package.swift` line 7)
- Architecture: Apple Silicon (arm64)
- UI: SwiftUI — `SettingsView` uses `Form` / `Section` / `Picker` / `@AppStorage` (see `SettingsView.swift` lines 5–13)
- Persistence: `UserDefaults.standard` — existing keys: `"selectedModel"`, `"launchAtLogin"`, `"pauseMediaWhileDictating"`, `"customDictionaryTerms"` (see `SettingsView.swift` lines 6–8, `AppDelegate.swift` line 99)
- Event tap: `CoreGraphics.CGEvent.tapCreate` — listen-only, `.cgSessionEventTap`, `.headInsertEventTap` (`HotkeyManager.swift` lines 25–32)
- Concurrency: `@MainActor` class for `AppDelegate`; hotkey callbacks hop to main actor via `Task { @MainActor in ... }` (`AppDelegate.swift` lines 46–57)

### Patterns to Follow

**UserDefaults + @AppStorage pattern** (from `SettingsView.swift` lines 6–8):
```swift
@AppStorage("activationKeyCode") private var activationKeyCode: Int = Int(Constants.defaultActivationKeyCode)
@AppStorage("activationMode") private var activationMode: String = ActivationMode.hold.rawValue
```
Note: `@AppStorage` does not support `CGKeyCode` (a `UInt64` typealias) directly; use `Int` and cast at call sites.

**Background-thread event tap pattern** (from `HotkeyManager.swift` lines 49–64):
The tap thread is created as a `Thread { [weak self] in ... }` closure, assigned `thread.name = "com.voxkey.eventtap"` and `thread.qualityOfService = .userInteractive` before calling `thread.start()`. `CFRunLoopGetCurrent()` inside the closure captures the background thread's run loop into `self.tapRunLoop`. Do not use `CFRunLoopGetMain()`.

**Stop pattern** (from `HotkeyManager.swift` lines 67–84):
`stop()` disables the tap, calls `CFRunLoopStop(tapRunLoop)`, removes the source, then nils all properties. `restart` must follow the same sequence before starting a new tap.

**Tap re-enable pattern** (from `HotkeyManager.swift` lines 89–95):
```swift
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    return
}
```
This block must remain unchanged in the refactored `handleFlagsChanged`.

**Keycode + flag-mask detection pattern** (from `HotkeyManager.swift` lines 97–113):
The existing approach reads `event.getIntegerValueField(.keyboardEventKeycode)` to get the exact keycode, then checks the corresponding flag bit in `event.flags`. Left and right modifiers share the same flag family (e.g., both Left and Right Control set `.maskControl`) — disambiguation is always by keycode, never by a separate flag bit. The refactored code must continue this approach, driven by `ActivationKey.activationKey(forKeyCode:).flagsMask`.

**Synthetic CGEvent test helper** (from `HotkeyManagerTests.swift` lines 22–28):
```swift
private func makeFlagsChangedEvent(keyCode: CGKeyCode, flags: CGEventFlags) -> CGEvent? {
    guard let event = CGEvent(source: nil) else { return nil }
    event.type = .flagsChanged
    event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
    event.flags = flags
    return event
}
```
All new `HotkeyManager` tests must reuse this helper without modification.

**AppDelegate callback wiring** (from `AppDelegate.swift` lines 44–57):
Callbacks assigned to `hotkeyManager.onKeyDown`/`onKeyUp` will become `hotkeyManager.onActivate`/`onDeactivate`. The closure bodies (`handleKeyDown()` / `handleKeyUp()`) remain unchanged — only the property name on `hotkeyManager` changes.

### Files to Reference

- `/Users/austingregersen/Developer/VoxKey/VoxKey/Managers/HotkeyManager.swift` — Full file; lines 88–113 contain `handleFlagsChanged` to be refactored
- `/Users/austingregersen/Developer/VoxKey/VoxKey/App/AppDelegate.swift` — Lines 44–57 for callback wiring; line 99 for `UserDefaults` read pattern
- `/Users/austingregersen/Developer/VoxKey/VoxKey/Views/SettingsView.swift` — Lines 15–108 for `Form`/`Section`/`Picker` patterns to follow in the new Activation section
- `/Users/austingregersen/Developer/VoxKey/VoxKey/Utilities/Constants.swift` — Full file; shows all existing constants; new defaults must be added here
- `/Users/austingregersen/Developer/VoxKey/VoxKeyTests/HotkeyManagerTests.swift` — Full file; all existing tests must remain passing; `makeFlagsChangedEvent` helper must be reused
- `/Users/austingregersen/Developer/VoxKey/Package.swift` — Confirms Swift 5.9 tools version, macOS 14 platform, single executable target named `VoxKey`

### Constraints

- Do NOT move the CGEventTap CFRunLoop to the main run loop. The dedicated background thread named `"com.voxkey.eventtap"` with QoS `.userInteractive` is load-bearing (see CLAUDE.md "Hotkey: the threading invariant"). Using `CFRunLoopGetMain()` or `RunLoop.main` for the tap source will cause event starvation when the app is launched via `open`.
- Do NOT re-enable the app sandbox. `com.apple.security.app-sandbox = false` in the entitlements is required for `CGEventTap` and clipboard manipulation.
- Do NOT add new Swift Package Manager dependencies.
- Do NOT delete existing tests. All existing `HotkeyManagerTests` cases must continue to pass (they may be updated for renamed callbacks).
- Do NOT commit or push changes. Implementation ends at a buildable, tested state; the user decides when to commit.
- `handleFlagsChanged` must remain `internal` access (not `private`) for testability — see CLAUDE.md.
- `TapStateMachine` must be a separate, standalone type (not a nested type inside `HotkeyManager`) so it can be unit-tested without a `CGEventTap` or TCC permissions.
- The Fn key (keycode `63`) may not produce `flagsChanged` events on all Apple keyboards; document this in code comments but do not restrict it from the picker — the user's hardware determines whether it works.
- `@AppStorage` does not support `CGKeyCode` (`UInt64`) directly; store as `Int` and cast at all use sites.

### Anti-Patterns to Avoid

- Do NOT use `if Constants.activationKeyCode == Constants.rightCtrlKeyCode then .maskControl else .maskAlternate` or any equivalent hardcoded conditional in `handleFlagsChanged`. The entire point of this feature is a table-driven lookup.
- Do NOT call `hotkeyManager.restart` on a background thread. `AppDelegate` is `@MainActor`; the `UserDefaults.didChangeNotification` observer must dispatch to the main actor before calling `restart`.
- Do NOT invoke `onActivate` or `onDeactivate` from within `restart(...)` itself. The restart must be a clean tap teardown and rebuild; any in-flight recording state is the caller's responsibility.
- Do NOT use `Thread.sleep` in `TapStateMachine` tests. Inject the clock closure (`clock: () -> TimeInterval`) and advance time synthetically.
- Do NOT use `DispatchQueue.asyncAfter` in `TapStateMachine`. The machine is purely synchronous; timing decisions are made at event-processing time by comparing `clock()` to stored timestamps.
- Do NOT store `CGEventFlags` masks inside `UserDefaults`. Only the `CGKeyCode` integer is persisted; the mask is always derived at runtime from `ActivationKey.activationKey(forKeyCode:)`.

## Implementation Plan

### Phase A: Model Layer and Persistence

#### Task A.1: Create `ActivationKey` Enum
- [ ] Create `/Users/austingregersen/Developer/VoxKey/VoxKey/Models/ActivationKey.swift`
- [ ] Define `enum ActivationKey: CaseIterable` with 10 cases (one per supported keycode)
- [ ] Add `var cgKeyCode: CGKeyCode` computed property
- [ ] Add `var flagsMask: CGEventFlags` computed property (use the table from R2: 62/.maskControl, 59/.maskControl, 61/.maskAlternate, 58/.maskAlternate, 54/.maskCommand, 55/.maskCommand, 60/.maskShift, 56/.maskShift, 57/.maskAlphaShift, 63/.maskSecondaryFn)
- [ ] Add `var label: String` computed property with human-readable names ("Right Control", "Left Control", "Right Option", "Left Option", "Right Command", "Left Command", "Right Shift", "Left Shift", "Caps Lock", "Function (Fn)")
- [ ] Add `static func activationKey(forKeyCode keyCode: CGKeyCode) -> ActivationKey?`
- **Verification:** `grep -n "case.*rightControl\|activationKey(forKeyCode" /Users/austingregersen/Developer/VoxKey/VoxKey/Models/ActivationKey.swift` returns matches; `swift build` exits 0

#### Task A.2: Create `ActivationMode` Enum
- [ ] Create `/Users/austingregersen/Developer/VoxKey/VoxKey/Models/ActivationMode.swift`
- [ ] Define `enum ActivationMode: String, CaseIterable` with cases `hold`, `singleTap`, `doubleTap`
- [ ] Add `var label: String` computed property ("Hold", "Single Tap", "Double Tap")
- [ ] Add `var description: String` computed property (one-line helper text for each mode)
- [ ] Add `static var current: ActivationMode` reading from `UserDefaults.standard` with `.hold` default
- **Verification:** `swift build` exits 0; `grep -n "singleTap\|doubleTap" /Users/austingregersen/Developer/VoxKey/VoxKey/Models/ActivationMode.swift` returns two matches

#### Task A.3: Update `Constants.swift`
- [ ] Add `static let defaultActivationKeyCode: CGKeyCode = 62`
- [ ] Add `static let defaultActivationMode: ActivationMode = .hold`
- [ ] Add `static let defaultDoubleTapWindowMs: Int = 400`
- [ ] Remove `static let rightOptionKeyCode` and `static let activationKeyCode` (these are now superseded; verify no other file references them before removing — use `grep -rn "rightOptionKeyCode\|\.activationKeyCode" /Users/austingregersen/Developer/VoxKey/VoxKey/`)
- **Verification:** `swift build` exits 0; `grep -n "defaultActivationKeyCode" /Users/austingregersen/Developer/VoxKey/VoxKey/Utilities/Constants.swift` returns one match with value `62`

#### Task A.4: Create `TapStateMachine`
- [ ] Create `/Users/austingregersen/Developer/VoxKey/VoxKey/Models/TapStateMachine.swift`
- [ ] Define `enum TapAction { case start, stop, noop }`
- [ ] Define `final class TapStateMachine` with init `(mode: ActivationMode, doubleTapWindowMs: Int, clock: @escaping () -> TimeInterval)`; `clock` defaults to `{ Date().timeIntervalSinceReferenceDate }`
- [ ] Implement `func process(isKeyDown: Bool) -> TapAction` that internally calls `clock()` to get current time
- [ ] Internal state for single-tap mode: `isRecording: Bool`; emit `.start` on first key-up when not recording, `.stop` on first key-up when recording
- [ ] Internal state for double-tap mode: `pendingFirstTapUpTime: TimeInterval?`, `isRecording: Bool`; emit `.start` when second key-down arrives within window of `pendingFirstTapUpTime`; emit `.stop` on key-up when recording; discard expired first-tap state on any new key-down outside the window
- [ ] Double-tap window boundary: `secondKeyDownTime < firstKeyUpTime + (doubleTapWindowMs / 1000.0)` (exclusive upper bound)
- [ ] Hold mode: `process` always returns `.noop` (not consulted in Hold mode)
- **Verification:** `swift build` exits 0; `grep -n "TapStateMachine\|TapAction" /Users/austingregersen/Developer/VoxKey/VoxKey/Models/TapStateMachine.swift` returns matches

---

### Phase B: HotkeyManager Refactor

#### Task B.1: Replace Hardcoded Flag Logic with `ActivationKey` Lookup
- [ ] Open `/Users/austingregersen/Developer/VoxKey/VoxKey/Managers/HotkeyManager.swift`
- [ ] Remove the `if Constants.activationKeyCode == Constants.rightCtrlKeyCode` conditional (lines 102–104)
- [ ] Replace with: `guard let key = ActivationKey.activationKey(forKeyCode: CGKeyCode(keyCode)) else { return }`
- [ ] Replace `controlDown` flag logic with: `let keyPressed = currentFlags.contains(key.flagsMask)`
- [ ] Rename `previousControlDown` to `previousKeyPressed` (update the `Bool` stored property and all references within the file)
- **Verification:** `grep -n "rightCtrlKeyCode\|maskAlternate" /Users/austingregersen/Developer/VoxKey/VoxKey/Managers/HotkeyManager.swift` returns no output; `swift build` exits 0

#### Task B.2: Add `onActivate`/`onDeactivate` and Remove `onKeyDown`/`onKeyUp`
- [ ] Rename `var onKeyDown: (() -> Void)?` to `var onActivate: (() -> Void)?`
- [ ] Rename `var onKeyUp: (() -> Void)?` to `var onDeactivate: (() -> Void)?`
- [ ] In `handleFlagsChanged` Hold-mode path: replace `onKeyDown?()` with `onActivate?()` and `onKeyUp?()` with `onDeactivate?()`
- **Verification:** `grep -rn "onKeyDown\|onKeyUp" /Users/austingregersen/Developer/VoxKey/VoxKey/` returns no output

#### Task B.3: Add Configurable Keycode and Mode to `HotkeyManager`
- [ ] Add stored properties `private var configuredKeyCode: CGKeyCode` and `private var configuredMode: ActivationMode` and `private var tapStateMachine: TapStateMachine?`
- [ ] Initialize `configuredKeyCode` from `UserDefaults.standard` integer for `"activationKeyCode"` (fallback to `Constants.defaultActivationKeyCode`) in `init()`
- [ ] Initialize `configuredMode` from `UserDefaults.standard` string for `"activationMode"` (fallback to `Constants.defaultActivationMode`) in `init()`
- [ ] Replace `guard keyCode == Constants.activationKeyCode` with `guard CGKeyCode(keyCode) == configuredKeyCode`
- [ ] In Hold mode: invoke `onActivate`/`onDeactivate` directly (existing logic, just renamed)
- [ ] In Single/Double Tap modes: create `tapStateMachine` if nil, call `tapStateMachine?.process(isKeyDown: keyPressed)` on both key-down and key-up events, map `.start` → `onActivate?()`, `.stop` → `onDeactivate?()`, `.noop` → nothing
- **Verification:** `swift build` exits 0; `swift test --filter HotkeyManagerTests/testRightCtrlKeyDownTriggersCallback` exits 0

#### Task B.4: Add `restart(keyCode:mode:doubleTapWindowMs:)` Method
- [ ] Add `func restart(keyCode: CGKeyCode, mode: ActivationMode, doubleTapWindowMs: Int)` to `HotkeyManager`
- [ ] Call `stop()` to tear down existing tap
- [ ] Set `configuredKeyCode = keyCode`, `configuredMode = mode`
- [ ] Reset `tapStateMachine` to nil (a fresh machine will be created on next event if needed)
- [ ] Call `start()` to create a new tap on a fresh background thread
- [ ] Log the restart at `logger.info` level with new keycode and mode
- **Verification:** `grep -n "func restart" /Users/austingregersen/Developer/VoxKey/VoxKey/Managers/HotkeyManager.swift` returns one match; `swift build` exits 0

---

### Phase C: AppDelegate Live-Apply Wiring

#### Task C.1: Update `AppDelegate` Callback Assignments
- [ ] Open `/Users/austingregersen/Developer/VoxKey/VoxKey/App/AppDelegate.swift`
- [ ] Change `hotkeyManager.onKeyDown = { ... }` to `hotkeyManager.onActivate = { ... }`
- [ ] Change `hotkeyManager.onKeyUp = { ... }` to `hotkeyManager.onDeactivate = { ... }`
- [ ] Update log messages inside the closures from "Right Ctrl DOWN/UP" to "Activation key activated/deactivated"
- **Verification:** `grep -n "onKeyDown\|onKeyUp" /Users/austingregersen/Developer/VoxKey/VoxKey/App/AppDelegate.swift` returns no output; `swift build` exits 0

#### Task C.2: Observe UserDefaults Changes for Live Apply
- [ ] In `applicationDidFinishLaunching`, after `startDictationPipeline()`, add:
  ```swift
  NotificationCenter.default.addObserver(
      self,
      selector: #selector(userDefaultsDidChange(_:)),
      name: UserDefaults.didChangeNotification,
      object: nil
  )
  ```
- [ ] Implement `@objc private func userDefaultsDidChange(_ notification: Notification)` on `AppDelegate`
- [ ] Inside the handler, read current `"activationKeyCode"` and `"activationMode"` from `UserDefaults.standard` using `Constants.defaultActivationKeyCode` and `Constants.defaultActivationMode` as fallbacks
- [ ] Only call `hotkeyManager.restart(...)` if either value differs from the current `configuredKeyCode` or `configuredMode` stored on the manager (add a read accessor to `HotkeyManager` for these if needed, or track last-applied values in `AppDelegate` using two private properties)
- [ ] In `applicationWillTerminate`, call `NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object: nil)`
- **Verification:** `grep -n "didChangeNotification" /Users/austingregersen/Developer/VoxKey/VoxKey/App/AppDelegate.swift` returns at least two matches (add and remove); `swift build` exits 0

---

### Phase D: Settings UI

#### Task D.1: Add Activation Section to `SettingsView`
- [ ] Open `/Users/austingregersen/Developer/VoxKey/VoxKey/Views/SettingsView.swift`
- [ ] Add `@AppStorage("activationKeyCode") private var activationKeyCode: Int = Int(Constants.defaultActivationKeyCode)` to the property list
- [ ] Add `@AppStorage("activationMode") private var activationMode: String = Constants.defaultActivationMode.rawValue` to the property list
- [ ] Add a new `Section("Activation")` block before the existing `Section("Transcription")` block (placing it first gives it visual prominence)
- [ ] Inside the section, add a `Picker("Activation Key", ...)` using `ForEach(ActivationKey.allCases, id: \.cgKeyCode)` with `Text(key.label).tag(Int(key.cgKeyCode))` and `selection: $activationKeyCode`
- [ ] Add a `Picker("Activation Mode", ...)` using `ForEach(ActivationMode.allCases, id: \.rawValue)` with `Text(mode.label).tag(mode.rawValue)` and `selection: $activationMode`
- [ ] Below each mode row (or as a footer), add brief description text from `ActivationMode.description`
- **Verification:** `swift build` exits 0; `grep -n "Section.*Activation\|activationKeyCode\|activationMode" /Users/austingregersen/Developer/VoxKey/VoxKey/Views/SettingsView.swift` returns at least three matches

#### Task D.2: Add Caps Lock + Hold Warning
- [ ] Inside `Section("Activation")`, after both pickers, add a conditional `HStack` (or `Label`) that renders when `activationKeyCode == 57 && activationMode == "hold"`
- [ ] Warning text: `"Caps Lock toggles on press and is unreliable in Hold mode. Switch to Single Tap or Double Tap."`
- [ ] Style: `.foregroundStyle(.orange)` and `.font(.caption)` to match macOS inline warning convention
- **Verification:** `swift build` exits 0; `grep -n "57\|Caps Lock" /Users/austingregersen/Developer/VoxKey/VoxKey/Views/SettingsView.swift` returns at least one match

#### Task D.3: Adjust `SettingsView` Frame Height
- [ ] The existing frame is `width: 450, height: 550` (line 110 of `SettingsView.swift`). The new section adds content; increase height to `680` to avoid clipping.
- **Verification:** `swift build` exits 0; `grep -n "frame.*height" /Users/austingregersen/Developer/VoxKey/VoxKey/Views/SettingsView.swift` shows updated value

---

### Phase E: Tests

#### Task E.1: Update Existing Tests for Renamed Callbacks
- [ ] Open `/Users/austingregersen/Developer/VoxKey/VoxKeyTests/HotkeyManagerTests.swift`
- [ ] Replace all `manager.onKeyDown` with `manager.onActivate` and `manager.onKeyUp` with `manager.onDeactivate` throughout the file
- [ ] Do NOT change keycode values or behavioral assertions — only the property names change
- **Verification:** `swift test --filter HotkeyManagerTests/testFullKeyDownUpCycle` exits 0

#### Task E.2: Add Keycode-to-Mask Parametrized Tests
- [ ] Add `func testActivationKeyMappingAllKeycodes()` that iterates all 10 `(keyCode, expectedMask)` pairs inline (no external parametrize library needed)
- [ ] For each pair: assert `ActivationKey.activationKey(forKeyCode: keyCode)` is non-nil and `.flagsMask == expectedMask`
- [ ] Also assert `ActivationKey.activationKey(forKeyCode: 0)` is nil
- **Verification:** `swift test --filter HotkeyManagerTests/testActivationKeyMappingAllKeycodes` exits 0

#### Task E.3: Add TapStateMachine Single-Tap Tests
- [ ] Add a new `final class TapStateMachineTests: XCTestCase` in the same file (or a new file `VoxKeyTests/TapStateMachineTests.swift`)
- [ ] `testSingleTapEmitsStart`: drive `isKeyDown=true` (noop), then `isKeyDown=false` (expect `.start`)
- [ ] `testSingleTapEmitsStopOnSecondTap`: after `.start`, drive another complete tap and expect `.stop`
- [ ] `testSingleTapKeyDownAloneIsNoop`: drive only `isKeyDown=true`, expect `.noop`
- [ ] Use the injected clock (fixed timestamp) — not real time
- **Verification:** `swift test --filter TapStateMachineTests` exits 0

#### Task E.4: Add TapStateMachine Double-Tap Tests
- [ ] `testDoubleTapWithinWindowEmitsStart`: inject clock returning T=0 for first key-down, T=0.1 for first key-up, T=0.4 for second key-down (within 400ms window), T=0.5 for second key-up → expect `.start`
- [ ] `testDoubleTapOutsideWindowIsNoop`: second key-down at T=0.5 (≥ first key-up + 400ms) → expect `.noop`
- [ ] `testDoubleTapBoundaryIsNoop`: second key-down at exactly `firstKeyUpTime + 0.400` → expect `.noop` (exclusive upper bound)
- [ ] `testDoubleTapStopViaSingleTap`: after machine emits `.start`, one complete tap emits `.stop`
- [ ] Use counter-based clock closure that returns pre-set timestamps from an array
- **Verification:** `swift test --filter TapStateMachineTests/testDoubleTapWithinWindowEmitsStart` exits 0; `swift test --filter TapStateMachineTests` exits 0

#### Task E.5: Add UserDefaults Persistence Tests
- [ ] `testActivationModePersistence`: write each of the three raw values to `UserDefaults`, read back, assert correct `ActivationMode` case; write nothing and assert default is `.hold`
- [ ] `testActivationKeyCodePersistence`: write each of the 10 keycodes as `Int` to `UserDefaults` under `"activationKeyCode"`, read back as `Int`, assert correct value; write nothing and assert default is `62`
- [ ] `testDoubleTapWindowFromUserDefaults`: write `250` to `"doubleTapWindowMs"`, read back, assert `250`; write nothing and assert default is `400`
- [ ] Use a separate `UserDefaults` suite (e.g., `UserDefaults(suiteName: "com.voxkey.tests")`) to avoid polluting the standard store; tear down in `tearDown()`
- **Verification:** `swift test --filter HotkeyManagerTests/testActivationModePersistence` exits 0

#### Task E.6: Full Test Suite Gate
- [ ] After all test additions, run the complete suite
- **Verification:** `swift test` exits 0; output contains "Test Suite 'All tests' passed"

---

### Phase F: Build Verification

#### Task F.1: Debug Build
- [ ] Run `swift build` from the repo root
- **Verification:** Exit 0, no errors or warnings that were not already present before this feature

#### Task F.2: Release Build and Install
- [ ] Run `./scripts/build.sh`
- **Verification:** Exit 0; `/Applications/VoxKey.app` exists; `codesign -dv /Applications/VoxKey.app 2>&1 | grep "VoxKey Dev"` is non-empty

---

## Verification Matrix

| Req ID | Requirement | Verification Command | Expected | Status |
|--------|-------------|---------------------|----------|--------|
| REQ-1 | ActivationMode enum and persistence | `swift test --filter HotkeyManagerTests/testActivationModePersistence` | Exit 0, 3 cases round-trip | Pending |
| REQ-2 | ActivationKey enum with keycode-to-mask table | `swift test --filter HotkeyManagerTests/testActivationKeyMappingAllKeycodes` | Exit 0, all 10 pairs correct | Pending |
| REQ-3 | HotkeyManager table-driven flag lookup | `grep -n "rightCtrlKeyCode\|maskAlternate" .../HotkeyManager.swift` | No output | Pending |
| REQ-4 | onActivate/onDeactivate semantic callbacks | `grep -rn "onKeyDown\|onKeyUp" .../VoxKey/` | No output | Pending |
| REQ-5 | TapStateMachine single tap mode | `swift test --filter TapStateMachineTests/testSingleTapEmitsStart` | Exit 0 | Pending |
| REQ-6 | TapStateMachine double tap mode | `swift test --filter TapStateMachineTests/testDoubleTapWithinWindowEmitsStart` | Exit 0 | Pending |
| REQ-7 | HotkeyManager routes to TapStateMachine | `swift test --filter HotkeyManagerTests/testSingleTapModeActivation` | Exit 0 | Pending |
| REQ-8 | restart(keyCode:mode:doubleTapWindowMs:) | `swift test --filter HotkeyManagerTests/testRestartChangesKeyCode` | Exit 0 | Pending |
| REQ-9 | Live apply via UserDefaults observation | `grep -n "didChangeNotification" .../AppDelegate.swift` | ≥2 matches | Pending |
| REQ-10 | Activation key persistence in UserDefaults | `swift test --filter HotkeyManagerTests/testActivationKeyCodePersistence` | Exit 0 | Pending |
| REQ-11 | Double tap window persistence | `swift test --filter HotkeyManagerTests/testDoubleTapWindowFromUserDefaults` | Exit 0 | Pending |
| REQ-12 | Settings UI activation section | `grep -n "Section.*Activation" .../SettingsView.swift` | ≥1 match | Pending |
| REQ-13 | Caps Lock + Hold mode warning | `grep -n "57\|Caps Lock" .../SettingsView.swift` | ≥1 match | Pending |
| REQ-14 | Backward compat — defaults to Right Control + Hold | `swift test --filter HotkeyManagerTests/testRightCtrlKeyDownTriggersCallback` | Exit 0 | Pending |
| REQ-15 | Background thread invariant preserved after restart | `grep -n "CFRunLoopGetMain\|RunLoop.main" .../HotkeyManager.swift` | No output | Pending |
| REQ-16 | All existing tests pass after refactor | `swift test` | Exit 0, "All tests passed" | Pending |
| REQ-17 | Full build and install succeeds | `./scripts/build.sh && codesign -dv /Applications/VoxKey.app 2>&1 \| grep "VoxKey Dev"` | Exit 0, non-empty | Pending |

## Open Questions

No unresolved questions remain. All decisions have been encoded in this spec:

1. **Single tap in double-tap mode stops recording** — Resolved: yes. A single complete tap stops recording when in double-tap mode. This is encoded in REQ-6 and `TapStateMachine` phase A.4. Rationale: requiring a second double-tap to stop is error-prone under time pressure; a single tap to stop is consistent with single-tap mode and lowers friction.

2. **`onKeyDown`/`onKeyUp` vs `onActivate`/`onDeactivate`** — Resolved: rename and remove the old names. Adding alongside would create two callback surfaces to maintain. Since `AppDelegate` is the only consumer, a direct rename is safe and cleaner. All tests are updated in Phase E, Task E.1.

3. **Where to store last-applied keycode/mode to avoid redundant restarts** — Resolved: add `private(set) var configuredKeyCode: CGKeyCode` and `private(set) var configuredMode: ActivationMode` as readable properties on `HotkeyManager`; `AppDelegate`'s `userDefaultsDidChange` reads these to detect actual changes before calling `restart`.

4. **Caps Lock compatibility** — Resolved: warn in the UI (REQ-13) but do not restrict the selection. macOS toggles Caps Lock state on press, so the flag bit alternates rather than remaining set while held. This makes Hold mode unreliable with Caps Lock (pressing once sets `.maskAlphaShift`; pressing again clears it regardless of physical hold). Tap modes work correctly because they fire on key-up. The warning is shown inline in Settings when the incompatible combination is selected.

## Iteration Log

_To be filled during implementation._

## Final Summary

_To be filled upon completion._
