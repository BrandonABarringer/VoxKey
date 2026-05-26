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

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("VoxKey launched")
        permissionManager.checkAllPermissions()
        startDictationPipeline()
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

        // Wire hotkey callbacks
        hotkeyManager.onKeyDown = { [weak self] in
            logger.info("Right Ctrl DOWN")
            Task { @MainActor in
                self?.handleKeyDown()
            }
        }

        hotkeyManager.onKeyUp = { [weak self] in
            logger.info("Right Ctrl UP")
            Task { @MainActor in
                self?.handleKeyUp()
            }
        }

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
                logger.info("Transcription: '\(text)'")
                appState.lastTranscription = text
                textInsertionManager.insertText(text)
            } catch {
                logger.error("Transcription failed: \(error.localizedDescription)")
                appState.errorMessage = "Transcription failed: \(error.localizedDescription)"
            }

            appState.currentState = .idle
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

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
    }
}
