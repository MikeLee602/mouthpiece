import AppKit
import CoreGraphics
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "Injector")

actor TextInjector: TextInjecting {

    func inject(_ text: String) async throws {
        log.notice("💉 inject called with \(text.count, privacy: .public) chars")
        let trusted = await MainActor.run { AXIsProcessTrusted() }
        log.notice("💉 AXIsProcessTrusted=\(trusted, privacy: .public)")
        guard trusted else {
            throw InjectionError.noAccessibilityPermission
        }

        let frontApp = await MainActor.run { NSWorkspace.shared.frontmostApplication?.localizedName ?? "?" }
        log.notice("💉 frontmost app: \(frontApp, privacy: .public)")

        // Save & write & restore must hop to MainActor for NSPasteboard safety
        let savedItems = await captureClipboard()
        log.notice("💉 saved \(savedItems.count, privacy: .public) clipboard items")

        let writeOK = await writeClipboard(text)
        log.notice("💉 writeClipboard ok=\(writeOK, privacy: .public)")
        guard writeOK else { throw InjectionError.clipboardWriteFailed }

        log.notice("💉 posting Cmd+V…")
        try await postCmdV()
        log.notice("💉 Cmd+V posted")

        // Wait for the paste action to complete in target app
        try? await Task.sleep(for: .milliseconds(120))

        await restoreClipboard(savedItems)
        log.notice("💉 clipboard restored, inject done")
    }

    @MainActor
    private func captureClipboard() -> [[String: Data]] {
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            return dict
        }
    }

    @MainActor
    private func writeClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    @MainActor
    private func restoreClipboard(_ saved: [[String: Data]]) {
        guard !saved.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for dict in saved {
            let item = NSPasteboardItem()
            for (typeRaw, data) in dict {
                item.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
            }
            pasteboard.writeObjects([item])
        }
    }

    @MainActor
    private func postCmdV() throws {
        let src = CGEventSource(stateID: .hidSystemState)
        // V keycode = 9
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else {
            throw InjectionError.eventPostFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
