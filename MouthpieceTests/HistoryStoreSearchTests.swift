import XCTest
@testable import Mouthpiece

@MainActor
final class HistoryStoreSearchTests: XCTestCase {

    func testSearchEmptyReturnsRecent() throws {
        let store = try HistoryStore(inMemory: true)
        store.save(.init(timestamp: Date(), rawText: "你好世界",
                         cleanedText: "你好世界", language: "zh",
                         durationSeconds: 1, appName: nil))
        let results = store.search(query: "")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchMatchesRawAndCleaned() throws {
        let store = try HistoryStore(inMemory: true)
        store.save(.init(timestamp: Date(), rawText: "嗯，今天天气真好",
                         cleanedText: "今天天气真好", language: "zh",
                         durationSeconds: 1, appName: nil))
        store.save(.init(timestamp: Date(), rawText: "再见",
                         cleanedText: "再见", language: "zh",
                         durationSeconds: 1, appName: nil))
        XCTAssertEqual(store.search(query: "天气").count, 1)
        XCTAssertEqual(store.search(query: "再见").count, 1)
        XCTAssertEqual(store.search(query: "不存在").count, 0)
        // 命中 raw 不命中 cleaned 也算
        XCTAssertEqual(store.search(query: "嗯").count, 1)
    }

    func testDeleteIds() throws {
        let store = try HistoryStore(inMemory: true)
        store.save(.init(timestamp: Date(), rawText: "a", cleanedText: "a",
                         language: "zh", durationSeconds: 1, appName: nil))
        store.save(.init(timestamp: Date(), rawText: "b", cleanedText: "b",
                         language: "zh", durationSeconds: 1, appName: nil))
        store.save(.init(timestamp: Date(), rawText: "c", cleanedText: "c",
                         language: "zh", durationSeconds: 1, appName: nil))
        let all = store.fetchRecent()
        XCTAssertEqual(all.count, 3)
        let toDelete = Set(all.prefix(2).map(\.id))
        store.delete(ids: toDelete)
        XCTAssertEqual(store.fetchRecent().count, 1)
    }

    func testDeleteAll() throws {
        let store = try HistoryStore(inMemory: true)
        for i in 0..<5 {
            store.save(.init(timestamp: Date(), rawText: "\(i)", cleanedText: "\(i)",
                             language: "zh", durationSeconds: 1, appName: nil))
        }
        XCTAssertEqual(store.fetchRecent().count, 5)
        store.deleteAll()
        XCTAssertEqual(store.fetchRecent().count, 0)
    }
}
