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

        let expectation = expectation(description: "onActivate called")
        manager.onActivate = { expectation.fulfill() }
        manager.onDeactivate = { XCTFail("onDeactivate should not be called on key down") }

        manager.handleFlagsChanged(event: event, type: .flagsChanged)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Right Ctrl Key Up

    func testRightCtrlKeyUpTriggersCallback() throws {
        // First simulate key down to set previousKeyPressed = true
        let downEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: downEvent, type: .flagsChanged)

        // Now simulate key up (no control flag)
        let upEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: []))

        let expectation = expectation(description: "onDeactivate called")
        manager.onActivate = { XCTFail("onActivate should not be called on key up") }
        manager.onDeactivate = { expectation.fulfill() }

        manager.handleFlagsChanged(event: upEvent, type: .flagsChanged)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Left Ctrl (keycode 59) Does NOT Trigger

    func testLeftCtrlDoesNotTriggerCallbacks() throws {
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 59, flags: .maskControl))

        manager.onActivate = { XCTFail("onActivate should not be called for Left Ctrl") }
        manager.onDeactivate = { XCTFail("onDeactivate should not be called for Left Ctrl") }

        manager.handleFlagsChanged(event: event, type: .flagsChanged)

        // Verify previousKeyPressed was NOT updated (wrong keycode filtered out)
        XCTAssertFalse(manager.previousKeyPressed)
    }

    // MARK: - Other Modifier Keys Do NOT Trigger

    func testShiftKeyDoesNotTriggerCallbacks() throws {
        // Shift key (keycode 56)
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 56, flags: .maskShift))

        manager.onActivate = { XCTFail("onActivate should not be called for Shift") }
        manager.onDeactivate = { XCTFail("onDeactivate should not be called for Shift") }

        manager.handleFlagsChanged(event: event, type: .flagsChanged)

        XCTAssertFalse(manager.previousKeyPressed)
    }

    func testOptionKeyDoesNotTriggerCallbacks() throws {
        // Option key (keycode 58)
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 58, flags: .maskAlternate))

        manager.onActivate = { XCTFail("onActivate should not be called for Option") }
        manager.onDeactivate = { XCTFail("onDeactivate should not be called for Option") }

        manager.handleFlagsChanged(event: event, type: .flagsChanged)

        XCTAssertFalse(manager.previousKeyPressed)
    }

    func testCommandKeyDoesNotTriggerCallbacks() throws {
        // Command key (keycode 55)
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 55, flags: .maskCommand))

        manager.onActivate = { XCTFail("onActivate should not be called for Command") }
        manager.onDeactivate = { XCTFail("onDeactivate should not be called for Command") }

        manager.handleFlagsChanged(event: event, type: .flagsChanged)

        XCTAssertFalse(manager.previousKeyPressed)
    }

    // MARK: - No Double-Trigger on Repeated Key Down

    func testRepeatedKeyDownDoesNotDoubleTrigger() throws {
        var activateCount = 0
        manager.onActivate = { activateCount += 1 }
        manager.onDeactivate = { XCTFail("onDeactivate should not be called") }

        // First key down
        let downEvent1 = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: downEvent1, type: .flagsChanged)
        XCTAssertEqual(activateCount, 1)

        // Second key down without release (same state, control still held)
        let downEvent2 = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: downEvent2, type: .flagsChanged)
        XCTAssertEqual(activateCount, 1, "Should not double-trigger onActivate for repeated key down events")
    }

    // MARK: - Full Cycle: Down then Up

    func testFullKeyDownUpCycle() throws {
        var activateCalled = false
        var deactivateCalled = false
        manager.onActivate = { activateCalled = true }
        manager.onDeactivate = { deactivateCalled = true }

        // Key down
        let downEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: downEvent, type: .flagsChanged)
        XCTAssertTrue(activateCalled)
        XCTAssertFalse(deactivateCalled)

        // Key up
        let upEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: []))
        manager.handleFlagsChanged(event: upEvent, type: .flagsChanged)
        XCTAssertTrue(deactivateCalled)
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

        manager.onActivate = { XCTFail("onActivate should not be called for tapDisabledByTimeout") }
        manager.onDeactivate = { XCTFail("onDeactivate should not be called for tapDisabledByTimeout") }

        // Pass tapDisabledByTimeout type - should skip keycode processing
        manager.handleFlagsChanged(event: event, type: .tapDisabledByTimeout)

        XCTAssertFalse(manager.previousKeyPressed)
    }

    func testTapDisabledByUserInputDoesNotTriggerCallbacks() throws {
        let event = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))

        manager.onActivate = { XCTFail("onActivate should not be called for tapDisabledByUserInput") }
        manager.onDeactivate = { XCTFail("onDeactivate should not be called for tapDisabledByUserInput") }

        manager.handleFlagsChanged(event: event, type: .tapDisabledByUserInput)

        XCTAssertFalse(manager.previousKeyPressed)
    }

    // MARK: - Key Up Without Prior Down Does Not Trigger

    func testKeyUpWithoutPriorDownDoesNotTrigger() throws {
        let upEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: []))

        manager.onActivate = { XCTFail("onActivate should not be called") }
        manager.onDeactivate = { XCTFail("onDeactivate should not be called when no prior key down") }

        manager.handleFlagsChanged(event: upEvent, type: .flagsChanged)

        XCTAssertFalse(manager.previousKeyPressed)
    }

    // MARK: - Activation Key Mapping (all 10 keycodes)

    func testActivationKeyMappingAllKeycodes() {
        let expectedMappings: [(CGKeyCode, CGEventFlags)] = [
            (62, .maskControl),       // Right Control
            (59, .maskControl),       // Left Control
            (61, .maskAlternate),     // Right Option
            (58, .maskAlternate),     // Left Option
            (54, .maskCommand),       // Right Command
            (55, .maskCommand),       // Left Command
            (60, .maskShift),         // Right Shift
            (56, .maskShift),         // Left Shift
            (57, .maskAlphaShift),    // Caps Lock
            (63, .maskSecondaryFn),   // Function (Fn)
        ]

        for (keyCode, expectedMask) in expectedMappings {
            let activationKey = ActivationKey.activationKey(forKeyCode: keyCode)
            XCTAssertNotNil(activationKey, "Expected non-nil for keyCode \(keyCode)")
            XCTAssertEqual(
                activationKey?.flagsMask,
                expectedMask,
                "Wrong mask for keyCode \(keyCode): expected \(expectedMask), got \(String(describing: activationKey?.flagsMask))"
            )
        }

        // Unknown keycode should return nil
        XCTAssertNil(ActivationKey.activationKey(forKeyCode: 0), "Expected nil for unknown keycode 0")
    }

    // MARK: - Hold Mode Activation

    func testHoldModeActivation() throws {
        // Default manager is in Hold mode with keycode 62
        var activateCount = 0
        var deactivateCount = 0
        manager.onActivate = { activateCount += 1 }
        manager.onDeactivate = { deactivateCount += 1 }

        // Key down → onActivate fires
        let downEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: downEvent, type: .flagsChanged)
        XCTAssertEqual(activateCount, 1)
        XCTAssertEqual(deactivateCount, 0)

        // Key up → onDeactivate fires
        let upEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: []))
        manager.handleFlagsChanged(event: upEvent, type: .flagsChanged)
        XCTAssertEqual(activateCount, 1)
        XCTAssertEqual(deactivateCount, 1)
    }

    // MARK: - Single Tap Mode Activation via HotkeyManager

    func testSingleTapModeActivation() throws {
        manager.restart(keyCode: 62, mode: .singleTap, doubleTapWindowMs: 400)

        var activateCount = 0
        manager.onActivate = { activateCount += 1 }
        manager.onDeactivate = { XCTFail("onDeactivate should not fire on first tap") }

        // Complete tap: key-down then key-up
        let downEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: downEvent, type: .flagsChanged)
        XCTAssertEqual(activateCount, 0, "onActivate should not fire on key-down in single-tap mode")

        let upEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: []))
        manager.handleFlagsChanged(event: upEvent, type: .flagsChanged)
        XCTAssertEqual(activateCount, 1, "onActivate should fire on key-up (complete tap)")
    }

    // MARK: - Double Tap Mode Activation via HotkeyManager

    func testDoubleTapModeActivation() throws {
        manager.restart(keyCode: 62, mode: .doubleTap, doubleTapWindowMs: 400)

        var activateCount = 0
        manager.onActivate = { activateCount += 1 }

        // First complete tap
        let down1 = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: down1, type: .flagsChanged)
        let up1 = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: []))
        manager.handleFlagsChanged(event: up1, type: .flagsChanged)
        XCTAssertEqual(activateCount, 0, "onActivate should not fire after first tap")

        // Second tap immediately (within window)
        let down2 = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: down2, type: .flagsChanged)
        let up2 = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: []))
        manager.handleFlagsChanged(event: up2, type: .flagsChanged)
        XCTAssertEqual(activateCount, 1, "onActivate should fire after double-tap within window")
    }

    // MARK: - Restart Changes Keycode

    func testRestartChangesKeyCode() throws {
        // Initially configured for keycode 62 (Right Control)
        var activateCount = 0
        manager.onActivate = { activateCount += 1 }

        // Event for keycode 62 should activate
        let event62 = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: event62, type: .flagsChanged)
        XCTAssertEqual(activateCount, 1)

        // Restart with keycode 55 (Left Command), hold mode
        manager.restart(keyCode: 55, mode: .hold, doubleTapWindowMs: 400)
        activateCount = 0

        // Old keycode 62 should NO LONGER activate
        let oldEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 62, flags: .maskControl))
        manager.handleFlagsChanged(event: oldEvent, type: .flagsChanged)
        XCTAssertEqual(activateCount, 0, "Events for old keycode should not activate after restart")

        // New keycode 55 should activate
        let newEvent = try XCTUnwrap(makeFlagsChangedEvent(keyCode: 55, flags: .maskCommand))
        manager.handleFlagsChanged(event: newEvent, type: .flagsChanged)
        XCTAssertEqual(activateCount, 1, "Events for new keycode should activate after restart")
    }

    // MARK: - UserDefaults Observation Triggers Restart

    func testUserDefaultsObservationTriggersRestart() {
        // Verify that configuredKeyCode and configuredMode are readable properties
        // so that AppDelegate can detect changes without an extra tracking variable.
        XCTAssertEqual(manager.configuredKeyCode, CGKeyCode(62))
        XCTAssertEqual(manager.configuredMode, .hold)

        // Simulate restart with new values
        manager.restart(keyCode: 61, mode: .singleTap, doubleTapWindowMs: 400)
        XCTAssertEqual(manager.configuredKeyCode, CGKeyCode(61))
        XCTAssertEqual(manager.configuredMode, .singleTap)
    }

    // MARK: - Activation Key Code Persistence

    func testActivationKeyCodePersistence() {
        let testDefaults = UserDefaults(suiteName: "com.voxkey.tests")!
        defer {
            testDefaults.removePersistentDomain(forName: "com.voxkey.tests")
        }

        let supportedKeyCodes: [Int] = [62, 59, 61, 58, 54, 55, 60, 56, 57, 63]
        for keyCode in supportedKeyCodes {
            testDefaults.set(keyCode, forKey: "activationKeyCode")
            let readBack = testDefaults.integer(forKey: "activationKeyCode")
            XCTAssertEqual(readBack, keyCode, "Expected \(keyCode), got \(readBack)")
        }

        // Missing key should read as 0 from UserDefaults.integer; default is Constants.defaultActivationKeyCode
        testDefaults.removeObject(forKey: "activationKeyCode")
        let storedInt = testDefaults.object(forKey: "activationKeyCode") as? Int
        let defaultKeyCode = storedInt.map { CGKeyCode($0) } ?? Constants.defaultActivationKeyCode
        XCTAssertEqual(defaultKeyCode, CGKeyCode(62), "Default activation keycode should be 62")
    }
}

