import Foundation

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
}
