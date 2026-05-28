// Minimal dependency-free checks runnable with just the Command Line Tools:
//
//     swift run ManagerChecks
//
// No XCTest, no Xcode, no CI. Runs all checks and exits non-zero if any failed,
// so it can gate a manual pre-push check if desired.
//
// The manager files under test (AudioCaptureManager, HotkeyManager, and the types
// HotkeyManager needs) are SYMLINKS in this directory pointing at the real sources
// under VoxKey/ — so these checks exercise the shipping code, not a copy. See the
// ManagerChecks target comment in Package.swift for why symlinks are used. main.swift
// is the only real file here.
//
// Coverage:
// - PR #1: the first-buffer wait (serial queue + continuation, off the main thread).
//   Verifies it resumes on a buffer, short-circuits when one is already present, and
//   bounds itself by the timeout — i.e. the "short tap keeps its audio" fix holds.
// - PR #2: HotkeyManager.restart() stores doubleTapWindowMs / mode / keycode on the
//   manager (the formerly-dead parameter now drives the TapStateMachine).

import Foundation

let done = DispatchSemaphore(value: 0)
nonisolated(unsafe) var exitCode: Int32 = 0

Task {
    var failures = 0
    func check(_ cond: Bool, _ name: String) {
        if cond { print("ok   - \(name)") }
        else { print("FAIL - \(name)"); failures += 1 }
    }

    // Resumes promptly once a buffer arrives — not blocked to the timeout.
    do {
        let m = AudioCaptureManager()
        let start = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { m.simulateFirstBufferArrival() }
        await m.awaitFirstBuffer()
        check(Date().timeIntervalSince(start) < 0.2, "awaitFirstBuffer resumes on buffer arrival")
    }

    // Short-circuits when a buffer is already present.
    do {
        let m = AudioCaptureManager()
        m.simulateFirstBufferArrival()
        try? await Task.sleep(nanoseconds: 30_000_000)
        let start = Date()
        await m.awaitFirstBuffer()
        check(Date().timeIntervalSince(start) < 0.05, "awaitFirstBuffer short-circuits when buffer present")
    }

    // Bounds itself by the timeout when no buffer ever arrives.
    do {
        let m = AudioCaptureManager()
        let start = Date()
        await m.awaitFirstBuffer()
        let elapsed = Date().timeIntervalSince(start)
        check(elapsed > 0.25 && elapsed < 0.6, "awaitFirstBuffer times out (\(String(format: "%.3f", elapsed))s) when no buffer")
    }

    // stopRecording on a fresh manager (not recording) returns empty, stays stopped.
    do {
        let m = AudioCaptureManager()
        let samples = await m.stopRecording()
        check(samples.isEmpty, "stopRecording returns empty when not recording")
        check(!m.currentlyRecording, "stopRecording leaves manager not recording")
    }

    // Concurrency stress: many simulated buffer arrivals racing a waiter, repeated.
    // The point of this check is to give ThreadSanitizer something to catch — run
    // it with `swift run --sanitize=thread ManagerChecks`. A clean pass here is the
    // evidence that rawBuffers / firstBufferContinuation access is properly
    // serialized on bufferQueue (the PR #1 review's data-race concern).
    do {
        for _ in 0..<50 {
            let m = AudioCaptureManager()
            for _ in 0..<8 {
                DispatchQueue.global().async { m.simulateFirstBufferArrival() }
            }
            await m.awaitFirstBuffer()
        }
        check(true, "50x concurrent arrival/wait cycles (run under TSan to detect races)")
    }

    // PR #2 review fix: doubleTapWindowMs is no longer a dead restart() parameter —
    // it is stored on the manager and used to build the TapStateMachine, rather than
    // read from UserDefaults at event time. restart() also calls start(), which
    // returns false here (no Accessibility), but the config writes happen first, so
    // configuredDoubleTapWindowMs reflects the passed value regardless.
    do {
        let h = HotkeyManager()
        h.restart(keyCode: 62, mode: .doubleTap, doubleTapWindowMs: 275)
        check(h.configuredDoubleTapWindowMs == 275, "restart() stores doubleTapWindowMs on the manager")
        check(h.configuredMode == .doubleTap, "restart() stores activation mode on the manager")
        check(h.configuredKeyCode == 62, "restart() stores keycode on the manager")
    }

    print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
    exitCode = failures == 0 ? 0 : 1
    done.signal()
}

done.wait()
exit(exitCode)
