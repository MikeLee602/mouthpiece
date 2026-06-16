import SwiftUI

/// 主窗壳：左侧 sidebar + 右侧内容。
/// - 仪表盘：今天上线
/// - 历史 / 词典：占位，P0-13 填
/// - 设置：占位，P0-14 填（独立窗也可走这）
struct MainWindowView: View {
    let coordinator: AppCoordinator

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case dashboard, history, dictionary, settings
        var id: String { rawValue }
        var label: String {
            switch self {
            case .dashboard: return "仪表盘"
            case .history: return "历史"
            case .dictionary: return "词典"
            case .settings: return "设置"
            }
        }
        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .history: return "clock.arrow.circlepath"
            case .dictionary: return "character.book.closed"
            case .settings: return "gearshape"
            }
        }
    }

    @State private var selection: Section = .dashboard

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { s in
                Label(s.label, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch selection {
            case .dashboard:
                DashboardView(coordinator: coordinator)
            case .history:
                HistoryListView(coordinator: coordinator)
            case .dictionary:
                DictionaryView(coordinator: coordinator)
            case .settings:
                SettingsView(coordinator: coordinator)
            }
        }
        .frame(minWidth: 820, minHeight: 540)
    }
}

private struct ComingSoonPanel: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(title).font(.title2.bold())
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 设置占位（独立窗口用）。P0-14 接入。
struct SettingsPlaceholderView: View {
    var body: some View {
        SettingsView(coordinator: nil)
    }
}
