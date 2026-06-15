import XCTest
@testable import Mouthpiece

@MainActor
final class FloatingBarStateTests: XCTestCase {

    func testInitialIdle() {
        let s = FloatingBarState()
        XCTAssertEqual(s.kind, .idle)
    }

    func testStartRecording() {
        let s = FloatingBarState()
        s.startRecording()
        if case .recording(let elapsed, let levels) = s.kind {
            XCTAssertEqual(elapsed, 0)
            XCTAssertEqual(levels, [])
        } else {
            XCTFail("expected recording")
        }
    }

    func testUpdateRecording() {
        let s = FloatingBarState()
        s.startRecording()
        s.updateRecording(elapsed: 2.5, levels: [0.1, 0.2, 0.3])
        if case .recording(let elapsed, let levels) = s.kind {
            XCTAssertEqual(elapsed, 2.5)
            XCTAssertEqual(levels, [0.1, 0.2, 0.3])
        } else {
            XCTFail("expected recording")
        }
    }

    func testProcessing() {
        let s = FloatingBarState()
        s.setProcessing()
        XCTAssertEqual(s.kind, .processing)
    }

    func testDoneAutoDismiss() async {
        let s = FloatingBarState()
        s.setDone(chars: 42)
        XCTAssertEqual(s.kind, .done(chars: 42))
        try? await Task.sleep(for: .milliseconds(1700))
        XCTAssertEqual(s.kind, .idle)
    }

    func testErrorAutoDismiss() async {
        let s = FloatingBarState()
        s.setError("test error")
        XCTAssertEqual(s.kind, .error("test error"))
        try? await Task.sleep(for: .milliseconds(3200))
        XCTAssertEqual(s.kind, .idle)
    }

    func testResetCancelsDismiss() async {
        let s = FloatingBarState()
        s.setDone(chars: 10)
        s.startRecording()  // cancels pending dismiss
        try? await Task.sleep(for: .milliseconds(1700))
        // should still be recording, not idle
        if case .recording = s.kind {} else {
            XCTFail("expected recording, got \(s.kind)")
        }
    }
}
