import Foundation

/// AI 润色：把 ASR 输出过一遍 LLM，做错字修正 + 标点 + 排版（markdown 列表/段落）。
///
/// 实现思路：
/// - 读 ~/.config/mouthpiece/config.json 拿 API key（个人本地用，不入仓）
/// - 没配置 = 自动 disable，回退原文（不阻塞 pipeline）
/// - 失败（超时 / 网络 / 5xx）= 回退原文 + log warning
/// - 成功 = 返回润色后文本
protocol Polishing: Sendable {
    /// 当前是否已配置可用。false 时调用 polish 直接返回原文。
    var isConfigured: Bool { get async }
    /// 把 raw 过一遍 LLM。失败回退 raw。
    func polish(_ raw: String) async -> String
}

/// 配置文件：~/.config/mouthpiece/config.json
/// {
///   "polish": {
///     "provider": "deepseek",
///     "apiKey": "sk-xxxxxx",
///     "model": "deepseek-chat",
///     "endpoint": "https://api.deepseek.com/v1/chat/completions"
///   }
/// }
struct PolishConfig: Codable, Sendable {
    let provider: String
    let apiKey: String
    let model: String
    let endpoint: String

    static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mouthpiece/config.json")
    }

    /// 从默认路径加载配置；不存在 / 解析失败返回 nil。
    static func loadDefault() -> PolishConfig? {
        guard let data = try? Data(contentsOf: defaultPath) else { return nil }
        struct Wrapper: Decodable { let polish: PolishConfig? }
        return try? JSONDecoder().decode(Wrapper.self, from: data).polish
    }
}
