import XCTest
@testable import Mouthpiece

@MainActor
final class PermissionServiceTests: XCTestCase {

    final class MockPermissionService: PermissionChecking {
        var microphone: MicrophonePermission = .notDetermined
        var accessibility: AccessibilityPermission = .notGranted
        var requestResult: MicrophonePermission = .granted

        func refresh() {}

        func requestMicrophone() async -> MicrophonePermission {
            microphone = requestResult
            return requestResult
        }
        func openMicrophoneSettings() {}
        func openAccessibilitySettings() {}
    }

    func testInitialState() {
        let svc: PermissionChecking = MockPermissionService()
        XCTAssertEqual(svc.microphone, .notDetermined)
        XCTAssertEqual(svc.accessibility, .notGranted)
    }

    func testRequestMicrophoneGranted() async {
        let svc = MockPermissionService()
        svc.requestResult = .granted
        let result = await svc.requestMicrophone()
        XCTAssertEqual(result, .granted)
        XCTAssertEqual(svc.microphone, .granted)
    }

    func testRequestMicrophoneDenied() async {
        let svc = MockPermissionService()
        svc.requestResult = .denied
        let result = await svc.requestMicrophone()
        XCTAssertEqual(result, .denied)
    }
}
