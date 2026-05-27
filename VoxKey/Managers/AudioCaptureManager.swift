import Foundation
@preconcurrency import AVFoundation

// @unchecked Sendable: shared across the realtime audio thread, the timeout task,
// and the caller. All mutable cross-thread state (`rawBuffers`,
// `firstBufferContinuation`) is accessed exclusively on `bufferQueue`, which
// serializes those accesses. `audioEngine`/`isRecording` are touched only from the
// recording lifecycle (start/stop), not from the concurrent closures.
final class AudioCaptureManager: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()

    /// Serial queue that owns `rawBuffers` and `firstBufferContinuation`. Every read
    /// and write of those two properties happens on this queue — the realtime audio
    /// tap callback, `startRecording`, and `stopRecording` all funnel through it. This
    /// is the single synchronization point that eliminates the data race between the
    /// audio thread appending buffers and the caller draining them.
    private let bufferQueue = DispatchQueue(label: "com.voxkey.audiocapture.buffers")
    private var rawBuffers: [AVAudioPCMBuffer] = []
    private var firstBufferContinuation: CheckedContinuation<Void, Never>?

    private var isRecording = false
    private let targetSampleRate: Double = 16000
    private let firstBufferTimeout: Double = 0.3

    func startRecording() throws {
        guard !isRecording else { return }

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        print("VoxKey: Hardware audio format: \(hardwareFormat)")

        bufferQueue.sync {
            rawBuffers.removeAll()
            firstBufferContinuation = nil
        }

        // Record in hardware format, convert later
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            // Copy the buffer since it gets reused
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
                for ch in 0..<Int(buffer.format.channelCount) {
                    dst[ch].update(from: src[ch], count: Int(buffer.frameLength))
                }
            }
            // Hop off the realtime audio thread onto bufferQueue. Never block the
            // audio thread — always async. Resume the first-buffer waiter, if any.
            self.bufferQueue.async {
                let wasEmpty = self.rawBuffers.isEmpty
                self.rawBuffers.append(copy)
                if wasEmpty {
                    self.firstBufferContinuation?.resume()
                    self.firstBufferContinuation = nil
                }
            }
        }

        try audioEngine.start()
        isRecording = true
    }

    /// Suspends until the first buffer has been appended, or `firstBufferTimeout`
    /// elapses — whichever comes first. Runs off the main thread (the caller awaits
    /// it from a `Task`), so it never stalls the UI run loop the way the old polling
    /// loop did. Exposed at internal access for tests to drive deterministically.
    func awaitFirstBuffer() async {
        let alreadyHave = bufferQueue.sync { !rawBuffers.isEmpty }
        if alreadyHave { return }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(firstBufferTimeout * 1_000_000_000))
            bufferQueue.async {
                self.firstBufferContinuation?.resume()
                self.firstBufferContinuation = nil
            }
        }

        // The timeout task, the tap callback, and this registration block all resume
        // the continuation via bufferQueue, so they're serialized — the first one to
        // run resumes and nils `firstBufferContinuation`; the others see nil and no-op.
        // That guarantees the continuation resumes exactly once. The two branches
        // below handle the buffer landing before vs. after we register the waiter.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            bufferQueue.async {
                if !self.rawBuffers.isEmpty {
                    // Buffer landed between the early check and now — resume directly
                    // without parking it in firstBufferContinuation.
                    cont.resume()
                } else {
                    self.firstBufferContinuation = cont
                }
            }
        }
        // Resolved (by buffer or timeout); cancel the timer so a stale fire is a no-op.
        timeoutTask.cancel()
    }

    func stopRecording() async -> [Float] {
        guard isRecording else { return [] }

        // The audio engine takes ~60–100ms after start() before its tap callback
        // fires with the first buffer. If stop() is called inside that window
        // (short tap, fast release), rawBuffers is empty and we'd drop the audio.
        // Wait briefly for at least one buffer to arrive before tearing down.
        await awaitFirstBuffer()

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false

        let buffers = bufferQueue.sync { () -> [AVAudioPCMBuffer] in
            let snapshot = rawBuffers
            rawBuffers.removeAll()
            return snapshot
        }

        guard !buffers.isEmpty else { return [] }

        let hardwareFormat = buffers[0].format

        // Calculate total frame count
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        print("VoxKey: Raw audio: \(totalFrames) frames at \(hardwareFormat.sampleRate)Hz (\(Double(totalFrames) / hardwareFormat.sampleRate)s)")

        // Concatenate all raw buffers into one
        guard let combined = AVAudioPCMBuffer(pcmFormat: hardwareFormat, frameCapacity: AVAudioFrameCount(totalFrames)) else {
            print("VoxKey: Failed to create combined buffer")
            return []
        }

        var offset: AVAudioFrameCount = 0
        for buf in buffers {
            if let src = buf.floatChannelData, let dst = combined.floatChannelData {
                for ch in 0..<Int(hardwareFormat.channelCount) {
                    dst[ch].advanced(by: Int(offset)).update(from: src[ch], count: Int(buf.frameLength))
                }
            }
            offset += buf.frameLength
        }
        combined.frameLength = offset

        // Convert to 16kHz mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("VoxKey: Failed to create target format")
            return []
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            print("VoxKey: Failed to create converter")
            return []
        }

        let outputFrameCount = AVAudioFrameCount(Double(combined.frameLength) * targetSampleRate / hardwareFormat.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            print("VoxKey: Failed to create output buffer")
            return []
        }

        var inputConsumed = false
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return combined
        }

        if status == .error || error != nil {
            print("VoxKey: Conversion error: \(error?.localizedDescription ?? "unknown")")
            return []
        }

        // Extract float samples
        guard let channelData = outputBuffer.floatChannelData else { return [] }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
        print("VoxKey: Converted audio: \(samples.count) samples at 16kHz (\(Double(samples.count) / targetSampleRate)s)")

        return samples
    }

    var currentlyRecording: Bool {
        isRecording
    }

    /// Test-only seam. Simulates the audio tap callback delivering its first buffer:
    /// appends a placeholder on `bufferQueue` and resumes any pending first-buffer
    /// waiter, exactly as the real callback does — without a live audio engine.
    /// Lets `awaitFirstBuffer()`'s signal/timeout logic be exercised deterministically.
    func simulateFirstBufferArrival() {
        guard let placeholder = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!,
            frameCapacity: 1
        ) else { return }
        bufferQueue.async {
            let wasEmpty = self.rawBuffers.isEmpty
            self.rawBuffers.append(placeholder)
            if wasEmpty {
                self.firstBufferContinuation?.resume()
                self.firstBufferContinuation = nil
            }
        }
    }
}

enum AudioCaptureError: LocalizedError {
    case formatCreationFailed
    case converterCreationFailed
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed: return "Failed to create target audio format"
        case .converterCreationFailed: return "Failed to create audio converter"
        case .engineStartFailed: return "Failed to start audio engine"
        }
    }
}
