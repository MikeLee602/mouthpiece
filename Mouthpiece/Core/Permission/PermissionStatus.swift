import AVFoundation

enum MicrophonePermission: Equatable, Sendable {
    case notDetermined
    case denied
    case granted
}

enum AccessibilityPermission: Equatable, Sendable {
    case granted
    case notGranted
}

@MainActor
protocol PermissionChecking: AnyObject {
    var microphone: MicrophonePermission { get }
    var accessibility: AccessibilityPermission { get }
    func refresh()
    func requestMicrophone() async -> MicrophonePermission
    func openMicrophoneSettings()
    func openAccessibilitySettings()
}
