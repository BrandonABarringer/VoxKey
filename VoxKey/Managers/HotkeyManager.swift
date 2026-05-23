import Foundation
import CoreGraphics
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.voxkey.VoxKey", category: "hotkey")

final class HotkeyManager {
    // MARK: - Semantic callbacks

    /// Called when the activation key is pressed (Hold mode: key-down; tap modes: complete tap or double-tap).
    var onActivate: (() -> Void)?

    /// Called when the activation key is released (Hold mode: key-up; tap modes: complete tap when recording).
    var onDeactivate: (() -> Void)?

    // MARK: - Private tap state

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var isRunning: Bool = false

    // MARK: - Configuration

    /// The keycode currently being monitored. Updated by `restart(keyCode:mode:doubleTapWindowMs:)`.
    private(set) var configuredKeyCode: CGKeyCode
    /// The activation mode currently in use. Updated by `restart(keyCode:mode:doubleTapWindowMs:)`.
    private(set) var configuredMode: ActivationMode

    // MARK: - Key-state tracking

    /// `true` while the configured key's modifier flag is set. Used in Hold mode to
    /// detect transitions (key-down: false → true; key-up: true → false).
    private(set) var previousKeyPressed: Bool = false

    // MARK: - Tap state machine (single/double tap modes only)

    private var tapStateMachine: TapStateMachine?

    // MARK: - Init

    init() {
        let storedKeyCode = UserDefaults.standard.object(forKey: "activationKeyCode") as? Int
        configuredKeyCode = storedKeyCode.map { CGKeyCode($0) } ?? Constants.defaultActivationKeyCode
        configuredMode = ActivationMode.current
    }

    // MARK: - Start / Stop

    func start() -> Bool {
        guard !isRunning else { return true }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else {
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                manager.handleFlagsChanged(event: event, type: type)
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPointer
        ) else {
            logger.error("Failed to create CGEventTap")
            return false
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        // Run the event tap on a dedicated background thread so SwiftUI's
        // main run loop cannot starve it of events (fixes launch-via-open issue).
        let thread = Thread { [weak self] in
            guard let self = self, let source = self.runLoopSource else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            logger.info("Event tap thread running")
            CFRunLoopRun()
            logger.info("Event tap thread exited")
        }
        thread.name = "com.voxkey.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.tapThread = thread

        isRunning = true
        return true
    }

    func stop() {
        guard isRunning else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let rl = tapRunLoop {
            CFRunLoopStop(rl)
        }
        if let source = runLoopSource, let rl = tapRunLoop {
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        isRunning = false
        previousKeyPressed = false
    }

    // MARK: - Restart with new configuration

    /// Tears down the existing CGEventTap and starts a new one with the given
    /// keycode, activation mode, and double-tap window.
    ///
    /// - Parameters:
    ///   - keyCode: The new keycode to monitor.
    ///   - mode: The new activation mode.
    ///   - doubleTapWindowMs: Double-tap detection window in milliseconds.
    ///
    /// This method must be called on the main actor (AppDelegate is @MainActor).
    /// It does NOT call `onActivate` or `onDeactivate`; any in-flight recording
    /// state is the caller's responsibility.
    func restart(keyCode: CGKeyCode, mode: ActivationMode, doubleTapWindowMs: Int) {
        logger.info("HotkeyManager restarting: keyCode=\(keyCode), mode=\(mode.rawValue)")
        stop()
        configuredKeyCode = keyCode
        configuredMode = mode
        // Reset the tap state machine so a fresh one is created on the next event.
        tapStateMachine = nil
        _ = start()
    }

    // MARK: - Event handling (internal for testability)

    // Internal access for testability (CGEventTap requires Accessibility permissions
    // which are not available in CI, so tests call this directly with mock CGEvents).
    func handleFlagsChanged(event: CGEvent, type: CGEventType) {
        // Re-enable the tap if macOS disabled it due to timeout or user input.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.warning("Event tap was disabled by system, re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Filter: only process events for the currently configured key.
        guard CGKeyCode(keyCode) == configuredKeyCode else { return }

        // Table-driven flag lookup: resolve the correct CGEventFlags mask for the
        // configured key. Returns early if the keycode is not in the supported set
        // (should not happen in practice since we set configuredKeyCode from ActivationKey).
        guard let activationKey = ActivationKey.activationKey(forKeyCode: CGKeyCode(keyCode)) else { return }

        let currentFlags = event.flags
        let keyPressed = currentFlags.contains(activationKey.flagsMask)

        switch configuredMode {
        case .hold:
            // In Hold mode, fire callbacks on transitions only (edge detection).
            if keyPressed && !previousKeyPressed {
                onActivate?()
            } else if !keyPressed && previousKeyPressed {
                onDeactivate?()
            }
            previousKeyPressed = keyPressed

        case .singleTap, .doubleTap:
            // In tap modes, only process actual flag transitions to avoid duplicate events.
            guard keyPressed != previousKeyPressed else { return }
            previousKeyPressed = keyPressed

            // Lazily create the tap state machine on first use so that restart() can
            // nil it out to get a clean state.
            if tapStateMachine == nil {
                let windowMs = UserDefaults.standard.object(forKey: "doubleTapWindowMs") as? Int
                    ?? Constants.defaultDoubleTapWindowMs
                tapStateMachine = TapStateMachine(mode: configuredMode, doubleTapWindowMs: windowMs)
            }

            let action = tapStateMachine!.process(isKeyDown: keyPressed)
            switch action {
            case .start:  onActivate?()
            case .stop:   onDeactivate?()
            case .noop:   break
            }
        }
    }

    deinit {
        stop()
    }
}
