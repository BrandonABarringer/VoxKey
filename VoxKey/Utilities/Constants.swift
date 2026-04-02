import Foundation
import CoreGraphics

enum Constants {
    static let rightOptionKeyCode: CGKeyCode = 61
    static let rightCtrlKeyCode: CGKeyCode = 62
    static let activationKeyCode: CGKeyCode = 62  // Right Control (change to 61 for Right Option)
    static let clipboardRestoreDelay: TimeInterval = 0.1
    static let defaultModel = "base"
    static let whisperModels = ["tiny", "base", "small", "medium", "large-v3-turbo"]
    static let bundleIdentifier = "com.voxkey.VoxKey"
    static let defaultDictionaryTerms = ["Claude", "CLAUDE.md", "Vercel", "git", "GitHub", "Rwest", "commit", "Yanmar"]
}
