import Foundation

/// 从"识别出的原文"和"用户改后的文本"里 diff 出词典建议。
///
/// 策略：LCS-based 分段 —— 找出保持不变的最长公共子序列，
/// 中间的差异段成对导出为 (旧, 新)。
///
/// 例：
///   old = "王梦松和赵远远的内容是一架报价体系"
///   new = "王孟松和赵远任的内容是一套报价体系"
///   → [("梦", "孟"), ("远", "任"), ("架", "套")]
///
/// 单字 diff 太琐碎，我们会：
/// - 合并相邻的 diff 段（"王梦松" 和 "王孟松" → 出 ("梦", "孟") 后与相邻扩展）
/// - 过滤只在标点/空格/大小写上的差异
/// - 去掉过长的 diff（超过 20 字大概率是重写而不是纠错）
enum DiffLearner {

    struct Suggestion: Equatable, Hashable {
        let pattern: String       // 旧的（识别错的）
        let replacement: String   // 新的（用户改的）
    }

    static func suggest(old: String, new: String, maxLen: Int = 20) -> [Suggestion] {
        if old == new { return [] }
        let a = Array(old)
        let b = Array(new)
        let ops = editOps(a, b)
        // ops 里连续的 non-equal 合并成一个 diff 段
        var out: [Suggestion] = []
        var oldSeg = ""
        var newSeg = ""
        var flushed = Set<Suggestion>()
        func flush() {
            let p = oldSeg.trimmingCharacters(in: .whitespaces)
            let r = newSeg.trimmingCharacters(in: .whitespaces)
            oldSeg = ""; newSeg = ""
            guard !p.isEmpty || !r.isEmpty else { return }
            guard p != r else { return }
            guard p.count <= maxLen, r.count <= maxLen else { return }
            // 只在标点/空格上不同，不算学习
            if isPunctSpaceOnly(p) && isPunctSpaceOnly(r) { return }
            let s = Suggestion(pattern: p, replacement: r)
            if !flushed.contains(s) {
                out.append(s)
                flushed.insert(s)
            }
        }
        for op in ops {
            switch op {
            case .equal:
                flush()
            case .delete(let c):
                oldSeg.append(c)
            case .insert(let c):
                newSeg.append(c)
            case .replace(let old, let new):
                oldSeg.append(old)
                newSeg.append(new)
            }
        }
        flush()
        return out
    }

    // MARK: - LCS-based edit ops

    private enum Op {
        case equal
        case delete(Character)
        case insert(Character)
        case replace(Character, Character)
    }

    private static func editOps(_ a: [Character], _ b: [Character]) -> [Op] {
        let m = a.count, n = b.count
        // DP 表：dp[i][j] = a[0..<i] → b[0..<j] 的最少编辑距离
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m where m > 0 {
            for j in 1...n where n > 0 {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
                }
            }
        }
        var ops: [Op] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i-1] == b[j-1] {
                ops.append(.equal)
                i -= 1; j -= 1
            } else if i > 0 && j > 0 && dp[i][j] == dp[i-1][j-1] + 1 {
                ops.append(.replace(a[i-1], b[j-1]))
                i -= 1; j -= 1
            } else if j > 0 && dp[i][j] == dp[i][j-1] + 1 {
                ops.append(.insert(b[j-1]))
                j -= 1
            } else if i > 0 {
                ops.append(.delete(a[i-1]))
                i -= 1
            }
        }
        return ops.reversed()
    }

    private static let punctuationSet: CharacterSet = {
        var s = CharacterSet.punctuationCharacters
        s.formUnion(.whitespacesAndNewlines)
        s.formUnion(.symbols)
        return s
    }()

    private static func isPunctSpaceOnly(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { punctuationSet.contains($0) }
    }
}