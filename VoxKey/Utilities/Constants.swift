import Foundation
import CoreGraphics

enum Constants {
    // MARK: - Activation Key Defaults

    /// Default activation keycode: Right Control (62).
    /// This value is used when no `"activationKeyCode"` entry exists in `UserDefaults`.
    static let defaultActivationKeyCode: CGKeyCode = 62

    /// Default activation mode: Hold.
    /// This value is used when no `"activationMode"` entry exists in `UserDefaults`.
    static let defaultActivationMode: ActivationMode = .hold

    /// Default double-tap detection window in milliseconds.
    /// This value is used when no `"doubleTapWindowMs"` entry exists in `UserDefaults`.
    static let defaultDoubleTapWindowMs: Int = 400

    // MARK: - App Settings

    static let clipboardRestoreDelay: TimeInterval = 0.25
    static let defaultModel = "base"
    static let whisperModels = ["tiny", "base", "small", "medium", "large-v3-turbo"]
    static let bundleIdentifier = "com.voxkey.VoxKey"
    static let defaultDictionaryTerms = ["Claude", "CLAUDE.md", "Vercel", "git", "GitHub", "Rwest", "commit", "Yanmar"]
}
