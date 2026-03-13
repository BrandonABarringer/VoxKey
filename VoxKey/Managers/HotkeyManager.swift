import Foundation
import CoreGraphics
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.voxkey.VoxKey", category: "hotkey")

final class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private(set) var previousControlDown: Bool = false
    private var isRunning: Bool = false

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
        previousControlDown = false
    }

    // Internal access for testability (CGEventTap requires accessibility permissions
    // which are not available in CI, so tests call this directly with mock CGEvents)
    func handleFlagsChanged(event: CGEvent, type: CGEventType) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.warning("Event tap was disabled by system, re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Constants.rightCtrlKeyCode else { return }

        let currentFlags = event.flags
        let controlDown = currentFlags.contains(.maskControl)

        if controlDown && !previousControlDown {
            onKeyDown?()
        } else if !controlDown && previousControlDown {
            onKeyUp?()
        }

        previousControlDown = controlDown
    }

    deinit {
        stop()
    }
}
