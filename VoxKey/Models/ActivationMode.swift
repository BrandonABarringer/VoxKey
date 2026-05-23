import Foundation

/// Determines how the activation key triggers dictation.
///
/// The raw string values are persisted to `UserDefaults` under `"activationMode"`.
enum ActivationMode: String, CaseIterable {
    /// Hold the key to record; release to stop. This is the default.
    case hold = "hold"

    /// Tap once to start recording; tap again to stop.
    case singleTap = "singleTap"

    /// Double-tap to start recording; tap once to stop.
    case doubleTap = "doubleTap"

    /// Human-readable label for the Settings UI picker.
    var label: String {
        switch self {
        case .hold:       return "Hold"
        case .singleTap:  return "Single Tap"
        case .doubleTap:  return "Double Tap"
        }
    }

    /// Brief description shown in the Settings UI below each mode option.
    var modeDescription: String {
        switch self {
        case .hold:
            return "Hold the key while speaking; release to transcribe."
        case .singleTap:
            return "Tap once to start recording; tap again to stop."
        case .doubleTap:
            return "Double-tap to start recording; tap once to stop."
        }
    }

    /// Reads the current activation mode from `UserDefaults.standard`.
    ///
    /// Returns `.hold` if no value has been stored or if the stored string
    /// does not correspond to a known case.
    static var current: ActivationMode {
        guard let rawValue = UserDefaults.standard.string(forKey: "activationMode"),
              let mode = ActivationMode(rawValue: rawValue) else {
            return .hold
        }
        return mode
    }
}
