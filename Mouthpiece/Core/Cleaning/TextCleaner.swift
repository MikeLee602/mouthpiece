import Foundation

struct TextCleaner: Sendable {

    func clean(_ text: String, options: CleanOptions) -> String {
        var s = text
        if options.removeFillers {
            s = removeFillers(s, list: CleanOptions.zhFillers + CleanOptions.enFillers + options.customFillers)
        }
        if options.removeRepetition {
            s = removeRepetition(s)
        }
        if options.normalizeSpaces {
            s = normalizeSpaces(s)
        }
        return s
    }

    private func removeFillers(_ text: String, list: [String]) -> String {
        var s = text
        for w in list {
            let escaped = NSRegularExpression.escapedPattern(for: w)
            let pattern: String
            if w.unicodeScalars.allSatisfy({ $0.isASCII }) {
                // English: word boundary, case-insensitive, optional trailing comma+space
                pattern = "(?i)\\b\(escaped)\\b\\s*,?\\s*"
            } else {
                // Chinese: direct match plus optional trailing punctuation
                pattern = "\(escaped)[，,。!?]?"
            }
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private func removeRepetition(_ text: String) -> String {
        // 1) Repeated single CJK chars (3+ in a row): 我我我 -> 我
        // Limit to CJK ranges so we don't collapse "hello" (ll) or legit pairs like "天天".
        // Require {2,} additional repeats (3+ total) so 2-char doublets stay intact.
        var s = text.replacingOccurrences(
            of: "([\\p{Han}])\\1{2,}",
            with: "$1",
            options: .regularExpression
        )
        // 2) English repeated words (case-insensitive)
        s = s.replacingOccurrences(
            of: "(?i)\\b(\\w+)(\\s+\\1\\b){1,}",
            with: "$1",
            options: .regularExpression
        )
        return s
    }

    private func normalizeSpaces(_ text: String) -> String {
        var s = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        // Remove space before Chinese/English punctuation
        s = s.replacingOccurrences(
            of: " ([，。,!?])",
            with: "$1",
            options: .regularExpression
        )
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
