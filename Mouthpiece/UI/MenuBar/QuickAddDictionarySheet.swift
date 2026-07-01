import SwiftUI
import AppKit

/// 快速添加词典 sheet —— 菜单栏一键触达。
///
/// 相比主窗词典页的 Add sheet：
/// - 支持从最近一条历史里带填「识别为」
/// - 更紧凑
/// - 保存后自动关掉
struct QuickAddDictionarySheet: View {
    let onSave: (DictionaryEntryDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var caseInsensitive = false
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .foregroundStyle(.tint)
                Text("记住这个词").font(.title3.bold())
                Spacer()
            }

            Text("下次识别到「识别为」时，自动替换成「应该是」。")
                .font(.callout)
                .foregroundStyle(.secondary)

            Form {
                TextField("识别为", text: $pattern, prompt: Text("如：王梦松"))
                    .textFieldStyle(.roundedBorder)
                TextField("应该是", text: $replacement, prompt: Text("如：王孟松"))
                    .textFieldStyle(.roundedBorder)
                Toggle("忽略大小写", isOn: $caseInsensitive)
                TextField("备注", text: $note, prompt: Text("可选，比如「团队成员姓名」"))
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.columns)

            // 从剪贴板贴入 pattern —— 常见 workflow：粘贴 app 里错的那段，然后手动改正
            Button {
                if let s = NSPasteboard.general.string(forType: .string) {
                    pattern = s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Label("从剪贴板贴入「识别为」", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    let r = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !p.isEmpty else { return }
                    onSave(.init(
                        pattern: p,
                        replacement: r,
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