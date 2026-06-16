import Foundation
import SwiftData

@MainActor
final class HistoryStore {
    private let container: ModelContainer

    init(inMemory: Bool = false) throws {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        self.container = try ModelContainer(
            for: TranscriptionEntry.self, DictionaryEntry.self,
            configurations: cfg
        )
    }

    var context: ModelContext { container.mainContext }

    /// 给 DictionaryStore 共用容器。
    var containerForSharing: ModelContainer { container }

    func save(_ draft: TranscriptionEntryDraft) {
        let entry = TranscriptionEntry(
            timestamp: draft.timestamp,
            rawText: draft.rawText,
            cleanedText: draft.cleanedText,
            language: draft.language,
            durationSeconds: draft.durationSeconds,
            appName: draft.appName
        )
        context.insert(entry)
        try? context.save()
    }

    func fetchRecent(limit: Int = 50) -> [TranscriptionEntry] {
        var desc = FetchDescriptor<TranscriptionEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = limit
        return (try? context.fetch(desc)) ?? []
    }

    func delete(id: UUID) {
        let pred = #Predicate<TranscriptionEntry> { $0.id == id }
        let desc = FetchDescriptor<TranscriptionEntry>(predicate: pred)
        if let entry = (try? context.fetch(desc))?.first {
            context.delete(entry)
            try? context.save()
        }
    }

    func purgeOlderThan(_ date: Date) {
        let pred = #Predicate<TranscriptionEntry> { $0.timestamp < date }
        let desc = FetchDescriptor<TranscriptionEntry>(predicate: pred)
        for entry in (try? context.fetch(desc)) ?? [] {
            context.delete(entry)
        }
        try? context.save()
    }

    /// 关键词搜索 raw + cleaned。空 query 等同 fetchRecent。
    func search(query: String, limit: Int = 200) -> [TranscriptionEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fetchRecent(limit: limit) }
        let pred = #Predicate<TranscriptionEntry> {
            $0.rawText.contains(trimmed) || $0.cleanedText.contains(trimmed)
        }
        var desc = FetchDescriptor<TranscriptionEntry>(
            predicate: pred,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = limit
        return (try? context.fetch(desc)) ?? []
    }

    /// 批量删除。
    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let pred = #Predicate<TranscriptionEntry> { ids.contains($0.id) }
        let desc = FetchDescriptor<TranscriptionEntry>(predicate: pred)
        for entry in (try? context.fetch(desc)) ?? [] {
            context.delete(entry)
        }
        try? context.save()
    }

    /// 全部清空。
    func deleteAll() {
        let desc = FetchDescriptor<TranscriptionEntry>()
        for entry in (try? context.fetch(desc)) ?? [] {
            context.delete(entry)
        }
        try? context.save()
    }
}
