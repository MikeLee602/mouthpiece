import AVFoundation
@preconcurrency import Speech
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "LiveTranscriber")

/// SFSpeechRecognizer 实时识别 — 给 floating bar 蹦字用，不做最终注入。
/// 最终高质量结果还是走 whisper-cli。
///
/// 不自己抓音频 —— 由调用方（AppCoordinator）把 AudioRecorder 的 buffer
/// 通过 feed(buffer:) 喂进来。这样不会和 AudioRecorder 抢 input device。
@MainActor
final class LiveTranscriber {

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// 给 feed(buffer:) 用的非隔离 request 引用。append 本身是线程安全的，
    /// 我们对它的 lifetime race（stop 后偶尔 buffer 漏到 nil）负责。
    nonisolated(unsafe) private var nonisolatedRequest: SFSpeechAudioBufferRecognitionRequest?

    /// 实时 partial 字符串回调。同一次录音会被反复回调，每次给最新的整段文本。
    var onPartial: (@MainActor (String) -> Void)?
    /// 出错（权限拒绝 / 模型缺失 / 引擎崩了 等）。
    var onError: (@MainActor (Error) -> Void)?

    private(set) var isRunning: Bool = false

    enum LiveError: Error, LocalizedError {
        case unavailable
        case authDenied
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: return "实时识别引擎不可用"
            case .authDenied: return "未授权语音识别（系统设置 → 隐私 → 语音识别）"
            case .engineFailed(let msg): return "引擎失败：\(msg)"
            }
        }
    }

    /// 启动实时识别会话。准备好后 caller 应通过 feed(buffer:) 喂音频。
    func start(localeIdentifier: String) async {
        guard !isRunning else { return }

        // 1. 权限
        let status = await Self.requestSpeechAuth()
        log.notice("Speech auth status: \(String(describing: status), privacy: .public)")
        guard status == .authorized else {
            log.error("Speech auth denied")
            onError?(LiveError.authDenied)
            return
        }

        // 2. 选 locale
        let locale = Self.resolveLocale(localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            log.error("SFSpeechRecognizer is nil for \(locale.identifier, privacy: .public)")
            onError?(LiveError.unavailable)
            return
        }
        log.notice("SFSpeechRecognizer: locale=\(recognizer.locale.identifier, privacy: .public) available=\(recognizer.isAvailable) onDevice=\(recognizer.supportsOnDeviceRecognition)")
        guard recognizer.isAvailable else {
            log.error("SFSpeechRecognizer unavailable")
            onError?(LiveError.unavailable)
            return
        }
        self.recognizer = recognizer

        // 3. request — partial + 标点
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        // 不强制 on-device — 中文模型可能没下完，允许云端
        self.request = request
        self.nonisolatedRequest = request

        // 4. task
        let weakSelf = WeakBox(self)
        self.task = recognizer.recognitionTask(with: request) { @Sendable result, error in
            Self.handleRecognitionCallback(weak: weakSelf, result: result, error: error)
        }

        isRunning = true
        log.notice("🎙 LiveTranscriber session ready (locale=\(locale.identifier, privacy: .public))")
    }

    /// AudioRecorder 调过来的实时 buffer。
    /// 这个方法可能在 audio render thread 上调用 —— nonisolated 必须。
    nonisolated func feed(buffer: AVAudioPCMBuffer) {
        let copy = Self.copyBuffer(buffer)
        let unchecked = UncheckedSendable(copy)
        Task { @MainActor [weak self] in
            self?.appendOnMain(unchecked.value)
        }
    }

    @MainActor
    private func appendOnMain(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
        Self.bufferStats.received += 1
        if Self.bufferStats.received % 50 == 1 {
            let frames = buffer.frameLength
            let sr = buffer.format.sampleRate
            log.notice("🎙 feed: count=\(Self.bufferStats.received) frames=\(frames) sr=\(sr)Hz mono=\(buffer.format.channelCount == 1)")
        }
    }

    /// 深拷贝 PCM buffer。原 buffer 引用 audio thread 的内存，跨线程后可能被覆盖。
    nonisolated private static func copyBuffer(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let copy = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: src.frameCapacity)!
        copy.frameLength = src.frameLength
        let frameCount = Int(src.frameLength)
        let channelCount = Int(src.format.channelCount)
        if let srcData = src.floatChannelData, let dstData = copy.floatChannelData {
            for c in 0..<channelCount {
                memcpy(dstData[c], srcData[c], frameCount * MemoryLayout<Float>.size)
            }
        }
        return copy
    }

    /// nonisolated 计数器，做日志抽样
    fileprivate final class BufferStats: @unchecked Sendable {
        var received: Int = 0
    }
    fileprivate static let bufferStats = BufferStats()

    func stop() {
        guard isRunning else { return }
        log.notice("🎙 LiveTranscriber stop")
        nonisolatedRequest = nil
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        isRunning = false
    }

    // MARK: - Helpers

    nonisolated private static func handleRecognitionCallback(
        weak weakBox: WeakBox<LiveTranscriber>,
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        let text = result?.bestTranscription.formattedString
        let realError: Error?
        if let error {
            let ns = error as NSError
            // 209/216/1101 = 正常生命周期事件（cancel / endAudio）
            if ns.domain == "kAFAssistantErrorDomain" && (ns.code == 209 || ns.code == 216 || ns.code == 1101) {
                realError = nil
            } else {
                realError = error
            }
        } else {
            realError = nil
        }

        Task { @MainActor in
            guard let live = weakBox.value else { return }
            if let text { live.onPartial?(text) }
            if let realError {
                log.error("Live recognition error: \(realError.localizedDescription, privacy: .public)")
                live.onError?(realError)
            }
        }
    }

    private nonisolated static func requestSpeechAuth() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    private static func resolveLocale(_ id: String) -> Locale {
        switch id {
        case "zh", "zh-CN": return Locale(identifier: "zh-CN")
        case "en", "en-US": return Locale(identifier: "en-US")
        case "auto": return Locale.current
        default: return Locale(identifier: id)
        }
    }
}

/// 跨 actor 安全的弱引用容器。
final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ v: T) { self.value = v }
}

/// 强行标记 Sendable 用——绕过 AVAudioPCMBuffer 不 Sendable 的限制。
/// 调用者负责保证拷贝后不再共享原始内存。
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ v: T) { self.value = v }
}