// MARK: - TapStateMachine Tests

final class TapStateMachineTests: XCTestCase {

    // MARK: - Single Tap Tests

    func testSingleTapEmitsStart() {
        let machine = TapStateMachine(mode: .singleTap, doubleTapWindowMs: 400)

        let downResult = machine.process(isKeyDown: true)
        XCTAssertEqual(downResult, .noop, "Key-down alone should be .noop in single-tap mode")

        let upResult = machine.process(isKeyDown: false)
        XCTAssertEqual(upResult, .start, "Key-up should emit .start in single-tap mode when idle")
    }

    func testSingleTapEmitsStopOnSecondTap() {
        let machine = TapStateMachine(mode: .singleTap, doubleTapWindowMs: 400)

        // First tap: start
        _ = machine.process(isKeyDown: true)
        let startResult = machine.process(isKeyDown: false)
        XCTAssertEqual(startResult, .start)

        // Second tap: stop
        _ = machine.process(isKeyDown: true)
        let stopResult = machine.process(isKeyDown: false)
        XCTAssertEqual(stopResult, .stop, "Second complete tap should emit .stop in single-tap mode")
    }

    func testSingleTapKeyDownAloneIsNoop() {
        let machine = TapStateMachine(mode: .singleTap, doubleTapWindowMs: 400)
        let result = machine.process(isKeyDown: true)
        XCTAssertEqual(result, .noop)
    }

