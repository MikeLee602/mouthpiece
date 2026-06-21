import XCTest
@testable import Mouthpiece

final class StreamingTranscriberTests: XCTestCase {

    func testHallucinationDetection() {
        XCTAssertTrue(StreamingTranscriber.isHallucination("(字幕製作:貝爾)"))
        XCTAssertTrue(StreamingTranscriber.isHallucination("感謝觀看"))
        XCTAssertTrue(StreamingTranscriber.isHallucination("Subtitles by community"))
        // 实测漏过的 short bracket-only 幻觉
        XCTAssertTrue(StreamingTranscriber.isHallucination("(在這裡)"))
        XCTAssertTrue(StreamingTranscriber.isHallucination("(背景音)"))
        XCTAssertTrue(StreamingTranscriber.isHallucination("（噪音）"))
        // v0.1.0 实测漏过：「字幕君」「我看不懂」
        XCTAssertTrue(StreamingTranscriber.isHallucination("(字幕君:我看不懂,请问你会不会用音乐?我看不懂)"))
        XCTAssertTrue(StreamingTranscriber.isHallucination("感謝收看"))
        XCTAssertFalse(StreamingTranscriber.isHallucination("这是一个测试"))
        XCTAssertFalse(StreamingTranscriber.isHallucination("今天天气真好"))
    }

    func testLongestSuffixPrefix() {
        XCTAssertEqual(StreamingTranscriber.longestSuffixPrefix("abcdef", "defghi"), 3)
        XCTAssertEqual(StreamingTranscriber.longestSuffixPrefix("hello", "world"), 0)
        XCTAssertEqual(StreamingTranscriber.longestSuffixPrefix("", "abc"), 0)
        XCTAssertEqual(StreamingTranscriber.longestSuffixPrefix("xyz", ""), 0)
        XCTAssertEqual(StreamingTranscriber.longestSuffixPrefix("abc", "abc"), 3)
        // 中文：「这是一个」末尾「一个」+「一个测试」开头「一个」 = 重叠 2 字
        XCTAssertEqual(StreamingTranscriber.longestSuffixPrefix("这是一个", "一个测试"), 2)
    }

    @MainActor
    func testMergePartialExtension() {
        // newTail 是 lastTail 的扩展（同一窗多识别了几个字）
        let s = StreamingTranscriber(binaryPath: "/dev/null", modelPath: "/dev/null")
        s.lastTail = "这是一个"
        s.mergePartial("这是一个测试")
        XCTAssertEqual(s.committed, "")
        XCTAssertEqual(s.lastTail, "这是一个测试")
    }

    @MainActor
    func testMergePartialOverlap() {
        // 滑窗滚动 — 上次「这是一个测试」，这次「一个测试任务」
        // 重叠 = 「一个测试」（4 字）
        // commit = 「这是」，lastTail = 「一个测试任务」
        let s = StreamingTranscriber(binaryPath: "/dev/null", modelPath: "/dev/null")
        s.lastTail = "这是一个测试"
        s.mergePartial("一个测试任务")
        XCTAssertEqual(s.committed, "这是")
        XCTAssertEqual(s.lastTail, "一个测试任务")
    }

    @MainActor
    func testMergePartialNoOverlap() {
        // 滑窗滚动太多，找不到重叠 — 整个 lastTail commit
        let s = StreamingTranscriber(binaryPath: "/dev/null", modelPath: "/dev/null")
        s.committed = "前文 "
        s.lastTail = "上一段"
        s.mergePartial("完全不同")
        XCTAssertEqual(s.committed, "前文 上一段")
        XCTAssertEqual(s.lastTail, "完全不同")
    }

