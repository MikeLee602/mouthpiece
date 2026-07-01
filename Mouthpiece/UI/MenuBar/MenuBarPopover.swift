import SwiftUI
import AppKit

/// 菜单栏 popover 主体。
/// - 顶部状态卡（idle / recording / transcribing / done / error）
/// - 录音提示
/// - 最近 5 条历史
/// - 操作区：主窗 / 设置 / 重新加载模型 / 退出
struct MenuBarPopover: View {

    let coordinator: AppCoordinator
    let openMain: () -> Void
    let openSettings: () -> Void

    @State private var refreshTick: Int = 0
    @State private var recents: [TranscriptionEntry] = []
    @State private var showAddDict: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            permissionBanner
            issuesBanner
            statusCard
            Divider()
            hint
            Divider()
            recentsSection
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            coordinator.permission.refresh()
            reload()
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            // 状态卡跟着 phase 变；同时偶尔刷新历史 + 权限。
            refreshTick &+= 1
            if refreshTick % 2 == 0 {
                coordinator.permission.refresh()
            }
            if refreshTick % 4 == 0 {
                reload()
            }
        }
    }

    @ViewBuilder
    private var permissionBanner: some View {
        let mic = coordinator.permission.microphone
        let acc = coordinator.permission.accessibility
        let micOK = mic == .granted
        let accOK = acc == .granted
        if !micOK || !accOK {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.red)
                    Text("权限未就绪").font(.caption.weight(.semibold))
                }
                if !micOK {
                    permissionRow(
                        title: "麦克风",
                        statusText: micText(mic),
                        action: "打开设置",
                        run: { coordinator.permission.openMicrophoneSettings() }
                    )
                }
                if !accOK {
                    permissionRow(
                        title: "辅助功能（粘贴需要）",
                        statusText: "未授权 — Cmd+V 无法触发",
                        action: "打开设置",
                        run: { coordinator.permission.openAccessibilitySettings() }
                    )
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func permissionRow(title: String, statusText: String, action: String, run: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2.weight(.medium))
                Text(statusText).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action, action: run)
                .buttonStyle(.borderless)
                .font(.caption2)
                .foregroundStyle(.tint)
        }
    }

    private func micText(_ status: MicrophonePermission) -> String {
        switch status {
        case .granted: return "已授权"
        case .denied: return "已被拒绝"
        case .notDetermined: return "等待首次授权"
        }
    }

    @ViewBuilder
    private var issuesBanner: some View {
        let errors = coordinator.startupIssues.filter { $0.level == .error }
        if !errors.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("无法转写").font(.caption.weight(.semibold))
                    Text(errors.first!.title)
                        .font(.caption2).foregroundStyle(.secondary)
                    if let hint = errors.first!.fixHint {
                        Text(hint).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Sections

    private var statusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: phaseIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(phaseColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(phaseTitle).font(.headline)
                Text(phaseSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var hint: some View {
        HStack(spacing: 6) {
            Image(systemName: "command")
            Text(hintText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var hintText: String {
        let key = AppSettings.shared.triggerKey.userLabel
        switch AppSettings.shared.hotKeyMode {
        case .pushToTalk: return "按住 \(key) 录音，松开自动粘贴"
        case .toggle: return "按一下 \(key) 开始，再按一下停止"
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("最近").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !recents.isEmpty {
                    Button("全部 →") { openMain() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            if recents.isEmpty {
                Text("还没有转写记录")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(recents.prefix(5), id: \.id) { entry in
                    recentRow(entry)
                }
            }
        }
    }

    private func recentRow(_ entry: TranscriptionEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.cleanedText)
                    .font(.system(size: 12))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(relativeTime(entry.timestamp))
                    if let app = entry.appName, !app.isEmpty {
                        Text("·")
                        Text(app)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Button {
                copyToClipboard(entry.cleanedText)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("复制到剪贴板")
        }
        .padding(.vertical, 2)
    }

    private var actions: some View {
        VStack(spacing: 6) {
            // 快速添加词典 —— 一等公民，明显位置，一键弹表单
            Button {
                showAddDict = true
            } label: {
                Label("添加词典（记住这个词）", systemImage: "plus.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)

            HStack(spacing: 8) {
                Button {
                    openMain()
                } label: {
                    Label("嘴替", systemImage: "rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    openSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 8) {
                Button {
                    Task { @MainActor in
                        await coordinator.loadModelIfNeeded()
                    }
                } label: {
                    Label("重载模型", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .controlSize(.small)
        .sheet(isPresented: $showAddDict) {
            QuickAddDictionarySheet { draft in
                coordinator.dictionary.add(draft)
            }
        }
    }

    // MARK: - Helpers

    private func reload() {
        recents = coordinator.history.fetchRecent(limit: 5)
    }

    private func copyToClipboard(_ text: String) {
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

    // MARK: - Phase mapping

    private var phaseIcon: String {
        switch coordinator.phase {
        case .idle: return "circle.fill"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .cleaning: return "sparkles"
        case .polishing: return "wand.and.stars"
        case .injecting: return "keyboard.fill"
        case .done: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var phaseColor: Color {
        switch coordinator.phase {
        case .idle: return .secondary
        case .recording: return .red
        case .transcribing, .cleaning: return .blue
        case .polishing: return .yellow
        case .injecting: return .purple
        case .done: return .green
        case .error: return .orange
        }
    }

    private var phaseTitle: String {
        switch coordinator.phase {
        case .idle: return "待机中"
        case .recording: return "正在录音"
        case .transcribing: return "正在识别"
        case .cleaning: return "正在整理"
        case .polishing: return "AI 润色中"
        case .injecting: return "正在粘贴"
        case .done(let n): return "已完成 \(n) 字"
        case .error: return "出错了"
        }
    }

    private var phaseSubtitle: String {
        switch coordinator.phase {
        case .idle: return "Mouthpiece 已就绪"
        case .recording: return "正在采集音频…"
        case .transcribing: return "Whisper 处理中"
        case .cleaning: return "去重 / 转简"
        case .polishing: return "DeepSeek 修字 / 排版"
        case .injecting: return "粘贴到当前应用"
        case .done: return "已粘贴到当前光标位置"
        case .error(let msg): return msg
        }
    }
}
