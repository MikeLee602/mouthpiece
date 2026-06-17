import Foundation
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "Streaming")

/// 滑动窗口实时识别器：录音同时每 N 秒跑一次 whisper-cli，
/// 把累积识别结果作为 partial 发出去。
///
/// 设计：
/// - 录音过程中调用 ingest(samples:) 不断喂样本
/// - 内部一个 timer + actor 周期性切片跑 whisper
/// - 用 small 模型保证延迟 < 切片时长
/// - finalize() 在录音结束时返回最后一次 partial（最终版本另外由 medium 跑）
///
/// 不重复跑相同区间：维护已跑过的 sample 偏移量，每次只跑新增片段。
/// 但 whisper 对孤立短片段质量差 —— 所以每次跑「最近 N 秒滑窗」而不是只跑新增。
/// 多次跑会得到不同结果，取最后一次的字符串作为当前 partial。
@MainActor
final class StreamingTranscriber {

    let binaryPath: String
    let modelPath: String
    /// 入站 sample 的真实 sample rate。会按这个 rate 写 WAV 头。
    /// whisper.cpp 接受 16k 以外的 rate，会内部 resample。
    let sampleRate: Double
    /// 滑窗大小（秒）。短窗精度差，长窗延迟高；3-5s 是平衡点。
    let windowSeconds: Double
    /// 每隔多久跑一次（秒）。
    let stepSeconds: Double

    private var samples: [Float] = []
    private var timer: Timer?
    private var inflight: Bool = false  // 防止重叠跑

    /// 累积式 partial 状态：
    /// - committed: 已经滚出滑窗、不会再变的文本
    /// - lastTail: 上一次滑窗识别结果（可能还会变）
    /// 显示文本 = committed + lastTail
    var committed: String = ""
    var lastTail: String = ""

    /// 实时 partial 文本回调（已是当前完整段：committed + tail）
    var onPartial: (@MainActor (String) -> Void)?

    init(binaryPath: String,
         modelPath: String,
         sampleRate: Double = 16000,
         windowSeconds: Double = 4.0,
         stepSeconds: Double = 2.0) {
        self.binaryPath = binaryPath
        self.modelPath = modelPath
        self.sampleRate = sampleRate
        self.windowSeconds = windowSeconds
        self.stepSeconds = stepSeconds
    }

