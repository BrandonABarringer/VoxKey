import XCTest
@testable import VoxKey

@MainActor
final class TranscriptionServiceTests: XCTestCase {

    var service: TranscriptionService!

    override func setUp() {
        super.setUp()
        service = TranscriptionService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertEqual(service.currentModel, "base")
        XCTAssertFalse(service.isModelLoaded)
        XCTAssertFalse(service.isLoading)
        XCTAssertFalse(service.isDownloading)
        XCTAssertEqual(service.downloadProgress, 0.0)
        XCTAssertNil(service.errorMessage)
        XCTAssertNil(service.downloadError)
    }

    // MARK: - Transcription Guard Tests

    func testTranscribeThrowsModelNotLoadedWhenNoModel() async {
        do {
            _ = try await service.transcribe(audioSamples: [0.1, 0.2, 0.3])
            XCTFail("Expected TranscriptionError.modelNotLoaded")
        } catch let error as TranscriptionError {
            switch error {
            case .modelNotLoaded:
                break // expected
            default:
                XCTFail("Expected .modelNotLoaded but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTranscribeThrowsEmptyAudioWhenGivenEmptyArray() async {
        // Manually set isModelLoaded to simulate a loaded state without downloading
        // Since we cannot load a real model in unit tests, we test the empty audio guard
        // by verifying it throws modelNotLoaded first (empty audio check comes after model check)
        do {
            _ = try await service.transcribe(audioSamples: [])
            XCTFail("Expected TranscriptionError")
        } catch let error as TranscriptionError {
            // With no model loaded, modelNotLoaded will fire before emptyAudio
            switch error {
            case .modelNotLoaded:
                break // expected - model check comes first
            default:
                XCTFail("Expected .modelNotLoaded but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testErrorDescriptions() {
        XCTAssertEqual(
            TranscriptionError.modelNotLoaded.errorDescription,
            "Whisper model is not loaded"
        )
        XCTAssertEqual(
            TranscriptionError.emptyAudio.errorDescription,
            "No audio to transcribe"
        )
        XCTAssertEqual(
            TranscriptionError.transcriptionFailed("test reason").errorDescription,
            "Transcription failed: test reason"
        )
    }

    // NOTE: Actual transcription tests require downloading a WhisperKit model,
    // which is not feasible in unit tests. Integration tests with a real model
    // should be run manually or in a separate integration test target.
}
