import Foundation
import Observation
import AppKit
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "Settings")

/// 触发键 已经在 Core/HotKey 里定义；此处做 user-facing label。
extension TriggerKey {
    var userLabel: String {
        switch self {
        case .fn: return "Fn"
        case .rightOption: return "右 Option"
        case .f13: return "F13"
        }
    }
}

/// 全局设置（UserDefaults 落盘）。变量改动 = 立即写盘 + UI 重绘。
@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    // MARK: - 通用
    var launchAtLogin: Bool {
        didSet { write() }
    }
    var showInDock: Bool {
        didSet { write(); applyDockPolicy() }
    }
    var notificationsEnabled: Bool {
        didSet { write() }
    }

    // MARK: - 录音
    var triggerKey: TriggerKey {
        didSet { write(); onTriggerKeyChange?(triggerKey) }
    }
    var maxRecordingSeconds: Int {  // 60..1800
        didSet { write() }
    }
    var soundFeedback: Bool {
        didSet { write() }
    }

    // MARK: - 转写
    var transcriptionLanguage: String {  // "auto" | "zh" | "en" | …
        didSet { write() }
    }
    var whisperBinaryPath: String {
        didSet { write() }
    }
    var whisperModelPath: String {
        didSet { write() }
    }

    // MARK: - 后处理
    var cleanFillerWords: Bool { didSet { write() } }
    var dedupRepeats: Bool { didSet { write() } }
    var convertTraditionalToSimplified: Bool { didSet { write() } }

    // MARK: - hooks
    var onTriggerKeyChange: ((TriggerKey) -> Void)?

    // MARK: - 内部
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.showInDock = defaults.bool(forKey: Keys.showInDock)
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        self.triggerKey = TriggerKey(rawValue: defaults.string(forKey: Keys.triggerKey) ?? "") ?? .fn
        self.maxRecordingSeconds = defaults.object(forKey: Keys.maxRecordingSeconds) as? Int ?? 600
        self.soundFeedback = defaults.object(forKey: Keys.soundFeedback) as? Bool ?? true
        self.transcriptionLanguage = defaults.string(forKey: Keys.transcriptionLanguage) ?? "zh"
        self.whisperBinaryPath = defaults.string(forKey: Keys.whisperBinaryPath) ?? "/opt/homebrew/bin/whisper-cli"
        self.whisperModelPath = defaults.string(forKey: Keys.whisperModelPath) ?? "/opt/homebrew/share/whisper.cpp/ggml-medium.bin"
        self.cleanFillerWords = defaults.object(forKey: Keys.cleanFillerWords) as? Bool ?? true
        self.dedupRepeats = defaults.object(forKey: Keys.dedupRepeats) as? Bool ?? true
        self.convertTraditionalToSimplified = defaults.object(forKey: Keys.convertTraditionalToSimplified) as? Bool ?? true
    }

    private func write() {
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        defaults.set(showInDock, forKey: Keys.showInDock)
        defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        defaults.set(triggerKey.rawValue, forKey: Keys.triggerKey)
        defaults.set(maxRecordingSeconds, forKey: Keys.maxRecordingSeconds)
        defaults.set(soundFeedback, forKey: Keys.soundFeedback)
        defaults.set(transcriptionLanguage, forKey: Keys.transcriptionLanguage)
        defaults.set(whisperBinaryPath, forKey: Keys.whisperBinaryPath)
        defaults.set(whisperModelPath, forKey: Keys.whisperModelPath)
        defaults.set(cleanFillerWords, forKey: Keys.cleanFillerWords)
        defaults.set(dedupRepeats, forKey: Keys.dedupRepeats)
        defaults.set(convertTraditionalToSimplified, forKey: Keys.convertTraditionalToSimplified)
    }

    private func applyDockPolicy() {
        // showInDock=true → .regular；false → .accessory（菜单栏-only）
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private enum Keys {
        static let launchAtLogin = "settings.launchAtLogin"
        static let showInDock = "settings.showInDock"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let triggerKey = "settings.triggerKey"
        static let maxRecordingSeconds = "settings.maxRecordingSeconds"
        static let soundFeedback = "settings.soundFeedback"
        static let transcriptionLanguage = "settings.transcriptionLanguage"
        static let whisperBinaryPath = "settings.whisperBinaryPath"
        static let whisperModelPath = "settings.whisperModelPath"
        static let cleanFillerWords = "settings.cleanFillerWords"
        static let dedupRepeats = "settings.dedupRepeats"
        static let convertTraditionalToSimplified = "settings.convertTraditionalToSimplified"
    }
}
