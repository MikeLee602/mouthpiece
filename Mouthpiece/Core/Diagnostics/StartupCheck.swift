import Foundation

/// 启动自检：检查二进制 / 模型 / 权限。
/// 不抛异常——只报告 issues。UI 决定怎么提示。
struct StartupCheck {
    enum IssueLevel: Sendable {
        case warning
        case error
    }
    struct Issue: Identifiable, Sendable {
        let id = UUID()
        let level: IssueLevel
        let title: String
        let detail: String
        let fixHint: String?
    }

    static func run(
        whisperBinary: String,
        whisperModel: String,
        whisperSmallModel: String = "/opt/homebrew/share/whisper.cpp/ggml-small.bin",
        opencc: String = "/opt/homebrew/bin/opencc"
    ) -> [Issue] {
        var issues: [Issue] = []
        let fm = FileManager.default

        if !fm.fileExists(atPath: whisperBinary) {
            issues.append(.init(
                level: .error,
                title: "找不到 whisper-cli",
                detail: "路径：\(whisperBinary)",
                fixHint: "运行 `brew install whisper-cpp`，或在 设置 → 转写 中重新选择"
            ))
        }
        if !fm.fileExists(atPath: whisperModel) {
            issues.append(.init(
                level: .error,
                title: "找不到 Whisper 模型",
                detail: "路径：\(whisperModel)",
                fixHint: "下载 ggml 模型并在 设置 → 转写 中选择文件"
            ))
        }
        if !fm.fileExists(atPath: whisperSmallModel) {
            issues.append(.init(
                level: .warning,
                title: "未安装 small 模型（实时预览将不可用）",
                detail: "路径：\(whisperSmallModel)",
                fixHint: "下载 ggml-small.bin 到该路径，启用录音中的实时蹦字预览。最终识别仍然走 medium 模型，质量不受影响。"
            ))
        }
        if !fm.fileExists(atPath: opencc) {
            issues.append(.init(
                level: .warning,
                title: "未安装 OpenCC（简繁转换将跳过）",
                detail: "路径：\(opencc)",
                fixHint: "运行 `brew install opencc` 启用自动繁→简"
            ))
        }
        return issues
    }
}
