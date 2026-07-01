import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 历史列表：搜索 + 多选 + 复制 / 删除 / 导出 JSON。
struct HistoryListView: View {
    let coordinator: AppCoordinator

    @State private var query: String = ""
    @State private var entries: [TranscriptionEntry] = []
    @State private var selection: Set<UUID> = []
    @State private var showingDeleteConfirm = false
    @State private var editingEntry: TranscriptionEntry?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reload() }
        .onChange(of: query) { reload() }
        .alert("删除选中的 \(selection.count) 条？", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                coordinator.history.delete(ids: selection)
                selection.removeAll()
                reload()
            }
        } message: {
            Text("这些记录会从设备上永久删除。")
        }
        .sheet(item: $editingEntry) { entry in
            EditHistoryEntrySheet(
                entry: entry,
                onSaveWithSuggestions: { newText, accepted in
                    // 1. 更新历史
                    coordinator.history.updateCleanedText(id: entry.id, newText: newText)
                    // 2. 接受的建议入词典
                    for s in accepted {
                        coordinator.dictionary.add(.init(
                            pattern: s.pattern,
                            replacement: s.replacement,
                            caseInsensitive: false,
                            note: "从纠错学习"
                        ))
                    }
                    reload()
                }
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索内容…", text: $query)
                .textFieldStyle(.plain)
            Spacer()
            if !selection.isEmpty {
                Text("\(selection.count) 选中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .controlSize(.small)
            }
            Button {
                exportSelectionOrAll()
            } label: {
                Label(selection.isEmpty ? "导出全部" : "导出选中", systemImage: "square.and.arrow.up")
            }
            .controlSize(.small)
            .disabled(entries.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var list: some View {
        Table(entries, selection: $selection) {
            TableColumn("内容") { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.cleanedText).lineLimit(2)
                    if entry.rawText != entry.cleanedText {
                        Text("原文: \(entry.rawText)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 240, ideal: 360)
            TableColumn("时间") { entry in
                Text(timeLabel(entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)
            TableColumn("应用") { entry in
                Text(entry.appName ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
            TableColumn("时长") { entry in
                Text(String(format: "%.1fs", entry.durationSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(60)
            TableColumn("字数") { entry in
                Text("\(entry.cleanedText.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(48)
            TableColumn("") { entry in
                HStack(spacing: 4) {
                    Button {
                        editingEntry = entry
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("纠错 / 学词")
                    Button {
                        copy(entry.cleanedText)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("复制")
                }
            }
            .width(60)
            .width(36)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "还没有转写记录" : "没有匹配的结果")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: -

    private func reload() {
        entries = coordinator.history.search(query: query, limit: 1000)
        // 清掉已不在列表里的选中项
        let ids = Set(entries.map(\.id))
        selection = selection.intersection(ids)
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "M/d HH:mm"
        }
        return f.string(from: date)
    }

    private func exportSelectionOrAll() {
        let target: [TranscriptionEntry] = selection.isEmpty
            ? entries
            : entries.filter { selection.contains($0.id) }
        guard !target.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "mouthpiece-history-\(f.string(from: Date())).json"
        panel.title = "导出历史"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let payload: [[String: Any]] = target.map { e in
                    [
                        "id": e.id.uuidString,
                        "timestamp": ISO8601DateFormatter().string(from: e.timestamp),
                        "rawText": e.rawText,
                        "cleanedText": e.cleanedText,
                        "language": e.language,
                        "durationSeconds": e.durationSeconds,
                        "appName": e.appName ?? NSNull()
                    ]
                }
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
                try data.write(to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
