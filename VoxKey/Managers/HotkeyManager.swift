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

    /// Signaled by the tap thread once `CFRunLoopRun()` returns (i.e. the thread is
    /// actually exiting). `stop()` waits on it so that, by the time `stop()` returns,
    /// the background thread can no longer be inside `handleFlagsChanged` reading the
    /// configuration. This is what makes `restart()`'s subsequent config writes safe.
    private var threadExitSemaphore: DispatchSemaphore?

    // MARK: - Configuration

    /// The keycode currently being monitored. Updated by `restart(keyCode:mode:doubleTapWindowMs:)`.
    private(set) var configuredKeyCode: CGKeyCode
    /// The activation mode currently in use. Updated by `restart(keyCode:mode:doubleTapWindowMs:)`.
    private(set) var configuredMode: ActivationMode
    /// Double-tap detection window in milliseconds. Updated by `restart(keyCode:mode:doubleTapWindowMs:)`
    /// and used when lazily creating the `TapStateMachine`, so the manager owns this
    /// config rather than reading `UserDefaults` at event time.
    private(set) var configuredDoubleTapWindowMs: Int

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
        configuredDoubleTapWindowMs = UserDefaults.standard.object(forKey: "doubleTapWindowMs") as? Int
            ?? Constants.defaultDoubleTapWindowMs
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

        let exitSemaphore = DispatchSemaphore(value: 0)
        threadExitSemaphore = exitSemaphore

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
            // Unblock stop(): the run loop has returned, so this thread will no
            // longer enter handleFlagsChanged.
            exitSemaphore.signal()
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
        if let source = runLoopSource, let rl = tapRunLoop {
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        if let rl = tapRunLoop {
            CFRunLoopStop(rl)
        }
        // Block until the tap thread has actually exited its run loop. CFRunLoopStop
        // is non-blocking, so without this wait the thread could still be inside
        // handleFlagsChanged while restart() mutates configuration below — a data
        // race on the dedicated-tap-thread invariant.
        //
        // This is a synchronous wait on the main thread, but it is a cold path:
        // stop()/restart() only run on an activation-setting change while idle (a
        // recording in progress defers the restart — see AppDelegate), never on the
        // per-keypress hot path. In practice the run loop returns within a run-loop
        // iteration of CFRunLoopStop, so the wait is sub-millisecond; the 0.2s is only
        // a ceiling guarding the case where the thread never started (e.g. start()
        // failed to create the tap, so the semaphore is never signaled).
        _ = threadExitSemaphore?.wait(timeout: .now() + 0.2)
        threadExitSemaphore = nil
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
    ///
    /// - Returns: `true` if the new event tap started successfully. `false` means the
    ///   tap could not be re-created (e.g. permissions became invalid) and the hotkey
    ///   is now inactive — the caller should surface this rather than leave the user
    ///   with a silently dead hotkey. The new configuration is still recorded and
    ///   persisted regardless, so a relaunch recovers it.
    @discardableResult
    func restart(keyCode: CGKeyCode, mode: ActivationMode, doubleTapWindowMs: Int) -> Bool {
        logger.info("HotkeyManager restarting: keyCode=\(keyCode), mode=\(mode.rawValue)")
        stop()
        configuredKeyCode = keyCode
        configuredMode = mode
        configuredDoubleTapWindowMs = doubleTapWindowMs
        // Reset the tap state machine so a fresh one is created on the next event.
        tapStateMachine = nil
        return start()
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
                tapStateMachine = TapStateMachine(mode: configuredMode, doubleTapWindowMs: configuredDoubleTapWindowMs)
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
