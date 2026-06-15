import SwiftUI
import AppKit

@main
struct MouthpieceApp: App {

    @State private var coordinator: AppCoordinator? = nil

    var body: some Scene {
        MenuBarExtra("Mouthpiece", systemImage: "mic.fill") {
            VStack(alignment: .leading, spacing: 4) {
                if let coord = coordinator {
                    Text(statusLabel(for: coord.phase))
                    Divider()
                    Text("按住 Fn 开始录音").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("初始化中…")
                }
                Divider()
                Button("退出") { NSApp.terminate(nil) }
            }
            .padding(8)
            .onAppear {
                if coordinator == nil {
                    Task { @MainActor in
                        let coord = makeCoordinator()
                        coord.start()
                        coordinator = coord
                        await coord.loadModelIfNeeded()
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
        let transcriber = WhisperKitTranscriber(modelName: "openai_whisper-medium")
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
