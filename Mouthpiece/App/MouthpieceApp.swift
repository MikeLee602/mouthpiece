import SwiftUI
import AppKit
import os.log

private let appLog = Logger(subsystem: "com.mouthpiece.app", category: "App")

/// AppDelegate guarantees we initialize the coordinator at app launch,
/// not lazily on first MenuBarExtra popup.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    var coordinator: AppCoordinator?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        appLog.notice("🚀 applicationDidFinishLaunching")
        Task { @MainActor in
            await self.bootstrap()
        }
    }

    @MainActor
    func bootstrap() async {
        guard coordinator == nil else { return }
        appLog.notice("🚀 Building coordinator...")

        let permission = PermissionService()
        let recorder = AudioRecorder()
        let transcriber = WhisperCLITranscriber(
            binaryPath: "/opt/homebrew/bin/whisper-cli",
            modelPath: "/opt/homebrew/share/whisper.cpp/ggml-medium.bin"
        )
        let injector = TextInjector()
        let bar = FloatingBarState()
        let window = FloatingBarWindow(state: bar)
        let coord = AppCoordinator(
            permission: permission,
            recorder: recorder,
            transcriber: transcriber,
            injector: injector,
            floatingBar: bar,
            floatingWindow: window
        )
        coord.start()
        self.coordinator = coord

        appLog.notice("🚀 Mic permission: \(String(describing: coord.permission.microphone))")
        if coord.permission.microphone == .notDetermined {
            appLog.notice("🚀 Requesting microphone permission proactively...")
            _ = await coord.permission.requestMicrophone()
        }
        appLog.notice("🚀 Loading model...")
        await coord.loadModelIfNeeded()
        appLog.notice("🚀 Bootstrap complete. Phase: \(String(describing: coord.phase))")
    }
}

@main
struct MouthpieceApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Mouthpiece", image: "MenuBarIcon") {
            MenuView(delegate: appDelegate)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuView: View {
    let delegate: AppDelegate
    @State private var refreshTrigger: Int = 0

    var body: some View {
        let coord = delegate.coordinator
        VStack(alignment: .leading, spacing: 4) {
            if let coord {
                Text(statusLabel(for: coord.phase))
                Divider()
                Text("按住 Fn 开始录音").font(.caption).foregroundStyle(.secondary)
                Divider()
                Button("重新加载模型") {
                    Task { @MainActor in
                        await coord.loadModelIfNeeded()
                    }
                }
            } else {
                Text("初始化中…")
            }
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
        .padding(8)
        .id(refreshTrigger)
        .onAppear { refreshTrigger += 1 }
    }

    private func statusLabel(for phase: AppCoordinator.Phase) -> String {
        switch phase {
        case .idle: return "● 待机"
        case .recording: return "🔴 录音中"
        case .transcribing: return "✦ 识别中"
        case .cleaning: return "🪄 整理中"
        case .injecting: return "⌨️ 粘贴中"
        case .done(let n): return "✓ 已完成 \(n) 字"
        case .error(let m): return "⚠ \(m)"
        }
    }
}
