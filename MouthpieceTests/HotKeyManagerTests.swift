import XCTest
import AppKit
@testable import Mouthpiece

@MainActor
final class HotKeyManagerTests: XCTestCase {

    func testFnKeyPressAndRelease() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn) { ev in events.append(ev) }

        mgr.handleFlagsChangedForTest(flags: [.function])
        mgr.handleFlagsChangedForTest(flags: [])

        XCTAssertEqual(events, [.pressed, .released])
    }

    func testIgnoresOtherModifiers() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn) { ev in events.append(ev) }

        mgr.handleFlagsChangedForTest(flags: [.command])
        mgr.handleFlagsChangedForTest(flags: [.command, .shift])
        mgr.handleFlagsChangedForTest(flags: [])

        XCTAssertEqual(events, [])
    }

    func testReleaseEventOnlyAfterPress() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn) { ev in events.append(ev) }

        mgr.handleFlagsChangedForTest(flags: [])

        XCTAssertEqual(events, [])
    }

    func testRepeatedPressDoesntDuplicate() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn) { ev in events.append(ev) }

        mgr.handleFlagsChangedForTest(flags: [.function])
        mgr.handleFlagsChangedForTest(flags: [.function])  // still down, no new press
        mgr.handleFlagsChangedForTest(flags: [])

        XCTAssertEqual(events, [.pressed, .released])
    }

    func testF13TriggerKeyHasNoModifierFlag() {
        XCTAssertNil(TriggerKey.f13.modifierFlag)
    }
}
