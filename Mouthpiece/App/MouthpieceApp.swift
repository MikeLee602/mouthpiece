import SwiftUI
import AppKit

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
                if coordinator == nil {
                    print("[App] onAppear triggered, building coordinator...")
                    Task { @MainActor in
                        let coord = makeCoordinator()
                        print("[App] Coordinator built, starting hotkey...")
                        coord.start()
                        coordinator = coord
                        print("[App] Mic permission status: \(coord.permission.microphone)")
                        // Proactively request microphone permission on first launch
                        if coord.permission.microphone == .notDetermined {
                            print("[App] Requesting microphone permission proactively...")
                            _ = await coord.permission.requestMicrophone()
                        }
                        print("[App] Loading model...")
                        await coord.loadModelIfNeeded()
                        print("[App] Initial setup complete. Phase: \(coord.phase)")
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
