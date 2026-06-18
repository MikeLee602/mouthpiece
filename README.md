# Mouthpiece (嘴替)

> 按一下 Fn 说话，本地识别，自动粘贴到任何 App。
> Press Fn to talk. Whisper transcribes locally. Text pastes wherever your cursor is.

[简体中文](#简体中文) · [English](#english)

---

## 简体中文

### 这是什么

**嘴替**是一个 macOS 菜单栏小工具：

1. 按一下 `Fn` 开始录音（再按一下停止；或长按说话）
2. 本地 Whisper 实时识别（边说边出字）
3. 松开 / 再按一下 → 自动粘贴到当前光标位置

任何 App 任何输入框都能用。文字、聊天、邮件、代码注释、Slack、微信网页版……

### 为什么用嘴替

- 🎙️ **完全本地**：whisper.cpp 跑在你的 Mac 上，麦克风音频不离开设备
- ⚡ **实时蹦字**：滑动窗口 + small 模型给你实时预览，停止后 medium 模型出最终高质量版本
- 🧹 **自动整理**：去掉「嗯/啊/那个」填充词，繁体自动转简体
- 📚 **词典 + 历史**：识别错的专有名词加进词典自动修正；历史可搜索 / 导出
- 🔓 **MIT 开源 + 完全免费**

### 安装

#### 1. 装两个 Homebrew 包

```bash
brew install whisper-cpp opencc
```

#### 2. 下载 Whisper 模型

```bash
# medium（必装，最终识别用，1.4 GB）
curl -L -o /opt/homebrew/share/whisper.cpp/ggml-medium.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin

# small（可选，实时预览用，466 MB）
curl -L -o /opt/homebrew/share/whisper.cpp/ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

#### 3. 下载 Mouthpiece

去 [Releases](https://github.com/MikeLee602/mouthpiece/releases) 下载最新 `Mouthpiece-x.y.z.dmg`，挂载，把 `Mouthpiece.app` 拖到 `/Applications`。

#### 4. 绕过 Gatekeeper（首次必做）

DMG 没经过 Apple 公证（个人开发者还在等证书），所以双击会被拒。两种办法：

**方法一**：右键 `Mouthpiece.app` → 打开 → 在弹窗里点「打开」（仅首次）

**方法二**（推荐）：Terminal 跑

```bash
xattr -d com.apple.quarantine /Applications/Mouthpiece.app
```

#### 5. 授权

第一次按 `Fn` 录音时，macOS 会请求三个权限：

- **麦克风**：必须授权
- **辅助功能**：必须授权（用来粘贴文字到当前 App）
- **语音识别**：可选（实时预览功能要）

### 使用

启动后菜单栏会有一个嘴形图标。

- **按一下 `Fn`** 开始录音 → **再按一下** 停止 → 文字自动粘贴
- 想用「按住说话」模式：菜单栏 → 嘴替 → 设置 → 录音 → 触发方式

### 设置

菜单栏 → 嘴替 → 仪表盘 / 历史 / 词典 / 设置

- **仪表盘**：今日 / 本周字数 / 平均时长 + 7 天柱图 + 最近 10 条
- **历史**：搜索 / 导出 JSON / 多选删除
- **词典**：识别错的词加规则自动替换（例：「纸笔体」→「GPT」）
- **设置**：触发键 / 触发方式 / 录音上限 / 转写语言 / 后处理开关

### 常见问题

**Q: partial 一直没出来？**
A: 检查菜单栏小图标点开后顶部是否有红色权限横幅；或 small 模型没装。

**Q: 「无法验证开发者」**
A: 见上面"绕过 Gatekeeper"。等开发者证书拿到会出公证版。

**Q: 我说话时 partial 偶尔有重复字**
A: 滑窗模型小、识别有微小漂移导致。停止后 final（medium）一般是干净的。

### 技术栈

- Swift 6 + SwiftUI（macOS 14+）
- AVFoundation（录音 + 实时 buffer tap）
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)（识别）
- [OpenCC](https://github.com/BYVoid/OpenCC)（繁→简）
- SwiftData（历史 / 词典持久化）

### License

MIT

---

## English

### What is this

**Mouthpiece** is a macOS menu bar dictation tool:

1. Press `Fn` to start recording (press again to stop; or hold to talk)
2. Whisper transcribes locally in real-time (text appears as you speak)
3. Release / press again → text pastes at the current cursor position

Works in any app, any text field. Documents, chat, email, code comments, Slack, etc.

### Why use it

- 🎙️ **Fully local**: whisper.cpp runs on your Mac. Audio never leaves the device.
- ⚡ **Live preview**: sliding-window small model for live transcription, then medium model for the final high-quality version.
- 🧹 **Cleanup**: filler word removal, traditional → simplified Chinese.
- 📚 **Dictionary + history**: searchable / exportable history, dictionary rules to auto-fix recurring mis-recognitions.
- 🔓 **MIT-licensed, free forever**.

### Install

#### 1. Install two Homebrew packages

```bash
brew install whisper-cpp opencc
```

#### 2. Download Whisper models

```bash
# medium (required, ~1.4 GB, used for the final transcription)
curl -L -o /opt/homebrew/share/whisper.cpp/ggml-medium.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin

# small (optional, ~466 MB, used for live preview)
curl -L -o /opt/homebrew/share/whisper.cpp/ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

#### 3. Download Mouthpiece

Grab the latest `Mouthpiece-x.y.z.dmg` from [Releases](https://github.com/MikeLee602/mouthpiece/releases), open it, drag `Mouthpiece.app` to `/Applications`.

#### 4. Bypass Gatekeeper (first time only)

The DMG isn't notarized yet (waiting on Apple Developer enrollment), so a plain double-click will be blocked. Two options:

**Option 1**: Right-click `Mouthpiece.app` → Open → confirm in the dialog.

**Option 2** (recommended): in Terminal:

```bash
xattr -d com.apple.quarantine /Applications/Mouthpiece.app
```

#### 5. Permissions

On first `Fn` press, macOS asks for three permissions:

- **Microphone**: required
- **Accessibility**: required (used to paste text)
- **Speech Recognition**: optional (only for the live-preview path; never used because Apple's Speech daemon is broken on macOS 26 with buffer-fed requests)

### Usage

After launch you'll see a mouth icon in the menu bar.

- **Press `Fn`** to start → **press again** to stop → text auto-pastes.
- Prefer push-to-talk: Menu Bar → Mouthpiece → Settings → Recording → Trigger style.

### Settings

Menu Bar → Mouthpiece → Dashboard / History / Dictionary / Settings.

- **Dashboard**: today / week counts + chars / avg duration + 7-day chart + recent 10
- **History**: search / export JSON / multi-select delete
- **Dictionary**: pattern → replacement rules (e.g. fix recurring mis-recognitions)
- **Settings**: trigger key / mode / max duration / transcription language / post-processing

### Tech

- Swift 6 + SwiftUI (macOS 14+)
- AVFoundation (recording + real-time buffer tap)
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (recognition)
- [OpenCC](https://github.com/BYVoid/OpenCC) (traditional → simplified)
- SwiftData (history / dictionary persistence)

### License

MIT
