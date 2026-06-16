import AVFoundation
import Observation
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "Audio")

@MainActor
@Observable
final class AudioRecorder: AudioRecording {

    private(set) var state: AudioRecorderState = .idle

    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var startTime: Date?
    private var timer: Timer?

    static let targetSampleRate: Double = 16000
    static let maxDuration: TimeInterval = 600  // 10 minutes

    init() {}

    func start() throws {
        guard case .idle = state else { return }

        // Each recording goes to a fresh temp WAV file. AVAudioRecorder writes
        // directly to disk, sidestepping the AVAudioEngine tap issues we hit
        // on macOS 26 (taps stopped firing after the first stop+start cycle).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mouthpiece-rec-\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Self.targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            guard rec.prepareToRecord() else {
                throw AudioRecorderError.engineFailedToStart
            }
            guard rec.record() else {
                throw AudioRecorderError.engineFailedToStart
            }
            self.recorder = rec
            self.currentURL = url
        } catch {
            log.error("🎤 AVAudioRecorder failed: \(String(describing: error), privacy: .public)")
            throw AudioRecorderError.engineFailedToStart
        }

        startTime = Date()
        state = .recording(elapsed: 0)
        startTimer()
        log.notice("🎤 AVAudioRecorder started, file=\(url.path, privacy: .public)")
    }

    func stop() async -> [Float] {
        timer?.invalidate()
        timer = nil

        guard let recorder, let url = currentURL else {
            log.error("🎤 stop called but no recorder")
            state = .finished(sampleCount: 0, sampleRate: Self.targetSampleRate)
            return []
        }

        recorder.stop()
        self.recorder = nil

        // Read the WAV file back as Float samples.
        let samples = Self.readWavAsFloat(url: url)
        log.notice("🎤 stop: read \(samples.count) samples from file, peakAbs=\(samples.map { abs($0) }.max() ?? 0)")
        // Clean up the temp recording file (we don't need it; transcriber writes
        // its own WAV from the samples).
        try? FileManager.default.removeItem(at: url)
        currentURL = nil

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
        state = .recording(elapsed: elapsed)
        if elapsed >= Self.maxDuration {
            Task { @MainActor in
                _ = await self.stop()
                self.state = .failed(.maxDurationReached)
            }
        }
    }

    /// Read a 16-bit mono PCM WAV file and return samples as Float in [-1, 1].
    /// Skips the 44-byte RIFF/WAVE header.
    static func readWavAsFloat(url: URL) -> [Float] {
        guard let data = try? Data(contentsOf: url), data.count > 44 else {
            return []
        }
        // Skip 44-byte standard WAV header. AVAudioRecorder writes a standard
        // 16-bit PCM header at this size.
        let pcm = data.subdata(in: 44..<data.count)
        let count = pcm.count / 2
        var floats = [Float](repeating: 0, count: count)
        pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let i16 = raw.bindMemory(to: Int16.self)
            for i in 0..<count {
                floats[i] = Float(i16[i]) / 32768.0
            }
        }
        return floats
    }
}
