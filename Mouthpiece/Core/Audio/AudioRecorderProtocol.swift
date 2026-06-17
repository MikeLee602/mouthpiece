import Foundation
import AVFoundation

enum AudioRecorderState: Equatable, Sendable {
    case idle
    case recording(elapsed: TimeInterval)
    case finished(sampleCount: Int, sampleRate: Double)
    case failed(AudioRecorderError)
}

enum AudioRecorderError: Error, Equatable, Sendable {
    case noPermission
    case engineFailedToStart
    case interrupted
    case maxDurationReached
}

@MainActor
protocol AudioRecording: AnyObject {
    var state: AudioRecorderState { get }
    func start() throws
    func stop() async -> [Float]
    /// 实时 buffer listener — 录音时每个 buffer 都会调用一次（在 audio render thread 上）。
    /// 用于喂给 SFSpeechRecognizer 等流式消费者。可选实现。
    func setBufferListener(_ listener: (@Sendable (AVAudioPCMBuffer) -> Void)?)
}

extension AudioRecording {
    func setBufferListener(_ listener: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        // default no-op for recorders that don't support live tap
    }
}
