import Foundation
import Observation

enum FloatingBarKind: Equatable, Sendable {
    case idle
    case recording(elapsed: TimeInterval, levels: [Float], partial: String)
    case processing(partial: String)
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
        kind = .recording(elapsed: 0, levels: [], partial: "")
    }

    func updateRecording(elapsed: TimeInterval, levels: [Float]) {
        if case .recording(_, _, let partial) = kind {
            kind = .recording(elapsed: elapsed, levels: levels, partial: partial)
        }
    }

    /// 实时识别 partial 文本更新。
    func updatePartial(_ text: String) {
        switch kind {
        case .recording(let elapsed, let levels, _):
            kind = .recording(elapsed: elapsed, levels: levels, partial: text)
        case .processing:
            kind = .processing(partial: text)
        default:
            break
        }
    }

    func setProcessing() {
        cancelDismiss()
        // 保留 partial 文本作为「正在润色」时的占位
        let carried: String
        if case .recording(_, _, let p) = kind { carried = p } else { carried = "" }
        kind = .processing(partial: carried)
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
