import Foundation
import AVFoundation

final class AudioCaptureManager {
    private let audioEngine = AVAudioEngine()
    private var rawBuffers: [AVAudioPCMBuffer] = []
    private var isRecording = false
    private let targetSampleRate: Double = 16000

    func startRecording() throws {
        guard !isRecording else { return }

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        print("VoxKey: Hardware audio format: \(hardwareFormat)")

        rawBuffers.removeAll()

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
            self.rawBuffers.append(copy)
        }

        try audioEngine.start()
        isRecording = true
    }

    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false

        guard !rawBuffers.isEmpty else { return [] }

        let hardwareFormat = rawBuffers[0].format

        // Calculate total frame count
        let totalFrames = rawBuffers.reduce(0) { $0 + Int($1.frameLength) }
        print("VoxKey: Raw audio: \(totalFrames) frames at \(hardwareFormat.sampleRate)Hz (\(Double(totalFrames) / hardwareFormat.sampleRate)s)")

        // Concatenate all raw buffers into one
        guard let combined = AVAudioPCMBuffer(pcmFormat: hardwareFormat, frameCapacity: AVAudioFrameCount(totalFrames)) else {
            print("VoxKey: Failed to create combined buffer")
            rawBuffers.removeAll()
            return []
        }

        var offset: AVAudioFrameCount = 0
        for buf in rawBuffers {
            if let src = buf.floatChannelData, let dst = combined.floatChannelData {
                for ch in 0..<Int(hardwareFormat.channelCount) {
                    dst[ch].advanced(by: Int(offset)).update(from: src[ch], count: Int(buf.frameLength))
                }
            }
            offset += buf.frameLength
        }
        combined.frameLength = offset
        rawBuffers.removeAll()

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
