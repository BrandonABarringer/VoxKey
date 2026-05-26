// Minimal dependency-free checks runnable with just the Command Line Tools:
//
//     swift run ManagerChecks
//
// No XCTest, no Xcode, no CI. Runs all checks and exits non-zero if any failed,
// so it can gate a manual pre-push check if desired. Compiles the real AudioCaptureManager.swift
// (listed as a source of this target in Package.swift) — these exercise the
// shipping code, not a copy.
//
// Coverage: the first-buffer wait that PR #1 introduced and PR #1's review feedback
// reshaped (serial queue + continuation, off the main thread). Verifies the wait
// resumes on a buffer, short-circuits when one is already present, and bounds itself
// by the timeout instead of hanging — i.e. the original "short tap keeps its audio"
// fix still holds after the concurrency rewrite.

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

    print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
    exitCode = failures == 0 ? 0 : 1
    done.signal()
}

done.wait()
exit(exitCode)
