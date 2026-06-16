import SwiftUI
import Charts

/// 主窗仪表盘：4 个 KPI 卡 + 7 天柱图 + 最近 10 条历史。
struct DashboardView: View {
    let coordinator: AppCoordinator

    @State private var stats: DashboardStats = .init()
    @State private var recents: [TranscriptionEntry] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                kpiGrid
                weekChart
                recentList
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reload() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            reload()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("仪表盘").font(.largeTitle.bold())
            if let last = stats.lastEntryAt {
                Text("最近一次：\(relativeTime(last))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("还没开始用过——按住 Fn 试试")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - KPI cards

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            kpiCard(title: "今日", value: "\(stats.todayCount)", unit: "条", icon: "sun.max.fill", tint: .orange)
            kpiCard(title: "本周", value: "\(stats.weekCount)", unit: "条", icon: "calendar", tint: .blue)
            kpiCard(title: "累计转写", value: "\(stats.totalChars)", unit: "字", icon: "textformat", tint: .green)
            kpiCard(title: "平均时长", value: stats.totalCount == 0 ? "—" : String(format: "%.1f", stats.avgSeconds), unit: "秒/条", icon: "timer", tint: .purple)
        }
    }

    private func kpiCard(title: String, value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(unit).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Week chart

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近 7 天").font(.headline)
            Chart {
                ForEach(Array(stats.dailyCounts.enumerated()), id: \.offset) { idx, count in
                    BarMark(
                        x: .value("天", dayLabel(idx)),
                        y: .value("条数", count)
                    )
                    .foregroundStyle(.blue.gradient)
                    .cornerRadius(4)
                }
            }
            .frame(height: 140)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func dayLabel(_ idx: Int) -> String {
        let cal = Calendar.current
        guard let date = cal.date(byAdding: .day, value: idx - 6, to: cal.startOfDay(for: Date())) else {
            return ""
        }
        if idx == 6 { return "今" }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    // MARK: - Recent list

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近转写").font(.headline)
                Spacer()
                Text("\(recents.count) / 10")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if recents.isEmpty {
                Text("还没有记录")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recents.enumerated()), id: \.element.id) { idx, entry in
                        recentRow(entry)
                        if idx < recents.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func recentRow(_ entry: TranscriptionEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.cleanedText)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text(relativeTime(entry.timestamp))
                    Text("·")
                    Text("\(entry.cleanedText.count) 字")
                    if entry.durationSeconds > 0 {
                        Text("·")
                        Text(String(format: "%.1fs", entry.durationSeconds))
                    }
                    if let app = entry.appName, !app.isEmpty {
                        Text("·")
                        Text(app)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Button {
                copy(entry.cleanedText)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制")
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func reload() {
        let entries = coordinator.history.fetchRecent(limit: 5000)
        self.stats = DashboardStats.compute(from: entries)
        self.recents = Array(entries.prefix(10))
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "zh_CN")
        return f.localizedString(for: date, relativeTo: Date())
    }
}
