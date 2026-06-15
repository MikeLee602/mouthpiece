import XCTest
@testable import Mouthpiece

final class TextCleanerTests: XCTestCase {

    let cleaner = TextCleaner()
    var opts: CleanOptions { .default }

    func testRemoveChineseFillers() {
        let result = cleaner.clean("嗯，那个，我想说就是今天天气不错", options: opts)
        XCTAssertFalse(result.contains("嗯"))
        XCTAssertFalse(result.contains("那个"))
        XCTAssertFalse(result.contains("就是"))
        XCTAssertTrue(result.contains("今天天气不错"))
    }

    func testRemoveEnglishFillers() {
        let result = cleaner.clean("um, I think you know, this is great", options: opts)
        XCTAssertFalse(result.lowercased().contains("um"))
        XCTAssertFalse(result.lowercased().contains("you know"))
        XCTAssertTrue(result.contains("I think"))
        XCTAssertTrue(result.contains("this is great"))
    }

    func testRemoveCharacterRepetition() {
        let result = cleaner.clean("我我我想说这个", options: opts)
        XCTAssertFalse(result.contains("我我"))
        XCTAssertTrue(result.contains("我想说"))
    }

    func testNormalizeSpaces() {
        let result = cleaner.clean("hello   world  !", options: opts)
        XCTAssertEqual(result, "hello world!")
    }

    func testKeepMeaningfulContent() {
        let result = cleaner.clean("我们今天讨论 AI 的未来", options: opts)
        XCTAssertTrue(result.contains("今天讨论"))
        XCTAssertTrue(result.contains("AI"))
        XCTAssertTrue(result.contains("未来"))
    }

    func testEmpty() {
        XCTAssertEqual(cleaner.clean("", options: opts), "")
    }

    func testWhitespaceOnly() {
        XCTAssertEqual(cleaner.clean("   ", options: opts), "")
    }

    func testAllOptionsOff() {
        var o = opts
        o.removeFillers = false
        o.removeRepetition = false
        o.normalizeSpaces = false
        let result = cleaner.clean("嗯 嗯  嗯", options: o)
        XCTAssertEqual(result, "嗯 嗯  嗯")
    }

    func testCustomFillers() {
        var o = opts
        o.customFillers = ["哎呀"]
        let result = cleaner.clean("哎呀我说错了", options: o)
        XCTAssertFalse(result.contains("哎呀"))
        XCTAssertTrue(result.contains("我说错了"))
    }

    func testEnglishWordRepetition() {
        let result = cleaner.clean("I I I really really mean it", options: opts)
        XCTAssertFalse(result.contains("I I"))
        XCTAssertFalse(result.contains("really really"))
        XCTAssertTrue(result.contains("mean it"))
    }
}
