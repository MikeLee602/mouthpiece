import AppKit
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "HotKey")

@MainActor
final class HotKeyManager {
    private(set) var triggerKey: TriggerKey
    private(set) var mode: HotKeyMode
    private var onEvent: @MainActor (HotKeyEvent) -> Void
    private var isPressed = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(triggerKey: TriggerKey,
         mode: HotKeyMode = .pushToTalk,
         onEvent: @escaping @MainActor (HotKeyEvent) -> Void = { _ in }) {
        self.triggerKey = triggerKey
        self.mode = mode
        self.onEvent = onEvent
    }

    func replaceHandler(_ handler: @escaping @MainActor (HotKeyEvent) -> Void) {
        self.onEvent = handler
    }

    /// Switch the trigger key at runtime. Restarts monitors if currently running.
    func setTriggerKey(_ key: TriggerKey) {
        guard key != triggerKey else { return }
        let wasRunning = globalMonitor != nil
        if wasRunning { stop() }
        // Reset pressed state — old key may have been "down" when swapped.
        if isPressed {
            isPressed = false
            onEvent(.released)
        }
        self.triggerKey = key
        log.notice("🎹 triggerKey switched to \(key.rawValue, privacy: .public)")
        if wasRunning { start() }
    }

    /// 切换 push-to-talk / toggle 模式。
    func setMode(_ newMode: HotKeyMode) {
        guard newMode != mode else { return }
        // 切换模式要重置内部状态，免得当前正在按着的状态被错误转译。
        if isPressed {
            isPressed = false
            onEvent(.released)
        }
        self.mode = newMode
        log.notice("🎹 mode switched to \(newMode.rawValue, privacy: .public)")
    }

    func start() {
        guard globalMonitor == nil else { return }
        log.notice("🎹 start() called, triggerKey=\(self.triggerKey.rawValue, privacy: .public)")
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(flags: event.modifierFlags)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(flags: event.modifierFlags)
            }
            return event
        }
        log.notice("🎹 monitors installed: global=\(self.globalMonitor != nil) local=\(self.localMonitor != nil)")
    }

    func stop() {
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    /// Test seam — directly invoke flag-changed handler.
    func handleFlagsChangedForTest(flags: NSEvent.ModifierFlags) {
        handleFlagsChanged(flags: flags)
    }

    private func handleFlagsChanged(flags: NSEvent.ModifierFlags) {
        guard let target = triggerKey.modifierFlag else { return }
        let nowDown = flags.contains(target)

        switch mode {
        case .pushToTalk:
            if nowDown && !isPressed {
                isPressed = true
                log.notice("🎹 PRESSED")
                onEvent(.pressed)
            } else if !nowDown && isPressed {
                isPressed = false
                log.notice("🎹 RELEASED")
                onEvent(.released)
            }
        case .toggle:
            // 只在「按下」边缘触发 toggled，按下到释放这段「按住」过程不动作。
            if nowDown && !isPressed {
                isPressed = true
                log.notice("🎹 TOGGLED")
                onEvent(.toggled)
            } else if !nowDown && isPressed {
                isPressed = false
                // toggle 模式下不发 .released
            }
        }
    }

    /// Watchdog: if a flagsChanged hasn't arrived in 8 seconds while pressed, force-release.
    /// This guards against the case where the modifier flag stays "stuck" (e.g. macOS intercepts it).
    func forceReleaseIfPressed() {
        if isPressed {
            log.notice("🎹 FORCE RELEASED (watchdog)")
            isPressed = false
            onEvent(.released)
        }
    }

    isolated deinit {
        // NSEvent.removeMonitor is fine to call from any thread; safe in deinit
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}
