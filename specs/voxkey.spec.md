# Implementation Spec: VoxKey - macOS Push-to-Talk Dictation Tool

**Created:** 2026-02-12
**Status:** Draft
**Last Updated:** 2026-02-12

## Problem Statement

macOS users need efficient text input via voice dictation, but existing solutions require multiple clicks, interrupting workflow, or rely on cloud services raising privacy concerns. Keyboard-based dictation activation (hold-to-record) is faster than clicking UI elements, and on-device transcription via WhisperKit eliminates network latency and privacy issues.

Success: A menu bar app where users hold Right Ctrl (keycode 62) to record, release to transcribe on-device, and have text inserted at cursor position in any app — all within 1-2 seconds for typical utterances (under 10 seconds of audio). Target users: knowledge workers on Apple Silicon Macs running macOS 14+.

## Deliverables

### Core Application Files

- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/App/VoxKeyApp.swift` - @main entry point, MenuBarExtra scene setup (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/App/AppDelegate.swift` - Application lifecycle, permission checks, onboarding coordinator (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Models/AppState.swift` - Observable app state (idle/recording/processing), model ObservableObject (create)

### Manager Layer

- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Managers/HotkeyManager.swift` - CGEventTap setup, flagsChanged monitoring, Right Ctrl (keycode 62) detection (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Managers/AudioCaptureManager.swift` - AVAudioEngine lifecycle, 16kHz mono PCM recording, buffer accumulation (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Managers/MenuBarManager.swift` - NSStatusItem management, menu construction, icon state updates (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Managers/TextInsertionManager.swift` - Clipboard save/restore, CGEventPost Cmd+V simulation (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Managers/PermissionManager.swift` - Accessibility/Microphone/Input Monitoring checks and requests (create)

### Service Layer

- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Services/TranscriptionService.swift` - WhisperKit integration, model loading/downloading, transcription execution (create)

### UI Components

- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Views/SettingsView.swift` - SwiftUI settings window (model picker, permissions, launch at login) (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Views/OnboardingView.swift` - Permission setup flow for first launch (create)

### Utilities and Resources

- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Utilities/Constants.swift` - Keycodes (Right Ctrl = 62), timeout values, model names (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Resources/Info.plist` - App configuration (LSUIElement = true, permissions usage strings, bundle ID) (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Resources/Assets.xcassets/` - App icon, menu bar icons (idle/recording/processing) (create)

### Testing

- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKeyTests/HotkeyManagerTests.swift` - Unit tests for keycode detection, key down/up events (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKeyTests/AudioCaptureManagerTests.swift` - Unit tests for buffer management, format conversion (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKeyTests/TranscriptionServiceTests.swift` - Unit tests for model loading, transcription pipeline (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKeyTests/TextInsertionManagerTests.swift` - Unit tests for clipboard save/restore logic (create)

### Build and Distribution

- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/scripts/notarize.sh` - Build + notarization script for direct DMG distribution (create)
- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/README.md` - Project documentation (setup, build, permissions, distribution) (create)

### Project Configuration

- [ ] `/Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey.xcodeproj/` - Xcode project with Swift Package Manager integration for WhisperKit (create)

## Requirements

### REQ-1: Right Ctrl Hotkey Detection

**Description:** The app must detect Right Ctrl key (keycode 62) press and release events system-wide to start/stop recording.

**Acceptance Criteria:**
- Given the app is running with Accessibility permissions granted
- When user presses and holds Right Ctrl (keycode 62)
- Then recording state activates immediately (within 50ms)

- Given recording is active
- When user releases Right Ctrl
- Then recording stops immediately and transcription begins

**Verification:**
- Command: `swift test --filter HotkeyManagerTests.testRightCtrlKeyDetection`
- Expected: Test passes, keycode 62 flagsChanged events correctly trigger keyDown and keyUp callbacks

**Priority:** Must
**Status:** Pending

### REQ-2: Audio Capture at 16kHz Mono PCM

**Description:** The app must capture microphone audio at 16kHz sample rate, mono channel, PCM format while Right Ctrl is held.

**Acceptance Criteria:**
- Given user holds Right Ctrl
- When AVAudioEngine is recording
- Then audio format is 16000 Hz, 1 channel, PCM linear

- Given recording is active for 3 seconds
- When recording stops
- Then accumulated buffer contains 48,000 samples (3s * 16,000 Hz)

**Verification:**
- Command: `swift test --filter AudioCaptureManagerTests.testAudioFormat`
- Expected: Test validates AVAudioFormat is 16kHz mono PCM, buffer sample count matches duration

**Priority:** Must
**Status:** Pending

### REQ-3: On-Device Transcription with WhisperKit

**Description:** The app must transcribe recorded audio using WhisperKit (Base model by default) entirely on-device.

**Acceptance Criteria:**
- Given recorded audio buffer is ready
- When TranscriptionService.transcribe() is called
- Then WhisperKit processes audio locally and returns transcribed text

- Given WhisperKit Base model is loaded
- When transcription is requested
- Then no network requests are made (on-device only)

**Verification:**
- Command: `swift test --filter TranscriptionServiceTests.testOnDeviceTranscription`
- Expected: Test passes, transcription returns non-empty string for test audio without network calls

**Priority:** Must
**Status:** Pending

### REQ-4: Text Insertion via Clipboard and Cmd+V

**Description:** The app must insert transcribed text at the cursor position in any focused app by saving clipboard, setting text, simulating Cmd+V, and restoring clipboard.

**Acceptance Criteria:**
- Given clipboard contains "original content"
- When TextInsertionManager inserts "transcribed text"
- Then clipboard temporarily contains "transcribed text", Cmd+V is simulated, and clipboard is restored to "original content" after 100ms

- Given any app with text field is focused
- When text insertion is triggered
- Then transcribed text appears at cursor position

**Verification:**
- Command: `swift test --filter TextInsertionManagerTests.testClipboardRestore`
- Expected: Test validates clipboard save/restore cycle, original content is preserved after insertion

**Priority:** Must
**Status:** Pending

### REQ-5: Menu Bar Icon State Updates

**Description:** Menu bar icon must reflect app state: gray mic (idle), red mic (recording), spinner (processing).

**Acceptance Criteria:**
- Given app state is idle
- Then menu bar icon displays gray microphone

- Given app state transitions to recording
- Then menu bar icon displays red microphone

- Given app state transitions to processing
- Then menu bar icon displays spinner animation

**Verification:**
- Manual: Press Right Ctrl and observe icon changes to red, release and observe spinner, then idle
- Expected: All three icon states display correctly during operation cycle

**Priority:** Must
**Status:** Pending

### REQ-6: Permission Checks and Onboarding

**Description:** The app must check for Accessibility, Microphone, and Input Monitoring permissions on launch and guide users through setup if missing.

**Acceptance Criteria:**
- Given app launches for the first time
- When any required permission is not granted
- Then OnboardingView appears with checklist and "Open System Settings" buttons

- Given all permissions are granted
- Then app starts normally without onboarding

**Verification:**
- Manual: Reset permissions via `tccutil reset Accessibility com.yourteam.VoxKey`, launch app
- Expected: Onboarding view appears with permission status indicators

**Priority:** Must
**Status:** Pending

### REQ-7: Whisper Model Selection

**Description:** Users must be able to select WhisperKit model (Tiny, Base, Small, Medium, Large) in settings with download progress shown.

**Acceptance Criteria:**
- Given user opens Settings
- When user selects "Small" model from dropdown
- Then download progress bar appears and model downloads

- Given model download completes
- Then new model is used for subsequent transcriptions

**Verification:**
- Manual: Open Settings, select different model, observe download progress
- Expected: Progress bar shows download, transcription uses newly selected model

**Priority:** Must
**Status:** Pending

### REQ-8: Launch at Login

**Description:** The app must support "Launch at Login" toggle in Settings using SMAppService (macOS 13+).

**Acceptance Criteria:**
- Given user enables "Launch at Login" in Settings
- When macOS restarts
- Then VoxKey launches automatically

- Given user disables "Launch at Login"
- Then VoxKey does not auto-launch on restart

**Verification:**
- Manual: Enable toggle, restart, confirm app launches
- Expected: App launches automatically on system start when enabled

**Priority:** Should
**Status:** Pending

### REQ-9: Menu Bar Dropdown Menu

**Description:** Left-clicking menu bar icon shows dropdown with status text, Settings option, and Quit option.

**Acceptance Criteria:**
- Given user left-clicks menu bar icon
- Then dropdown menu appears with:
  - Status text line (e.g., "Ready", "Recording...", "Processing...")
  - "Settings..." menu item
  - Separator
  - "Quit VoxKey" menu item

**Verification:**
- Manual: Click menu bar icon, observe menu items
- Expected: All menu items present and functional

**Priority:** Must
**Status:** Pending

### REQ-10: Silent Operation

**Description:** The app must operate silently with no audio feedback (beeps, clicks, or spoken confirmations).

**Acceptance Criteria:**
- Given user records and releases Right Ctrl
- When transcription completes
- Then no sound is played

**Verification:**
- Manual: Record and transcribe with system volume up
- Expected: No audio feedback during operation

**Priority:** Must
**Status:** Pending

### REQ-11: Error Handling - Permission Denied

**Description:** If permissions are denied after initial setup, show alert with "Open System Settings" button and warning icon in menu bar.

**Acceptance Criteria:**
- Given Accessibility permission is revoked
- When user attempts to use hotkey
- Then alert appears: "VoxKey needs Accessibility permission. [Open System Settings] [Cancel]"

- Given permissions are denied
- Then menu bar icon shows warning indicator

**Verification:**
- Manual: Revoke Accessibility permission, attempt to record
- Expected: Alert appears with actionable button, menu bar shows warning

**Priority:** Must
**Status:** Pending

### REQ-12: Error Handling - Transcription Failure

**Description:** If transcription fails, show brief system notification "Transcription failed" without blocking app.

**Acceptance Criteria:**
- Given transcription encounters error (e.g., empty audio, WhisperKit crash)
- When error occurs
- Then NSUserNotification appears briefly with "Transcription failed" message

- Given notification is shown
- Then app returns to idle state and remains functional

**Verification:**
- Unit test: `swift test --filter TranscriptionServiceTests.testTranscriptionFailureNotification`
- Expected: Test simulates failure, verifies notification is posted

**Priority:** Must
**Status:** Pending

### REQ-13: Error Handling - Model Download Failure

**Description:** If WhisperKit model download fails, show error in Settings with Retry button.

**Acceptance Criteria:**
- Given user selects new model
- When download fails (network error, disk space)
- Then Settings shows "Download failed: [reason]" with [Retry] button

**Verification:**
- Manual: Simulate network error during download (disconnect WiFi)
- Expected: Error message appears with functional Retry button

**Priority:** Should
**Status:** Pending

### REQ-14: macOS 14+ and Apple Silicon Only

**Description:** The app must target macOS 14+ and Apple Silicon architecture, with explicit checks preventing launch on unsupported systems.

**Acceptance Criteria:**
- Given Xcode project deployment target is set to macOS 14.0
- When app is built
- Then binary requires macOS 14.0 minimum

- Given user attempts to run on macOS 13 or Intel Mac
- Then system prevents launch with version/architecture error

**Verification:**
- Command: Check Xcode project settings `grep -A 2 "MACOSX_DEPLOYMENT_TARGET" VoxKey.xcodeproj/project.pbxproj`
- Expected: Shows `MACOSX_DEPLOYMENT_TARGET = 14.0;` and `ARCHS = arm64;`

**Priority:** Must
**Status:** Pending

### REQ-15: No Dock Icon (LSUIElement)

**Description:** The app must not appear in the Dock (menu bar only), configured via Info.plist LSUIElement = true.

**Acceptance Criteria:**
- Given VoxKey is running
- Then no Dock icon appears
- And menu bar icon is visible

**Verification:**
- Manual: Launch app, check Dock
- Command: `defaults read /Users/brandonbarringer/Desktop/sites/native-apps/VoxKey/VoxKey/Resources/Info.plist LSUIElement`
- Expected: Returns "1" (true), no Dock icon visible

**Priority:** Must
**Status:** Pending

### REQ-16: Notarized DMG Distribution

**Description:** The app must be distributed as a notarized DMG for direct download (not App Store).

**Acceptance Criteria:**
- Given build script runs successfully
- When `scripts/notarize.sh` completes
- Then notarized DMG is created in `build/` directory

- Given DMG is downloaded
- When user opens DMG
- Then macOS does not show "unverified developer" warning

**Verification:**
- Command: `./scripts/notarize.sh && spctl --assess --type install build/VoxKey.dmg`
- Expected: Exit code 0, DMG passes Gatekeeper check

**Priority:** Must
**Status:** Pending

## Technical Context

### Technologies

- **Language:** Swift 5.9+
- **Minimum OS:** macOS 14.0 (Sonoma)
- **Architecture:** Apple Silicon (arm64) only
- **UI Framework:** SwiftUI 5.0+ (Settings window, onboarding)
- **Menu Bar:** MenuBarExtra API (SwiftUI-based status item)
- **Audio:** AVFoundation (AVAudioEngine, AVAudioConverter)
- **Transcription:** WhisperKit (Swift Package Manager dependency)
- **Event Handling:** CoreGraphics (CGEventTap, CGEventPost)
- **Permissions:** ApplicationServices (AXIsProcessTrustedWithOptions)
- **Launch at Login:** ServiceManagement (SMAppService, macOS 13+)
- **Testing:** XCTest (unit tests for core logic only)
- **Build Tool:** Xcode 15+

### Patterns to Follow

#### Swift Concurrency
- Use `async/await` for all asynchronous operations (audio capture, transcription, model downloads)
- Use `@MainActor` for UI updates and state changes
- Example pattern:
  ```swift
  @MainActor
  class AppState: ObservableObject {
      @Published var currentState: State = .idle

      func updateState(_ newState: State) {
          currentState = newState
      }
  }
  ```

#### Observable State Management
- Single source of truth: `AppState` ObservableObject shared across managers
- Managers observe state changes via Combine or callbacks
- Settings use SwiftUI `@AppStorage` for persistence
- Example:
  ```swift
  @AppStorage("selectedModel") private var selectedModel: String = "base"
  @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
  ```

#### CGEventTap Pattern
- Create event tap with `kCGEventTapOptionDefault` and `CGEventMask` for `flagsChanged`
- Filter for keycode 62 (Right Ctrl) specifically
- Install tap on main run loop: `CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)`
- Example:
  ```swift
  let eventMask = (1 << CGEventType.flagsChanged.rawValue)
  guard let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(eventMask),
      callback: eventTapCallback,
      userInfo: nil
  ) else {
      fatalError("Failed to create event tap")
  }
  ```

#### AVAudioEngine Buffer Management
- Use `AVAudioInputNode.installTap(onBus:bufferSize:format:)` to capture audio
- Convert to 16kHz mono using `AVAudioConverter`
- Accumulate buffers in `[AVAudioPCMBuffer]` array
- Concatenate on stop for transcription
- Example:
  ```swift
  let inputNode = audioEngine.inputNode
  let recordingFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16000,
      channels: 1,
      interleaved: false
  )!
  inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
      self.buffers.append(buffer)
  }
  ```

#### WhisperKit Integration
- Load model asynchronously on first use or model change
- Use `WhisperKit.transcribe(audioPath:)` or buffer-based API
- Handle model download progress with `Progress` observation
- Example:
  ```swift
  import WhisperKit

  let whisperKit = try await WhisperKit(model: "base")
  let transcription = try await whisperKit.transcribe(audioBuffer: pcmBuffer)
  ```

#### Clipboard Save/Restore
- Save all pasteboard types, not just string
- Use `NSPasteboard.general`
- Restore after brief delay (100ms) to allow paste to complete
- Example:
  ```swift
  let pasteboard = NSPasteboard.general
  let savedItems = pasteboard.pasteboardItems
  pasteboard.clearContents()
  pasteboard.setString(text, forType: .string)
  // Simulate Cmd+V via CGEventPost
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      pasteboard.clearContents()
      pasteboard.writeObjects(savedItems ?? [])
  }
  ```

### Files to Reference

Since this is a new project, there are no existing files to reference. All patterns above should be followed as stated.

### Constraints

- **No Dock Icon:** Must set `LSUIElement = true` in Info.plist
- **No App Store Distribution:** CGEventTap/CGEventPost are not allowed in sandboxed apps
- **Apple Silicon Only:** WhisperKit requires Apple Silicon for Core ML optimizations
- **macOS 14+ Only:** MenuBarExtra API and latest SMAppService require macOS 14
- **Hardcoded Hotkey:** Right Ctrl (keycode 62) is not configurable in MVP
- **No Cloud Fallback:** MVP uses WhisperKit only, no Deepgram or other cloud services
- **English Only:** No explicit language picker, Whisper auto-detects language
- **No Audio Feedback:** Silent operation (no beeps or spoken confirmations)
- **No Customization:** MVP has fixed behavior; hotkey, feedback, and language are not user-configurable

### Anti-Patterns to Avoid

- **Don't use `NSEvent.addGlobalMonitorForEvents`:** This requires Accessibility permission but doesn't work for modifier-only keys. Use CGEventTap with flagsChanged instead.
- **Don't store audio in memory indefinitely:** Clear buffer array after transcription completes to avoid memory leaks.
- **Don't block main thread during transcription:** WhisperKit transcription is CPU-intensive; always run on background queue and update UI on main thread.
- **Don't use `setTimeout` equivalents for clipboard restore:** Use `DispatchQueue.main.asyncAfter` with precise delay (100ms) to ensure paste completes.
- **Don't assume permissions are granted:** Check all three permissions (Accessibility, Microphone, Input Monitoring) on every launch and before operations.
- **Don't hardcode file paths for WhisperKit models:** Use WhisperKit's built-in model management and download APIs.
- **Don't create custom audio file formats:** WhisperKit expects 16kHz mono PCM; any other format will fail or produce poor results.
- **Don't use deprecated APIs:** Avoid `LSSharedFileListInsertItemURL` for launch at login; use `SMAppService` (macOS 13+).

### Development Setup Notes

- **Xcode Version:** 15.0+ required for Swift 5.9 and macOS 14 SDK
- **WhisperKit Dependency:** Add via Swift Package Manager in Xcode (URL: https://github.com/argmaxinc/WhisperKit)
- **Code Signing:** Required for notarization; configure in Xcode project settings
- **Entitlements:** No special entitlements needed (not sandboxed)
- **Info.plist Keys Required:**
  - `LSUIElement = true` (no Dock icon)
  - `NSMicrophoneUsageDescription = "VoxKey records audio for on-device transcription."`
  - `NSAccessibilityUsageDescription = "VoxKey needs Accessibility permission to detect hotkey and insert text."`
  - `CFBundleIdentifier = "com.yourteam.VoxKey"` (replace with your team ID)

## Implementation Plan

### Phase 1: Project Setup and Core Infrastructure

#### Task 1.1: Create Xcode Project and Configure Info.plist
- [ ] Create new macOS App project in Xcode 15+
- [ ] Set deployment target to macOS 14.0
- [ ] Set architecture to arm64 (Apple Silicon only)
- [ ] Configure Info.plist:
  - Set `LSUIElement = true`
  - Add `NSMicrophoneUsageDescription`
  - Add `NSAccessibilityUsageDescription`
  - Set bundle identifier
- [ ] Add WhisperKit via Swift Package Manager
- **Verification:** Project builds successfully, `swift build` exits with code 0

#### Task 1.2: Implement AppState Observable Model
- [ ] Create `/VoxKey/Models/AppState.swift`
- [ ] Define `State` enum: `.idle`, `.recording`, `.processing`
- [ ] Implement `@Published var currentState: State`
- [ ] Add `@MainActor` annotation for thread safety
- **Verification:** `swift test --filter AppStateTests` passes (test state transitions)

#### Task 1.3: Implement Constants Utility
- [ ] Create `/VoxKey/Utilities/Constants.swift`
- [ ] Define `kRightCtrlKeyCode: CGKeyCode = 62`
- [ ] Define model names: `whisperModels = ["tiny", "base", "small", "medium", "large"]`
- [ ] Define `clipboardRestoreDelay: TimeInterval = 0.1`
- **Verification:** File exists, constants are accessible, `grep "kRightCtrlKeyCode = 62" Constants.swift` returns match

### Phase 2: Permission Management and Onboarding

#### Task 2.1: Implement PermissionManager
- [ ] Create `/VoxKey/Managers/PermissionManager.swift`
- [ ] Implement `checkAccessibilityPermission()` using `AXIsProcessTrustedWithOptions`
- [ ] Implement `checkMicrophonePermission()` using `AVCaptureDevice.authorizationStatus`
- [ ] Implement `checkInputMonitoringPermission()` (macOS 14+ specific check)
- [ ] Implement `requestPermission(type:)` to prompt System Settings
- [ ] Implement `allPermissionsGranted() -> Bool`
- **Verification:** `swift test --filter PermissionManagerTests` passes (mock permission checks)

#### Task 2.2: Implement OnboardingView
- [ ] Create `/VoxKey/Views/OnboardingView.swift`
- [ ] SwiftUI view with checklist for three permissions
- [ ] Add "Open System Settings" buttons for each permission
- [ ] Add permission status indicators (✓ granted, ✗ denied)
- [ ] Implement dismiss logic when all permissions granted
- **Verification:** Build and run, manually test onboarding flow, all buttons functional

#### Task 2.3: Integrate Onboarding in AppDelegate
- [ ] Create `/VoxKey/App/AppDelegate.swift`
- [ ] Implement `applicationDidFinishLaunching()`
- [ ] Check permissions on launch using `PermissionManager`
- [ ] Show `OnboardingView` if any permission denied
- [ ] Proceed to normal operation if all granted
- **Verification:** Reset permissions, launch app, confirm onboarding appears

### Phase 3: Hotkey Detection and Audio Capture

#### Task 3.1: Implement HotkeyManager
- [ ] Create `/VoxKey/Managers/HotkeyManager.swift`
- [ ] Implement CGEventTap for `flagsChanged` events
- [ ] Filter for keycode 62 (Right Ctrl)
- [ ] Detect key down (flag set) and key up (flag cleared)
- [ ] Expose callbacks: `onKeyDown`, `onKeyUp`
- [ ] Install tap on main run loop
- **Verification:** `swift test --filter HotkeyManagerTests.testRightCtrlKeyDetection` passes

#### Task 3.2: Implement AudioCaptureManager
- [ ] Create `/VoxKey/Managers/AudioCaptureManager.swift`
- [ ] Setup AVAudioEngine with input node
- [ ] Configure 16kHz mono PCM format using `AVAudioFormat`
- [ ] Implement `startRecording()` to install tap and start engine
- [ ] Implement `stopRecording() -> AVAudioPCMBuffer` to return concatenated buffer
- [ ] Accumulate buffers in array during recording
- [ ] Clear buffers after stop
- **Verification:** `swift test --filter AudioCaptureManagerTests.testAudioFormat` passes (validates format and buffer accumulation)

#### Task 3.3: Wire Hotkey to Audio Capture
- [ ] In `AppDelegate` or coordinator, instantiate `HotkeyManager` and `AudioCaptureManager`
- [ ] Set `HotkeyManager.onKeyDown` to call `AudioCaptureManager.startRecording()`
- [ ] Set `HotkeyManager.onKeyUp` to call `AudioCaptureManager.stopRecording()`
- [ ] Update `AppState.currentState` to `.recording` on key down, `.processing` on key up
- **Verification:** Manual test with print statements, confirm recording starts/stops on Right Ctrl press/release

### Phase 4: Transcription Service with WhisperKit

#### Task 4.1: Implement TranscriptionService
- [ ] Create `/VoxKey/Services/TranscriptionService.swift`
- [ ] Import WhisperKit framework
- [ ] Implement `loadModel(name: String) async throws` to initialize WhisperKit
- [ ] Implement `transcribe(buffer: AVAudioPCMBuffer) async throws -> String`
- [ ] Handle model download progress with `Progress` observation
- [ ] Expose `currentModel` and `isDownloading` published properties
- **Verification:** `swift test --filter TranscriptionServiceTests.testOnDeviceTranscription` passes (uses test audio fixture)

#### Task 4.2: Integrate Transcription Pipeline
- [ ] In audio capture callback (key up), pass buffer to `TranscriptionService.transcribe()`
- [ ] Update `AppState.currentState` to `.processing` during transcription
- [ ] On transcription success, pass text to `TextInsertionManager`
- [ ] On transcription failure, post `NSUserNotification` with "Transcription failed"
- [ ] Return to `.idle` state after completion or error
- **Verification:** Manual test, record 3-second phrase, confirm transcription completes and state transitions

### Phase 5: Text Insertion

#### Task 5.1: Implement TextInsertionManager
- [ ] Create `/VoxKey/Managers/TextInsertionManager.swift`
- [ ] Implement `insertText(_ text: String)` method
- [ ] Save current clipboard contents using `NSPasteboard.general.pasteboardItems`
- [ ] Set transcribed text to clipboard
- [ ] Simulate Cmd+V using `CGEventPost` with `CGEventCreateKeyboardEvent`
- [ ] Restore original clipboard after 100ms delay
- **Verification:** `swift test --filter TextInsertionManagerTests.testClipboardRestore` passes

#### Task 5.2: Integrate Text Insertion into Pipeline
- [ ] After transcription succeeds, call `TextInsertionManager.insertText(transcribedText)`
- [ ] Ensure insertion happens on main thread
- [ ] Update `AppState` to `.idle` after insertion completes
- **Verification:** Manual test in TextEdit, dictate phrase, confirm text appears at cursor and clipboard is restored

### Phase 6: Menu Bar UI and Settings

#### Task 6.1: Implement MenuBarManager
- [ ] Create `/VoxKey/Managers/MenuBarManager.swift`
- [ ] Create `NSStatusItem` with custom icon
- [ ] Implement icon state updates: `updateIcon(state: AppState.State)`
- [ ] Load gray mic, red mic, and spinner icons from Assets.xcassets
- [ ] Construct dropdown menu with status text, Settings, and Quit items
- **Verification:** Manual test, click menu bar icon, confirm menu appears with all items

#### Task 6.2: Create Menu Bar Icons
- [ ] Create `/VoxKey/Resources/Assets.xcassets/` folder
- [ ] Add three icon sets: `mic-idle.pdf` (gray), `mic-recording.pdf` (red), `spinner.pdf` (animated)
- [ ] Ensure icons are template images (monochrome, adapt to menu bar appearance)
- [ ] Export as PDF vectors for retina support
- **Verification:** Build app, icons display correctly in light/dark menu bar modes

#### Task 6.3: Implement SettingsView
- [ ] Create `/VoxKey/Views/SettingsView.swift`
- [ ] Add SwiftUI Picker for Whisper model selection (Tiny, Base, Small, Medium, Large)
- [ ] Bind to `@AppStorage("selectedModel")`
- [ ] Show download progress bar when model is downloading
- [ ] Add "Launch at Login" Toggle bound to `@AppStorage("launchAtLogin")`
- [ ] Add permission status indicators (read-only, show current state)
- [ ] Add About section with app version (read from Bundle)
- **Verification:** Open Settings, change model, confirm UI updates and model downloads

#### Task 6.4: Implement Launch at Login
- [ ] In SettingsView, observe `launchAtLogin` changes
- [ ] Use `SMAppService.mainApp.register()` when enabled
- [ ] Use `SMAppService.mainApp.unregister()` when disabled
- [ ] Handle errors gracefully (show alert if registration fails)
- **Verification:** Enable toggle, restart Mac, confirm app auto-launches

### Phase 7: Error Handling and Edge Cases

#### Task 7.1: Implement Permission Denied Error Handling
- [ ] Add permission check before hotkey operation
- [ ] Show alert with "Open System Settings" button if permission denied mid-operation
- [ ] Add warning indicator to menu bar icon when permissions are missing
- [ ] Update menu status text to show "Permissions Required"
- **Verification:** Revoke Accessibility, attempt to record, confirm alert appears

#### Task 7.2: Implement Transcription Failure Notification
- [ ] Wrap `TranscriptionService.transcribe()` in try-catch
- [ ] On failure, post `NSUserNotification` with "Transcription failed"
- [ ] Log error details to console for debugging
- [ ] Ensure app returns to `.idle` state (remains functional)
- **Verification:** `swift test --filter TranscriptionServiceTests.testTranscriptionFailureNotification` passes

#### Task 7.3: Implement Model Download Failure Handling
- [ ] In SettingsView, observe `TranscriptionService.downloadError`
- [ ] Show error message in Settings UI when download fails
- [ ] Add "Retry" button that re-attempts download
- [ ] Disable model picker during download
- **Verification:** Simulate network error, confirm error message and Retry button appear

### Phase 8: Testing and Verification

#### Task 8.1: Write Unit Tests for Core Managers
- [ ] Create `/VoxKeyTests/HotkeyManagerTests.swift` (test keycode 62 detection)
- [ ] Create `/VoxKeyTests/AudioCaptureManagerTests.swift` (test format and buffer logic)
- [ ] Create `/VoxKeyTests/TranscriptionServiceTests.swift` (test model loading and transcription)
- [ ] Create `/VoxKeyTests/TextInsertionManagerTests.swift` (test clipboard save/restore)
- **Verification:** `swift test` exits with code 0, all tests pass

#### Task 8.2: Manual Integration Testing
- [ ] Test full recording → transcription → insertion flow with various apps (TextEdit, Notes, Chrome)
- [ ] Test permission denial scenarios (revoke each permission, attempt operation)
- [ ] Test model switching (change model in Settings, confirm new model is used)
- [ ] Test launch at login (enable, restart, confirm auto-launch)
- [ ] Test clipboard preservation (copy text, dictate, confirm original clipboard restored)
- **Verification:** Create manual test checklist, verify all scenarios pass

### Phase 9: Build and Distribution

#### Task 9.1: Create Notarization Script
- [ ] Create `/scripts/notarize.sh`
- [ ] Script steps: clean build, archive, export as DMG, sign, notarize, staple
- [ ] Use `xcrun notarytool` for notarization
- [ ] Output notarized DMG to `/build/VoxKey.dmg`
- **Verification:** Run `./scripts/notarize.sh`, confirm DMG is created and notarized (`spctl --assess` passes)

#### Task 9.2: Create README Documentation
- [ ] Create `/README.md`
- [ ] Document: setup instructions, build process, permissions required, usage guide
- [ ] Include: architecture overview, technology stack, distribution instructions
- [ ] Add: troubleshooting section for common issues
- **Verification:** File exists, contains all required sections

#### Task 9.3: Final Build and Validation
- [ ] Run full build: `swift build --configuration release`
- [ ] Test on clean macOS 14 VM (no permissions pre-granted)
- [ ] Install from DMG, complete onboarding, test full flow
- [ ] Verify no Dock icon appears (`LSUIElement` working)
- [ ] Verify Gatekeeper acceptance (no "unverified developer" warning)
- **Verification:** App installs and runs successfully on clean system without warnings

## Verification Matrix

| Req ID | Requirement | Verification | Status | Notes |
|--------|-------------|--------------|--------|-------|
| REQ-1 | Right Ctrl Hotkey Detection | `swift test --filter HotkeyManagerTests.testRightCtrlKeyDetection` | Pending | Keycode 62 detection |
| REQ-2 | Audio Capture 16kHz Mono PCM | `swift test --filter AudioCaptureManagerTests.testAudioFormat` | Pending | Format validation |
| REQ-3 | On-Device Transcription | `swift test --filter TranscriptionServiceTests.testOnDeviceTranscription` | Pending | WhisperKit integration |
| REQ-4 | Text Insertion via Clipboard | `swift test --filter TextInsertionManagerTests.testClipboardRestore` | Pending | Clipboard save/restore |
| REQ-5 | Menu Bar Icon States | Manual: Observe icon changes during operation | Pending | Gray/Red/Spinner |
| REQ-6 | Permission Checks | Manual: Reset permissions, launch app | Pending | Onboarding flow |
| REQ-7 | Whisper Model Selection | Manual: Change model in Settings | Pending | Download progress |
| REQ-8 | Launch at Login | Manual: Enable, restart, verify auto-launch | Pending | SMAppService |
| REQ-9 | Menu Bar Dropdown | Manual: Click icon, check menu items | Pending | Status/Settings/Quit |
| REQ-10 | Silent Operation | Manual: Record with volume up, no audio feedback | Pending | No sounds |
| REQ-11 | Permission Denied Handling | Manual: Revoke permission, attempt operation | Pending | Alert + warning icon |
| REQ-12 | Transcription Failure Notification | `swift test --filter TranscriptionServiceTests.testTranscriptionFailureNotification` | Pending | NSUserNotification |
| REQ-13 | Model Download Failure | Manual: Simulate network error | Pending | Retry button |
| REQ-14 | macOS 14+ Apple Silicon | `grep MACOSX_DEPLOYMENT_TARGET VoxKey.xcodeproj/project.pbxproj` | Pending | 14.0, arm64 |
| REQ-15 | No Dock Icon | `defaults read Info.plist LSUIElement` + Manual | Pending | Returns "1" |
| REQ-16 | Notarized DMG | `./scripts/notarize.sh && spctl --assess build/VoxKey.dmg` | Pending | Gatekeeper pass |

## Iteration Log

_To be filled during implementation by agents or developers_

## Final Summary

_To be filled upon completion_
