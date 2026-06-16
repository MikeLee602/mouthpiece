import Foundation
import SwiftData

/// 词典存储。共用 HistoryStore 的 ModelContainer。
@MainActor
final class DictionaryStore {
    private let container: ModelContainer

    /// 直接从 HistoryStore 借容器。
    init(sharing history: HistoryStore) {
        self.container = history.containerForSharing
    }

    private var context: ModelContext { container.mainContext }

    func add(_ draft: DictionaryEntryDraft) {
        let e = DictionaryEntry(
            pattern: draft.pattern,
            replacement: draft.replacement,
            caseInsensitive: draft.caseInsensitive,
            note: draft.note
        )
        context.insert(e)
        try? context.save()
    }

    func update(_ entry: DictionaryEntry) {
        try? context.save()
    }

    func delete(id: UUID) {
        let pred = #Predicate<DictionaryEntry> { $0.id == id }
        let desc = FetchDescriptor<DictionaryEntry>(predicate: pred)
        if let e = (try? context.fetch(desc))?.first {
            context.delete(e)
            try? context.save()
        }
    }

    func deleteAll() {
        let desc = FetchDescriptor<DictionaryEntry>()
        for e in (try? context.fetch(desc)) ?? [] {
            context.delete(e)
        }
        try? context.save()
    }

    func fetchAll() -> [DictionaryEntry] {
        let desc = FetchDescriptor<DictionaryEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(desc)) ?? []
    }

    /// 取一份不可变快照，给 actor / 后台线程用。
    func snapshot() -> [DictionaryRule] {
        fetchAll()
            .filter { $0.enabled }
            .map { DictionaryRule(pattern: $0.pattern, replacement: $0.replacement, caseInsensitive: $0.caseInsensitive) }
    }
}

/// 不可变规则快照，跨线程安全。
struct DictionaryRule: Sendable, Equatable {
    let pattern: String
    let replacement: String
    let caseInsensitive: Bool

    func apply(to text: String) -> String {
        guard !pattern.isEmpty else { return text }
        let opts: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
        return text.replacingOccurrences(of: pattern, with: replacement, options: opts)
    }
}

extension Array where Element == DictionaryRule {
    func apply(to text: String) -> String {
        var s = text
        for rule in self { s = rule.apply(to: s) }
        return s
    }
}
