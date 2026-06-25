import Foundation
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "Polish")

/// DeepSeek（或任何 OpenAI 兼容 endpoint）实现。
/// 失败任何情况都回退 raw —— polish 不能阻塞 pipeline。
actor DeepSeekPolisher: Polishing {

    private let config: PolishConfig?
    private let urlSession: URLSession

    init(config: PolishConfig?) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8.0
        cfg.timeoutIntervalForResource = 12.0
        self.urlSession = URLSession(configuration: cfg)
    }

    var isConfigured: Bool {
        get async { config != nil && !(config?.apiKey.isEmpty ?? true) }
    }

    func polish(_ raw: String) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        guard let config else {
            // 没配置 — 静默回退，不打 warning（这是预期行为）
            return raw
        }

        do {
            let polished = try await callDeepSeek(text: trimmed, config: config)
            log.notice("✨ polished: \(polished.count) chars (raw=\(trimmed.count))")
            return polished
        } catch {
            log.warning("✨ polish failed (\(error.localizedDescription, privacy: .public)), falling back to raw")
            return raw
        }
    }

    enum PolishError: Error, LocalizedError {
        case badURL
        case httpStatus(Int)
        case malformedResponse
        case emptyContent

        var errorDescription: String? {
            switch self {
            case .badURL: return "endpoint URL malformed"
            case .httpStatus(let s): return "HTTP \(s)"
            case .malformedResponse: return "malformed JSON"
            case .emptyContent: return "empty content"
            }
        }
    }

    private func callDeepSeek(text: String, config: PolishConfig) async throws -> String {
        guard let url = URL(string: config.endpoint) else { throw PolishError.badURL }

        let systemPrompt = """
        你是语音转写后处理助手。用户给你一段从 ASR 识别出的中文（偶尔混英文）。请：
        1. 主动修正同音错字、近音错字、专有名词错误（如「使用VESCO」→「使用 VSCode」、「鸡屁体」→「GPT」、「采想」→「采销」），结合上下文推断真实意图
        2. 补全/调整标点
        3. 如果有明显结构（含三个或以上并列项 + 用「第一/第二/第三」「一是/二是」「另外/此外/最后」等连接词；或有 if/else / for 等代码字眼），用 markdown 格式化（- 列表、## 标题、` 代码块）；普通流水句保持流水
        4. 不扩写、不总结、不改变原意，字数基本不变

        只输出修正后文本，不要解释、不要 ``` 包装。
        """

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
            "temperature": 0.2,
            "max_tokens": max(256, text.count * 4),
            "stream": false,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw PolishError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            // 调试：留 5xx 错误的体到日志
            if let s = String(data: data, encoding: .utf8) {
                log.warning("✨ http=\(http.statusCode) body=\(s, privacy: .public)")
            }
            throw PolishError.httpStatus(http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw PolishError.malformedResponse
        }
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw PolishError.emptyContent }
        return cleaned
    }
}

/// 永远 disable 的占位实现（测试 / 没配置时用）
struct NoopPolisher: Polishing {
    var isConfigured: Bool { get async { false } }
    func polish(_ raw: String) async -> String { raw }
}
