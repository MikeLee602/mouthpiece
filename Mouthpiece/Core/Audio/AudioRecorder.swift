import AVFoundation
import Observation

/// Holds audio buffer state separate from the @MainActor class so the AVAudio render thread
/// can mutate it without ever touching MainActor-isolated state.
final class AudioBufferStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mouthpiece.audio-buffer")
    private var pendingChunks: [[Float]] = []
    private var _converter: AVAudioConverter?

    var converter: AVAudioConverter? {
        get { queue.sync { _converter } }
        set { queue.sync { _converter = newValue } }
    }

    func append(_ chunk: [Float]) {
        queue.sync { pendingChunks.append(chunk) }
    }

    func drain() -> [[Float]] {
        queue.sync {
            let c = pendingChunks
            pendingChunks.removeAll()
            return c
        }
    }

    func clear() {
        queue.sync { pendingChunks.removeAll() }
    }
}

@MainActor
@Observable
final class AudioRecorder: AudioRecording {

    private(set) var state: AudioRecorderState = .idle

    private let engine = AVAudioEngine()
    private let store = AudioBufferStore()
    private var sampleBuffer: [Float] = []
    private var startTime: Date?
    private var timer: Timer?

    static let targetSampleRate: Double = 16000
    static let maxDuration: TimeInterval = 600  // 10 minutes

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
        store.converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        sampleBuffer.removeAll(keepingCapacity: true)
        store.clear()

        // Capture store and target format by value; both are Sendable.
        let store = self.store
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            // We are on a real-time audio thread. DO NOT touch any MainActor state.
            // We only use `store` (Sendable) and pure operations.
            Self.processBuffer(buffer, targetFormat: targetFormat, store: store)
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
        let chunks = store.drain()
        for chunk in chunks {
            sampleBuffer.append(contentsOf: chunk)
        }
    }

    /// Pure, nonisolated helper. Runs on the AVAudio render thread.
    /// Does NOT touch any MainActor state — only the Sendable `store`.
    nonisolated private static func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        targetFormat: AVAudioFormat,
        store: AudioBufferStore
    ) {
        guard let converter = store.converter else { return }
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
        store.append(chunk)
    }
}
