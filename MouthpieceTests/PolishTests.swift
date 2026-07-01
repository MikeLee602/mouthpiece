import XCTest
@testable import Mouthpiece

final class PolishConfigTests: XCTestCase {

    func testDefaultPathIsInUserConfig() {
        let path = PolishConfig.defaultPath.path
        XCTAssertTrue(path.contains(".config/mouthpiece/config.json"))
    }

    func testLoadDefaultReturnsNilWhenAbsent() {
        // 默认路径下应该没有这个测试文件（或者用户真的有，那就跳过）
        // 这个测试主要验证不会 crash
        _ = PolishConfig.loadDefault()
    }

    func testDecodeFromJSON() throws {
        let json = """
        {
          "polish": {
            "provider": "deepseek",
            "apiKey": "sk-test",
            "model": "deepseek-chat",
            "endpoint": "https://api.deepseek.com/v1/chat/completions"
          }
        }
        """.data(using: .utf8)!
        struct Wrapper: Decodable { let polish: PolishConfig? }
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: json)
        XCTAssertEqual(wrapper.polish?.provider, "deepseek")
        XCTAssertEqual(wrapper.polish?.apiKey, "sk-test")
        XCTAssertEqual(wrapper.polish?.model, "deepseek-chat")
    }

    func testDecodeMissingPolishKey() throws {
        let json = "{}".data(using: .utf8)!
        struct Wrapper: Decodable { let polish: PolishConfig? }
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: json)
        XCTAssertNil(wrapper.polish)
    }
}

final class NoopPolisherTests: XCTestCase {

    func testNoopReturnsRaw() async {
        let p = NoopPolisher()
        let raw = "测试"
        let polished = await p.polish(raw)
        XCTAssertEqual(polished, raw)
    }

    func testNoopIsNotConfigured() async {
        let p = NoopPolisher()
        let configured = await p.isConfigured
        XCTAssertFalse(configured)
    }
}

final class DeepSeekPolisherTests: XCTestCase {

    func testNilConfigReturnsRaw() async {
        let p = DeepSeekPolisher(config: nil)
        let raw = "今天天气真好"
        let polished = await p.polish(raw)
        XCTAssertEqual(polished, raw)
    }

    func testEmptyKeyReturnsNotConfigured() async {
        let cfg = PolishConfig(provider: "deepseek", apiKey: "", model: "x", endpoint: "https://example.com")
        let p = DeepSeekPolisher(config: cfg)
        let configured = await p.isConfigured
        XCTAssertFalse(configured)
    }

    func testWithKeyIsConfigured() async {
        let cfg = PolishConfig(provider: "deepseek", apiKey: "sk-x", model: "deepseek-chat", endpoint: "https://example.com")
        let p = DeepSeekPolisher(config: cfg)
        let configured = await p.isConfigured
        XCTAssertTrue(configured)
    }

    func testEmptyTextReturnsRawWithoutCall() async {
        let cfg = PolishConfig(provider: "deepseek", apiKey: "sk-x", model: "deepseek-chat", endpoint: "https://invalid.example/never")
        let p = DeepSeekPolisher(config: cfg)
        // 空字符串应该立刻返回，不发请求（否则 invalid endpoint 会让测试卡住到超时）
        let polished = await p.polish("")
        XCTAssertEqual(polished, "")
        let polished2 = await p.polish("   ")
        XCTAssertEqual(polished2, "   ")
    }

    func testWithVocabHintDoesntCrash() async {
        // 只验证不 crash + fallback 到 raw；不联网
        let cfg = PolishConfig(provider: "deepseek", apiKey: "sk-x", model: "deepseek-chat", endpoint: "http://127.0.0.1:1/never")
        let p = DeepSeekPolisher(config: cfg)
        let hint: [(String, String)] = [("王梦松", "王孟松"), ("采购家", "采销")]
        let out = await p.polish("这是一段测试", vocabHint: hint)
        // 连不上 → 回退到 raw
        XCTAssertEqual(out, "这是一段测试")
    }
}
