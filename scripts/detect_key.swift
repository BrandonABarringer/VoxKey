import CoreGraphics
import Foundation

print("Press any key to see its keycode. Press Ctrl+C to quit.")
print("Listening for ALL keyboard events...\n")

let eventMask = (1 << CGEventType.keyDown.rawValue) |
                (1 << CGEventType.keyUp.rawValue) |
                (1 << CGEventType.flagsChanged.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask(eventMask),
    callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        switch type {
        case .flagsChanged:
            var modifiers: [String] = []
            if flags.contains(.maskControl) { modifiers.append("Control") }
            if flags.contains(.maskShift) { modifiers.append("Shift") }
            if flags.contains(.maskAlternate) { modifiers.append("Option") }
            if flags.contains(.maskCommand) { modifiers.append("Command") }
            print("flagsChanged | keyCode: \(keyCode) | modifiers: \(modifiers.joined(separator: ", "))")
        case .keyDown:
            print("keyDown      | keyCode: \(keyCode)")
        case .keyUp:
            print("keyUp        | keyCode: \(keyCode)")
        default:
            break
        }

        return Unmanaged.passRetained(event)
    },
    userInfo: nil
) else {
    print("ERROR: Failed to create event tap. Check Accessibility/Input Monitoring permissions.")
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("Tap created successfully. Waiting for key events...\n")
CFRunLoopRun()
