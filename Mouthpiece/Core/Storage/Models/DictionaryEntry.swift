import Foundation
import SwiftData

/// 词典条目：把识别出的 `pattern` 替换为 `replacement`。
/// 用例："GPT" 被 whisper 识别成 "纸笔体" / "鸡屁体"，加一行规则修正回来；
/// 或者全公司专有名词的拼写修正（如「京me」「真自营」）。
@Model
final class DictionaryEntry {
    var id: UUID
    var pattern: String
    var replacement: String
    var caseInsensitive: Bool
    var enabled: Bool
    var createdAt: Date
    var note: String?

    init(id: UUID = UUID(),
         pattern: String,
         replacement: String,
         caseInsensitive: Bool = false,
         enabled: Bool = true,
         createdAt: Date = Date(),
         note: String? = nil) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
        self.caseInsensitive = caseInsensitive
        self.enabled = enabled
        self.createdAt = createdAt
        self.note = note
    }
}

/// Sendable 草稿，跨 actor 安全。
struct DictionaryEntryDraft: Sendable {
    let pattern: String
    let replacement: String
    let caseInsensitive: Bool
    let note: String?
}
