import XCTest
import CoreGraphics
@testable import VoxKey

final class HotkeyManagerTests: XCTestCase {

    var manager: HotkeyManager!

    override func setUp() {
        super.setUp()
        manager = HotkeyManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Helper

    /// Creates a mock CGEvent simulating a flagsChanged event with the given keycode and flags.
    private func makeFlagsChangedEvent(keyCode: CGKeyCode, flags: CGEventFlags) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        event.type = .flagsChanged
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
        event.flags = flags
        return event
    }

    // MARK: - Right Ctrl Key Down

    func testRightCtrlKeyDownTriggersCallback() throws {
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))

        let expectation = expectation(description: "onKeyDown called")
        manager.onKeyDown = { expectation.fulfill() }
        manager.onKeyUp = { XCTFail("onKeyUp should not be called on key down") }

        manager.handleFlagsChanged(event: event, type: .flagsChanged)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Right Ctrl Key Up

    func testRightCtrlKeyUpTriggersCallback() throws {
        // First simulate key down to set previousControlDown = true
        let downEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: downEvent, type: .flagsChanged)

        // Now simulate key up (no control flag)
        let upEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: []))

        let expectation = expectation(description: "onKeyUp called")
        manager.onKeyDown = { XCTFail("onKeyDown should not be called on key up") }
        manager.onKeyUp = { expectation.fulfill() }

        manager.handleFlagsChanged(event: upEvent, type: .flagsChanged)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Left Ctrl (keycode 59) Does NOT Trigger

    func testLeftCtrlDoesNotTriggerCallbacks() throws {
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 59, flags: .maskControl))

        manager.onKeyDown = { XCTFail("onKeyDown should not be called for Left Ctrl") }
        manager.onKeyUp = { XCTFail("onKeyUp should not be called for Left Ctrl") }

        manager.handleFlagsChanged(event: event, type: .flagsChanged)

        // Verify previousControlDown was NOT updated
        XCTAssertFalse(manager.previousControlDown)
    }

    // MARK: - Other Modifier Keys Do NOT Trigger

    func testShiftKeyDoesNotTriggerCallbacks() throws {
        // Shift key (keycode 56)
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 56, flags: .maskShift))

        manager.onKeyDown = { XCTFail("onKeyDown should not be called for Shift") }
        manager.onKeyUp = { XCTFail("onKeyUp should not be called for Shift") }

        manager.handleFlagsChanged(event: event, type: .flagsChanged)

        XCTAssertFalse(manager.previousControlDown)
    }

    func testOptionKeyDoesNotTriggerCallbacks() throws {
        // Option key (keycode 58)
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 58, flags: .maskAlternate))

        manager.onKeyDown = { XCTFail("onKeyDown should not be called for Option") }
        manager.onKeyUp = { XCTFail("onKeyUp should not be called for Option") }

        manager.handleFlagsChanged(event: event, type: .flagsChanged)

        XCTAssertFalse(manager.previousControlDown)
    }

    func testCommandKeyDoesNotTriggerCallbacks() throws {
        // Command key (keycode 55)
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 55, flags: .maskCommand))

        manager.onKeyDown = { XCTFail("onKeyDown should not be called for Command") }
        manager.onKeyUp = { XCTFail("onKeyUp should not be called for Command") }

        manager.handleFlagsChanged(event: event, type: .flagsChanged)

        XCTAssertFalse(manager.previousControlDown)
    }

    // MARK: - No Double-Trigger on Repeated Key Down

    func testRepeatedKeyDownDoesNotDoubleTrigger() throws {
        var keyDownCount = 0
        manager.onKeyDown = { keyDownCount += 1 }
        manager.onKeyUp = { XCTFail("onKeyUp should not be called") }

        // First key down
        let downEvent1 = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: downEvent1, type: .flagsChanged)
        XCTAssertEqual(keyDownCount, 1)

        // Second key down without release (same state, control still held)
        let downEvent2 = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: downEvent2, type: .flagsChanged)
        XCTAssertEqual(keyDownCount, 1, "Should not double-trigger onKeyDown for repeated key down events")
    }

    // MARK: - Full Cycle: Down then Up

    func testFullKeyDownUpCycle() throws {
        var downCalled = false
        var upCalled = false
        manager.onKeyDown = { downCalled = true }
        manager.onKeyUp = { upCalled = true }

        // Key down
        let downEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: downEvent, type: .flagsChanged)
        XCTAssertTrue(downCalled)
        XCTAssertFalse(upCalled)

        // Key up
        let upEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: []))
        manager.handleFlagsChanged(event: upEvent, type: .flagsChanged)
        XCTAssertTrue(upCalled)
    }

    // MARK: - start() Returns False Without Accessibility

    func testStartReturnsFalseWithoutAccessibility() {
        // In CI/test environments, AXIsProcessTrusted() returns false
        // unless the app has been explicitly granted Accessibility.
        // We can only validate the return value; if trusted, skip.
        let result = manager.start()
        if !AXIsProcessTrusted() {
            XCTAssertFalse(result, "start() should return false when accessibility is not granted")
        } else {
            // If somehow trusted (e.g., local dev), just verify it returns true
            XCTAssertTrue(result)
            manager.stop()
        }
    }

    // MARK: - Tap Disabled Re-enable

    func testTapDisabledByTimeoutDoesNotTriggerCallbacks() throws {
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))

        manager.onKeyDown = { XCTFail("onKeyDown should not be called for tapDisabledByTimeout") }
        manager.onKeyUp = { XCTFail("onKeyUp should not be called for tapDisabledByTimeout") }

        // Pass tapDisabledByTimeout type - should skip keycode processing
        manager.handleFlagsChanged(event: event, type: .tapDisabledByTimeout)

        XCTAssertFalse(manager.previousControlDown)
    }

    func testTapDisabledByUserInputDoesNotTriggerCallbacks() throws {
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))

        manager.onKeyDown = { XCTFail("onKeyDown should not be called for tapDisabledByUserInput") }
        manager.onKeyUp = { XCTFail("onKeyUp should not be called for tapDisabledByUserInput") }

        manager.handleFlagsChanged(event: event, type: .tapDisabledByUserInput)

        XCTAssertFalse(manager.previousControlDown)
    }

    // MARK: - Key Up Without Prior Down Does Not Trigger

    func testKeyUpWithoutPriorDownDoesNotTrigger() throws {
        let upEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: []))

        manager.onKeyDown = { XCTFail("onKeyDown should not be called") }
        manager.onKeyUp = { XCTFail("onKeyUp should not be called when no prior key down") }

        manager.handleFlagsChanged(event: upEvent, type: .flagsChanged)

        XCTAssertFalse(manager.previousControlDown)
    }
}
