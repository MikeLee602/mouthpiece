import XCTest
@testable import Mouthpiece

final class TranscribingTests: XCTestCase {

    actor MockTranscriber: Transcribing {
        var isReady: Bool = false
        var loadCalled = false
        var resultToReturn: TranscriptionResult?
        var errorToThrow: TranscriptionError?

        func loadModel() async throws {
            if let e = errorToThrow { throw e }
            loadCalled = true
            isReady = true
        }

        func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
            if let e = errorToThrow { throw e }
            return resultToReturn ?? .empty
        }

        func setReady(_ v: Bool) { isReady = v }
        func setResult(_ r: TranscriptionResult) { resultToReturn = r }
        func setError(_ e: TranscriptionError?) { errorToThrow = e }
    }

    func testInitialNotReady() async {
        let t = MockTranscriber()
        let ready = await t.isReady
        XCTAssertFalse(ready)
    }

    func testLoadMarksReady() async throws {
        let t = MockTranscriber()
        try await t.loadModel()
        let ready = await t.isReady
        XCTAssertTrue(ready)
    }

    func testTranscribeReturnsResult() async throws {
        let t = MockTranscriber()
        await t.setResult(TranscriptionResult(text: "你好世界", language: "zh", segments: [], durationSeconds: 1.0))
        let r = try await t.transcribe(samples: [0, 0, 0], language: "zh")
        XCTAssertEqual(r.text, "你好世界")
    }

    func testTranscribeThrows() async {
        let t = MockTranscriber()
        await t.setError(.modelNotReady)
        do {
            _ = try await t.transcribe(samples: [], language: nil)
            XCTFail("expected throw")
        } catch let e as TranscriptionError {
            XCTAssertEqual(e, .modelNotReady)
        } catch {
            XCTFail("wrong error type")
        }
    }
}
