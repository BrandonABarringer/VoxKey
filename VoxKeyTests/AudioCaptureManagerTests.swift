import XCTest
@testable import VoxKey

final class AudioCaptureManagerTests: XCTestCase {

    private var sut: AudioCaptureManager!

    override func setUp() {
        super.setUp()
        sut = AudioCaptureManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState_isNotRecording() {
        XCTAssertFalse(sut.currentlyRecording)
    }

    // MARK: - stopRecording When Not Recording

    func testStopRecording_whenNotRecording_returnsEmptyArray() {
        let samples = sut.stopRecording()
        XCTAssertTrue(samples.isEmpty)
    }

    func testStopRecording_whenNotRecording_remainsNotRecording() {
        _ = sut.stopRecording()
        XCTAssertFalse(sut.currentlyRecording)
    }

    // MARK: - Target Format Constants

    func testTargetFormat_is16kHzMonoFloat32() {
        // Verify the target format WhisperKit expects can be created
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )
        XCTAssertNotNil(format)
        XCTAssertEqual(format?.sampleRate, 16000)
        XCTAssertEqual(format?.channelCount, 1)
        XCTAssertEqual(format?.commonFormat, .pcmFormatFloat32)
    }

    // MARK: - Audio Capture Error Descriptions

    func testAudioCaptureError_formatCreationFailed_hasDescription() {
        let error = AudioCaptureError.formatCreationFailed
        XCTAssertEqual(error.errorDescription, "Failed to create target audio format")
    }

    func testAudioCaptureError_converterCreationFailed_hasDescription() {
        let error = AudioCaptureError.converterCreationFailed
        XCTAssertEqual(error.errorDescription, "Failed to create audio converter")
    }

    func testAudioCaptureError_engineStartFailed_hasDescription() {
        let error = AudioCaptureError.engineStartFailed
        XCTAssertEqual(error.errorDescription, "Failed to start audio engine")
    }

    // NOTE: Actual audio capture (startRecording, buffer accumulation, sample concatenation)
    // cannot be unit tested without hardware microphone access. These paths require
    // integration testing on a real device with microphone permission granted.
}
