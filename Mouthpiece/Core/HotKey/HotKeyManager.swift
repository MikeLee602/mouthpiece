import AppKit
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "HotKey")

@MainActor
final class HotKeyManager {
    private(set) var triggerKey: TriggerKey
    private var onEvent: @MainActor (HotKeyEvent) -> Void
    private var isPressed = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(triggerKey: TriggerKey, onEvent: @escaping @MainActor (HotKeyEvent) -> Void = { _ in }) {
        self.triggerKey = triggerKey
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

        if nowDown && !isPressed {
            isPressed = true
            log.notice("🎹 PRESSED")
            onEvent(.pressed)
        } else if !nowDown && isPressed {
            isPressed = false
            log.notice("🎹 RELEASED")
            onEvent(.released)
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
