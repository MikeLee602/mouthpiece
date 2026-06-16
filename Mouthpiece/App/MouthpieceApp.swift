import SwiftUI
import AppKit
import os.log

private let appLog = Logger(subsystem: "com.mouthpiece.app", category: "App")

@main
struct MouthpieceApp: App {

    @State private var coordinator: AppCoordinator? = nil

    var body: some Scene {
        MenuBarExtra("Mouthpiece", image: "MenuBarIcon") {
            VStack(alignment: .leading, spacing: 4) {
                if let coord = coordinator {
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
            .onAppear {
                appLog.notice("📱 MenuBarExtra onAppear")
                if coordinator == nil {
                    appLog.notice("📱 Building coordinator...")
                    Task { @MainActor in
                        let coord = makeCoordinator()
                        appLog.notice("📱 Coordinator built, starting hotkey...")
                        coord.start()
                        coordinator = coord
                        appLog.notice("📱 Mic permission status: \(String(describing: coord.permission.microphone))")
                        if coord.permission.microphone == .notDetermined {
                            appLog.notice("📱 Requesting microphone permission proactively...")
                            _ = await coord.permission.requestMicrophone()
                        }
                        appLog.notice("📱 Loading model...")
                        await coord.loadModelIfNeeded()
                        appLog.notice("📱 Initial setup complete. Phase: \(String(describing: coord.phase))")
                    }
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }

    @MainActor
    private func makeCoordinator() -> AppCoordinator {
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
        return coord
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
