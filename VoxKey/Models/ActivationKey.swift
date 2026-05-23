import Foundation
import CoreGraphics

enum ActivationKey: CaseIterable {
    case rightControl
    case leftControl
    case rightOption
    case leftOption
    case rightCommand
    case leftCommand
    case rightShift
    case leftShift
    case capsLock
    case function

    var cgKeyCode: CGKeyCode {
        switch self {
        case .rightControl:  return 62
        case .leftControl:   return 59
        case .rightOption:   return 61
        case .leftOption:    return 58
        case .rightCommand:  return 54
        case .leftCommand:   return 55
        case .rightShift:    return 60
        case .leftShift:     return 56
        case .capsLock:      return 57
        case .function:      return 63
        }
    }

    var flagsMask: CGEventFlags {
        switch self {
        case .rightControl, .leftControl:  return .maskControl
        case .rightOption, .leftOption:    return .maskAlternate
        case .rightCommand, .leftCommand:  return .maskCommand
        case .rightShift, .leftShift:      return .maskShift
        case .capsLock:                    return .maskAlphaShift
        case .function:                    return .maskSecondaryFn
        }
    }

    var label: String {
        switch self {
        case .rightControl:  return "Right Control"
        case .leftControl:   return "Left Control"
        case .rightOption:   return "Right Option"
        case .leftOption:    return "Left Option"
        case .rightCommand:  return "Right Command"
        case .leftCommand:   return "Left Command"
        case .rightShift:    return "Right Shift"
        case .leftShift:     return "Left Shift"
        case .capsLock:      return "Caps Lock"
        case .function:      return "Function (Fn)"
        }
    }

    static func activationKey(forKeyCode keyCode: CGKeyCode) -> ActivationKey? {
        ActivationKey.allCases.first { $0.cgKeyCode == keyCode }
    }
}
