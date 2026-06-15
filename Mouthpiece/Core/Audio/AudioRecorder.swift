import AVFoundation
import Observation

@MainActor
@Observable
final class AudioRecorder: AudioRecording {

    private(set) var state: AudioRecorderState = .idle

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var sampleBuffer: [Float] = []
    private var startTime: Date?
    private var timer: Timer?

    nonisolated(unsafe) private var bufferQueue = DispatchQueue(label: "com.mouthpiece.audio-buffer")
    nonisolated(unsafe) private var pendingChunks: [[Float]] = []

    static let targetSampleRate: Double = 16000
    static let maxDuration: TimeInterval = 600  // 10 分钟

    init() {}

    func start() throws {
        guard case .idle = state else { return }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.engineFailedToStart
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        sampleBuffer.removeAll(keepingCapacity: true)
        bufferQueue.sync { pendingChunks.removeAll() }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.appendBufferNonisolated(buffer, targetFormat: targetFormat)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecorderError.engineFailedToStart
        }

        startTime = Date()
        state = .recording(elapsed: 0)
        startTimer()
    }

    func stop() async -> [Float] {
        timer?.invalidate()
        timer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // Drain pending chunks
        drainPending()
        let samples = sampleBuffer
        state = .finished(sampleCount: samples.count, sampleRate: Self.targetSampleRate)
        return samples
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        drainPending()
        state = .recording(elapsed: elapsed)
        if elapsed >= Self.maxDuration {
            Task { @MainActor in
                _ = await self.stop()
                self.state = .failed(.maxDurationReached)
            }
        }
    }

    private func drainPending() {
        let chunks: [[Float]] = bufferQueue.sync {
            let c = pendingChunks
            pendingChunks.removeAll()
            return c
        }
        for chunk in chunks {
            sampleBuffer.append(contentsOf: chunk)
        }
    }

    /// Runs on AVAudioEngine render thread. Convert + enqueue to main actor.
    nonisolated private func appendBufferNonisolated(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter = converterUnsafe else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

        var err: NSError?
        var consumed = false
        converter.convert(to: outBuf, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, let data = outBuf.floatChannelData?[0] else { return }
        let frames = Int(outBuf.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: data, count: frames))
        bufferQueue.sync { pendingChunks.append(chunk) }
    }

    nonisolated private var converterUnsafe: AVAudioConverter? {
        // Read converter from MainActor field. In practice it's set once in start() before
        // the tap is installed, and only read during the tap callback, so racy reads are benign.
        MainActor.assumeIsolated { converter }
    }
}
