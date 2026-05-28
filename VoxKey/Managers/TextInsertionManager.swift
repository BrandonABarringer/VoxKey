import Foundation
import AppKit
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.voxkey.VoxKey", category: "insert")

final class TextInsertionManager {

    func insertText(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general

        // 1. Save current clipboard contents (all types)
        let savedItems = savePasteboard(pasteboard)
        logger.info("Saved \(savedItems.count, privacy: .public) clipboard items")

        // 2. Set transcribed text to clipboard
        pasteboard.clearContents()
        let writeSucceeded = pasteboard.setString(text, forType: .string)
        logger.info("Clipboard write: \(writeSucceeded ? "OK" : "FAILED", privacy: .public), len=\(text.count, privacy: .public)")

        // Verify the clipboard actually holds the text we just wrote.
        let verify = pasteboard.string(forType: .string) ?? "<nil>"
        let verifyOK = verify == text
        logger.info("Clipboard verify: \(verifyOK ? "match" : "MISMATCH", privacy: .public), read-len=\(verify.count, privacy: .public)")

        // 3. Simulate Cmd+V
        simulatePaste()
        logger.info("Posted Cmd+V events")

        // 4. Restore clipboard after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.clipboardRestoreDelay) {
            self.restorePasteboard(pasteboard, items: savedItems)
            logger.info("Clipboard restored")
        }
    }

    // Save all pasteboard items with their types and data
    // Internal access for testing
    func savePasteboard(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        var saved: [[(NSPasteboard.PasteboardType, Data)]] = []
        guard let items = pasteboard.pasteboardItems else { return saved }

        for item in items {
            var itemData: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData.append((type, data))
                }
            }
            saved.append(itemData)
        }
        return saved
    }

    // Restore all pasteboard items
    // Internal access for testing
    func restorePasteboard(_ pasteboard: NSPasteboard, items: [[(NSPasteboard.PasteboardType, Data)]]) {
        pasteboard.clearContents()

        guard !items.isEmpty else { return }

        var pasteboardItems: [NSPasteboardItem] = []
        for itemData in items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboardItems.append(item)
        }
        pasteboard.writeObjects(pasteboardItems)
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Key code for 'v' is 0x09 (9)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
