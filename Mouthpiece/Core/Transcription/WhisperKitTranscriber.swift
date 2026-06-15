import Foundation
@preconcurrency import WhisperKit

actor WhisperKitTranscriber: Transcribing {

    private var pipe: WhisperKit?
    private var ready: Bool = false
    let modelName: String

    init(modelName: String = "openai_whisper-medium") {
        self.modelName = modelName
    }

    var isReady: Bool {
        get async { ready }
    }

    func loadModel() async throws {
        guard pipe == nil else { return }
        do {
            self.pipe = try await WhisperKit(model: modelName)
            self.ready = true
        } catch {
            throw TranscriptionError.modelDownloadFailed(String(describing: error))
        }
    }

    func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
        guard let pipe else {
            throw TranscriptionError.modelNotReady
        }
        do {
            let opts = DecodingOptions(
                language: language,
                detectLanguage: language == nil,
                skipSpecialTokens: true,
                withoutTimestamps: false
            )
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: opts)
            let texts = results.map { $0.text }.joined()
            let lang = results.first?.language ?? language ?? "zh"
            var segs: [TranscriptionResult.Segment] = []
            for r in results {
                for s in r.segments {
                    segs.append(.init(
                        start: Double(s.start),
                        end: Double(s.end),
                        text: s.text
                    ))
                }
            }
            return TranscriptionResult(
                text: texts,
                language: lang,
                segments: segs,
                durationSeconds: Double(samples.count) / 16000.0
            )
        } catch {
            throw TranscriptionError.transcribeFailed(String(describing: error))
        }
    }
}
