import XCTest
@testable import Mouthpiece

final class DashboardStatsTests: XCTestCase {

    func testEmpty() {
        let s = DashboardStats.compute(from: [])
        XCTAssertEqual(s.totalCount, 0)
        XCTAssertEqual(s.todayCount, 0)
        XCTAssertEqual(s.weekCount, 0)
        XCTAssertEqual(s.totalChars, 0)
        XCTAssertEqual(s.avgChars, 0)
        XCTAssertNil(s.lastEntryAt)
        XCTAssertEqual(s.dailyCounts, [0, 0, 0, 0, 0, 0, 0])
    }

    func testTodayWeekTotals() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 12))!
        let today = now
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let sixDaysAgo = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!.addingTimeInterval(60)
        let eightDaysAgo = cal.date(byAdding: .day, value: -8, to: now)!

        let entries = [
            entry(at: today, text: "你好", duration: 2),
            entry(at: today, text: "再见", duration: 1.5),
            entry(at: yesterday, text: "测试一二三", duration: 3),
            entry(at: sixDaysAgo, text: "边界", duration: 1),
            entry(at: eightDaysAgo, text: "应该不算本周", duration: 1),
        ]

        let s = DashboardStats.compute(from: entries, now: now)
        XCTAssertEqual(s.totalCount, 5)
        XCTAssertEqual(s.todayCount, 2)
        XCTAssertEqual(s.weekCount, 4, "8 天前的应该不计入本周")
        XCTAssertEqual(s.totalChars, 2 + 2 + 5 + 2 + 6)
        XCTAssertEqual(s.totalSeconds, 8.5, accuracy: 0.001)
        XCTAssertEqual(s.avgSeconds, 8.5 / 5, accuracy: 0.001)
        XCTAssertEqual(s.lastEntryAt, today)
    }

    func testDailyCountsBucketing() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 12))!
        let today = cal.startOfDay(for: now).addingTimeInterval(60)
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
        let entries = [
            entry(at: today, text: "a", duration: 1),
            entry(at: today, text: "b", duration: 1),
            entry(at: twoDaysAgo, text: "c", duration: 1),
        ]
        let s = DashboardStats.compute(from: entries, now: now)
        // dailyCounts[6] = 今天
        XCTAssertEqual(s.dailyCounts[6], 2)
        // dailyCounts[4] = 2 天前 (6-2)
        XCTAssertEqual(s.dailyCounts[4], 1)
        XCTAssertEqual(s.dailyCounts.reduce(0, +), 3)
    }

    // MARK: - helpers

    private func entry(at date: Date, text: String, duration: Double) -> TranscriptionEntry {
        TranscriptionEntry(
            timestamp: date,
            rawText: text,
            cleanedText: text,
            language: "zh",
            durationSeconds: duration,
            appName: nil
        )
    }
}