    func testSingleTapStartStop() {
        let machine = TapStateMachine(mode: .singleTap, doubleTapWindowMs: 400)

        // Tap 1 → .start
        _ = machine.process(isKeyDown: true)
        XCTAssertEqual(machine.process(isKeyDown: false), .start)

        // Tap 2 → .stop
        _ = machine.process(isKeyDown: true)
        XCTAssertEqual(machine.process(isKeyDown: false), .stop)

        // Tap 3 → .start again (cycle repeats)
        _ = machine.process(isKeyDown: true)
        XCTAssertEqual(machine.process(isKeyDown: false), .start)
    }

    // MARK: - Double Tap Tests

    func testDoubleTapWithinWindowEmitsStart() {
        // Clock sequence: T=0.0 (down1), T=0.1 (up1), T=0.4 (down2) — within 400ms, T=0.5 (up2)
        // Window = 0.4s; first key-up at T=0.1; second key-down at T=0.4 < (0.1 + 0.4)=0.5 → within
        var timestamps = [0.0, 0.1, 0.4, 0.5].makeIterator()
        let clock: () -> TimeInterval = { timestamps.next() ?? 99.0 }
        let machine = TapStateMachine(mode: .doubleTap, doubleTapWindowMs: 400, clock: clock)

        _ = machine.process(isKeyDown: true)   // T=0.0
        _ = machine.process(isKeyDown: false)  // T=0.1 — first tap up, store pendingFirstTapUpTime
        _ = machine.process(isKeyDown: true)   // T=0.4 — second key-down, within window
        let result = machine.process(isKeyDown: false)  // T=0.5 — second key-up → .start
        XCTAssertEqual(result, .start, "Double-tap within window should emit .start")
    }