    func start() {
        guard timer == nil else { return }
        samples.removeAll(keepingCapacity: true)
        committed = ""
        lastTail = ""
        log.notice("🌀 streaming start (window=\(self.windowSeconds)s step=\(self.stepSeconds)s)")
        timer = Timer.scheduledTimer(withTimeInterval: stepSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// AudioRecorder 喂入样本（已经是 16k Float，和 whisper 期望一致）。
    func ingest(samples newSamples: [Float]) {
        samples.append(contentsOf: newSamples)
    }

    /// 录音结束。停 timer，返回最后一次 partial（如果还在跑就等它完）。
    func stop() {
        timer?.invalidate()
        timer = nil
        log.notice("🌀 streaming stop (\(self.samples.count) total samples accumulated)")
        samples.removeAll()
        committed = ""
        lastTail = ""
    }

    private func tick() {
        guard !inflight else {
            log.notice("🌀 tick skipped (still in-flight)")
            return
        }
        // 取最近 windowSeconds 秒的样本
        let needSamples = Int(windowSeconds * sampleRate)
        guard samples.count >= Int(sampleRate * 0.8) else {
            // 不到 0.8 秒不跑，避免幻觉
            return
        }
        let window: [Float]
        if samples.count >= needSamples {
            window = Array(samples.suffix(needSamples))
        } else {
            window = samples
        }

        inflight = true
        let bin = binaryPath
        let model = modelPath
        Task.detached(priority: .userInitiated) { [weak self] in
            let text = await Self.runWhisper(binaryPath: bin, modelPath: model, samples: window)
            await MainActor.run {
                guard let self else { return }
                self.inflight = false
                guard let text, !text.isEmpty else { return }
                // 过滤典型幻觉行（whisper 在静音段会蹦出"字幕製作"等）
                if Self.isHallucination(text) {
                    log.notice("🌀 partial dropped (hallucination): \(text, privacy: .public)")
                    return
                }
                // 累积逻辑：把上一段 lastTail 和这一段 text 找 LCS（共同前缀），
                // 之前的部分提交到 committed，新的部分作为 lastTail。
                self.mergePartial(text)
                let merged = self.committed + self.lastTail
                log.notice("🌀 partial: \(merged, privacy: .public)")
                self.onPartial?(merged)
            }
        }
    }

    /// 合并新 partial 到累积状态。
    /// 关键挑战：whisper 同一段音频跑两次结果可能有标点/空格差异，
    /// 严格 prefix 匹配会丢掉重叠，导致重复。所以比较时用"骨架"
    /// （去除标点空格）。
    func mergePartial(_ newTail: String) {
        if lastTail.isEmpty {
            lastTail = newTail
            return
        }
        let oldSkel = Self.skeleton(lastTail)
        let newSkel = Self.skeleton(newTail)
        if newSkel.hasPrefix(oldSkel) {
            // newTail 是 lastTail 的扩展（同一窗内多识别了几个字）
            lastTail = newTail
            return
        }
        // 滑窗滚动了 — 找 oldSkel 后缀和 newSkel 前缀的重叠
        let overlap = Self.longestSuffixPrefix(oldSkel, newSkel)
        if overlap > 0 {
            // 把 lastTail 中"对应到 oldSkel 前 (count - overlap) 字符"的那部分 commit
            // 因为 skeleton 长度 != 原文长度（标点空格被去了），需要按 skeleton 字符索引找原文切点
            let commitSkelLen = oldSkel.count - overlap
            let cutIdx = Self.indexInOriginal(skeletonPrefixCount: commitSkelLen, original: lastTail)
            let commitPart = String(lastTail.prefix(cutIdx))
            committed += commitPart
            lastTail = newTail
        } else {
            // 完全找不到重叠 — 整个 lastTail commit
            committed += lastTail
            lastTail = newTail
        }
    }

    /// 去掉标点 / 空格 / 换行，方便跨次识别比较"骨架"
    nonisolated static func skeleton(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if ch.isLetter || ch.isNumber {
                // 不去大小写——专有名词大小写有意义
                out.append(ch)
            }
        }
        return out
    }

    /// 给定 original 字符串，找到使其 skeleton 前 N 字的原文切割位置（字符索引，含末尾空标点）
    nonisolated static func indexInOriginal(skeletonPrefixCount n: Int, original: String) -> Int {
        var skelCount = 0
        var idx = 0
        for ch in original {
            if skelCount >= n { break }
            if ch.isLetter || ch.isNumber { skelCount += 1 }
            idx += 1
        }
        return idx
    }

    /// 检测明显的 whisper 幻觉行
    nonisolated static func isHallucination(_ text: String) -> Bool {
        let hallmarks = [
            "字幕製作", "字幕制作", "字幕由", "字幕组",
            "請訂閱", "请订阅", "感謝觀看", "感谢观看",
            "謝謝", "MBC 뉴스", "ご視聴", "Thanks for watching",
            "Subtitles by", "Translated by",
        ]
        for m in hallmarks where text.contains(m) {
            return true
        }
        return false
    }

    /// 求 a 的后缀和 b 的前缀的最长重叠长度（按字符）
    nonisolated static func longestSuffixPrefix(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let maxLen = min(aChars.count, bChars.count)
        var best = 0
        // 从大到小试，找到第一个匹配的就是最大
        for len in stride(from: maxLen, through: 1, by: -1) {
            let aSuf = aChars.suffix(len)
            let bPre = bChars.prefix(len)
            if Array(aSuf) == Array(bPre) {
                best = len
                break
            }
        }
        return best
    }

    /// 跑一次 whisper-cli，返回拼接的文本。失败返回 nil。
    nonisolated private static func runWhisper(
        binaryPath: String,
        modelPath: String,
        samples: [Float]
    ) async -> String? {
        let tmpDir = FileManager.default.temporaryDirectory
        let wavURL = tmpDir.appendingPathComponent("mp-stream-\(UUID().uuidString).wav")
        let wavData = pcmToWav(samples: samples)
        do {
            try wavData.write(to: wavURL)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "-m", modelPath,
            "-f", wavURL.path,
            "-l", "zh",
            "-t", "4",
            "-np",
            "-nt",  // no timestamps —— 我们只要文本
        ]
        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()  // discard
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func pcmToWav(samples: [Float]) -> Data {
        let sampleRate: UInt32 = 16000
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)

        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            let i = Int16(clamped * 32767.0)
            var le = i.littleEndian
            withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
        }
        let dataSize = UInt32(pcm.count)
        let chunkSize: UInt32 = 36 + dataSize

        func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }
        func le16(_ v: UInt16) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 2) }

        var out = Data()
        out.append(Data("RIFF".utf8))
        out.append(le32(chunkSize))
        out.append(Data("WAVE".utf8))
        out.append(Data("fmt ".utf8))
        out.append(le32(16))
        out.append(le16(1))
        out.append(le16(numChannels))
        out.append(le32(sampleRate))
        out.append(le32(byteRate))
        out.append(le16(blockAlign))
        out.append(le16(bitsPerSample))
        out.append(Data("data".utf8))
        out.append(le32(dataSize))
        out.append(pcm)
        return out
    }
}
