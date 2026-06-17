import AVFoundation
import Observation
import os
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "Audio")

/// 录音器：用 AVAudioEngine + tap，buffer 一边写盘（给 whisper 用）一边
/// 推送给 listener（给 SFSpeechRecognizer 用）。
///
/// 历史背景：
/// - V1: AVAudioEngine + tap → macOS 26 上 stop+start 后 tap 不再 fire（buffer 重复）
/// - V2: AVAudioRecorder direct-to-disk → tap 问题没了，但占了 input device，
///       AVAudioEngine 在 LiveTranscriber 里抓不到 buffer（这次发现）
/// - V3（现在）: AVAudioEngine + tap，每次 start 重建 engine 解决 V1 stale buffer，
///       同时把 buffer 推给可选的 listener，供 SFSpeech 复用
@MainActor
@Observable
final class AudioRecorder: AudioRecording {

    private(set) var state: AudioRecorderState = .idle

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var startTime: Date?
    private var timer: Timer?
    private var listener: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// 累积音频样本。tap 在 audio thread 写，stop 在 main 读。
    /// 用 OSAllocatedUnfairLock 包起来；它在 sync 和 async 上下文都安全。
    private let samples = OSAllocatedUnfairLock<[Float]>(initialState: [])

    static let targetSampleRate: Double = 16000
    static let maxDuration: TimeInterval = 600  // 10 minutes

    init() {}

    func setBufferListener(_ listener: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        self.listener = listener
    }

    func start() throws {
        if case .recording = state {
            log.notice("🎤 start() called but already recording, skipping")
            return
        }

        // 重建 engine —— 解决 V1 时代 stop+start 后 tap 不 fire 的问题
        teardownEngine()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // 输出文件用 16kHz mono float32（whisper 喜欢这格式；写盘后再转 int16）
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mouthpiece-rec-\(UUID().uuidString).caf")
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]

        do {
            self.audioFile = try AVAudioFile(forWriting: url, settings: outputSettings)
        } catch {
            log.error("🎤 AVAudioFile create failed: \(error.localizedDescription, privacy: .public)")
            throw AudioRecorderError.engineFailedToStart
        }

        sampleAccumulatorReset()

        // tap closure 在 audio render thread；nonisolated install 避免 MainActor 检查 crash
        let samplesLock = self.samples
        Self.installTap(
            input: input,
            format: inputFormat,
            file: self.audioFile,
            listener: self.listener,
            onSamples: { floats in
                samplesLock.withLock { $0.append(contentsOf: floats) }
            }
        )

        do {
            engine.prepare()
            try engine.start()
        } catch {
            log.error("🎤 engine.start failed: \(error.localizedDescription, privacy: .public)")
            input.removeTap(onBus: 0)
            self.audioFile = nil
            throw AudioRecorderError.engineFailedToStart
        }

        self.engine = engine
        startTime = Date()
        state = .recording(elapsed: 0)
        startTimer()
        log.notice("🎤 AudioRecorder started, file=\(url.path, privacy: .public) input=\(inputFormat.sampleRate)Hz/\(inputFormat.channelCount)ch")
    }

    func stop() async -> [Float] {
        timer?.invalidate()
        timer = nil

        guard let engine else {
            log.error("🎤 stop called but no engine")
            state = .finished(sampleCount: 0, sampleRate: Self.targetSampleRate)
            return []
        }

        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.audioFile = nil
        let inputRate = engine.inputNode.outputFormat(forBus: 0).sampleRate
        self.engine = nil

        let captured = samples.withLock { state -> [Float] in
            let s = state
            state.removeAll()
            return s
        }

        let resampled = Self.resample(captured, from: inputRate, to: Self.targetSampleRate)

        let peak = resampled.map { abs($0) }.max() ?? 0
        log.notice("🎤 stop: \(resampled.count) samples (after resample), peakAbs=\(peak)")

        state = .finished(sampleCount: resampled.count, sampleRate: Self.targetSampleRate)
        return resampled
    }

    private func sampleAccumulatorReset() {
        samples.withLock { $0.removeAll(keepingCapacity: true) }
    }

    private func teardownEngine() {
        if let engine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        audioFile = nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        state = .recording(elapsed: elapsed)
        if elapsed >= Self.maxDuration {
            Task { @MainActor in
                _ = await self.stop()
                self.state = .failed(.maxDurationReached)
            }
        }
    }

    /// nonisolated tap installer — closure 在 audio render thread 跑，必须不能继承 MainActor
    nonisolated private static func installTap(
        input: AVAudioInputNode,
        format: AVAudioFormat,
        file: AVAudioFile?,
        listener: (@Sendable (AVAudioPCMBuffer) -> Void)?,
        onSamples: @escaping @Sendable ([Float]) -> Void
    ) {
        // 软件增益：AVAudioEngine 没有系统层 AGC，原始电平比 AVAudioRecorder 低很多。
        // 5x 会把高峰 clip 死；3x + soft limit (0.95) 保持动态范围。
        let gain: Float = 3.0
        let limit: Float = 0.95
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            // 1. 增益（in-place 改 buffer）
            applyGainInPlace(buffer: buffer, gain: gain, limit: limit)
            // 2. 写盘（已带增益）
            try? file?.write(from: buffer)
            // 3. 喂给实时 listener（已带增益）
            listener?(buffer)
            // 4. 累积 float 数据 — 用 channel 0
            if let channelData = buffer.floatChannelData {
                let frameLen = Int(buffer.frameLength)
                let ptr = channelData[0]
                let arr = Array(UnsafeBufferPointer(start: ptr, count: frameLen))
                onSamples(arr)
            }
        }
    }

    nonisolated private static func applyGainInPlace(buffer: AVAudioPCMBuffer, gain: Float, limit: Float) {
        guard let channels = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        for c in 0..<channelCount {
            let ptr = channels[c]
            for i in 0..<frameCount {
                let v = ptr[i] * gain
                ptr[i] = max(-limit, min(limit, v))
            }
        }
    }

    /// 简易重采样：从 inputRate 到 targetRate 的整数倍/分数比较好处理；
    /// 这里用线性插值。AVAudioEngine 通常是 44.1k/48k 输入，转 16k 给 whisper。
    nonisolated static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard sourceRate != targetRate, !samples.isEmpty else { return samples }
        let ratio = sourceRate / targetRate
        let outCount = Int(Double(samples.count) / ratio)
        guard outCount > 0 else { return [] }
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let src = Double(i) * ratio
            let lo = Int(src)
            let hi = min(lo + 1, samples.count - 1)
            let frac = Float(src - Double(lo))
            out[i] = samples[lo] * (1 - frac) + samples[hi] * frac
        }
        return out
    }
}