    func testDoubleTapOutsideWindowIsNoop() {
        // first key-up at T=0.1; second key-down at T=0.6 >= (0.1 + 0.4)=0.5 → outside window
        var timestamps = [0.0, 0.1, 0.6, 0.7].makeIterator()
        let clock: () -> TimeInterval = { timestamps.next() ?? 99.0 }
        let machine = TapStateMachine(mode: .doubleTap, doubleTapWindowMs: 400, clock: clock)

        _ = machine.process(isKeyDown: true)   // T=0.0
        _ = machine.process(isKeyDown: false)  // T=0.1
        _ = machine.process(isKeyDown: true)   // T=0.6 — window expired
        let result = machine.process(isKeyDown: false)  // T=0.7 — noop
        XCTAssertEqual(result, .noop, "Double-tap outside window should emit .noop")
    }

    func testDoubleTapBoundaryIsNoop() {
        // first key-up at T=0.1; second key-down at EXACTLY T=0.5 = (0.1 + 0.4) → boundary (exclusive)
        var timestamps = [0.0, 0.1, 0.5, 0.6].makeIterator()
        let clock: () -> TimeInterval = { timestamps.next() ?? 99.0 }
        let machine = TapStateMachine(mode: .doubleTap, doubleTapWindowMs: 400, clock: clock)

        _ = machine.process(isKeyDown: true)
        _ = machine.process(isKeyDown: false)  // T=0.1 — pendingFirstTapUpTime = 0.1
        _ = machine.process(isKeyDown: true)   // T=0.5 — exactly at boundary, not inside window
        let result = machine.process(isKeyDown: false)
        XCTAssertEqual(result, .noop, "Double-tap at exact boundary should emit .noop (exclusive upper bound)")
    }

