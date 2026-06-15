import AppKit
import SwiftUI

@MainActor
final class FloatingBarWindow: NSWindow {

    let state: FloatingBarState

    init(state: FloatingBarState = FloatingBarState()) {
        self.state = state

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: FloatingBarView(state: state))
        host.translatesAutoresizingMaskIntoConstraints = false
        contentView = host

        repositionToBottomCenter()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionToBottomCenter),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func repositionToBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let w: CGFloat = 280
        let h: CGFloat = 44
        let x = f.midX - w / 2
        let y = f.minY + 32
        setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    func showIfNeeded() {
        if !isVisible {
            orderFrontRegardless()
        }
    }

    func hideIfIdle() {
        if case .idle = state.kind {
            orderOut(nil)
        }
    }
}
