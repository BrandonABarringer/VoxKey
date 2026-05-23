import AppKit
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.voxkey.VoxKey", category: "app")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Shared state - accessible from VoxKeyApp
    let appState = AppState()
    let permissionManager = PermissionManager()
    let transcriptionService = TranscriptionService()

    // Non-UI managers
    private let hotkeyManager = HotkeyManager()
    private let audioCaptureManager = AudioCaptureManager()
    private let textInsertionManager = TextInsertionManager()
    private let mediaPauseManager = MediaPauseManager()

    // Onboarding window
    private var onboardingWindow: NSWindow?

    // Track last-applied settings so we only restart when values actually change.
    private var lastAppliedKeyCode: CGKeyCode = Constants.defaultActivationKeyCode
    private var lastAppliedMode: ActivationMode = Constants.defaultActivationMode
    private var pendingActivationRestart: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("VoxKey launched")
        permissionManager.checkAllPermissions()
        startDictationPipeline()

        // Observe UserDefaults changes to apply new activation key / mode live.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    private func startDictationPipeline() {
        logger.info("Starting dictation pipeline")

        // Load WhisperKit model
        Task {
            do {
                logger.info("Loading WhisperKit model...")
                try await transcriptionService.loadModel()
                logger.info("Model loaded successfully")
            } catch {
                logger.error("Failed to load model: \(error.localizedDescription)")
                appState.errorMessage = "Failed to load model: \(error.localizedDescription)"
            }
        }

        // Wire hotkey callbacks using semantic names
        hotkeyManager.onActivate = { [weak self] in
            logger.info("Activation key activated")
            Task { @MainActor in
                self?.handleKeyDown()
            }
        }

        hotkeyManager.onDeactivate = { [weak self] in
            logger.info("Activation key deactivated")
            Task { @MainActor in
                self?.handleKeyUp()
            }
        }

        // Record the initial configured values so we can detect changes later.
        lastAppliedKeyCode = hotkeyManager.configuredKeyCode
        lastAppliedMode = hotkeyManager.configuredMode

        // Start listening for hotkey
        let started = hotkeyManager.start()
        logger.info("Hotkey manager started: \(started)")
        if !started {
            logger.error("Hotkey manager failed to start - showing onboarding")
            appState.errorMessage = "Failed to start hotkey listener. Check Accessibility permissions."
            showOnboarding()
        }
    }

    private func handleKeyDown() {
        logger.info("handleKeyDown - state: \(String(describing: self.appState.currentState))")
        guard appState.currentState == .idle else {
            logger.info("Ignoring key down, not idle")
            return
        }

        appState.currentState = .recording

        // Pause BEFORE startRecording so the input-device-running probe in
        // MediaPauseManager doesn't see our own mic activity and misclassify it
        // as an active call.
        if shouldPauseMedia {
            mediaPauseManager.pauseIfPlaying()
        }

        do {
            try audioCaptureManager.startRecording()
            logger.info("Recording started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            if shouldPauseMedia {
                mediaPauseManager.resumeIfPaused()
            }
            appState.currentState = .idle
            appState.errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private var shouldPauseMedia: Bool {
        UserDefaults.standard.object(forKey: "pauseMediaWhileDictating") as? Bool ?? true
    }

    private func handleKeyUp() {
        logger.info("handleKeyUp - state: \(String(describing: self.appState.currentState))")
        guard appState.currentState == .recording else {
            logger.info("Ignoring key up, not recording")
            return
        }

        Task {
            let audioSamples = await audioCaptureManager.stopRecording()
            logger.info("Audio captured: \(audioSamples.count) samples (\(Double(audioSamples.count) / 16000.0)s)")

            mediaPauseManager.resumeIfPaused()

            appState.currentState = .processing

            do {
                let text = try await transcriptionService.transcribe(audioSamples: audioSamples)
                logger.info("Transcription succeeded, length=\(text.count, privacy: .public)")
                appState.lastTranscription = text
                logger.info("Before insertText, clipboard write + paste")
                textInsertionManager.insertText(text)
                logger.info("After insertText")
            } catch {
                logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                appState.errorMessage = "Transcription failed: \(error.localizedDescription)"
            }

            appState.currentState = .idle
            logger.info("State -> idle")

            // Apply any activation-config change that arrived during recording.
            if pendingActivationRestart {
                let storedKeyCodeInt = UserDefaults.standard.object(forKey: "activationKeyCode") as? Int
                let keyCode = storedKeyCodeInt.map { CGKeyCode($0) } ?? Constants.defaultActivationKeyCode
                applyActivationConfig(keyCode: keyCode, mode: ActivationMode.current)
            }
        }
    }

    private func showOnboarding() {
        NSApp.setActivationPolicy(.regular)

        let onboardingView = OnboardingView(onComplete: { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            NSApp.setActivationPolicy(.accessory)
            self?.startDictationPipeline()
        })
        .environmentObject(permissionManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoxKey Setup"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window
    }

    // MARK: - UserDefaults live-apply

    @objc private func userDefaultsDidChange(_ notification: Notification) {
        let storedKeyCodeInt = UserDefaults.standard.object(forKey: "activationKeyCode") as? Int
        let newKeyCode = storedKeyCodeInt.map { CGKeyCode($0) } ?? Constants.defaultActivationKeyCode
        let newMode = ActivationMode.current

        guard newKeyCode != lastAppliedKeyCode || newMode != lastAppliedMode else {
            return
        }

        // Defer restart if a recording is in progress — restarting the event tap
        // mid-recording drops the audio buffer. Re-apply when state returns to idle.
        guard appState.currentState == .idle else {
            logger.info("Activation config changed during recording; deferring restart")
            pendingActivationRestart = true
            return
        }

        applyActivationConfig(keyCode: newKeyCode, mode: newMode)
    }

    private func applyActivationConfig(keyCode: CGKeyCode, mode: ActivationMode) {
        logger.info("Activation config changed: keyCode=\(keyCode), mode=\(mode.rawValue)")
        let doubleTapWindowMs = UserDefaults.standard.object(forKey: "doubleTapWindowMs") as? Int
            ?? Constants.defaultDoubleTapWindowMs
        lastAppliedKeyCode = keyCode
        lastAppliedMode = mode
        pendingActivationRestart = false
        hotkeyManager.restart(keyCode: keyCode, mode: mode, doubleTapWindowMs: doubleTapWindowMs)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object: nil)
        hotkeyManager.stop()
    }
}
