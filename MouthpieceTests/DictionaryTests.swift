import XCTest
@testable import Mouthpiece

final class DictionaryRuleTests: XCTestCase {

    func testCaseSensitiveReplace() {
        let rule = DictionaryRule(pattern: "纸笔体", replacement: "GPT", caseInsensitive: false)
        XCTAssertEqual(rule.apply(to: "我用纸笔体写代码"), "我用GPT写代码")
        XCTAssertEqual(rule.apply(to: "纸笔体很厉害"), "GPT很厉害")
    }

    func testCaseInsensitiveReplace() {
        let rule = DictionaryRule(pattern: "api", replacement: "API", caseInsensitive: true)
        XCTAssertEqual(rule.apply(to: "Api Api API"), "API API API")
    }

    func testNoMatch() {
        let rule = DictionaryRule(pattern: "X", replacement: "Y", caseInsensitive: false)
        XCTAssertEqual(rule.apply(to: "hello"), "hello")
    }

    func testEmptyPatternDoesNothing() {
        let rule = DictionaryRule(pattern: "", replacement: "X", caseInsensitive: false)
        XCTAssertEqual(rule.apply(to: "hello"), "hello")
    }

    func testArrayApplyComposes() {
        let rules: [DictionaryRule] = [
            .init(pattern: "纸笔体", replacement: "GPT", caseInsensitive: false),
            .init(pattern: "京东", replacement: "JD", caseInsensitive: false),
        ]
        XCTAssertEqual(
            rules.apply(to: "我在京东用纸笔体"),
            "我在JD用GPT"
        )
    }

    func testArrayApplyOrderMatters() {
        // 链式：先把 "abc" 替换成 "xyz"，再把 "xyz" 替换成 "FINAL"
        let rules: [DictionaryRule] = [
            .init(pattern: "abc", replacement: "xyz", caseInsensitive: false),
            .init(pattern: "xyz", replacement: "FINAL", caseInsensitive: false),
        ]
        XCTAssertEqual(rules.apply(to: "abc"), "FINAL")
    }
}

@MainActor
final class DictionaryStoreTests: XCTestCase {

    func testAddFetchAndSnapshot() throws {
        let history = try HistoryStore(inMemory: true)
        let dict = DictionaryStore(sharing: history)
        XCTAssertEqual(dict.fetchAll().count, 0)
        XCTAssertEqual(dict.snapshot().count, 0)

        dict.add(.init(pattern: "纸笔体", replacement: "GPT",
                       caseInsensitive: false, note: nil))
        XCTAssertEqual(dict.fetchAll().count, 1)
        XCTAssertEqual(dict.snapshot().count, 1)
    }

    func testSnapshotExcludesDisabled() throws {
        let history = try HistoryStore(inMemory: true)
        let dict = DictionaryStore(sharing: history)
        dict.add(.init(pattern: "a", replacement: "A", caseInsensitive: false, note: nil))
        dict.add(.init(pattern: "b", replacement: "B", caseInsensitive: false, note: nil))
        // 把第一条禁用
        if let first = dict.fetchAll().first {
            first.enabled = false
            dict.update(first)
        }
        XCTAssertEqual(dict.fetchAll().count, 2)
        XCTAssertEqual(dict.snapshot().count, 1, "禁用的应该不出现在 snapshot 里")
    }

    func testDeleteAll() throws {
        let history = try HistoryStore(inMemory: true)
        let dict = DictionaryStore(sharing: history)
        dict.add(.init(pattern: "a", replacement: "A", caseInsensitive: false, note: nil))
        dict.add(.init(pattern: "b", replacement: "B", caseInsensitive: false, note: nil))
        XCTAssertEqual(dict.fetchAll().count, 2)
        dict.deleteAll()
        XCTAssertEqual(dict.fetchAll().count, 0)
    }
}
