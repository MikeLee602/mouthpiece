import XCTest
@testable import Mouthpiece

@MainActor
final class HistoryStoreTests: XCTestCase {

    func testSaveAndFetch() throws {
        let store = try HistoryStore(inMemory: true)
        let draft = TranscriptionEntryDraft(
            timestamp: Date(),
            rawText: "嗯你好",
            cleanedText: "你好",
            language: "zh",
            durationSeconds: 1.2,
            appName: "Test"
        )
        store.save(draft)
        let items = store.fetchRecent(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.cleanedText, "你好")
    }

    func testPurgeOlderThan() throws {
        let store = try HistoryStore(inMemory: true)
        let old = Date(timeIntervalSinceNow: -86400 * 40)
        let recent = Date()
        store.save(.init(timestamp: old, rawText: "old", cleanedText: "old",
                         language: "zh", durationSeconds: 1, appName: nil))
        store.save(.init(timestamp: recent, rawText: "new", cleanedText: "new",
                         language: "zh", durationSeconds: 1, appName: nil))
        store.purgeOlderThan(Date(timeIntervalSinceNow: -86400 * 30))
        let items = store.fetchRecent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.cleanedText, "new")
    }

    func testDelete() throws {
        let store = try HistoryStore(inMemory: true)
        store.save(.init(timestamp: Date(), rawText: "a", cleanedText: "a",
                         language: "zh", durationSeconds: 1, appName: nil))
        store.save(.init(timestamp: Date(), rawText: "b", cleanedText: "b",
                         language: "zh", durationSeconds: 1, appName: nil))
        let items = store.fetchRecent()
        XCTAssertEqual(items.count, 2)
        if let id = items.first?.id {
            store.delete(id: id)
        }
        XCTAssertEqual(store.fetchRecent().count, 1)
    }
}
