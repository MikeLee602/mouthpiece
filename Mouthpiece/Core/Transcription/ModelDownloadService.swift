import Foundation
@preconcurrency import WhisperKit
import Observation

/// Optional convenience service for downloading the Whisper model.
///
/// `WhisperKit(model:)` in `WhisperKitTranscriber.loadModel()` already handles
/// auto-downloading on first use, so this service is mainly a UI affordance for
/// showing "downloading…" / "ready" / "failed" state ahead of the first call.
///
/// Progress reporting via the WhisperKit `progressCallback` is intentionally
/// omitted: the callback type is not `Sendable`, so under Swift 6 strict
/// concurrency we can't safely capture our `@MainActor` state from inside it.
/// We surface coarse state (downloading -> ready/failed) instead.
@MainActor
@Observable
final class ModelDownloadService {

    enum Status: Equatable, Sendable {
        case idle
        case downloading(progress: Double)
        case ready
        case failed(String)
    }

    private(set) var status: Status = .idle
    let modelName: String

    init(modelName: String) { self.modelName = modelName }

    func ensureModel() async {
        status = .downloading(progress: 0)
        let modelName = self.modelName
        let result: Result<Void, Error> = await Task.detached {
            do {
                _ = try await WhisperKit.download(
                    variant: modelName,
                    downloadBase: nil
                )
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            status = .ready
        case .failure(let error):
            status = .failed(String(describing: error))
        }
    }
}
