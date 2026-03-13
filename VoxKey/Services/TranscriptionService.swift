import Foundation
import WhisperKit

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyAudio
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model is not loaded"
        case .emptyAudio: return "No audio to transcribe"
        case .transcriptionFailed(let reason): return "Transcription failed: \(reason)"
        }
    }
}

@MainActor
final class TranscriptionService: ObservableObject {
    @Published var currentModel: String = Constants.defaultModel
    @Published var isModelLoaded: Bool = false
    @Published var isLoading: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var downloadError: String?

    private var whisperKit: WhisperKit?

    func loadModel(_ modelName: String? = nil) async throws {
        let model = modelName ?? currentModel
        isLoading = true
        isDownloading = true
        errorMessage = nil
        downloadError = nil
        downloadProgress = 0.0

        do {
            let config = WhisperKitConfig(model: model, verbose: false)
            whisperKit = try await WhisperKit(config)
            currentModel = model
            isModelLoaded = true
            isLoading = false
            isDownloading = false
            downloadProgress = 1.0
        } catch {
            isLoading = false
            isDownloading = false
            isModelLoaded = false
            let message = "Failed to load model '\(model)': \(error.localizedDescription)"
            errorMessage = message
            downloadError = message
            throw error
        }
    }

    func transcribe(audioSamples: [Float]) async throws -> String {
        guard let whisperKit = whisperKit, isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        do {
            let options = buildDecodingOptions()
            let results: [TranscriptionResult] = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)
            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            if text.isEmpty {
                throw TranscriptionError.transcriptionFailed("No speech detected")
            }

            return text
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    private func buildDecodingOptions() -> DecodingOptions? {
        guard let tokenizer = whisperKit?.tokenizer else { return nil }
        let terms = UserDefaults.standard.stringArray(forKey: "customDictionaryTerms") ?? Constants.defaultDictionaryTerms
        guard !terms.isEmpty else { return nil }
        let promptText = " " + terms.joined(separator: ", ")
        let promptTokens = tokenizer.encode(text: promptText)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return DecodingOptions(promptTokens: promptTokens)
    }

    func switchModel(to modelName: String) async throws {
        whisperKit = nil
        isModelLoaded = false
        try await loadModel(modelName)
    }
}
