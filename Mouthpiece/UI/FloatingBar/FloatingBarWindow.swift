import AppKit
import SwiftUI

@MainActor
final class FloatingBarWindow: NSWindow {

    let state: FloatingBarState
    private var hostingView: NSHostingView<FloatingBarView>!
    private static let baseHeight: CGFloat = 44
    private static let bottomMargin: CGFloat = 32

    init(state: FloatingBarState = FloatingBarState()) {
        self.state = state

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: Self.baseHeight),
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
        // 自动跟随 SwiftUI 内容大小调整 — partial 越长 bar 越宽
        if #available(macOS 13.0, *) {
            host.sizingOptions = [.intrinsicContentSize]
        }
        self.hostingView = host
        contentView = host

        // 监听内容大小变化，每次都重定位到底部居中
        host.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentResized),
            name: NSView.frameDidChangeNotification,
            object: host
        )

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

    @objc private func contentResized() {
        repositionToBottomCenter()
    }

    @objc func repositionToBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        // 按 SwiftUI 内容的 intrinsicContentSize 算窗口大小，加点 padding
        let intrinsic = hostingView?.intrinsicContentSize ?? NSSize(width: 280, height: Self.baseHeight)
        let maxW = f.width * 0.7  // 防止极长 partial 横跨整屏
        let minW: CGFloat = 200
        let w = max(minW, min(intrinsic.width, maxW))
        let h = max(Self.baseHeight, intrinsic.height)
        let x = f.midX - w / 2
        let y = f.minY + Self.bottomMargin
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
