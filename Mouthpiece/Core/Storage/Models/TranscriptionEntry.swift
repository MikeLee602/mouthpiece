import Foundation
import SwiftData

@Model
final class TranscriptionEntry: Identifiable {
    var id: UUID
    var timestamp: Date
    var rawText: String
    var cleanedText: String
    var language: String
    var durationSeconds: Double
    var appName: String?

    init(id: UUID = UUID(),
         timestamp: Date,
         rawText: String,
         cleanedText: String,
         language: String,
         durationSeconds: Double,
         appName: String?) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.language = language
        self.durationSeconds = durationSeconds
        self.appName = appName
    }
}

struct TranscriptionEntryDraft: Sendable {
    let timestamp: Date
    let rawText: String
    let cleanedText: String
    let language: String
    let durationSeconds: Double
    let appName: String?
}