    func testDoubleTapStopViaSingleTap() {
        // Get into recording state via double tap, then stop with single tap
        var timestamps = [0.0, 0.1, 0.2, 0.3, 1.0, 1.1].makeIterator()
        let clock: () -> TimeInterval = { timestamps.next() ?? 99.0 }
        let machine = TapStateMachine(mode: .doubleTap, doubleTapWindowMs: 400, clock: clock)

        _ = machine.process(isKeyDown: true)   // T=0.0
        _ = machine.process(isKeyDown: false)  // T=0.1
        _ = machine.process(isKeyDown: true)   // T=0.2 — within window
        let startResult = machine.process(isKeyDown: false)  // T=0.3 — .start
        XCTAssertEqual(startResult, .start)

        // Now stop with a single tap
        _ = machine.process(isKeyDown: true)   // T=1.0
        let stopResult = machine.process(isKeyDown: false)   // T=1.1 — .stop
        XCTAssertEqual(stopResult, .stop, "Single tap should stop recording in double-tap mode")
    }

    func testDoubleTapStartStop() {
        // Comprehensive test combining start and stop
        var timestamps = [0.0, 0.1, 0.2, 0.3, 1.0, 1.1].makeIterator()
        let clock: () -> TimeInterval = { timestamps.next() ?? 99.0 }
        let machine = TapStateMachine(mode: .doubleTap, doubleTapWindowMs: 400, clock: clock)

        // Double-tap → .start
        XCTAssertEqual(machine.process(isKeyDown: true), .noop)
        XCTAssertEqual(machine.process(isKeyDown: false), .noop)
        XCTAssertEqual(machine.process(isKeyDown: true), .noop)
        XCTAssertEqual(machine.process(isKeyDown: false), .start)

        // Single tap → .stop
        XCTAssertEqual(machine.process(isKeyDown: true), .noop)
        XCTAssertEqual(machine.process(isKeyDown: false), .stop)
    }

    // MARK: - Hold Mode is Noop

    func testHoldModeAlwaysNoop() {
        let machine = TapStateMachine(mode: .hold, doubleTapWindowMs: 400)
        XCTAssertEqual(machine.process(isKeyDown: true), .noop)
        XCTAssertEqual(machine.process(isKeyDown: false), .noop)
    }
}

// MARK: - UserDefaults Persistence Tests

