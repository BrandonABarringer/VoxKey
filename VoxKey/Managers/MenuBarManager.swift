import AppKit
import SwiftUI

@MainActor
final class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?

    @Published var currentState: AppState.DictationState = .idle

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: .idle)
    }

    func updateIcon(for state: AppState.DictationState) {
        currentState = state
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let accessibilityLabel: String

        switch state {
        case .idle:
            symbolName = "mic"
            accessibilityLabel = "VoxKey - Ready"
        case .recording:
            symbolName = "mic.fill"
            accessibilityLabel = "VoxKey - Recording"
        case .processing:
            symbolName = "ellipsis.circle"
            accessibilityLabel = "VoxKey - Processing"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        image?.isTemplate = true
        button.image = image
        button.toolTip = accessibilityLabel
    }

    func setMenu(_ menu: NSMenu) {
        statusItem?.menu = menu
    }

    var statusText: String {
        switch currentState {
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .processing: return "Processing..."
        }
    }
}
