import XCTest
import AppKit
@testable import VoxKey

final class TextInsertionManagerTests: XCTestCase {

    var sut: TextInsertionManager!

    override func setUp() {
        super.setUp()
        sut = TextInsertionManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - insertText with empty string

    func testInsertTextWithEmptyStringDoesNothing() {
        // Inserting empty text should return immediately without crashing
        // and should not modify the clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        sut.insertText("")

        // Clipboard should remain unchanged
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    // MARK: - savePasteboard / restorePasteboard round-trip

    func testSaveAndRestorePreservesStringContent() {
        let pasteboard = NSPasteboard.general
        let originalText = "clipboard content to preserve"

        // Set up known clipboard state
        pasteboard.clearContents()
        pasteboard.setString(originalText, forType: .string)

        // Save current state
        let saved = sut.savePasteboard(pasteboard)
        XCTAssertFalse(saved.isEmpty, "Saved items should not be empty")

        // Modify clipboard (simulating what insertText does)
        pasteboard.clearContents()
        pasteboard.setString("temporary transcription text", forType: .string)
        XCTAssertEqual(pasteboard.string(forType: .string), "temporary transcription text")

        // Restore original state
        sut.restorePasteboard(pasteboard, items: saved)

        // Verify original content is restored
        XCTAssertEqual(pasteboard.string(forType: .string), originalText)
    }

    func testSaveAndRestoreHandlesEmptyPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let saved = sut.savePasteboard(pasteboard)

        // Restoring empty saved items should not crash
        sut.restorePasteboard(pasteboard, items: saved)

        // Pasteboard should still be empty (no string content)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testRestoreWithEmptyItemsArrayClearsPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("some text", forType: .string)

        // Restoring with empty array should clear the pasteboard
        sut.restorePasteboard(pasteboard, items: [])

        XCTAssertNil(pasteboard.string(forType: .string))
    }

    // MARK: - Paste simulation note

    // NOTE: Cannot test simulatePaste() in unit tests because it requires:
    // - A running GUI application with event loop
    // - Accessibility permissions granted to the test runner
    // - A focused text input field to receive the paste
    // Paste simulation must be verified via manual integration testing.
}
