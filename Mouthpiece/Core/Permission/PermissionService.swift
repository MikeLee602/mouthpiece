import AVFoundation
import AppKit
import Observation

@MainActor
@Observable
final class PermissionService: PermissionChecking {

    private(set) var microphone: MicrophonePermission
    private(set) var accessibility: AccessibilityPermission

    init() {
        self.microphone = Self.currentMic()
        self.accessibility = Self.currentAccessibility()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        microphone = Self.currentMic()
        accessibility = Self.currentAccessibility()
    }

    func requestMicrophone() async -> MicrophonePermission {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        let status: MicrophonePermission = granted ? .granted : .denied
        microphone = status
        return status
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private static func currentMic() -> MicrophonePermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    private static func currentAccessibility() -> AccessibilityPermission {
        AXIsProcessTrusted() ? .granted : .notGranted
    }
}
