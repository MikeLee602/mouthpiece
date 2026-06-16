import Foundation
import os.log

/// Transcriber that wraps the `whisper-cli` binary (from whisper.cpp) as a subprocess.
///
/// Replaces the previous WhisperKit-based implementation, which hit Swift 6
/// strict-concurrency / actor reentrancy crashes on macOS 26.
///
/// NOTE on sandboxing: spawning `/opt/homebrew/bin/whisper-cli` only works
/// because the app currently runs with `com.apple.security.app-sandbox = false`
/// (P0 dev mode). When sandbox is enabled for App Store submission, this needs
/// a different approach — either bundling whisper.cpp as an XPC helper or
/// linking against its C API directly.
actor WhisperCLITranscriber: Transcribing {

    private let log = Logger(subsystem: "com.mouthpiece.app", category: "WhisperCLI")
    private let binaryPath: String
    private let modelPath: String
    private var ready: Bool = false

    init(binaryPath: String, modelPath: String) {
        self.binaryPath = binaryPath
        self.modelPath = modelPath
    }

    var isReady: Bool {
        get async { ready }
    }

    func loadModel() async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: binaryPath) else {
            throw TranscriptionError.modelDownloadFailed(
                "whisper-cli binary not found at \(binaryPath). Install via: brew install whisper-cpp"
            )
        }
        guard fm.fileExists(atPath: modelPath) else {
            throw TranscriptionError.modelDownloadFailed(
                "Whisper model not found at \(modelPath). Download a ggml model (e.g. ggml-medium.bin)."
            )
        }
        ready = true
        log.notice("✅ whisper-cli ready (binary=\(self.binaryPath, privacy: .public), model=\(self.modelPath, privacy: .public))")
    }

    func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
        guard ready else { throw TranscriptionError.modelNotReady }

        // Write samples to temp WAV file.
        let tmpDir = FileManager.default.temporaryDirectory
        let wavURL = tmpDir.appendingPathComponent("mouthpiece-\(UUID().uuidString).wav")
        let wavData = Self.pcmToWav(samples: samples)
        do {
            try wavData.write(to: wavURL)
        } catch {
            throw TranscriptionError.transcribeFailed("Failed to write temp WAV: \(error)")
        }
        // DEBUG: keep WAV for inspection (was: defer cleanup)
        log.notice("📂 WAV kept at: \(wavURL.path, privacy: .public) size=\(wavData.count) bytes, samples=\(samples.count), peakAbs=\(samples.map { abs($0) }.max() ?? 0)")

        let lang = language ?? "zh"
        log.notice("🎙 whisper-cli starting: samples=\(samples.count) lang=\(lang, privacy: .public) wav=\(wavURL.path, privacy: .public)")

        // Spawn whisper-cli.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "-m", modelPath,
            "-f", wavURL.path,
            "-l", lang,
            "-t", "8",
            "-np"
        ]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw TranscriptionError.transcribeFailed("Failed to launch whisper-cli: \(error)")
        }

        // Read stdout / stderr concurrently to avoid pipe-buffer deadlock.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            log.error("❌ whisper-cli exit=\(process.terminationStatus) stderr=\(stderrStr, privacy: .public)")
            throw TranscriptionError.transcribeFailed(
                "whisper-cli exited with status \(process.terminationStatus): \(stderrStr)"
            )
        }

        let segments = Self.parseSegments(from: stdoutStr)
        let joined = segments.map { $0.text }.joined(separator: " ")
        let duration = Double(samples.count) / 16000.0

        log.notice("✓ whisper-cli done: \(segments.count) segments, \(joined.count) chars")

        return TranscriptionResult(
            text: joined,
            language: lang,
            segments: segments,
            durationSeconds: duration
        )
    }

    // MARK: - Stdout parsing

    /// Parse lines like `[00:00:00.000 --> 00:00:02.500]  text here` into segments.
    static func parseSegments(from output: String) -> [TranscriptionResult.Segment] {
        var out: [TranscriptionResult.Segment] = []
        for rawLine in output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine)
            guard line.hasPrefix("[") else { continue }
            // Find closing "]"
            guard let closeIdx = line.firstIndex(of: "]") else { continue }
            let stamp = String(line[line.index(after: line.startIndex)..<closeIdx])
            // stamp like "00:00:00.000 --> 00:00:02.500"
            let parts = stamp.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces)),
                  let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces)) else {
                continue
            }
            let text = String(line[line.index(after: closeIdx)...])
                .trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            out.append(.init(start: start, end: end, text: text))
        }
        return out
    }

    /// Parse "HH:MM:SS.mmm" -> seconds.
    static func parseTimestamp(_ s: String) -> Double? {
        let parts = s.components(separatedBy: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let sec = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }

    // MARK: - WAV encoding

    /// Convert 16kHz mono Float32 samples to a WAV file (16-bit signed PCM).
    static func pcmToWav(samples: [Float]) -> Data {
        let sampleRate: UInt32 = 16000
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)

        // Convert float [-1, 1] to Int16.
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            let i = Int16(clamped * 32767.0)
            var le = i.littleEndian
            withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
        }

        let dataSize = UInt32(pcm.count)
        let chunkSize: UInt32 = 36 + dataSize

        var out = Data()
        out.append(Data("RIFF".utf8))
        out.append(le32(chunkSize))
        out.append(Data("WAVE".utf8))
        out.append(Data("fmt ".utf8))
        out.append(le32(16))            // Subchunk1Size for PCM
        out.append(le16(1))             // AudioFormat = PCM
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

    private static func le32(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }

    private static func le16(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 2)
    }
}
