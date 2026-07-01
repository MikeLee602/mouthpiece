import XCTest
@testable import Mouthpiece

final class DiffLearnerTests: XCTestCase {

    func testIdenticalReturnsEmpty() {
        let s = DiffLearner.suggest(old: "abc", new: "abc")
        XCTAssertEqual(s, [])
    }

    func testSingleCharCorrection() {
        let s = DiffLearner.suggest(old: "王梦松", new: "王孟松")
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].pattern, "梦")
        XCTAssertEqual(s[0].replacement, "孟")
    }

    func testMultipleCorrections() {
        // "王梦松和赵远远" → "王孟松和赵远任"
        let s = DiffLearner.suggest(old: "王梦松和赵远远", new: "王孟松和赵远任")
        XCTAssertEqual(s.count, 2)
        let asSet = Set(s.map { "\($0.pattern)→\($0.replacement)" })
        XCTAssertEqual(asSet, Set(["梦→孟", "远→任"]))
    }

    func testInsertion() {
        // 用户加了字：应该出 ("", 新加的字)
        let s = DiffLearner.suggest(old: "采销", new: "采购销售")
        XCTAssertFalse(s.isEmpty, "expected non-empty suggestions: \(s)")
    }

    func testDeletion() {
        let s = DiffLearner.suggest(old: "谢谢大家", new: "谢谢")
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.contains(where: { $0.pattern == "大家" && $0.replacement == "" }))
    }

    func testPunctOnlyDifferenceIgnored() {
        // 只加了逗号 —— 不产生规则
        let s = DiffLearner.suggest(old: "你好世界", new: "你好，世界")
        // "，" 单独作为 diff，pattern="" replacement="，" 应被过滤（isPunctSpaceOnly）
        for sug in s {
            XCTAssertFalse(sug.pattern.isEmpty && !sug.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sug.replacement.trimmingCharacters(in: CharacterSet.punctuationCharacters).isEmpty,
                           "punct-only insertion should be filtered: \(sug)")
        }
    }

    func testTooLongDiffFiltered() {
        // 用户几乎重写整段 —— maxLen 过滤掉
        let old = "识别错的一整句话很长很长"
        let new = "完全另一段内容和上面没关系哈哈哈"
        let s = DiffLearner.suggest(old: old, new: new, maxLen: 5)
        // 我们把 maxLen 收窄到 5，所有 diff 段都超长 → 应该都被过滤
        XCTAssertTrue(s.isEmpty, "long rewrites should be filtered, got: \(s)")
    }

    func testDeduplication() {
        // 同一个 pattern 出现两次
        let s = DiffLearner.suggest(old: "梦梦", new: "孟孟")
        // 由于是逐字 replace，"梦"→"孟" 应该只出一条
        let patterns = Set(s.map { $0.pattern })
        XCTAssertEqual(patterns.count, s.count, "duplicates: \(s)")
    }
}