import Foundation

struct TranscriptionResult: Equatable, Sendable {
    let text: String
    let language: String
    let segments: [Segment]
    let durationSeconds: Double

    struct Segment: Equatable, Sendable {
        let start: Double
        let end: Double
        let text: String
    }

    static let empty = TranscriptionResult(text: "", language: "zh", segments: [], durationSeconds: 0)
}

enum TranscriptionError: Error, Equatable, Sendable {
    case modelNotReady
    case modelDownloadFailed(String)
    case transcribeFailed(String)
}

protocol Transcribing: AnyObject, Sendable {
    var isReady: Bool { get async }
    func loadModel() async throws
    func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult
}
