import Foundation
import Observation

enum FloatingBarKind: Equatable, Sendable {
    case idle
    case recording(elapsed: TimeInterval, levels: [Float])
    case processing
    case done(chars: Int)
    case error(String)
}

@MainActor
@Observable
final class FloatingBarState {
    var kind: FloatingBarKind = .idle
    private var dismissTask: Task<Void, Never>?

    func startRecording() {
        cancelDismiss()
        kind = .recording(elapsed: 0, levels: [])
    }

    func updateRecording(elapsed: TimeInterval, levels: [Float]) {
        if case .recording = kind {
            kind = .recording(elapsed: elapsed, levels: levels)
        }
    }

    func setProcessing() {
        cancelDismiss()
        kind = .processing
    }

    func setDone(chars: Int) {
        cancelDismiss()
        kind = .done(chars: chars)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self else { return }
            if case .done = self.kind { self.kind = .idle }
        }
    }

    func setError(_ msg: String) {
        cancelDismiss()
        kind = .error(msg)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            if case .error = self.kind { self.kind = .idle }
        }
    }

    func reset() {
        cancelDismiss()
        kind = .idle
    }

    private func cancelDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}
