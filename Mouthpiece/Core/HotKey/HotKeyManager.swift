import AppKit

@MainActor
final class HotKeyManager {
    private let triggerKey: TriggerKey
    private let onEvent: @MainActor (HotKeyEvent) -> Void
    private var isPressed = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(triggerKey: TriggerKey, onEvent: @escaping @MainActor (HotKeyEvent) -> Void) {
        self.triggerKey = triggerKey
        self.onEvent = onEvent
    }

    func start() {
        guard globalMonitor == nil else { return }
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
            onEvent(.pressed)
        } else if !nowDown && isPressed {
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
