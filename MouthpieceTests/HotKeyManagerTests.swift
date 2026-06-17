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

    // MARK: - Toggle mode

    func testToggleModeEmitsToggledOnPressOnly() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn, mode: .toggle) { ev in events.append(ev) }

        // 按下 → toggled
        mgr.handleFlagsChangedForTest(flags: [.function])
        // 松开 → 不发任何事件（toggle 不在松开时动作）
        mgr.handleFlagsChangedForTest(flags: [])

        XCTAssertEqual(events, [.toggled])
    }

    func testToggleModeTwoPressesEmitTwoToggles() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn, mode: .toggle) { ev in events.append(ev) }

        // 第一次按下 + 松开
        mgr.handleFlagsChangedForTest(flags: [.function])
        mgr.handleFlagsChangedForTest(flags: [])
        // 第二次按下 + 松开
        mgr.handleFlagsChangedForTest(flags: [.function])
        mgr.handleFlagsChangedForTest(flags: [])

        XCTAssertEqual(events, [.toggled, .toggled])
    }

    func testSwitchModeResetsState() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn, mode: .pushToTalk) { ev in events.append(ev) }

        // 按下（push-to-talk 下 .pressed），不松开就切到 toggle
        mgr.handleFlagsChangedForTest(flags: [.function])
        XCTAssertEqual(events.last, .pressed)
        mgr.setMode(.toggle)
        // 切换时应当 force release
        XCTAssertEqual(events, [.pressed, .released])
        // 松开（仍按着 fn 开关 mode 的实际效果会更复杂，但模拟松开）
        mgr.handleFlagsChangedForTest(flags: [])
        // toggle 模式下松开不发事件
        XCTAssertEqual(events, [.pressed, .released])
    }

    func testPushToTalkAndToggleAreIndependent() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn, mode: .pushToTalk) { ev in events.append(ev) }
        mgr.handleFlagsChangedForTest(flags: [.function])
        mgr.handleFlagsChangedForTest(flags: [])
        XCTAssertEqual(events, [.pressed, .released])
    }
}
