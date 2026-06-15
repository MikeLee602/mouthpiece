import AppKit

enum TriggerKey: String, CaseIterable, Codable, Sendable {
    case fn = "Fn"
    case rightOption = "Right Option"
    case f13 = "F13"

    var modifierFlag: NSEvent.ModifierFlags? {
        switch self {
        case .fn: return .function
        case .rightOption: return [.option]
        case .f13: return nil
        }
    }

    var displayName: String { rawValue }
}

enum HotKeyEvent: Equatable, Sendable {
    case pressed
    case released
}