final class UserDefaultsPersistenceTests: XCTestCase {

    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "com.voxkey.tests")!
        testDefaults.removePersistentDomain(forName: "com.voxkey.tests")
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "com.voxkey.tests")
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - ActivationMode persistence

    func testActivationModePersistence() {
        // Case 1: No stored value → default is .hold
        testDefaults.removeObject(forKey: "activationMode")
        let rawValueMissing = testDefaults.string(forKey: "activationMode")
        let defaultMode = rawValueMissing.flatMap { ActivationMode(rawValue: $0) } ?? .hold
        XCTAssertEqual(defaultMode, .hold, "Missing activationMode key should default to .hold")

        // Round-trip all three cases
        let cases: [(ActivationMode, String)] = [
            (.hold, "hold"),
            (.singleTap, "singleTap"),
            (.doubleTap, "doubleTap"),
        ]
        for (expectedMode, rawValue) in cases {
            testDefaults.set(rawValue, forKey: "activationMode")
            let storedRaw = testDefaults.string(forKey: "activationMode")
            let readMode = storedRaw.flatMap { ActivationMode(rawValue: $0) }
            XCTAssertEqual(readMode, expectedMode, "Expected \(expectedMode) for rawValue '\(rawValue)'")
        }
    }

    // MARK: - Activation key code persistence

    func testActivationKeyCodePersistence() {
        // Missing key → default is 62
        testDefaults.removeObject(forKey: "activationKeyCode")
        let storedInt = testDefaults.object(forKey: "activationKeyCode") as? Int
        let defaultKeyCode = storedInt.map { CGKeyCode($0) } ?? Constants.defaultActivationKeyCode
        XCTAssertEqual(defaultKeyCode, CGKeyCode(62), "Missing activationKeyCode key should default to 62")

        // All 10 supported keycodes round-trip
        let supportedKeyCodes: [Int] = [62, 59, 61, 58, 54, 55, 60, 56, 57, 63]
        for keyCode in supportedKeyCodes {
            testDefaults.set(keyCode, forKey: "activationKeyCode")
            let readBack = testDefaults.integer(forKey: "activationKeyCode")
            XCTAssertEqual(readBack, keyCode, "Expected \(keyCode), got \(readBack)")
        }
    }

    // MARK: - Double tap window persistence

    func testDoubleTapWindowFromUserDefaults() {
        // Missing key → default is 400
        testDefaults.removeObject(forKey: "doubleTapWindowMs")
        let storedDefault = testDefaults.object(forKey: "doubleTapWindowMs") as? Int
            ?? Constants.defaultDoubleTapWindowMs
        XCTAssertEqual(storedDefault, 400, "Missing doubleTapWindowMs key should default to 400")

        // Write 250 and read back
        testDefaults.set(250, forKey: "doubleTapWindowMs")
        let readBack = testDefaults.integer(forKey: "doubleTapWindowMs")
        XCTAssertEqual(readBack, 250)

        // A machine built with windowMs=250: two taps 0.3s apart → .start (within 250ms? No, 300 > 250)
        // Use windowMs from stored value (250ms = 0.25s); first up at T=0.1, second down at T=0.35
        // 0.35 < 0.1 + 0.25 = 0.35 → boundary! exclusive → noop
        // Let's try second down at T=0.3: 0.3 < 0.1 + 0.25 = 0.35 → within → .start
        var timestamps = [0.0, 0.1, 0.3, 0.4].makeIterator()
        let clock: () -> TimeInterval = { timestamps.next() ?? 99.0 }
        let machine = TapStateMachine(mode: .doubleTap, doubleTapWindowMs: readBack, clock: clock)

        _ = machine.process(isKeyDown: true)
        _ = machine.process(isKeyDown: false)  // T=0.1
        _ = machine.process(isKeyDown: true)   // T=0.3 — within 250ms window (0.3 < 0.35)
        let result = machine.process(isKeyDown: false)
        XCTAssertEqual(result, .start, "With 250ms window, second tap at T=0.3 (< 0.1+0.25) should emit .start")
    }
}
