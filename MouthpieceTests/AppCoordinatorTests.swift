import XCTest
@testable import Mouthpiece

@MainActor
final class AppCoordinatorTests: XCTestCase {

    final class MockRecorder: AudioRecording {
        var state: AudioRecorderState = .idle
        var samplesToReturn: [Float] = Array(repeating: 0.1, count: 1600)

        func start() throws { state = .recording(elapsed: 0) }
        func stop() async -> [Float] {
            state = .finished(sampleCount: samplesToReturn.count, sampleRate: 16000)
            return samplesToReturn
        }
    }

    actor MockTranscriber: Transcribing {
        var isReady: Bool = true
        var resultText: String = "嗯，你好世界"

        func loadModel() async throws { isReady = true }
        func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
            return TranscriptionResult(text: resultText, language: "zh", segments: [], durationSeconds: 1.0)
        }

        func setReady(_ v: Bool) { isReady = v }
    }

    actor MockInjector: TextInjecting {
        var injected: [String] = []
        func inject(_ text: String) async throws {
            injected.append(text)
        }
        func getInjected() -> [String] { injected }
    }

    func makeCoordinator(
        transcriberReady: Bool = true
    ) async -> (AppCoordinator, MockRecorder, MockTranscriber, MockInjector) {
        let perm = PermissionService()
        // The coordinator uses `permission.microphone` only at startRecording.
        // We verify transitions without depending on real permission state — tests
        // that drive the recording path will land in `.error` if mic isn't granted,
        // which we detect.
        let rec = MockRecorder()
        let trn = MockTranscriber()
        await trn.setReady(transcriberReady)
        let inj = MockInjector()
        let bar = FloatingBarState()
        let win = FloatingBarWindow(state: bar)
        let coord = AppCoordinator(
            permission: perm,
            recorder: rec,
            transcriber: trn,
            cleaner: TextCleaner(),
            injector: inj,
            floatingBar: bar,
            floatingWindow: win
        )
        return (coord, rec, trn, inj)
    }

    func testInitialPhaseIsIdle() async {
        let (coord, _, _, _) = await makeCoordinator()
        XCTAssertEqual(coord.phase, .idle)
    }

    func testReleaseWithoutPressIsNoOp() async {
        let (coord, _, _, inj) = await makeCoordinator()
        coord.handleHotkey(.released)
        try? await Task.sleep(for: .milliseconds(50))
        let injected = await inj.getInjected()
        XCTAssertEqual(injected.count, 0)
    }

    func testTranscriberNotReadyShowsError() async {
        let (coord, _, _, _) = await makeCoordinator(transcriberReady: false)
        // Simulate Fn press
        coord.handleHotkey(.pressed)
        try? await Task.sleep(for: .milliseconds(100))
        // Phase should be error if mic granted, or also error if mic not granted
        if case .error = coord.phase {
            // ok
        } else {
            XCTFail("expected error phase, got \(coord.phase)")
        }
    }
}
