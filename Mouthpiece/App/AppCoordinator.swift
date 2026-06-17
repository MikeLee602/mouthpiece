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

    /// 启动自检发现的问题 — UI 可以在 popover / 主窗顶部展示。
    var startupIssues: [StartupCheck.Issue] = []

    // Dependencies
    let permission: PermissionService
    private let hotkey: HotKeyManager
    private let recorder: any AudioRecording
    private let transcriber: any Transcribing
    private let cleaner: TextCleaner
    private let simplifier = SimplifiedChineseConverter()
    private let injector: any TextInjecting
    let history: HistoryStore
    let dictionary: DictionaryStore
    let floatingBar: FloatingBarState
    private let floatingWindow: FloatingBarWindow

    /// 实时识别 — 给 floating bar 蹦字。可选；初始化时未必启动。
    private let live = LiveTranscriber()
    /// 滑动窗口实时识别（whisper-cli small）—— D 方案 fallback。
    private let streaming = StreamingTranscriber(
        binaryPath: "/opt/homebrew/bin/whisper-cli",
        modelPath: "/opt/homebrew/share/whisper.cpp/ggml-small.bin"
    )
    /// 当前实时识别累积的最新 partial（finishRecording 时如果 whisper 失败会用它兜底）。
    private var lastLivePartial: String = ""

    var cleanOptions: CleanOptions = .default

    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?

    init(
        permission: PermissionService,
        recorder: any AudioRecording,
        transcriber: any Transcribing,
        cleaner: TextCleaner = TextCleaner(),
        injector: any TextInjecting,
        history: HistoryStore,
        dictionary: DictionaryStore,
        floatingBar: FloatingBarState,
        floatingWindow: FloatingBarWindow,
        triggerKey: TriggerKey = .fn,
        hotKeyMode: HotKeyMode = .pushToTalk
    ) {
        self.permission = permission
        self.recorder = recorder
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.history = history
        self.dictionary = dictionary
        self.floatingBar = floatingBar
        self.floatingWindow = floatingWindow
        self.hotkey = HotKeyManager(triggerKey: triggerKey, mode: hotKeyMode)

        // Wire up the hotkey handler now that self exists.
        self.hotkey.replaceHandler { [weak self] event in
            self?.handleHotkey(event)
        }

        // Live transcriber → 实时蹦字到 floating bar
        live.onPartial = { [weak self] text in
            guard let self else { return }
            self.lastLivePartial = text
            self.floatingBar.updatePartial(text)
        }
        live.onError = { [weak self] error in
            // 实时识别失败不致命 — 继续录音，最终还是 whisper-cli 给结果。
            log.error("Live transcribe error (non-fatal): \(error.localizedDescription, privacy: .public)")
            self?.floatingBar.updatePartial("")
        }

        // Streaming transcriber (whisper-cli small) → 实时蹦字 fallback
        streaming.onPartial = { [weak self] text in
            guard let self else { return }
            self.lastLivePartial = text
            self.floatingBar.updatePartial(text)
        }

        // 把 recorder 的 buffer 流式喂给 streaming —— 在 audio thread 上 resample 到 16k
        recorder.setBufferListener({ buffer in
            // 提取 channel 0 的 float samples
            guard let channelData = buffer.floatChannelData else { return }
            let frameLen = Int(buffer.frameLength)
            let raw = Array(UnsafeBufferPointer(start: channelData[0], count: frameLen))
            // resample 48k → 16k 给 whisper 用
            let resampled = AudioRecorder.resample(raw, from: buffer.format.sampleRate, to: 16000)
            let unchecked = UncheckedSendable(resampled)
            Task { @MainActor [weak self] in
                self?.streaming.ingest(samples: unchecked.value)
            }
        })
    }

    func start() {
        log.notice("🟢 start() called")
        hotkey.start()
    }

    /// 切换触发键（设置页用）。
    func setTriggerKey(_ key: TriggerKey) {
        hotkey.setTriggerKey(key)
    }

    /// 切换触发模式（push-to-talk vs toggle）。
    func setHotKeyMode(_ mode: HotKeyMode) {
        hotkey.setMode(mode)
    }

    /// 当前触发键。
    var currentTriggerKey: TriggerKey { hotkey.triggerKey }
    var currentHotKeyMode: HotKeyMode { hotkey.mode }

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
        case .toggled:
            // toggle 模式：当前在 idle/error/done → 开始；否则 → 停止
            switch phase {
            case .idle, .error, .done:
                Task { await startRecording() }
            case .recording:
                Task { await finishRecording() }
            case .transcribing, .cleaning, .injecting:
                // 处理中再按一下 → 忽略，避免抢占
                log.notice("🔑 toggle ignored (phase busy)")
            }
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
            // 启动滑动窗口实时识别（whisper-cli small）
            lastLivePartial = ""
            streaming.start()
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
        // 同时停 live 和 streaming
        live.stop()
        streaming.stop()
        phase = .transcribing
        floatingBar.setProcessing()

        do {
            log.notice("🏁 Calling transcriber.transcribe()...")
            let result = try await transcriber.transcribe(samples: samples, language: nil)
            log.notice("🏁 Transcribed: \(result.text)")

            phase = .cleaning
            let settings = AppSettings.shared
            var opts = cleanOptions
            opts.removeFillers = settings.cleanFillerWords
            opts.removeRepetition = settings.dedupRepeats
            let cleaned = cleaner.clean(result.text, options: opts)
            log.notice("🏁 Cleaned: \(cleaned)")

            let simplified = settings.convertTraditionalToSimplified
                ? simplifier.convert(cleaned)
                : cleaned
            log.notice("🏁 Simplified: \(simplified, privacy: .public)")

            let dictApplied = dictionary.snapshot().apply(to: simplified)
            if dictApplied != simplified {
                log.notice("🏁 Dictionary applied: \(dictApplied, privacy: .public)")
            }

            phase = .injecting
            log.notice("🏁 Calling injector.inject()...")
            try await injector.inject(dictApplied)

            // Persist history (best-effort)
            let entry = TranscriptionEntryDraft(
                timestamp: Date(),
                rawText: result.text,
                cleanedText: dictApplied,
                language: result.language,
                durationSeconds: result.durationSeconds,
                appName: NSWorkspace.shared.frontmostApplication?.localizedName
            )
            history.save(entry)
            log.notice("📝 Saved to history (\(entry.cleanedText.count) chars)")

            if AppSettings.shared.notificationsEnabled {
                NotificationCenterHelper.showTranscriptionDone(text: dictApplied)
            }

            phase = .done(chars: dictApplied.count)
            floatingBar.setDone(chars: dictApplied.count)

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
