import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum DictationState {
        case idle
        case recording
        case processing
    }

    @Published var currentState: DictationState = .idle
    @Published var lastTranscription: String = ""
    @Published var errorMessage: String?
}