    @MainActor
    func testMergePartialIgnoresPunctuation() {
        // 实测 bug：whisper 同一段两次识别可能加标点；累积应该按骨架对齐
        // 上次「这是一个长达」+ 这次「现在开始录制 这是一个长达10秒」
        // 重叠（按骨架）= 「这是一个长达」 → commit "" + lastTail = 第二次的整段
        // 注意第一次「现在开始录制」也要保留 — 所以更好的测试场景：
        let s = StreamingTranscriber(binaryPath: "/dev/null", modelPath: "/dev/null")
        s.lastTail = "好的现在开始录制这是一个长达"
        s.mergePartial("现在开始录制 这是一个长达10秒钟")
        // 骨架重叠 = "现在开始录制这是一个长达" (12 字)
        // commit = "好的"，lastTail = "现在开始录制 这是一个长达10秒钟"
        XCTAssertEqual(s.committed, "好的")
        XCTAssertEqual(s.lastTail, "现在开始录制 这是一个长达10秒钟")
    }

    func testSkeleton() {
        XCTAssertEqual(StreamingTranscriber.skeleton("Hello, world!"), "Helloworld")
        XCTAssertEqual(StreamingTranscriber.skeleton("这是一个 测试。"), "这是一个测试")
        XCTAssertEqual(StreamingTranscriber.skeleton("a b c"), "abc")
    }

    func testIndexInOriginal() {
        // "这是一个 测试" 取前 4 字骨架 = "这是一个" → 切到含空格之前，4 个字符
        XCTAssertEqual(StreamingTranscriber.indexInOriginal(skeletonPrefixCount: 4, original: "这是一个 测试"), 4)
        // "这是, 一个" 取前 3 字 = "这是一" → 切到第 5 个字符（"这是, 一"）
        XCTAssertEqual(StreamingTranscriber.indexInOriginal(skeletonPrefixCount: 3, original: "这是, 一个"), 5)
    }

    func testFuzzySuffixPrefixExact() {
        // 至少要 4 字才认作重叠
        XCTAssertEqual(StreamingTranscriber.fuzzySuffixPrefix("这是一次测试", "测试任务"), 0)
        // 4 字以上的重叠正常返回
        XCTAssertEqual(StreamingTranscriber.fuzzySuffixPrefix("abcdefgh", "efghxyzw"), 4)
    }

    func testFuzzySuffixPrefixToleratesOneOff() {
        // 真实 whisper bug：「这是一次测试使用」+「这是一次测试是用vscode...」
        // 「使用」vs「是用」一字不同；6 字重叠 5/6 = 83% 应该判为重叠
        let oldSkel = "这是一次测试使用"
        let newSkel = "这是一次测试是用vscode进行测试时间10秒"
        let overlap = StreamingTranscriber.fuzzySuffixPrefix(oldSkel, newSkel)
        XCTAssertGreaterThanOrEqual(overlap, 6, "应找到 \(overlap) 字重叠")
    }

    func testFuzzySuffixPrefixRejectsShortMatch() {
        // 不到 4 字的"重叠"不算
        XCTAssertEqual(StreamingTranscriber.fuzzySuffixPrefix("abcXY", "XYdef"), 0)
    }

    @MainActor
    func testMergeWhisperRecognitionDrift() {
        // 端到端复现真实 bug：首段「这是一次测试使用」+ 二段「这是一次测试是用vscode进行测试时间10秒」
        // 二段几乎完整覆盖了一段（8 字里 7 字相同 = 87.5%）→ fuzzy match 8 字
        // 期望：commit ""，lastTail = 第二段全部，无重复
        let s = StreamingTranscriber(binaryPath: "/dev/null", modelPath: "/dev/null")
        s.lastTail = "这是一次测试使用"
        s.mergePartial("这是一次测试是用vscode进行测试时间10秒")
        XCTAssertEqual(s.lastTail, "这是一次测试是用vscode进行测试时间10秒")
        // 最关键：合并后总文本不能包含两次「这是一次测试」
        let merged = s.committed + s.lastTail
        let occurrences = merged.components(separatedBy: "这是一次测试").count - 1
        XCTAssertEqual(occurrences, 1, "expected single occurrence, got: '\(merged)'")
    }
}
