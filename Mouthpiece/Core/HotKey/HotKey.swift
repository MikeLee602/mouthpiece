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
    /// Toggle 模式下用——一次按下 = 切换录音状态。
    case toggled
}

/// 触发语义：按住 vs 切换。
enum HotKeyMode: String, CaseIterable, Codable, Sendable {
    /// 按住录音，松开停止（默认 / 经典）。
    case pushToTalk = "push-to-talk"
    /// 按一下开始，再按一下停止。
    case toggle = "toggle"

    var displayName: String {
        switch self {
        case .pushToTalk: return "按住说话"
        case .toggle: return "按一下开始 / 再按一下停止"
        }
    }
}
