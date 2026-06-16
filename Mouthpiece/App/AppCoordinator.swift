import Foundation
import AppKit
import Observation
import os.log

private let log = Logger(subsystem: "com.mouthpiece.app", category: "Coordinator")

@MainActor
@Observable
final class AppCoordinator {

    enum Phase: Equatable, Sendable {
        case idle
        case recording
        case transcribing
        case cleaning
        case injecting
        case done(chars: Int)
        case error(String)
    }

    private(set) var phase: Phase = .idle

    // Dependencies
    let permission: PermissionService
    private let hotkey: HotKeyManager
    private let recorder: any AudioRecording
    private let transcriber: any Transcribing
    private let cleaner: TextCleaner
    private let injector: any TextInjecting
    let floatingBar: FloatingBarState
    private let floatingWindow: FloatingBarWindow

    var cleanOptions: CleanOptions = .default

    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?

    init(
        permission: PermissionService,
        recorder: any AudioRecording,
        transcriber: any Transcribing,
        cleaner: TextCleaner = TextCleaner(),
        injector: any TextInjecting,
        floatingBar: FloatingBarState,
        floatingWindow: FloatingBarWindow,
        triggerKey: TriggerKey = .fn
    ) {
        self.permission = permission
        self.recorder = recorder
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.floatingBar = floatingBar
        self.floatingWindow = floatingWindow
        self.hotkey = HotKeyManager(triggerKey: triggerKey)

        // Wire up the hotkey handler now that self exists.
        self.hotkey.replaceHandler { [weak self] event in
            self?.handleHotkey(event)
        }
    }

    func start() {
        log.notice("🟢 start() called")
        hotkey.start()
    }

    func stop() {
        hotkey.stop()
    }

    func handleHotkey(_ event: HotKeyEvent) {
        log.notice("🔑 handleHotkey: \(String(describing: event)), phase: \(String(describing: self.phase))")
        switch event {
        case .pressed:
            Task { await startRecording() }
        case .released:
            Task { await finishRecording() }
        }
    }

    func loadModelIfNeeded() async {
        log.notice("📦 loadModelIfNeeded called")
        let ready = await transcriber.isReady
        log.notice("📦 transcriber.isReady = \(ready)")
        guard !ready else {
            log.notice("📦 Model already ready, skipping")
            return
        }
        do {
            log.notice("📦 Calling transcriber.loadModel()...")
            try await transcriber.loadModel()
            log.notice("✅ loadModel succeeded!")
            // Reset error phase if we previously errored
            if case .error = phase { phase = .idle }
        } catch {
            log.error("❌ loadModel FAILED: \(String(describing: error))")
            phase = .error("模型加载失败: \(error)")
            floatingBar.setError("模型加载失败")
            floatingWindow.showIfNeeded()
        }
    }

    // MARK: Pipeline

    private func startRecording() async {
        guard phase == .idle else { return }
        log.notice("🎤 startRecording: mic=\(String(describing: self.permission.microphone))")

        // Permission gate
        guard permission.microphone == .granted else {
            log.notice("🎤 Mic not granted, requesting...")
            // Try to actively request — this triggers the system dialog
            Task {
                _ = await permission.requestMicrophone()
            }
            phase = .error("没有麦克风权限")
            floatingBar.setError("正在请求麦克风权限")
            floatingWindow.showIfNeeded()
            return
        }

        let ready = await transcriber.isReady
        guard ready else {
            phase = .error("模型还没准备好")
            floatingBar.setError("模型加载中…")
            floatingWindow.showIfNeeded()
            // Kick off model load in background; user can retry
            Task { await loadModelIfNeeded() }
            return
        }

        do {
            try recorder.start()
            phase = .recording
            recordingStartedAt = Date()
            floatingBar.startRecording()
            floatingWindow.showIfNeeded()
            startElapsedTimer()
        } catch {
            phase = .error("\(error)")
            floatingBar.setError("\(error)")
            floatingWindow.showIfNeeded()
        }
    }

    private func finishRecording() async {
        log.notice("🏁 finishRecording called, phase: \(String(describing: self.phase))")
        guard phase == .recording else {
            log.notice("🏁 phase != recording, skipping")
            return
        }
        stopElapsedTimer()

        log.notice("🏁 Calling recorder.stop()...")
        let samples = await recorder.stop()
        log.notice("🏁 Got \(samples.count) samples")
        phase = .transcribing
        floatingBar.setProcessing()

        do {
            log.notice("🏁 Calling transcriber.transcribe()...")
            let result = try await transcriber.transcribe(samples: samples, language: nil)
            log.notice("🏁 Transcribed: \(result.text)")

            phase = .cleaning
            let cleaned = cleaner.clean(result.text, options: cleanOptions)
            log.notice("🏁 Cleaned: \(cleaned)")

            phase = .injecting
            log.notice("🏁 Calling injector.inject()...")
            try await injector.inject(cleaned)

            // TODO P0-10: persist to history
            phase = .done(chars: cleaned.count)
            floatingBar.setDone(chars: cleaned.count)

            // After 1.5s the floatingBar auto-resets to .idle.
            // Hide the window to avoid leaking pixel space on screen.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1700))
                self.floatingWindow.hideIfIdle()
                self.phase = .idle
            }
        } catch {
            phase = .error("\(error)")
            floatingBar.setError(extractErrorMessage(error))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                self.floatingWindow.hideIfIdle()
                self.phase = .idle
            }
        }
    }

    private func extractErrorMessage(_ e: Error) -> String {
        if let te = e as? TranscriptionError {
            switch te {
            case .modelNotReady: return "模型未就绪"
            case .modelDownloadFailed(let m): return "模型下载失败: \(m.prefix(40))"
            case .transcribeFailed(let m): return "识别失败: \(m.prefix(40))"
            }
        }
        if let ie = e as? InjectionError {
            switch ie {
            case .noAccessibilityPermission: return "需要辅助功能权限"
            case .clipboardWriteFailed: return "剪贴板写入失败"
            case .eventPostFailed: return "粘贴失败"
            }
        }
        return String(describing: e)
    }

    // MARK: Recording elapsed timer

    private func startElapsedTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickElapsed() }
        }
    }

    private func stopElapsedTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func tickElapsed() {
        guard let start = recordingStartedAt else { return }
        let elapsed = Date().timeIntervalSince(start)
        floatingBar.updateRecording(elapsed: elapsed, levels: [])
    }
}
