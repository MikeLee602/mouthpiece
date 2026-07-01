import SwiftUI

/// 纠错 & 学词 sheet。
///
/// 交互：
/// 1. 顶部大文本框显示当前 cleanedText，用户直接编辑
/// 2. 编辑时实时 diff，把 (旧, 新) 建议列在下方
/// 3. 每个建议一个复选框，用户勾选哪些真的入词典（默认全选）
/// 4. 「保存」把编辑后的文本写回历史 + 勾选的建议入词典
struct EditHistoryEntrySheet: View {
    let entry: TranscriptionEntry
    let onSaveWithSuggestions: (String, [DiffLearner.Suggestion]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedText: String = ""
    @State private var accepted: Set<DiffLearner.Suggestion> = []
    @State private var initialText: String = ""

    var suggestions: [DiffLearner.Suggestion] {
        DiffLearner.suggest(old: initialText, new: editedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "pencil.and.list.clipboard")
                    .foregroundStyle(.tint)
                Text("纠错并学习").font(.title3.bold())
                Spacer()
            }
            Text("修改错的字。保存后，AI 会记住这些改法，下次自动改对。")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("识别文本").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $editedText)
                    .font(.system(size: 13))
                    .frame(minHeight: 100, maxHeight: 200)
                    .padding(6)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5))
            }

            if entry.rawText != initialText {
                DisclosureGroup("查看 Whisper 原文") {
                    Text(entry.rawText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 4))
                        .textSelection(.enabled)
                }
                .font(.caption)
            }

            let sugs = suggestions
            if !sugs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("学习这些改法").font(.caption).foregroundStyle(.secondary)
                    ForEach(sugs, id: \.self) { s in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { accepted.contains(s) },
                                set: { on in
                                    if on { accepted.insert(s) } else { accepted.remove(s) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            HStack(spacing: 4) {
                                Text(s.pattern.isEmpty ? "（无）" : s.pattern)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .strikethrough()
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                                Text(s.replacement.isEmpty ? "（删除）" : s.replacement)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(8)
                .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSaveWithSuggestions(editedText, Array(accepted))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editedText == initialText)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            initialText = entry.cleanedText
            editedText = entry.cleanedText
        }
        .onChange(of: editedText) {
            // 编辑变化 → 默认全部勾选新建议
            accepted = Set(suggestions)
        }
    }
}