import Foundation

enum TapAction {
    case start
    case stop
    case noop
}

/// Converts raw key-down / key-up events into semantic `start` / `stop` actions
/// for Single Tap and Double Tap activation modes.
///
/// Hold mode is handled directly by `HotkeyManager` and never reaches this machine.
final class TapStateMachine {

    /// All possible states for both tap modes, expressed explicitly so transitions
    /// are correct-by-inspection.
    private enum State {
        /// No key activity in flight.
        case idle
        /// (Double tap only) First complete tap finished at this time; waiting for
        /// a second key-down within the window to confirm the double tap.
        case awaitingSecondTapDown(firstUpTime: TimeInterval)
        /// (Double tap only) Second key-down arrived within the window; waiting
        /// for the matching key-up to emit `.start`.
        case confirmedDoubleTapDown
        /// Recording is active; the next complete tap will emit `.stop`.
        case recording
    }

    private let mode: ActivationMode
    private let windowSeconds: Double
    private let clock: () -> TimeInterval
    private var state: State = .idle

    init(
        mode: ActivationMode,
        doubleTapWindowMs: Int = Constants.defaultDoubleTapWindowMs,
        clock: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.mode = mode
        self.windowSeconds = Double(doubleTapWindowMs) / 1000.0
        self.clock = clock
    }

    func process(isKeyDown: Bool) -> TapAction {
        switch mode {
        case .hold:
            return .noop
        case .singleTap:
            return processSingleTap(isKeyDown: isKeyDown)
        case .doubleTap:
            return processDoubleTap(isKeyDown: isKeyDown)
        }
    }

    // MARK: - Single Tap

    private func processSingleTap(isKeyDown: Bool) -> TapAction {
        // Single tap: act on key-up only (a complete tap).
        guard !isKeyDown else { return .noop }

        switch state {
        case .idle:
            state = .recording
            return .start
        case .recording:
            state = .idle
            return .stop
        case .awaitingSecondTapDown, .confirmedDoubleTapDown:
            // Unreachable in single-tap mode.
            state = .idle
            return .noop
        }
    }

    // MARK: - Double Tap

    private func processDoubleTap(isKeyDown: Bool) -> TapAction {
        switch (state, isKeyDown) {

        // First key-down of a potential tap.
        case (.idle, true):
            return .noop

        // First key-up — record time and wait for a second key-down.
        case (.idle, false):
            state = .awaitingSecondTapDown(firstUpTime: clock())
            return .noop

        // Second key-down. Confirm if within window; otherwise restart the cycle.
        case (.awaitingSecondTapDown(let firstUpTime), true):
            if clock() < firstUpTime + windowSeconds {
                state = .confirmedDoubleTapDown
            } else {
                // Window expired: treat as a fresh first tap.
                state = .idle
            }
            return .noop

        // Stale key-up while awaiting (shouldn't happen in practice — discard).
        case (.awaitingSecondTapDown, false):
            state = .idle
            return .noop

        // Second key-up of confirmed double tap — emit start.
        case (.confirmedDoubleTapDown, false):
            state = .recording
            return .start

        // Extra key-down while confirmed (shouldn't happen — keep state).
        case (.confirmedDoubleTapDown, true):
            return .noop

        // Recording active: next complete tap stops. Act on key-up.
        case (.recording, true):
            return .noop
        case (.recording, false):
            state = .idle
            return .stop
        }
    }
}
