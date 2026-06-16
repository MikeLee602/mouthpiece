import XCTest
@testable import Mouthpiece

final class SimplifiedChineseConverterTests: XCTestCase {

    func testConvertsTraditionalToSimplified() throws {
        let conv = SimplifiedChineseConverter()
        // Skip the test if opencc isn't installed (CI may not have it).
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/opencc") else {
            throw XCTSkip("opencc not installed")
        }
        XCTAssertEqual(conv.convert("今天天氣真好"), "今天天气真好")
        XCTAssertEqual(conv.convert("測試一下繁體字"), "测试一下繁体字")
    }

    func testEmptyStringPassthrough() {
        let conv = SimplifiedChineseConverter()
        XCTAssertEqual(conv.convert(""), "")
    }

    func testAlreadySimplifiedUnchanged() throws {
        let conv = SimplifiedChineseConverter()
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/opencc") else {
            throw XCTSkip("opencc not installed")
        }
        XCTAssertEqual(conv.convert("简体字保持不变"), "简体字保持不变")
    }

    func testMissingBinaryFallsBackToInput() {
        let conv = SimplifiedChineseConverter(binaryPath: "/nonexistent/opencc")
        XCTAssertEqual(conv.convert("今天天氣真好"), "今天天氣真好")
    }
}
