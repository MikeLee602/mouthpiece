import SwiftUI

/// 词典管理：定义把识别出的 pattern 替换成 replacement 的规则。
/// 应用时机：cleaned + simplified 之后，inject 之前。
struct DictionaryView: View {
    let coordinator: AppCoordinator

    @State private var entries: [DictionaryEntry] = []
    @State private var selection: Set<UUID> = []
    @State private var showAddSheet = false

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
        .sheet(isPresented: $showAddSheet) {
            AddDictionarySheet { draft in
                coordinator.dictionary.add(draft)
                reload()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("词典").font(.headline)
            Text("识别结果会按下面的规则替换")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !selection.isEmpty {
                Button(role: .destructive) {
                    for id in selection {
                        coordinator.dictionary.delete(id: id)
                    }
                    selection.removeAll()
                    reload()
                } label: {
                    Label("删除 \(selection.count)", systemImage: "trash")
                }
                .controlSize(.small)
            }
            Button {
                showAddSheet = true
            } label: {
                Label("新增", systemImage: "plus")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var list: some View {
        Table(entries, selection: $selection) {
            TableColumn("启用") { entry in
                Toggle("", isOn: Binding(
                    get: { entry.enabled },
                    set: { newValue in
                        entry.enabled = newValue
                        coordinator.dictionary.update(entry)
                        reload()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            .width(48)
            TableColumn("识别为") { entry in
                Text(entry.pattern).font(.system(size: 13, design: .monospaced))
            }
            .width(min: 100, ideal: 160)
            TableColumn("替换为") { entry in
                Text(entry.replacement).font(.system(size: 13, design: .monospaced))
            }
            .width(min: 100, ideal: 160)
            TableColumn("忽略大小写") { entry in
                Image(systemName: entry.caseInsensitive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.caseInsensitive ? Color.green : Color.secondary)
            }
            .width(80)
            TableColumn("备注") { entry in
                Text(entry.note ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 200)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("还没有词典规则").font(.callout).foregroundStyle(.secondary)
            Text("常见用法：把 whisper 识别错的专有名词修正回来\n（如 GPT、API、京东等）")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
            Button("添加第一条") { showAddSheet = true }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() {
        entries = coordinator.dictionary.fetchAll()
        let ids = Set(entries.map(\.id))
        selection = selection.intersection(ids)
    }
}

private struct AddDictionarySheet: View {
    let onSave: (DictionaryEntryDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var caseInsensitive = false
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新增词典规则").font(.title3.bold())
            Form {
                TextField("识别为", text: $pattern, prompt: Text("如：纸笔体"))
                TextField("替换为", text: $replacement, prompt: Text("如：GPT"))
                Toggle("忽略大小写", isOn: $caseInsensitive)
                TextField("备注", text: $note, prompt: Text("可选"))
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedPattern.isEmpty else { return }
                    onSave(.init(
                        pattern: trimmedPattern,
                        replacement: replacement,
                        caseInsensitive: caseInsensitive,
                        note: note.isEmpty ? nil : note
                    ))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
