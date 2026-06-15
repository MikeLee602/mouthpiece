import XCTest
@testable import Mouthpiece

final class SmokeTests: XCTestCase {
    func testAppBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.mouthpiece.app")
    }
}
