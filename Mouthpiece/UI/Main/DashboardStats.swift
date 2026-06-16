import Foundation

/// 仪表盘汇总数据。所有计算都在 `compute(from:)` 一次性算出，
/// 避免 UI 多次遍历。
struct DashboardStats: Equatable, Sendable {
    var totalCount: Int = 0
    var todayCount: Int = 0
    var weekCount: Int = 0
    var totalChars: Int = 0
    var totalSeconds: Double = 0
    var avgChars: Double = 0
    var avgSeconds: Double = 0
    /// 最近 7 天每天的条数（index 0 = 6 天前，index 6 = 今天）
    var dailyCounts: [Int] = Array(repeating: 0, count: 7)
    var lastEntryAt: Date?

    static func compute(from entries: [TranscriptionEntry], now: Date = Date()) -> DashboardStats {
        var s = DashboardStats()
        s.totalCount = entries.count
        guard !entries.isEmpty else { return s }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        guard let weekAgoStart = cal.date(byAdding: .day, value: -6, to: startOfToday) else { return s }

        for e in entries {
            s.totalChars += e.cleanedText.count
            s.totalSeconds += e.durationSeconds

            if e.timestamp >= startOfToday {
                s.todayCount += 1
            }
            if e.timestamp >= weekAgoStart {
                let day = cal.dateComponents([.day], from: weekAgoStart, to: e.timestamp).day ?? 0
                let idx = max(0, min(6, day))
                s.dailyCounts[idx] += 1
                s.weekCount += 1
            }
        }

        s.avgChars = Double(s.totalChars) / Double(s.totalCount)
        s.avgSeconds = s.totalSeconds / Double(s.totalCount)
        s.lastEntryAt = entries.map(\.timestamp).max()
        return s
    }
}
