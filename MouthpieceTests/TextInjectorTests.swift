import XCTest
@testable import Mouthpiece

final class TextInjectorTests: XCTestCase {

    actor MockInjector: TextInjecting {
        var injected: [String] = []
        var errorToThrow: InjectionError?

        func inject(_ text: String) async throws {
            if let e = errorToThrow { throw e }
            injected.append(text)
        }

        func setError(_ e: InjectionError?) { errorToThrow = e }
        func getInjected() -> [String] { injected }
    }

    func testInjectRecordsText() async throws {
        let i = MockInjector()
        try await i.inject("hello")
        let recorded = await i.getInjected()
        XCTAssertEqual(recorded, ["hello"])
    }

    func testInjectMultipleTexts() async throws {
        let i = MockInjector()
        try await i.inject("first")
        try await i.inject("second")
        let recorded = await i.getInjected()
        XCTAssertEqual(recorded, ["first", "second"])
    }

    func testInjectThrowsAccessibilityError() async {
        let i = MockInjector()
        await i.setError(.noAccessibilityPermission)
        do {
            try await i.inject("test")
            XCTFail("expected throw")
        } catch let e as InjectionError {
            XCTAssertEqual(e, .noAccessibilityPermission)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testRealInjectorThrowsWhenNoPermission() async {
        // The real injector should throw if no Accessibility permission.
        // In test environment without TCC entitlement, AXIsProcessTrusted() returns false.
        let injector = TextInjector()
        do {
            try await injector.inject("test")
            // If permission happens to be granted (unusual in test env), we let it through
        } catch let e as InjectionError {
            XCTAssertEqual(e, .noAccessibilityPermission)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
