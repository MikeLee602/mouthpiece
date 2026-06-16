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

    private var mainWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?

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

        let settings = AppSettings.shared
        let permission = PermissionService()
        let recorder = AudioRecorder()
        let transcriber = WhisperCLITranscriber(
            binaryPath: settings.whisperBinaryPath,
            modelPath: settings.whisperModelPath
        )
        let injector = TextInjector()
        let bar = FloatingBarState()
        let window = FloatingBarWindow(state: bar)
        let history: HistoryStore
        do {
            history = try HistoryStore()
        } catch {
            appLog.error("🚀 Failed to init HistoryStore: \(String(describing: error))")
            return  // App can't function without history; bail out cleanly
        }
        let dictionary = DictionaryStore(sharing: history)
        let coord = AppCoordinator(
            permission: permission,
            recorder: recorder,
            transcriber: transcriber,
            injector: injector,
            history: history,
            dictionary: dictionary,
            floatingBar: bar,
            floatingWindow: window,
            triggerKey: settings.triggerKey
        )
        coord.start()
        self.coordinator = coord

        // Hot-swap trigger key when user changes it in Settings.
        settings.onTriggerKeyChange = { [weak coord] key in
            coord?.setTriggerKey(key)
        }

        appLog.notice("🚀 Mic permission: \(String(describing: coord.permission.microphone))")
        if coord.permission.microphone == .notDetermined {
            appLog.notice("🚀 Requesting microphone permission proactively...")
            _ = await coord.permission.requestMicrophone()
        }
        appLog.notice("🚀 Loading model...")
        await coord.loadModelIfNeeded()
        appLog.notice("🚀 Bootstrap complete. Phase: \(String(describing: coord.phase))")

        // Background: housekeeping + diagnostics
        let issues = StartupCheck.run(
            whisperBinary: settings.whisperBinaryPath,
            whisperModel: settings.whisperModelPath
        )
        for issue in issues {
            appLog.notice("🩺 \(issue.title, privacy: .public): \(issue.detail, privacy: .public)")
        }
        coord.startupIssues = issues

        // 历史保留 30 天 / 上限 1000 条 — 启动时清一次
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        history.purgeOlderThan(cutoff)

        // 通知权限（不阻塞）
        if settings.notificationsEnabled {
            NotificationCenterHelper.requestAuthorizationIfNeeded()
        }
    }

    @MainActor
    func openMainWindow() {
        guard let coord = coordinator else { return }
        if let wc = mainWindowController {
            wc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: MainWindowView(coordinator: coord))
        let window = NSWindow(contentViewController: host)
        window.title = "嘴替"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 500))
        window.center()
        let wc = NSWindowController(window: window)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.mainWindowController = wc
    }

    @MainActor
    func openSettingsWindow() {
        if let wc = settingsWindowController {
            wc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsPlaceholderView())
        let window = NSWindow(contentViewController: host)
        window.title = "Mouthpiece 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 420))
        window.center()
        let wc = NSWindowController(window: window)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindowController = wc
    }
}

@main
struct MouthpieceApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Mouthpiece", image: "MenuBarIcon") {
            PopoverHost(delegate: appDelegate)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Wraps MenuBarPopover and reacts to coordinator becoming ready.
private struct PopoverHost: View {
    let delegate: AppDelegate
    @State private var refreshTrigger: Int = 0

    var body: some View {
        Group {
            if let coord = delegate.coordinator {
                MenuBarPopover(
                    coordinator: coord,
                    openMain: { delegate.openMainWindow() },
                    openSettings: { delegate.openSettingsWindow() }
                )
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("初始化中…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(width: 240)
            }
        }
        .id(refreshTrigger)
        .onAppear { refreshTrigger += 1 }
    }
}
