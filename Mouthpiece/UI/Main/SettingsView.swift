import SwiftUI
import AppKit

struct SettingsView: View {
    let coordinator: AppCoordinator?  // optional for preview / standalone

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gear") }
            RecordingSettingsView()
                .tabItem { Label("录音", systemImage: "mic") }
            TranscriptionSettingsView()
                .tabItem { Label("转写", systemImage: "waveform") }
            PostProcessSettingsView()
                .tabItem { Label("后处理", systemImage: "wand.and.stars") }
            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 440)
        .padding(.top, 4)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("启动") {
                Toggle("登录时自动启动", isOn: $settings.launchAtLogin)
                Toggle("在 Dock 显示", isOn: $settings.showInDock)
            }
            Section("通知") {
                Toggle("完成转写后弹通知", isOn: $settings.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }
}

// MARK: - Recording

private struct RecordingSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("触发键") {
                Picker("按住开始录音", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases, id: \.self) { k in
                        Text(k.userLabel).tag(k)
                    }
                }
                Text("按住所选键开始录音，松开停止并自动转写。Fn 在大部分 Mac 上最方便。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("录音上限") {
                HStack {
                    Stepper("\(settings.maxRecordingSeconds) 秒",
                            value: $settings.maxRecordingSeconds,
                            in: 60...1800,
                            step: 30)
                }
                Text("达到上限后自动停止录音。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("反馈") {
                Toggle("录音开始 / 结束时播放系统音", isOn: $settings.soundFeedback)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }
}

// MARK: - Transcription

private struct TranscriptionSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("语言") {
                Picker("识别语言", selection: $settings.transcriptionLanguage) {
                    Text("中文").tag("zh")
                    Text("英文").tag("en")
                    Text("自动检测").tag("auto")
                }
            }
            Section("Whisper 路径") {
                HStack {
                    TextField("whisper-cli 二进制", text: $settings.whisperBinaryPath)
                    Button("选择…") { pickFile($settings.whisperBinaryPath) }
                }
                HStack {
                    TextField("Whisper 模型", text: $settings.whisperModelPath)
                    Button("选择…") { pickFile($settings.whisperModelPath) }
                }
                Text("由 `brew install whisper-cpp` 提供；或自行下载 ggml 模型并选择路径。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }

    private func pickFile(_ binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }
}

// MARK: - Post-process

private struct PostProcessSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("识别后清洗") {
                Toggle("去除「嗯/呃/那个」等填充词", isOn: $settings.cleanFillerWords)
                Toggle("合并重复句", isOn: $settings.dedupRepeats)
                Text("Whisper 偶尔会重复同一句，开启后会去重。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("简繁转换") {
                Toggle("自动转为简体中文（OpenCC t2s）", isOn: $settings.convertTraditionalToSimplified)
                Text("依赖 `brew install opencc`；未安装则跳过。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }
}

// MARK: - About

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("嘴替 / Mouthpiece").font(.title2.bold())
            Text(version)
                .font(.callout).foregroundStyle(.secondary)
            Divider().padding(.horizontal, 60)
            Text("按住 Fn → 说话 → 松开 → 文字粘贴到光标位置")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("项目主页") { open("https://github.com/") }
                Button("反馈") { open("https://github.com/") }
                Button("MIT License") { open("https://opensource.org/license/mit/") }
            }
            .buttonStyle(.link)
            Spacer()
            Text("Powered by whisper.cpp · OpenCC")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (\(b))"
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
