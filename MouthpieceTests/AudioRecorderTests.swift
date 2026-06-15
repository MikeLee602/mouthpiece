import XCTest
@testable import Mouthpiece

@MainActor
final class AudioRecorderTests: XCTestCase {

    final class MockRecorder: AudioRecording {
        var state: AudioRecorderState = .idle
        var samplesToReturn: [Float] = []
        var startThrows: AudioRecorderError?

        func start() throws {
            if let e = startThrows { throw e }
            state = .recording(elapsed: 0)
        }

        func stop() async -> [Float] {
            state = .finished(sampleCount: samplesToReturn.count, sampleRate: 16000)
            return samplesToReturn
        }
    }

    func testInitialState() {
        let r: AudioRecording = MockRecorder()
        XCTAssertEqual(r.state, .idle)
    }

    func testStartChangesToRecording() throws {
        let r = MockRecorder()
        try r.start()
        if case .recording = r.state {} else { XCTFail("expected recording") }
    }

    func testStopReturnsSamples() async {
        let r = MockRecorder()
        r.samplesToReturn = Array(repeating: Float(0.1), count: 16000)
        try? r.start()
        let s = await r.stop()
        XCTAssertEqual(s.count, 16000)
        if case .finished(let n, let sr) = r.state {
            XCTAssertEqual(n, 16000)
            XCTAssertEqual(sr, 16000)
        } else {
            XCTFail("expected finished")
        }
    }

    func testStartThrowsPropagates() {
        let r = MockRecorder()
        r.startThrows = .engineFailedToStart
        XCTAssertThrowsError(try r.start()) { err in
            XCTAssertEqual(err as? AudioRecorderError, .engineFailedToStart)
        }
    }

    func testRealRecorderInitialState() {
        let r = AudioRecorder()
        XCTAssertEqual(r.state, .idle)
    }
}
