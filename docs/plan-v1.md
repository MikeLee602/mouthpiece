# Mouthpiece (嘴替) — Implementation Plan v1

> **目标**：做一个 macOS 全局语音输入工具，对标 Typeless 但开源免费。按住 Fn 说话，松开自动识别+清洗+粘贴到当前光标。
> **平台**：macOS 13+（SwiftUI 需要 13+ 的部分 API）
> **分发**：GitHub Release（DMG 直装）+ App Store 双线
> **协议**：MIT 开源
> **品牌**：Mouthpiece / 嘴替

---

## 0. 当前状态

- 项目名：`mouthpiece`
- 项目目录：`~/projects/mouthpiece/`
- GitHub 仓库：**待你创建**（建议 `github.com/<你的id>/mouthpiece` public）
- Apple Developer 账号：**你正在注册**（中国大陆个人账号，$99/年）
- 实现计划：本文档
- **最低系统版本：macOS 14.0 Sonoma**（原定 13+，但用 SwiftData 和 @Observable 需要 14+，调整后用户覆盖率仍 80%+）

---

## 1. 总体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Mouthpiece.app                           │
│                  (Swift + SwiftUI)                          │
├─────────────────────────────────────────────────────────────┤
│  入口：MouthpieceApp.swift                                  │
│  ├── @main, scene = Settings + MenuBarExtra                 │
│  └── 启动 AppCoordinator                                    │
├─────────────────────────────────────────────────────────────┤
│  Core 层（业务逻辑，无 UI 依赖）                            │
│  ├── HotKeyManager       全局快捷键监听（Fn 长按）         │
│  ├── AudioRecorder       AVAudioEngine 采集（16kHz mono）  │
│  ├── VADService          WebRTC-VAD swift binding (或简化) │
│  ├── TranscriptionService WhisperKit 调用                  │
│  ├── TextCleaner         正则清洗（去填充词等）            │
│  ├── LLMPolisher         Claude API 智能润色（可选）       │
│  ├── TextInjector        Cmd+V 模拟粘贴（CGEvent）         │
│  ├── PermissionService   麦克风/Accessibility 权限自检    │
│  ├── HistoryStore        SwiftData 持久化历史              │
│  ├── DictionaryStore     SwiftData 持久化个人词典          │
│  └── ErrorReporter       错误统一上报到 UI                 │
├─────────────────────────────────────────────────────────────┤
│  UI 层（SwiftUI）                                           │
│  ├── MenuBarExtraView    菜单栏图标 + 弹出菜单             │
│  ├── FloatingBarWindow   屏幕底部居中浮条                  │
│  ├── MainWindow          主窗口（首页/历史/词典）          │
│  ├── OnboardingWindow    首次启动引导                       │
│  └── SettingsWindow      设置面板                           │
├─────────────────────────────────────────────────────────────┤
│  Resources                                                  │
│  ├── WhisperKit Models   ggml-medium.bin (~1.5GB)         │
│  └── Assets.xcassets     图标、品牌色                       │
└─────────────────────────────────────────────────────────────┘
```

**关键设计原则**：
- Core 全部用 `actor` 或 `@MainActor` 隔离，避免并发数据竞争
- UI 用 `@Observable`（iOS 17+/macOS 14+）做状态管理，告别 Combine 繁杂
- 所有跟系统/网络打交道的服务都包一层 `protocol`，便于单元测试 mock
- 文件 < 300 行、单一职责

---

## 2. 项目结构

```
~/projects/mouthpiece/
├── Mouthpiece.xcodeproj
├── Mouthpiece/                       # App target
│   ├── App/
│   │   ├── MouthpieceApp.swift       # @main entry
│   │   └── AppCoordinator.swift      # 协调器，串起所有 service
│   ├── Core/
│   │   ├── HotKey/
│   │   │   └── HotKeyManager.swift
│   │   ├── Audio/
│   │   │   ├── AudioRecorder.swift
│   │   │   └── VADService.swift
│   │   ├── Transcription/
│   │   │   ├── TranscriptionService.swift
│   │   │   └── WhisperKitWrapper.swift
│   │   ├── Cleaning/
│   │   │   ├── TextCleaner.swift     # 正则清洗
│   │   │   └── LLMPolisher.swift     # Claude API
│   │   ├── Injection/
│   │   │   └── TextInjector.swift
│   │   ├── Permission/
│   │   │   └── PermissionService.swift
│   │   ├── Storage/
│   │   │   ├── HistoryStore.swift    # SwiftData
│   │   │   ├── DictionaryStore.swift
│   │   │   └── Models/               # SwiftData @Model
│   │   └── Errors/
│   │       └── MouthpieceError.swift
│   ├── UI/
│   │   ├── MenuBar/
│   │   │   ├── MenuBarController.swift
│   │   │   └── MenuBarView.swift
│   │   ├── FloatingBar/
│   │   │   ├── FloatingBarWindow.swift
│   │   │   └── FloatingBarView.swift
│   │   ├── MainWindow/
│   │   │   ├── MainWindow.swift
│   │   │   ├── HomeView.swift
│   │   │   ├── HistoryView.swift
│   │   │   └── DictionaryView.swift
│   │   ├── Onboarding/
│   │   │   ├── OnboardingWindow.swift
│   │   │   └── steps/                # 4 步：权限/快捷键/试录/完成
│   │   └── Settings/
│   │       ├── SettingsWindow.swift
│   │       └── tabs/                 # General/Audio/Cleaning/Hotkey/History
│   ├── Resources/
│   │   ├── Assets.xcassets           # 嘴形菜单栏图标 + 品牌色 + 主图标
│   │   └── Models/                   # WhisperKit 模型（首次下载）
│   ├── Info.plist
│   └── Mouthpiece.entitlements
├── MouthpieceTests/                  # 单元测试
│   ├── Core/
│   └── ...
├── MouthpieceUITests/                # UI 自动化测试
├── docs/
│   ├── plan-v1.md                    # 本文档
│   ├── architecture.md
│   ├── release-checklist.md
│   ├── appstore-submission.md
│   └── screenshots/                  # App Store 用截图
├── scripts/
│   ├── build-release.sh              # 本地打 DMG
│   ├── notarize.sh                   # 公证
│   └── update-version.sh
├── .github/
│   └── workflows/
│       ├── test.yml                  # PR 触发跑测试
│       └── release.yml               # tag 触发出 DMG + Release
├── LICENSE                            # MIT
├── README.md
├── CONTRIBUTING.md
├── CHANGELOG.md
└── .gitignore
```

---

## 3. P0 任务清单（15 个）— v1 必做

每个任务后面跟着估时（小时）。**TDD 节奏 + 频繁 commit**。

| # | 任务 | 估时 | 依赖 |
|---|---|---|---|
| **P0-01** | 项目脚手架 + Xcode 项目 + CI 框架 | 4h | 无 |
| **P0-02** | 权限服务 + 麦克风权限引导 | 3h | 01 |
| **P0-03** | 全局快捷键监听（Fn 长按） | 4h | 01 |
| **P0-04** | 音频采集（AVAudioEngine 16kHz mono） | 4h | 02 |
| **P0-05** | WhisperKit 集成 + 中文 medium 模型 | 6h | 04 |
| **P0-06** | 录音浮条窗口（屏幕底部居中，4 态） | 5h | 03, 04 |
| **P0-07** | 文本清洗 TextCleaner（正则去填充词等） | 3h | 05 |
| **P0-08** | 文本注入 TextInjector（Cmd+V 模拟） | 3h | 07 |
| **P0-09** | Pipeline 编排（快捷键→录音→识别→清洗→注入） | 4h | 03,04,05,07,08 |
| **P0-10** | 历史存储 HistoryStore（SwiftData） | 4h | 09 |
| **P0-11** | 菜单栏图标 + 弹出菜单 | 4h | 10 |
| **P0-12** | 主窗口首页 + 数据卡片 | 6h | 10 |
| **P0-13** | 历史记录页 + 词典页（基础版） | 5h | 10 |
| **P0-14** | 设置面板（基础 5 个 tab） | 6h | 03,07,10 |
| **P0-15** | 错误处理 + 边界场景（10 分钟限制 / 麦克风丢失 / 模型未下载等） | 5h | 全部 |

**P0 总估时：~70 小时**（按每天 8 小时算，**约 9 个工作日**；考虑调试和踩坑实际 2-3 周）

---

## 4. P1 任务清单（10 个）— 体验完善

| # | 任务 | 估时 | 依赖 |
|---|---|---|---|
| **P1-01** | Onboarding 首次启动引导（4 步） | 5h | P0 完成 |
| **P1-02** | LLM 智能润色（Claude API） | 5h | P0-07 |
| **P1-03** | 个人词典（识别时 prompt 注入） | 5h | P0-13 |
| **P1-04** | 中英混合保留 + 自动语言检测 | 4h | P0-05 |
| **P1-05** | 智能结构格式化（"第一/第二/第三"→列表） | 4h | P0-07 |
| **P1-06** | Edit 模式（选中文字 + 说指令） | 8h | P0-08, P1-02 |
| **P1-07** | 不同 App 不同语气 | 5h | P1-02 |
| **P1-08** | 历史保留期可配置 + 自动清理 | 3h | P0-10 |
| **P1-09** | 翻译模式（双击 Fn） | 4h | P1-02 |
| **P1-10** | 个性化进度指示 + 累计统计 | 4h | P0-10 |

**P1 总估时：~47 小时**（约 6 个工作日）

---

## 5. 发布流程任务

| # | 任务 | 估时 |
|---|---|---|
| **R-01** | App 签名（Developer ID Application 证书） | 2h |
| **R-02** | 公证脚本（notarytool） | 3h |
| **R-03** | DMG 打包脚本（create-dmg） | 2h |
| **R-04** | GitHub Actions：tag 推送自动出 release | 4h |
| **R-05** | App Sandbox 适配（entitlements 调整） | 6h |
| **R-06** | App Store Connect 元数据填充 | 3h |
| **R-07** | App Store 截图（5 张，1280×800） | 4h |
| **R-08** | 隐私清单 PrivacyManifest.plist | 2h |
| **R-09** | Sparkle 自动更新（GitHub 版用） | 4h |
| **R-10** | 首次提审 + 反馈整改 | 8h（不确定，可能更多） |

**发布流程总估时：~38 小时**

---

## 6. 总工程量

| 阶段 | 估时（编码）| 实际周期（含调试踩坑）|
|---|---|---|
| Phase 1: P0 GitHub MVP | 70h | **2.5 周** |
| Phase 2: P1 体验完善 | 47h | **1.5 周** |
| Phase 3: 发布 + App Store | 38h | **2 周** |
| **总计** | **155h** | **约 6 周** |

---

## 7. 各 Phase 里程碑

| Phase | 完成标志 | 目标日期 |
|---|---|---|
| Phase 1 | 你本地装上 DMG，能 Fn + 说话 + 粘贴到任意 App | T+2.5w |
| Phase 2 | Claude 润色、Edit 模式、词典全部能用 | T+4w |
| Phase 3a | GitHub Release 发布 v1.0.0，签名公证 | T+5w |
| Phase 3b | 提交 App Store 审核 | T+5.5w |
| Phase 3c | App Store 上架 | T+6-8w |

---

## 8. 风险清单

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| WhisperKit 中文识别质量不达预期 | 中 | 高 | 准备 fallback 到内嵌 whisper.cpp |
| App Store 首次审核被拒 | 高 | 中 | 提前读 Sandbox 规范，Accessibility 用法写清楚 |
| Apple Developer 注册卡审核 | 低 | 高 | 你提前注册（已开始） |
| Fn 键检测在不同 Mac 键盘表现不一致 | 中 | 中 | 提供备选键（Right Option/F13） |
| WhisperKit 模型大（1.5GB），首次下载体验差 | 高 | 中 | 进度条 + 后台下载 + 启动时不强制 |
| 中文 IME 输入法干扰 Cmd+V 注入 | 中 | 高 | 临时关 IME 或检测 IME 状态做兼容 |

---

下面是各任务的详细实现描述。每个任务包含：文件清单、TDD 步骤、关键代码骨架、验收标准、commit 信息。

---

# Part II: P0 任务详细实现

---

## P0-01: 项目脚手架 + Xcode 项目 + CI 框架

**估时**: 4h | **依赖**: 无

**Files:**
- Create: `~/projects/mouthpiece/Mouthpiece.xcodeproj` (Xcode 生成)
- Create: `~/projects/mouthpiece/Mouthpiece/App/MouthpieceApp.swift`
- Create: `~/projects/mouthpiece/Mouthpiece/Info.plist`
- Create: `~/projects/mouthpiece/Mouthpiece/Mouthpiece.entitlements`
- Create: `~/projects/mouthpiece/MouthpieceTests/SmokeTests.swift`
- Create: `~/projects/mouthpiece/.gitignore`
- Create: `~/projects/mouthpiece/.swiftlint.yml`
- Create: `~/projects/mouthpiece/.github/workflows/test.yml`
- Create: `~/projects/mouthpiece/LICENSE` (MIT)
- Create: `~/projects/mouthpiece/README.md`

### Step 1: 在 Xcode 里创建项目

打开 Xcode → File → New → Project → macOS → App。
- Product Name: `Mouthpiece`
- Team: 你的 Apple ID（或暂时 None）
- Organization Identifier: `com.mouthpiece`
- Bundle Identifier: `com.mouthpiece.app`
- Interface: SwiftUI
- Language: Swift
- Storage: None（我们手动加 SwiftData）
- Include Tests: ✓
- Save 到 `~/projects/mouthpiece/`

### Step 2: 项目设置

打开 `Mouthpiece` target → General：
- Minimum Deployments: macOS 14.0
- Category: Productivity

→ Signing & Capabilities：
- Signing Certificate: Development（暂时）
- 添加 Capability: `App Sandbox`
- App Sandbox 里勾选: `User Selected File (Read/Write)`, `Network: Outgoing Connections`(Claude API 用)
- 添加 Capability: `Hardened Runtime`
- Hardened Runtime 里勾选: `Audio Input`

→ Info.plist 里添加：
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Mouthpiece 需要麦克风权限将你的语音转为文字。</string>
<key>LSUIElement</key>
<true/>
```
`LSUIElement=true` 让 App 没有 Dock 图标，纯菜单栏 App。

### Step 3: 写 MouthpieceApp.swift

`Mouthpiece/App/MouthpieceApp.swift`:
```swift
import SwiftUI

@main
struct MouthpieceApp: App {
    var body: some Scene {
        MenuBarExtra("Mouthpiece", systemImage: "mic.fill") {
            Text("Mouthpiece 启动了")
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
```

### Step 4: 写冒烟测试

`MouthpieceTests/SmokeTests.swift`:
```swift
import XCTest
@testable import Mouthpiece

final class SmokeTests: XCTestCase {
    func testAppBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.mouthpiece.app")
    }
}
```

跑测试：Xcode 里 Cmd+U。预期通过。

### Step 5: 配置 .gitignore

`~/projects/mouthpiece/.gitignore`:
```
.DS_Store
build/
DerivedData/
*.xcuserdata/
*.xcuserstate
*.xcscmblueprint
*.xccheckout
xcuserdata/
Pods/
*.swp
.build/
.idea/
secrets/
```

### Step 6: 配置 SwiftLint

`~/projects/mouthpiece/.swiftlint.yml`:
```yaml
disabled_rules:
  - line_length
  - trailing_whitespace
opt_in_rules:
  - empty_count
  - explicit_init
  - force_unwrapping
excluded:
  - Pods
  - .build
  - DerivedData
identifier_name:
  min_length: 2
```

把 SwiftLint 加到 Xcode Build Phase（不强制）：
```bash
if which swiftlint >/dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed"
fi
```

### Step 7: 配置 GitHub Actions CI

`.github/workflows/test.yml`:
```yaml
name: Test

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app
      - name: Build & Test
        run: |
          xcodebuild test \
            -project Mouthpiece.xcodeproj \
            -scheme Mouthpiece \
            -destination 'platform=macOS' \
            -resultBundlePath TestResults \
            CODE_SIGNING_ALLOWED=NO
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: TestResults
```

### Step 8: LICENSE 和 README

`LICENSE`（MIT 模板，自己网上找完整文本，填年份 2026 和姓名）。

`README.md`：
```markdown
# Mouthpiece（嘴替）

按住 Fn 说话，自动识别并粘贴到任何 App 的光标位置。

- 🎙️ 本地 Whisper 识别，数据不出 Mac
- ⚡ 任何 App 任何输入框都能用
- 🧹 自动去掉"嗯/啊/那个"等填充词
- 🔓 完全开源，免费使用
- 🍎 macOS 14.0+

## 状态
开发中。预计 6 周内 v1.0 发布。

## License
MIT
```

### Step 9: 初始化 git 并 commit

```bash
cd ~/projects/mouthpiece
git init
git branch -m main
git add -A
git commit -m "chore: scaffold mouthpiece xcode project"
```

### 验收标准
- [ ] `Cmd+R` 跑起来：菜单栏出现一个麦克风图标，点击有菜单
- [ ] `Cmd+U` 测试通过：1 个 smoke 测试
- [ ] 没有 Dock 图标（LSUIElement 生效）
- [ ] `git log` 有一个干净的初始 commit

---

## P0-02: 权限服务 + 麦克风权限引导

**估时**: 3h | **依赖**: P0-01

**Files:**
- Create: `Core/Permission/PermissionService.swift`
- Create: `Core/Permission/PermissionStatus.swift`
- Create: `UI/Permission/PermissionPromptView.swift`
- Create: `MouthpieceTests/PermissionServiceTests.swift`

### Step 1: 定义协议和数据模型

`Core/Permission/PermissionStatus.swift`:
```swift
import AVFoundation

enum MicrophonePermission: Equatable {
    case notDetermined
    case denied
    case granted
}

enum AccessibilityPermission: Equatable {
    case granted
    case notGranted
}

protocol PermissionChecking: AnyObject {
    var microphone: MicrophonePermission { get }
    var accessibility: AccessibilityPermission { get }
    func requestMicrophone() async -> MicrophonePermission
    func openMicrophoneSettings()
    func openAccessibilitySettings()
}
```

### Step 2: 写测试（mock 实现）

`MouthpieceTests/PermissionServiceTests.swift`:
```swift
import XCTest
@testable import Mouthpiece

final class PermissionServiceTests: XCTestCase {

    final class MockPermissionService: PermissionChecking {
        var microphone: MicrophonePermission = .notDetermined
        var accessibility: AccessibilityPermission = .notGranted
        var requestResult: MicrophonePermission = .granted

        func requestMicrophone() async -> MicrophonePermission {
            microphone = requestResult
            return requestResult
        }
        func openMicrophoneSettings() {}
        func openAccessibilitySettings() {}
    }

    func testInitialState() {
        let svc: PermissionChecking = MockPermissionService()
        XCTAssertEqual(svc.microphone, .notDetermined)
        XCTAssertEqual(svc.accessibility, .notGranted)
    }

    func testRequestMicrophoneGranted() async {
        let svc = MockPermissionService()
        svc.requestResult = .granted
        let result = await svc.requestMicrophone()
        XCTAssertEqual(result, .granted)
        XCTAssertEqual(svc.microphone, .granted)
    }

    func testRequestMicrophoneDenied() async {
        let svc = MockPermissionService()
        svc.requestResult = .denied
        let result = await svc.requestMicrophone()
        XCTAssertEqual(result, .denied)
    }
}
```

### Step 3: 实现真实 PermissionService

`Core/Permission/PermissionService.swift`:
```swift
import AVFoundation
import AppKit
import Observation

@Observable
final class PermissionService: PermissionChecking {

    private(set) var microphone: MicrophonePermission
    private(set) var accessibility: AccessibilityPermission

    init() {
        self.microphone = Self.currentMic()
        self.accessibility = Self.currentAccessibility()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        microphone = Self.currentMic()
        accessibility = Self.currentAccessibility()
    }

    func requestMicrophone() async -> MicrophonePermission {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        let status: MicrophonePermission = granted ? .granted : .denied
        await MainActor.run { self.microphone = status }
        return status
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private static func currentMic() -> MicrophonePermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    private static func currentAccessibility() -> AccessibilityPermission {
        AXIsProcessTrusted() ? .granted : .notGranted
    }
}
```

### Step 4: 引导 UI

`UI/Permission/PermissionPromptView.swift`:
```swift
import SwiftUI

struct PermissionPromptView: View {
    @Bindable var service: PermissionService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mouthpiece 需要权限")
                .font(.title2).bold()

            permissionRow(
                title: "麦克风",
                description: "用于将你说的话转为文字",
                granted: service.microphone == .granted,
                action: {
                    if service.microphone == .notDetermined {
                        Task { await service.requestMicrophone() }
                    } else {
                        service.openMicrophoneSettings()
                    }
                }
            )

            permissionRow(
                title: "辅助功能",
                description: "用于自动粘贴文字到光标位置",
                granted: service.accessibility == .granted,
                action: { service.openAccessibilitySettings() }
            )
        }
        .padding(24)
        .frame(width: 480)
    }

    @ViewBuilder
    private func permissionRow(title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("授权", action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}
```

### Step 5: 跑测试

```
Cmd+U
```
预期：3 个测试通过。

### Step 6: Commit
```bash
git add -A
git commit -m "feat: permission service + onboarding UI"
```

### 验收标准
- [ ] 测试 3/3 通过
- [ ] PermissionPromptView 能在 SwiftUI Preview 里渲染
- [ ] 在新 Mac 上首次跑，调用 requestMicrophone 会触发系统弹窗

---

## P0-03: 全局快捷键监听（Fn 长按）

**估时**: 4h | **依赖**: P0-01

**Files:**
- Create: `Core/HotKey/HotKey.swift`
- Create: `Core/HotKey/HotKeyManager.swift`
- Create: `MouthpieceTests/HotKeyManagerTests.swift`

### 关键技术点
- macOS 没有专门的 Fn 长按 API，要通过 `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` 监听 modifier flag 变化
- Fn 键对应 `NSEvent.ModifierFlags.function`（值 `1 << 23`）
- 长按 = 按下后 N 毫秒内没松开
- 因为是 global monitor，**必须有 Accessibility 权限**才能监听全局键盘

### Step 1: 定义类型

`Core/HotKey/HotKey.swift`:
```swift
import AppKit

enum TriggerKey: String, CaseIterable, Codable {
    case fn = "Fn"
    case rightOption = "Right Option"
    case f13 = "F13"

    var modifierFlag: NSEvent.ModifierFlags? {
        switch self {
        case .fn: return .function
        case .rightOption: return [.option]   // 注意：还要检查 keyCode==61 确保是右
        case .f13: return nil                  // 不是 modifier，是普通 key
        }
    }
}

enum HotKeyEvent: Equatable {
    case pressed
    case released
}
```

### Step 2: 写测试（mock 事件源）

`MouthpieceTests/HotKeyManagerTests.swift`:
```swift
import XCTest
@testable import Mouthpiece

final class HotKeyManagerTests: XCTestCase {

    func testFnKeyDetection() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn) { ev in events.append(ev) }

        mgr.handleFlagsChangedForTest(flags: [.function])
        mgr.handleFlagsChangedForTest(flags: [])

        XCTAssertEqual(events, [.pressed, .released])
    }

    func testIgnoresOtherModifiers() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn) { ev in events.append(ev) }

        mgr.handleFlagsChangedForTest(flags: [.command])
        mgr.handleFlagsChangedForTest(flags: [.command, .shift])
        mgr.handleFlagsChangedForTest(flags: [])

        XCTAssertEqual(events, [])
    }

    func testReleaseEventOnlyAfterPress() {
        var events: [HotKeyEvent] = []
        let mgr = HotKeyManager(triggerKey: .fn) { ev in events.append(ev) }

        mgr.handleFlagsChangedForTest(flags: [])

        XCTAssertEqual(events, [])
    }
}
```

### Step 3: 实现 HotKeyManager

`Core/HotKey/HotKeyManager.swift`:
```swift
import AppKit

@MainActor
final class HotKeyManager {
    private let triggerKey: TriggerKey
    private let onEvent: (HotKeyEvent) -> Void
    private var isPressed = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(triggerKey: TriggerKey, onEvent: @escaping (HotKeyEvent) -> Void) {
        self.triggerKey = triggerKey
        self.onEvent = onEvent
    }

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(flags: event.modifierFlags)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(flags: event.modifierFlags)
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    /// Visible to tests
    func handleFlagsChangedForTest(flags: NSEvent.ModifierFlags) {
        handleFlagsChanged(flags: flags)
    }

    private func handleFlagsChanged(flags: NSEvent.ModifierFlags) {
        guard let target = triggerKey.modifierFlag else { return }
        let nowDown = flags.contains(target)

        if nowDown && !isPressed {
            isPressed = true
            onEvent(.pressed)
        } else if !nowDown && isPressed {
            isPressed = false
            onEvent(.released)
        }
    }
}
```

### Step 4: 跑测试

预期 3 个测试通过。

### Step 5: 集成进 App（先打日志，下个任务再串）

修改 `MouthpieceApp.swift`：
```swift
import SwiftUI

@main
struct MouthpieceApp: App {
    @State private var hotkeyManager: HotKeyManager?

    var body: some Scene {
        MenuBarExtra("Mouthpiece", systemImage: "mic.fill") {
            Text("按住 Fn 测试")
            Button("退出") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: hotkeyManager == nil) { _, _ in
            if hotkeyManager == nil {
                let mgr = HotKeyManager(triggerKey: .fn) { ev in
                    print("[hotkey] \(ev)")
                }
                mgr.start()
                hotkeyManager = mgr
            }
        }
    }
}
```

### Step 6: 手动验证

在 Xcode 跑 App，控制台按 Fn 应该打印：
```
[hotkey] pressed
[hotkey] released
```
注意：如果没有 Accessibility 权限，global monitor 不工作，只 local 工作（App 在前台时才有）。下一个任务我们处理这个。

### Step 7: Commit
```bash
git add -A
git commit -m "feat: global Fn-key hot-key manager"
```

### 验收标准
- [ ] 单测 3/3 通过
- [ ] 在 Xcode 里跑，按 Fn 控制台有日志
- [ ] 已知限制：global monitor 需要 Accessibility 权限，P0-15 会处理

---


## P0-04: 音频采集（AVAudioEngine 16kHz mono）

**估时**: 4h | **依赖**: P0-02

**Files:**
- Create: `Core/Audio/AudioRecorder.swift`
- Create: `Core/Audio/AudioRecorderProtocol.swift`
- Create: `MouthpieceTests/AudioRecorderTests.swift`

### 关键技术点
- AVAudioEngine inputNode 默认是系统采样率（通常 44.1k 或 48k）
- WhisperKit 要求 16kHz 单声道 Float32 PCM
- 必须用 AVAudioConverter 做重采样
- 10 分钟硬上限（10*60*16000=9,600,000 samples），9 分钟开始警告

### Step 1: 协议

`Core/Audio/AudioRecorderProtocol.swift`:
```swift
import Foundation

enum AudioRecorderState: Equatable {
    case idle
    case recording(elapsed: TimeInterval)
    case finished(samples: [Float], sampleRate: Double)
    case failed(AudioRecorderError)
}

enum AudioRecorderError: Error, Equatable {
    case noPermission
    case engineFailedToStart
    case interrupted
    case maxDurationReached
}

protocol AudioRecording: AnyObject {
    var state: AudioRecorderState { get }
    func start() throws
    func stop() async -> [Float]
}
```

### Step 2: 测试

`MouthpieceTests/AudioRecorderTests.swift`:
```swift
import XCTest
@testable import Mouthpiece

final class AudioRecorderTests: XCTestCase {

    final class MockRecorder: AudioRecording {
        var state: AudioRecorderState = .idle
        var samplesToReturn: [Float] = []

        func start() throws { state = .recording(elapsed: 0) }
        func stop() async -> [Float] {
            state = .finished(samples: samplesToReturn, sampleRate: 16000)
            return samplesToReturn
        }
    }

    func testInitialState() {
        let r: AudioRecording = MockRecorder()
        XCTAssertEqual(r.state, .idle)
    }

    func testStartChangesState() throws {
        let r = MockRecorder()
        try r.start()
        if case .recording = r.state {} else { XCTFail("expected recording") }
    }

    func testStopReturnsSamples() async {
        let r = MockRecorder()
        r.samplesToReturn = Array(repeating: Float(0.1), count: 16000)
        try? r.start()
        let s = await r.stop()
        XCTAssertEqual(s.count, 16000)
    }
}
```

### Step 3: 实现

`Core/Audio/AudioRecorder.swift`:
```swift
import AVFoundation
import Observation

@Observable
final class AudioRecorder: AudioRecording {

    private(set) var state: AudioRecorderState = .idle

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var sampleBuffer: [Float] = []
    private var startTime: Date?
    private var timer: Timer?

    static let targetSampleRate: Double = 16000
    static let maxDuration: TimeInterval = 600  // 10 分钟

    func start() throws {
        guard case .idle = state else { return }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.engineFailedToStart
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer: buffer, targetFormat: targetFormat)
        }

        sampleBuffer.removeAll(keepingCapacity: true)
        startTime = Date()

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecorderError.engineFailedToStart
        }

        state = .recording(elapsed: 0)
        startTimer()
    }

    func stop() async -> [Float] {
        timer?.invalidate(); timer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let samples = sampleBuffer
        state = .finished(samples: samples, sampleRate: Self.targetSampleRate)
        return samples
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickElapsed()
        }
    }

    private func tickElapsed() {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        state = .recording(elapsed: elapsed)
        if elapsed >= Self.maxDuration {
            Task { _ = await self.stop() }
            state = .failed(.maxDurationReached)
        }
    }

    private func append(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter else { return }
        let outBuf = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        )!
        var err: NSError?
        var consumed = false
        converter.convert(to: outBuf, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, let data = outBuf.floatChannelData?[0] else { return }
        let frames = Int(outBuf.frameLength)
        sampleBuffer.append(contentsOf: UnsafeBufferPointer(start: data, count: frames))
    }
}
```

### Step 4: Commit
```bash
git commit -m "feat: 16kHz mono audio recorder via AVAudioEngine"
```

### 验收标准
- [ ] 3 个单测通过
- [ ] 手动测试：在 Xcode 跑一次 start/stop，检查 `samples.count > 0` 且 ≈ 录音时长 × 16000

---

## P0-05: WhisperKit 集成 + 中文 medium 模型

**估时**: 6h | **依赖**: P0-04

**Files:**
- Create: `Core/Transcription/Transcribing.swift`
- Create: `Core/Transcription/WhisperKitTranscriber.swift`
- Create: `Core/Transcription/ModelDownloadService.swift`
- Create: `MouthpieceTests/TranscribingTests.swift`

### Step 1: 加 Swift Package 依赖

Xcode → File → Add Package Dependencies → `https://github.com/argmaxinc/WhisperKit` → 选 `Up to next major: 0.7.0`。Add to Target: Mouthpiece。

### Step 2: 协议

`Core/Transcription/Transcribing.swift`:
```swift
import Foundation

struct TranscriptionResult: Equatable {
    let text: String
    let language: String
    let segments: [Segment]
    let durationSeconds: Double

    struct Segment: Equatable {
        let start: Double
        let end: Double
        let text: String
    }
}

enum TranscriptionError: Error, Equatable {
    case modelNotReady
    case modelDownloadFailed(String)
    case transcribeFailed(String)
}

protocol Transcribing: AnyObject {
    var isReady: Bool { get }
    func loadModel() async throws
    func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult
}
```

### Step 3: 测试

```swift
import XCTest
@testable import Mouthpiece

final class TranscribingTests: XCTestCase {

    final class MockTranscriber: Transcribing {
        var isReady: Bool = false
        var loadCalled = false
        var resultToReturn: TranscriptionResult?
        var errorToThrow: TranscriptionError?

        func loadModel() async throws {
            loadCalled = true
            isReady = true
        }

        func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
            if let err = errorToThrow { throw err }
            return resultToReturn ?? TranscriptionResult(text: "", language: "zh", segments: [], durationSeconds: 0)
        }
    }

    func testTranscribeReturnsResult() async throws {
        let t = MockTranscriber()
        t.resultToReturn = TranscriptionResult(text: "你好世界", language: "zh", segments: [], durationSeconds: 1.0)
        let r = try await t.transcribe(samples: [0,0,0], language: "zh")
        XCTAssertEqual(r.text, "你好世界")
    }

    func testTranscribeThrows() async {
        let t = MockTranscriber()
        t.errorToThrow = .modelNotReady
        do {
            _ = try await t.transcribe(samples: [], language: nil)
            XCTFail("expected throw")
        } catch let e as TranscriptionError {
            XCTAssertEqual(e, .modelNotReady)
        } catch { XCTFail("wrong error") }
    }
}
```

### Step 4: 实现 WhisperKit 包装

`Core/Transcription/WhisperKitTranscriber.swift`:
```swift
import Foundation
import WhisperKit

actor WhisperKitTranscriber: Transcribing {

    private var pipe: WhisperKit?
    private(set) var isReady: Bool = false
    let modelName: String

    init(modelName: String = "openai_whisper-medium") {
        self.modelName = modelName
    }

    func loadModel() async throws {
        do {
            pipe = try await WhisperKit(model: modelName)
            isReady = true
        } catch {
            throw TranscriptionError.modelDownloadFailed(String(describing: error))
        }
    }

    func transcribe(samples: [Float], language: String?) async throws -> TranscriptionResult {
        guard let pipe else { throw TranscriptionError.modelNotReady }
        do {
            let results = try await pipe.transcribe(
                audioArray: samples,
                decodeOptions: DecodingOptions(
                    language: language,
                    detectLanguage: language == nil,
                    skipSpecialTokens: true,
                    withoutTimestamps: false
                )
            )
            let text = results.map(\.text).joined()
            let lang = results.first?.language ?? language ?? "zh"
            let segs = results.flatMap { r in
                r.segments.map { TranscriptionResult.Segment(start: Double($0.start), end: Double($0.end), text: $0.text) }
            }
            return TranscriptionResult(
                text: text,
                language: lang,
                segments: segs,
                durationSeconds: Double(samples.count) / 16000.0
            )
        } catch {
            throw TranscriptionError.transcribeFailed(String(describing: error))
        }
    }
}
```

> 注意：WhisperKit API 在 0.7.x 版本会有微调，写代码时按当时 WhisperKit 文档对齐。

### Step 5: 模型下载进度服务（首次启动用）

`Core/Transcription/ModelDownloadService.swift`:
```swift
import Foundation
import WhisperKit
import Observation

@Observable
final class ModelDownloadService {
    enum Status: Equatable {
        case idle
        case downloading(progress: Double)
        case ready
        case failed(String)
    }

    private(set) var status: Status = .idle
    let modelName: String

    init(modelName: String) { self.modelName = modelName }

    func ensureModel() async {
        status = .downloading(progress: 0)
        do {
            // WhisperKit 的 download 自带进度，需要订阅 progress
            let folder = try await WhisperKit.download(variant: modelName, downloadBase: nil)
            _ = folder
            status = .ready
        } catch {
            status = .failed(String(describing: error))
        }
    }
}
```

### Step 6: Commit
```bash
git commit -m "feat: WhisperKit integration with model download flow"
```

### 验收标准
- [ ] 2 个单测通过
- [ ] 第一次跑 App 会下载 medium 模型（~800MB），需联网
- [ ] 跑通后调一次 transcribe，输入 P0-04 录的样本，看到中文输出

---

## P0-06: 录音浮条窗口（屏幕底部居中，4 态）

**估时**: 5h | **依赖**: P0-03, P0-04

**Files:**
- Create: `UI/FloatingBar/FloatingBarState.swift`
- Create: `UI/FloatingBar/FloatingBarWindow.swift`
- Create: `UI/FloatingBar/FloatingBarView.swift`
- Create: `MouthpieceTests/FloatingBarStateTests.swift`

### Step 1: 状态机

`UI/FloatingBar/FloatingBarState.swift`:
```swift
import Foundation
import Observation

enum FloatingBarKind: Equatable {
    case idle
    case recording(elapsed: TimeInterval, levels: [Float])
    case processing
    case done(chars: Int)
    case error(String)
}

@Observable
final class FloatingBarState {
    var kind: FloatingBarKind = .idle

    func startRecording() {
        kind = .recording(elapsed: 0, levels: [])
    }
    func updateRecording(elapsed: TimeInterval, levels: [Float]) {
        if case .recording = kind {
            kind = .recording(elapsed: elapsed, levels: levels)
        }
    }
    func setProcessing() { kind = .processing }
    func setDone(chars: Int) {
        kind = .done(chars: chars)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            if case .done = kind { kind = .idle }
        }
    }
    func setError(_ msg: String) {
        kind = .error(msg)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if case .error = kind { kind = .idle }
        }
    }
}
```

### Step 2: 测试

```swift
import XCTest
@testable import Mouthpiece

final class FloatingBarStateTests: XCTestCase {
    func testStartRecording() {
        let s = FloatingBarState()
        s.startRecording()
        if case .recording(let elapsed, _) = s.kind {
            XCTAssertEqual(elapsed, 0)
        } else { XCTFail() }
    }
    func testProcessing() {
        let s = FloatingBarState()
        s.setProcessing()
        XCTAssertEqual(s.kind, .processing)
    }
    func testDoneAutoDismiss() async {
        let s = FloatingBarState()
        s.setDone(chars: 42)
        XCTAssertEqual(s.kind, .done(chars: 42))
        try? await Task.sleep(for: .milliseconds(1700))
        XCTAssertEqual(s.kind, .idle)
    }
}
```

### Step 3: 实现 SwiftUI 视图

`UI/FloatingBar/FloatingBarView.swift`:
```swift
import SwiftUI

struct FloatingBarView: View {
    let state: FloatingBarState

    var body: some View {
        Group {
            switch state.kind {
            case .idle: EmptyView()
            case .recording(let elapsed, let levels): recording(elapsed: elapsed, levels: levels)
            case .processing: processing
            case .done(let n): done(n)
            case .error(let msg): errorPill(msg)
            }
        }
        .animation(.snappy(duration: 0.2), value: state.kind)
    }

    @ViewBuilder
    private func recording(elapsed: TimeInterval, levels: [Float]) -> some View {
        pill {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text("听着呢")
            waveform(levels)
            timer(elapsed)
        }
    }

    private var processing: some View {
        pill {
            ProgressView().controlSize(.small)
            Text("润色中…")
        }
    }

    private func done(_ n: Int) -> some View {
        pill {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("已粘贴 \(n) 字")
        }
    }

    private func errorPill(_ msg: String) -> some View {
        pill {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(msg)
        }
    }

    private func waveform(_ levels: [Float]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array((levels.suffix(12)).enumerated()), id: \.offset) { _, v in
                Capsule()
                    .fill(.white)
                    .frame(width: 2, height: max(4, CGFloat(v) * 16))
            }
        }
        .frame(width: 36)
    }

    private func timer(_ elapsed: TimeInterval) -> some View {
        let mm = Int(elapsed) / 60
        let ss = Int(elapsed) % 60
        return Text(String(format: "%d:%02d", mm, ss))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func pill<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) { content() }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.85), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}
```

### Step 4: NSWindow 容器（不接受鼠标、置顶、跨 Desktop）

`UI/FloatingBar/FloatingBarWindow.swift`:
```swift
import AppKit
import SwiftUI

final class FloatingBarWindow: NSWindow {
    let state = FloatingBarState()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        hasShadow = false

        contentView = NSHostingView(rootView: FloatingBarView(state: state))
        repositionToBottomCenter()

        NotificationCenter.default.addObserver(self, selector: #selector(repositionToBottomCenter),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc func repositionToBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let w: CGFloat = 220, h: CGFloat = 44
        let x = f.midX - w / 2
        let y = f.minY + 32
        setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    func showIfNeeded() {
        if !isVisible { orderFrontRegardless() }
    }
}
```

### Step 5: Commit
```bash
git commit -m "feat: floating bar window with 4-state pill UI"
```

### 验收标准
- [ ] 3 个单测通过
- [ ] 手动调 `state.startRecording()` 屏幕底部出现黑色 pill
- [ ] `state.setDone(...)` 后 1.5 秒自动消失

---


## P0-07: TextCleaner（正则清洗）

**估时**: 3h | **依赖**: P0-05

**Files:**
- Create: `Core/Cleaning/TextCleaner.swift`
- Create: `Core/Cleaning/CleanOptions.swift`
- Create: `MouthpieceTests/TextCleanerTests.swift`

### Step 1: 配置类型

`Core/Cleaning/CleanOptions.swift`:
```swift
import Foundation

struct CleanOptions: Codable {
    var removeFillers: Bool = true
    var removeRepetition: Bool = true
    var normalizeSpaces: Bool = true
    var customFillers: [String] = []

    static let `default` = CleanOptions()
    static let zhFillers = ["嗯", "啊", "呃", "那个", "就是", "然后", "这个", "其实", "比如说"]
    static let enFillers = ["um", "uh", "you know", "like", "i mean", "basically"]
}
```

### Step 2: 测试驱动

`MouthpieceTests/TextCleanerTests.swift`:
```swift
import XCTest
@testable import Mouthpiece

final class TextCleanerTests: XCTestCase {
    let cleaner = TextCleaner()
    var opts: CleanOptions { .default }

    func testRemoveChineseFillers() {
        XCTAssertEqual(
            cleaner.clean("嗯，那个，我想说就是今天天气不错", options: opts),
            "我想说今天天气不错"
        )
    }

    func testRemoveEnglishFillers() {
        XCTAssertEqual(
            cleaner.clean("um, I think you know, this is great", options: opts),
            "I think this is great"
        )
    }

    func testRemoveRepetition() {
        XCTAssertEqual(
            cleaner.clean("我我我想说说说这个", options: opts),
            "我想说这个"
        )
    }

    func testNormalizeSpaces() {
        XCTAssertEqual(
            cleaner.clean("hello   world  !", options: opts),
            "hello world !"
        )
    }

    func testKeepMeaningfulContent() {
        XCTAssertEqual(
            cleaner.clean("我们今天讨论 AI 的未来", options: opts),
            "我们今天讨论 AI 的未来"
        )
    }

    func testEmpty() {
        XCTAssertEqual(cleaner.clean("", options: opts), "")
    }

    func testAllOptionsOff() {
        var o = opts
        o.removeFillers = false
        o.removeRepetition = false
        o.normalizeSpaces = false
        XCTAssertEqual(cleaner.clean("嗯 嗯  嗯", options: o), "嗯 嗯  嗯")
    }
}
```

### Step 3: 实现

`Core/Cleaning/TextCleaner.swift`:
```swift
import Foundation

struct TextCleaner {

    func clean(_ text: String, options: CleanOptions) -> String {
        var s = text
        if options.removeFillers {
            s = removeFillers(s, list: CleanOptions.zhFillers + CleanOptions.enFillers + options.customFillers)
        }
        if options.removeRepetition {
            s = removeRepetition(s)
        }
        if options.normalizeSpaces {
            s = normalizeSpaces(s)
        }
        return s
    }

    private func removeFillers(_ text: String, list: [String]) -> String {
        var s = text
        for w in list {
            // 按词边界匹配中文不容易，用直接替换 + 周围的标点 / 空格清理
            let patterns: [String]
            if w.unicodeScalars.allSatisfy({ $0.isASCII }) {
                // 英文：词边界 + 大小写不敏感
                patterns = ["(?i)\\b\(NSRegularExpression.escapedPattern(for: w))\\b\\s*,?\\s*"]
            } else {
                // 中文：直接匹配 + 可选标点
                patterns = ["\(NSRegularExpression.escapedPattern(for: w))[，,。!?]?"]
            }
            for p in patterns {
                s = s.replacingOccurrences(of: p, with: "", options: .regularExpression)
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private func removeRepetition(_ text: String) -> String {
        // 1) 重复单字（中文）：(\X)\1{1,} → \1
        var s = text.replacingOccurrences(of: "(.)\\1{1,}", with: "$1", options: .regularExpression)
        // 2) 重复短词（中文 2-3 字）：(..) 立即重复 2+ 次 → 一次
        s = s.replacingOccurrences(of: "(..)\\1{1,}", with: "$1", options: .regularExpression)
        // 3) 英文重复单词
        s = s.replacingOccurrences(of: "(?i)\\b(\\w+)(\\s+\\1\\b){1,}", with: "$1", options: .regularExpression)
        return s
    }

    private func normalizeSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ([，。,!?])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

> 注意：中文去填充词容易"误杀"——比如"那个文件"里的"那个"是合理用词。第一版接受这个偏差，给用户在设置里关掉的选项，后面 P1-02 用 LLM 润色会更准。

### Step 4: Commit
```bash
git commit -m "feat: regex-based text cleaner"
```

### 验收标准
- [ ] 7 个测试通过
- [ ] 手动测试若干句子，输出看起来"清爽"

---

## P0-08: TextInjector（Cmd+V 模拟粘贴）

**估时**: 3h | **依赖**: P0-07

**Files:**
- Create: `Core/Injection/TextInjector.swift`
- Create: `Core/Injection/TextInjectingProtocol.swift`
- Create: `MouthpieceTests/TextInjectorTests.swift`

### 关键技术点
- 通过剪贴板中转：保存旧剪贴板 → 写入新文字 → 发 Cmd+V → 还原旧剪贴板
- 要 Accessibility 权限才能 post CGEvent
- 还原要延迟 100ms 否则粘贴的可能是旧的
- 中文 IME 状态下 Cmd+V 也能正常粘贴（不走 input method）

### Step 1: 协议

```swift
import Foundation

enum InjectionError: Error, Equatable {
    case noAccessibilityPermission
    case clipboardWriteFailed
}

protocol TextInjecting: AnyObject {
    func inject(_ text: String) async throws
}
```

### Step 2: 测试（mock pasteboard + event poster）

```swift
import XCTest
@testable import Mouthpiece

final class TextInjectorTests: XCTestCase {

    final class MockInjector: TextInjecting {
        var injected: [String] = []
        var errorToThrow: InjectionError?
        func inject(_ text: String) async throws {
            if let e = errorToThrow { throw e }
            injected.append(text)
        }
    }

    func testInjectRecordsText() async throws {
        let i = MockInjector()
        try await i.inject("hello")
        XCTAssertEqual(i.injected, ["hello"])
    }
}
```

### Step 3: 实现

`Core/Injection/TextInjector.swift`:
```swift
import AppKit
import CoreGraphics

final class TextInjector: TextInjecting {

    func inject(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw InjectionError.noAccessibilityPermission
        }

        let pasteboard = NSPasteboard.general
        // Save current
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types {
                if let d = item.data(forType: t) { dict[t] = d }
            }
            return dict
        }

        // Write new text
        pasteboard.clearContents()
        let ok = pasteboard.setString(text, forType: .string)
        guard ok else { throw InjectionError.clipboardWriteFailed }

        // Post Cmd+V
        try await postCmdV()

        // Wait for paste to complete
        try? await Task.sleep(for: .milliseconds(120))

        // Restore
        if let saved = savedItems {
            pasteboard.clearContents()
            for dict in saved {
                let item = NSPasteboardItem()
                for (type, data) in dict {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
    }

    private func postCmdV() async throws {
        let src = CGEventSource(stateID: .hidSystemState)
        // V keycode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
```

### Step 4: Commit
```bash
git commit -m "feat: text injection via clipboard + Cmd+V simulation"
```

### 验收标准
- [ ] 1 个 mock 单测通过
- [ ] 手动测试：跑 App → 在 Cursor / TextEdit 里点光标 → 调 `injector.inject("测试文字")` → 看到文字出现且原剪贴板内容被还原

---

## P0-09: Pipeline 编排（AppCoordinator）

**估时**: 4h | **依赖**: P0-03, P0-04, P0-05, P0-07, P0-08

**Files:**
- Create: `App/AppCoordinator.swift`
- Create: `MouthpieceTests/AppCoordinatorTests.swift`

### 状态机

```
idle
  └─[Fn pressed]→ recording
                    └─[Fn released]→ transcribing
                                       └─[whisper done]→ cleaning
                                                          └─[clean done]→ injecting
                                                                           └─[inject done]→ savingToHistory
                                                                                              └─[done]→ idle
  └─[error 任何阶段]→ error → idle
```

### Step 1: 实现

`App/AppCoordinator.swift`:
```swift
import Foundation
import Observation

@MainActor
@Observable
final class AppCoordinator {

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case cleaning
        case injecting
        case done(chars: Int)
        case error(String)
    }

    private(set) var phase: Phase = .idle

    let permission: PermissionService
    let hotkey: HotKeyManager
    let recorder: AudioRecording
    let transcriber: Transcribing
    let cleaner: TextCleaner
    let injector: TextInjecting
    let floatingBar: FloatingBarState
    let history: HistoryStore   // P0-10 引入，先 stub

    var cleanOptions: CleanOptions = .default

    init(permission: PermissionService,
         hotkey: HotKeyManager,
         recorder: AudioRecording,
         transcriber: Transcribing,
         cleaner: TextCleaner,
         injector: TextInjecting,
         floatingBar: FloatingBarState,
         history: HistoryStore) {
        self.permission = permission
        self.hotkey = hotkey
        self.recorder = recorder
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.injector = injector
        self.floatingBar = floatingBar
        self.history = history
    }

    func wire() {
        // 把 hotkey 的回调指到自己的 handle
        // 实际 HotKeyManager 的 init 接受闭包，这里需要重构成支持 set 闭包
    }

    func handleHotkey(_ ev: HotKeyEvent) {
        switch ev {
        case .pressed:
            Task { await startRecording() }
        case .released:
            Task { await finishRecording() }
        }
    }

    private func startRecording() async {
        guard phase == .idle else { return }
        guard transcriber.isReady else {
            phase = .error("模型还没准备好")
            floatingBar.setError("模型还没准备好")
            return
        }
        do {
            try recorder.start()
            phase = .recording
            floatingBar.startRecording()
        } catch {
            phase = .error("\(error)")
            floatingBar.setError("\(error)")
        }
    }

    private func finishRecording() async {
        guard phase == .recording else { return }
        let samples = await recorder.stop()
        phase = .transcribing
        floatingBar.setProcessing()

        do {
            let result = try await transcriber.transcribe(samples: samples, language: nil)
            phase = .cleaning
            let cleaned = cleaner.clean(result.text, options: cleanOptions)

            phase = .injecting
            try await injector.inject(cleaned)

            // 历史
            await history.save(.init(
                timestamp: Date(),
                rawText: result.text,
                cleanedText: cleaned,
                language: result.language,
                durationSeconds: result.durationSeconds,
                appName: NSWorkspace.shared.frontmostApplication?.localizedName
            ))

            phase = .done(chars: cleaned.count)
            floatingBar.setDone(chars: cleaned.count)
            await reset()
        } catch {
            phase = .error("\(error)")
            floatingBar.setError("\(error)")
            await reset()
        }
    }

    private func reset() async {
        try? await Task.sleep(for: .milliseconds(1600))
        phase = .idle
    }
}
```

### Step 2: 测试

测试状态机本身——用 mock 服务跑一遍完整流程，断言 phase 序列。略，类似前面任务。

### Step 3: Commit
```bash
git commit -m "feat: app coordinator wiring hotkey to inject pipeline"
```

### 验收标准
- [ ] 状态序列测试通过
- [ ] 端到端：按 Fn → 说话 → 松开 → 听到 Whisper 跑 → 看到文字粘贴到当前光标

---


## P0-10: HistoryStore（SwiftData）

**估时**: 4h | **依赖**: P0-09

**Files:**
- Create: `Core/Storage/Models/TranscriptionEntry.swift`
- Create: `Core/Storage/HistoryStore.swift`
- Create: `MouthpieceTests/HistoryStoreTests.swift`

### Step 1: 数据模型

```swift
import Foundation
import SwiftData

@Model
final class TranscriptionEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var rawText: String
    var cleanedText: String
    var language: String
    var durationSeconds: Double
    var appName: String?

    init(id: UUID = UUID(), timestamp: Date, rawText: String, cleanedText: String,
         language: String, durationSeconds: Double, appName: String?) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.language = language
        self.durationSeconds = durationSeconds
        self.appName = appName
    }
}

struct TranscriptionEntryDraft {
    let timestamp: Date
    let rawText: String
    let cleanedText: String
    let language: String
    let durationSeconds: Double
    let appName: String?
}
```

### Step 2: HistoryStore actor

```swift
import Foundation
import SwiftData

actor HistoryStore {

    private let container: ModelContainer

    init(inMemory: Bool = false) throws {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        self.container = try ModelContainer(for: TranscriptionEntry.self, configurations: cfg)
    }

    @MainActor
    private var context: ModelContext { container.mainContext }

    @MainActor
    func save(_ draft: TranscriptionEntryDraft) {
        let entry = TranscriptionEntry(
            timestamp: draft.timestamp,
            rawText: draft.rawText,
            cleanedText: draft.cleanedText,
            language: draft.language,
            durationSeconds: draft.durationSeconds,
            appName: draft.appName
        )
        context.insert(entry)
        try? context.save()
    }

    @MainActor
    func fetchRecent(limit: Int = 50) -> [TranscriptionEntry] {
        var desc = FetchDescriptor<TranscriptionEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        desc.fetchLimit = limit
        return (try? context.fetch(desc)) ?? []
    }

    @MainActor
    func delete(id: UUID) {
        let pred = #Predicate<TranscriptionEntry> { $0.id == id }
        let desc = FetchDescriptor<TranscriptionEntry>(predicate: pred)
        if let entry = (try? context.fetch(desc))?.first {
            context.delete(entry)
            try? context.save()
        }
    }

    @MainActor
    func purgeOlderThan(_ date: Date) {
        let pred = #Predicate<TranscriptionEntry> { $0.timestamp < date }
        let desc = FetchDescriptor<TranscriptionEntry>(predicate: pred)
        for entry in (try? context.fetch(desc)) ?? [] {
            context.delete(entry)
        }
        try? context.save()
    }
}
```

### Step 3: 测试

```swift
import XCTest
@testable import Mouthpiece

@MainActor
final class HistoryStoreTests: XCTestCase {
    var store: HistoryStore!

    override func setUp() async throws {
        store = try HistoryStore(inMemory: true)
    }

    func testSaveAndFetch() async {
        await store.save(.init(timestamp: Date(), rawText: "嗯你好", cleanedText: "你好",
                               language: "zh", durationSeconds: 1.2, appName: "Test"))
        let items = await store.fetchRecent(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.cleanedText, "你好")
    }

    func testPurge() async {
        let old = Date(timeIntervalSinceNow: -86400 * 40)
        let recent = Date()
        await store.save(.init(timestamp: old, rawText: "old", cleanedText: "old", language: "zh", durationSeconds: 1, appName: nil))
        await store.save(.init(timestamp: recent, rawText: "new", cleanedText: "new", language: "zh", durationSeconds: 1, appName: nil))
        await store.purgeOlderThan(Date(timeIntervalSinceNow: -86400 * 30))
        let items = await store.fetchRecent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.cleanedText, "new")
    }
}
```

### Step 4: Commit
```bash
git commit -m "feat: history store with SwiftData persistence"
```

### 验收标准
- [ ] 2 个测试通过
- [ ] App 重启后历史还在

---

## P0-11: 菜单栏图标 + 弹出菜单

**估时**: 4h | **依赖**: P0-10

**Files:**
- Create: `UI/MenuBar/MenuBarView.swift`
- Modify: `Mouthpiece/App/MouthpieceApp.swift`
- Create: `Resources/Assets.xcassets/MouthIcon.imageset/` (PDF/SVG 嘴形图标)

### 嘴形图标说明

需要做一个**单色 PDF 矢量**作为 menu bar template image：
- 16×16 / 32×32 / 24×24 三个 size
- 纯黑色填充
- 形状：一个简化的嘴（两条弧线构成一个张开的嘴）

设计建议（你或我用 Figma 画一下，导出 SVG/PDF）：
```
    .--.
   ( oo )
    `--'
```
简化版本就是两条曲线：上唇 + 下唇。

或先用 SF Symbol `mouth.fill` 凑合，等 P1 再换自定义。

### Step 1: 菜单栏视图

```swift
import SwiftUI

struct MenuBarView: View {
    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow
            Divider()
            recentRow
            Divider()
            Button("打开主窗口") { openMainWindow() }
            Button("设置…") { openSettings() }
            Divider()
            Button("退出 Mouthpiece") { NSApp.terminate(nil) }
        }
    }

    private var statusRow: some View {
        HStack {
            Circle()
                .fill(coordinator.phase == .idle ? .gray : .green)
                .frame(width: 8, height: 8)
            Text(statusText)
            Spacer()
            Text("按住 Fn")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.top, 4)
    }

    private var statusText: String {
        switch coordinator.phase {
        case .idle: return "待机"
        case .recording: return "录音中"
        case .transcribing: return "识别中"
        case .cleaning: return "整理中"
        case .injecting: return "粘贴中"
        case .done: return "已完成"
        case .error: return "出错了"
        }
    }

    @ViewBuilder
    private var recentRow: some View {
        let recent = coordinator.recentEntries.prefix(3)
        if recent.isEmpty {
            Text("还没识别过任何内容").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
        } else {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, e in
                Button(action: { copyToClipboard(e.cleanedText) }) {
                    Text(e.cleanedText.prefix(40))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private func openMainWindow() { /* 由 MouthpieceApp 注入 */ }
    private func openSettings() { /* 同上 */ }
    private func copyToClipboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
```

### Step 2: 接入 MouthpieceApp

```swift
@main
struct MouthpieceApp: App {
    @State private var coordinator = makeCoordinator()

    var body: some Scene {
        MenuBarExtra("Mouthpiece", image: "MouthIcon") {
            MenuBarView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.menu)

        // 主窗口
        WindowGroup("Mouthpiece", id: "main") {
            MainWindow(coordinator: coordinator)
        }

        // 设置
        Settings {
            SettingsWindow(coordinator: coordinator)
        }
    }

    static func makeCoordinator() -> AppCoordinator {
        // 装配所有 service
        // 略 ...
    }
}
```

### Step 3: Commit
```bash
git commit -m "feat: menubar icon with status + recent + nav"
```

### 验收标准
- [ ] 菜单栏出现嘴形图标
- [ ] 点击图标弹出菜单，看到状态/最近识别/打开主窗口/设置/退出
- [ ] 最近识别记录可点击复制

---

## P0-12: 主窗口首页 + 数据卡片

**估时**: 6h | **依赖**: P0-10

**Files:**
- Create: `UI/MainWindow/MainWindow.swift`
- Create: `UI/MainWindow/Sidebar.swift`
- Create: `UI/MainWindow/HomeView.swift`
- Create: `UI/MainWindow/StatCard.swift`

### Step 1: 主窗口骨架

```swift
import SwiftUI

struct MainWindow: View {
    let coordinator: AppCoordinator
    @State private var selectedTab: SidebarItem = .home

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selectedTab)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            switch selectedTab {
            case .home:       HomeView(coordinator: coordinator)
            case .history:    HistoryView(coordinator: coordinator)
            case .dictionary: DictionaryView(coordinator: coordinator)
            }
        }
        .frame(minWidth: 800, minHeight: 560)
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, history, dictionary
    var id: String { rawValue }
    var label: String { ["home": "首页", "history": "历史记录", "dictionary": "词典"][rawValue]! }
    var icon: String { ["home": "house", "history": "clock", "dictionary": "book"][rawValue]! }
}

struct Sidebar: View {
    @Binding var selection: SidebarItem
    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.label, systemImage: item.icon).tag(item)
        }
        .listStyle(.sidebar)
    }
}
```

### Step 2: 首页视图

```swift
struct HomeView: View {
    let coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statsRow
                recentSection
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("自然说话，完美书写 — 在任何应用中")
                .font(.title2).bold()
            Text("按住 Fn 开始和停止语音输入。")
                .foregroundStyle(.secondary)
        }
    }

    private var statsRow: some View {
        let stats = coordinator.computeStats()
        return HStack(spacing: 14) {
            StatCard(label: "节省时间", value: stats.timeSavedDisplay, icon: "clock")
            StatCard(label: "口述字数", value: "\(stats.totalChars)", icon: "doc.text")
            StatCard(label: "速度", value: "\(stats.wpm) 字/分", icon: "speedometer")
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近识别").font(.headline)
            ForEach(coordinator.recentEntries.prefix(5)) { entry in
                RecentRow(entry: entry)
            }
        }
    }
}

struct StatCard: View {
    let label: String, value: String, icon: String
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title2).bold()
            }
            Spacer()
            Image(systemName: icon).foregroundStyle(.secondary).font(.title)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

### Step 3: Commit
```bash
git commit -m "feat: main window with sidebar and home view"
```

### 验收标准
- [ ] 双击 Dock（或菜单栏点"打开主窗口"）能看到主窗口
- [ ] sidebar 切换三个 tab
- [ ] 首页能看到 3 个数据卡片

---


## P0-13: 历史记录页 + 词典页（基础版）

**估时**: 5h | **依赖**: P0-10

**Files:**
- Create: `UI/MainWindow/HistoryView.swift`
- Create: `UI/MainWindow/DictionaryView.swift`
- Create: `Core/Storage/Models/DictionaryWord.swift`
- Create: `Core/Storage/DictionaryStore.swift`

### Step 1: 历史记录视图

```swift
import SwiftUI

struct HistoryView: View {
    let coordinator: AppCoordinator
    @State private var search: String = ""
    @State private var selectedEntry: TranscriptionEntry?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            HSplitView {
                list
                detail
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索…", text: $search)
                .textFieldStyle(.plain)
        }
        .padding(12)
    }

    private var list: some View {
        let entries = coordinator.searchHistory(query: search)
        return List(entries, selection: $selectedEntry) { entry in
            VStack(alignment: .leading) {
                Text(entry.cleanedText).lineLimit(2)
                HStack {
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
                    Text(entry.appName ?? "")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .tag(entry as TranscriptionEntry?)
        }
        .frame(minWidth: 280)
    }

    @ViewBuilder
    private var detail: some View {
        if let e = selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Section { Text(e.cleanedText) } header: { Text("清洗后").font(.headline) }
                    Section { Text(e.rawText) } header: { Text("原始识别").font(.headline) }
                    HStack {
                        Button("复制清洗结果") { copy(e.cleanedText) }
                        Button("复制原始") { copy(e.rawText) }
                        Button("删除", role: .destructive) {
                            Task { await coordinator.deleteHistory(id: e.id); selectedEntry = nil }
                        }
                    }
                }.padding(20)
            }
        } else {
            Text("从左侧选择一条记录").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
```

### Step 2: 词典模型 + Store

```swift
import SwiftData

@Model
final class DictionaryWord {
    @Attribute(.unique) var id: UUID
    var word: String
    var pinyin: String?     // 自定义拼音/发音提示
    var note: String?
    var addedAt: Date

    init(word: String, pinyin: String? = nil, note: String? = nil) {
        self.id = UUID()
        self.word = word
        self.pinyin = pinyin
        self.note = note
        self.addedAt = Date()
    }
}

actor DictionaryStore {
    private let container: ModelContainer

    init(inMemory: Bool = false) throws {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: DictionaryWord.self, configurations: cfg)
    }

    @MainActor func add(_ word: String, pinyin: String? = nil, note: String? = nil) {
        let w = DictionaryWord(word: word, pinyin: pinyin, note: note)
        container.mainContext.insert(w)
        try? container.mainContext.save()
    }

    @MainActor func fetchAll() -> [DictionaryWord] {
        let desc = FetchDescriptor<DictionaryWord>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        return (try? container.mainContext.fetch(desc)) ?? []
    }

    @MainActor func delete(_ word: DictionaryWord) {
        container.mainContext.delete(word)
        try? container.mainContext.save()
    }
}
```

### Step 3: 词典视图

```swift
struct DictionaryView: View {
    let coordinator: AppCoordinator
    @State private var newWord = ""
    @State private var newNote = ""

    var body: some View {
        VStack {
            HStack {
                TextField("添加新词…", text: $newWord)
                TextField("备注（可选）", text: $newNote)
                Button("添加") {
                    Task {
                        await coordinator.addDictionaryWord(newWord, note: newNote.isEmpty ? nil : newNote)
                        newWord = ""; newNote = ""
                    }
                }
                .disabled(newWord.isEmpty)
            }
            .padding(12)
            Divider()
            List(coordinator.dictionaryWords) { w in
                HStack {
                    VStack(alignment: .leading) {
                        Text(w.word).bold()
                        if let n = w.note { Text(n).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button(action: { Task { await coordinator.deleteWord(w) }}) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
```

### Step 4: Commit
```bash
git commit -m "feat: history view with search + dictionary CRUD"
```

### 验收标准
- [ ] 历史搜索能过滤
- [ ] 点详情看到原始/清洗对比
- [ ] 词典能添加/删除

---

## P0-14: 设置面板（5 个 tab）

**估时**: 6h | **依赖**: P0-03, P0-07, P0-10

**Files:**
- Create: `UI/Settings/SettingsWindow.swift`
- Create: `UI/Settings/tabs/GeneralTab.swift`
- Create: `UI/Settings/tabs/AudioTab.swift`
- Create: `UI/Settings/tabs/HotkeyTab.swift`
- Create: `UI/Settings/tabs/CleaningTab.swift`
- Create: `UI/Settings/tabs/HistoryTab.swift`

### Step 1: SettingsWindow 入口

```swift
import SwiftUI

struct SettingsWindow: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            GeneralTab(coordinator: coordinator)
                .tabItem { Label("通用", systemImage: "gear") }
            AudioTab(coordinator: coordinator)
                .tabItem { Label("音频", systemImage: "mic") }
            HotkeyTab(coordinator: coordinator)
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            CleaningTab(coordinator: coordinator)
                .tabItem { Label("清洗", systemImage: "wand.and.stars") }
            HistoryTab(coordinator: coordinator)
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 600, height: 420)
        .padding(20)
    }
}
```

### Step 2: 5 个 tab 内容（要点示例，详细按 Form 写）

**GeneralTab**: 开机自启（用 ServiceManagement 框架的 SMAppService.mainApp.register/unregister）、菜单栏图标显示、识别提示音、语言（默认中文）

**AudioTab**: 麦克风设备下拉（用 AVCaptureDevice.devices(for: .audio) 列出）、VAD 灵敏度滑块、音量测试条

**HotkeyTab**: 触发键 segmented picker（Fn / Right Option / F13）、冲突检测提示（如选 Fn 但发现系统有冲突）

**CleaningTab**: 去填充词开关、去重复开关、规范化空格开关、自定义填充词列表（增删）、调用 Claude API 开关 + API key 输入

**HistoryTab**: 保留期下拉（7/30/90 天/永久）、立即清空按钮

GeneralTab 示例：
```swift
struct GeneralTab: View {
    let coordinator: AppCoordinator
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        Form {
            Toggle("登录时自动启动", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in toggleLaunchAtLogin(on) }
            Toggle("显示菜单栏图标", isOn: $showMenuBarIcon)
            Text("Mouthpiece v1.0.0  ·  开源 MIT").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggleLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { print("launch-at-login error:", error) }
    }
}
```

### Step 3: Commit
```bash
git commit -m "feat: settings panel with 5 tabs"
```

### 验收标准
- [ ] 设置窗口能打开
- [ ] 5 个 tab 都有内容
- [ ] 改设置能持久化（AppStorage / UserDefaults）

---

## P0-15: 错误处理 + 边界场景

**估时**: 5h | **依赖**: 全部

**目标**：把所有"用户可能遇到的崩溃和卡顿"覆盖到。

### 必须处理的 13 个边界

| # | 场景 | 处理 |
|---|---|---|
| 1 | 10 分钟录音上限 | recorder 自动停 + 浮条提示"已达 10 分钟" |
| 2 | 9 分钟警告 | 浮条加倒计时提示 |
| 3 | 录音中拔耳机/麦克风 | engine 抛错 → 浮条红 "麦克风丢失" + 已录部分保存到历史 |
| 4 | Whisper 模型还没下载 | 启动时检测，没模型就阻止录音 + 弹窗引导下载 |
| 5 | Whisper 模型下载失败 | 设置面板 → Audio tab 显示状态 + 重试按钮 |
| 6 | 麦克风权限被撤销（运行中） | observer 监听 + 浮条红 + 引导重新授权 |
| 7 | Accessibility 权限被撤销 | inject 时报错 → 浮条红 + 一键跳系统设置 |
| 8 | 网络断（Claude API 用） | LLM 润色 fallback 到 regex 清洗 + 浮条提示"在线润色失败，已用本地清洗" |
| 9 | 同时录音（多次按 Fn） | coordinator 状态机忽略；调试日志 |
| 10 | 识别结果置信度低 | 浮条加问号 + 可选"忽略 / 重试" |
| 11 | 剪贴板还原失败 | 警告日志，不打扰用户 |
| 12 | 主屏切换 | floating bar window 监听 didChangeScreen 重新定位 |
| 13 | 录音中 Mac 休眠 | engine 暂停 → 醒来后重置状态机到 idle |

### Step 1: 在 AppCoordinator 加 watchdog

```swift
extension AppCoordinator {

    func observeSystem() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { _ in /* 设备变化 */ }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // 醒来重置
            Task { @MainActor in self?.resetToIdle() }
        }
    }

    func resetToIdle() {
        phase = .idle
        floatingBar.kind = .idle
    }
}
```

### Step 2: 浮条加 9 分钟警告

在 AudioRecorder 的 tickElapsed 里：
```swift
if elapsed > 540 && elapsed < 543 {
    // 触发一次警告
    NotificationCenter.default.post(name: .recordingApproachingLimit, object: nil)
}
```

AppCoordinator 监听该通知，给 floatingBar 加临时提示。

### Step 3: 模型未下载阻塞

```swift
private func startRecording() async {
    guard transcriber.isReady else {
        await showModelDownloadPrompt()
        return
    }
    // ...
}

private func showModelDownloadPrompt() async {
    // 弹一个 NSAlert：模型未下载，是否现在下载？
}
```

### Step 4: 错误统一上报

```swift
enum MouthpieceError: Error, LocalizedError {
    case noMicrophonePermission
    case noAccessibilityPermission
    case modelNotDownloaded
    case microphoneDisconnected
    case recordingTooLong
    case transcribeFailed(String)
    case injectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noMicrophonePermission: return "请授权麦克风权限"
        case .noAccessibilityPermission: return "请授权辅助功能权限"
        case .modelNotDownloaded: return "Whisper 模型未下载"
        case .microphoneDisconnected: return "麦克风已断开"
        case .recordingTooLong: return "已达 10 分钟录音上限"
        case .transcribeFailed(let m): return "识别失败：\(m)"
        case .injectionFailed(let m): return "粘贴失败：\(m)"
        }
    }
}
```

### Step 5: Commit
```bash
git commit -m "feat: comprehensive error handling and edge cases"
```

### 验收标准
- [ ] 拔耳机录音中：浮条变红，已录内容存到历史
- [ ] 模型未下载时按 Fn：弹窗引导
- [ ] 撤销麦克风权限：下次录音明确提示
- [ ] 撤销 Accessibility 权限：注入失败有明确提示

---


# Part III: P1 任务详细实现（10 个，体验完善）

每个 P1 任务比 P0 简化（只给文件 + 关键步骤 + 验收，详细代码到时实现）。

---

## P1-01: Onboarding 引导（4 步）

**估时**: 5h | **依赖**: P0 完成

**Files:**
- Create: `UI/Onboarding/OnboardingWindow.swift`
- Create: `UI/Onboarding/steps/Step1Welcome.swift`
- Create: `UI/Onboarding/steps/Step2Permissions.swift`
- Create: `UI/Onboarding/steps/Step3Hotkey.swift`
- Create: `UI/Onboarding/steps/Step4TryIt.swift`

**4 步流程**：
1. **欢迎**：品牌介绍 + 隐私承诺（你的录音不离开 Mac）+ "下一步"
2. **权限**：检查麦克风 + Accessibility，未授权按钮跳系统设置
3. **快捷键**：默认 Fn，可改。检测一次按 Fn 看监听是否生效
4. **试录**：让用户说一句话 → 显示识别结果 → "完成"

用 `@AppStorage("hasOnboarded") = false` 触发：app 启动时检查，false 就开 Onboarding。

**验收**：首次启动看到引导，4 步完成后再启动不再显示。

---

## P1-02: LLM 智能润色（Claude API）

**估时**: 5h | **依赖**: P0-07

**Files:**
- Create: `Core/Cleaning/LLMPolisher.swift`
- Create: `Core/Cleaning/AnthropicClient.swift`

**流程**：
- Pipeline 在 TextCleaner 后插一个 LLMPolisher 步骤
- 调 `claude-haiku-4-5`（便宜快）
- prompt：`你是文本润色专家。下面是用户的口述。请：1)去掉自我纠正 2)加合理标点 3)分段。保持原意，不要添加。直接输出润色后文字。\n\n{text}`
- 失败 fallback 到 TextCleaner 结果
- 设置面板可关 + 输入 Anthropic key（存 macOS Keychain）

**验收**：
- 关掉时纯 regex 清洗
- 开启 + 有效 key：句子更顺、有标点
- 网络断了不阻塞，1.5 秒超时 fallback

---

## P1-03: 个人词典识别注入

**估时**: 5h | **依赖**: P0-13

**Files:**
- Modify: `Core/Transcription/WhisperKitTranscriber.swift`

**做法**：
- WhisperKit DecodingOptions 支持 `prompt` 参数：前置一段文字偏置识别
- 把词典里的词拼成 "（请使用这些词：李言, MVS, 京me）" 喂进去
- 测试：故意说一个含专有词的句子，对比开/关词典的识别结果

**验收**：识别"MVS 系统"不会变成"MV 是系统"

---

## P1-04: 中英混合自动保留

**估时**: 4h | **依赖**: P0-05

**Files:**
- Modify: `Core/Transcription/WhisperKitTranscriber.swift`
- Modify: `Core/Cleaning/TextCleaner.swift`

**做法**：
- WhisperKit DecodingOptions `language=nil` + `detectLanguage=true`
- 但 medium 模型混合识别会偶尔把英文翻译成中文。后处理：检测原音频里有 / 没有英文音节，对照转录里有 / 没有英文，不一致就重跑 segment
- 简化版：识别后用正则保护已识别的英文词不被清洗
- 测试 case："我要去开 meeting" → 输出保留 "meeting"

**验收**：英文专有名词原样保留

---

## P1-05: 智能结构化（列表 / 标题）

**估时**: 4h | **依赖**: P0-07

**Files:**
- Modify: `Core/Cleaning/TextCleaner.swift`

**规则**：
- "第一/第二/第三" → `1. ... 2. ... 3. ...`
- "首先...其次...最后" → 同上
- "标题是 XXX，下面三点：..." → `## XXX\n1. ...`
- 单独的"分号"或"句号"明显标记 → 强制断句

**验收**：用一段口述测试，输出是清晰的 Markdown

---

## P1-06: Edit 模式（选中文字 + 说指令）

**估时**: 8h | **依赖**: P0-08, P1-02

**Files:**
- Create: `Core/Injection/SelectedTextReader.swift`
- Modify: `App/AppCoordinator.swift`

**关键**：
- 双击 Fn 进入 Edit 模式（不双击就是普通 Dictate）
- 读取当前选中文字：用 AX API（AXUIElementCopyAttributeValue 取 kAXSelectedTextAttribute）
- 说出"短一点 / 长一点 / 正式一点 / 翻译成英文 / 总结一下"
- 调 Claude API：`prompt + 选中文字 + 用户指令`
- 用 inject 替换选中文字（先 Cmd+A 选中替换，或 Cmd+V 替换选中）

**验收**：选中一段文字，双击 Fn，说"短一点"，文字自动缩短

---

## P1-07: 不同 App 不同语气

**估时**: 5h | **依赖**: P1-02

**Files:**
- Modify: `Core/Cleaning/LLMPolisher.swift`
- Add: `Resources/AppToneMap.json`

**做法**：
- 检测前台 App（NSWorkspace.shared.frontmostApplication）
- 映射到 tone：邮件 App → 正式 / 微信 → 口语化 / Cursor → 代码注释风 / Slack → 简洁
- 在 prompt 里加 "Style: \(tone)"
- 用户在设置里可改映射

**验收**：在邮件 App 录"明天开会" → "您好，明天有会议安排"；在微信录 → "明天开会"

---

## P1-08: 历史保留期 + 自动清理

**估时**: 3h | **依赖**: P0-10

**Files:**
- Modify: `Core/Storage/HistoryStore.swift`
- Modify: `UI/Settings/tabs/HistoryTab.swift`

**做法**：
- 设置里 "保留期: 7 / 30 / 90 天 / 永久"
- App 启动时跑 `purgeOlderThan(Date().addingTimeInterval(-保留期))`
- 每天定时跑一次（用 NSBackgroundActivityScheduler）

**验收**：把保留期设 7 天，伪造一个 8 天前的记录，重启 App，记录消失

---

## P1-09: 翻译模式（双击 Fn）

**估时**: 4h | **依赖**: P1-02

**Files:**
- Modify: `Core/HotKey/HotKeyManager.swift` (加双击检测)
- Modify: `App/AppCoordinator.swift`

**做法**：
- HotKeyManager 检测两次 pressed 间隔 < 400ms = 双击
- 双击 + 录音 → 识别后调 Claude API：`Translate to {目标语言}: {text}`
- 目标语言在设置里配（默认英文）

**验收**：双击 Fn 说"明天开会"，输出 "Meeting tomorrow"

---

## P1-10: 个性化进度 + 统计

**估时**: 4h | **依赖**: P0-10

**Files:**
- Create: `Core/Stats/StatsService.swift`
- Modify: `UI/MainWindow/HomeView.swift`

**指标**：
- 累计字数
- 累计录音时长
- 节省时间（用平均打字速度 60wpm 估算）
- 平均速度（口述速度）
- 个性化进度（用了 N 次，模型对你"熟悉度" %）

**验收**：首页 4 张卡片 + 环形进度

---


# Part IV: 发布流程详细实现

---

## R-01: Developer ID 签名（GitHub 分发版）

**估时**: 2h

**前提**：已注册 Apple Developer 账号（你正在做）

**步骤**：

1. **生成证书**：登录 https://developer.apple.com/account/resources/certificates
   - 点击 "+" → 选 "Developer ID Application"（不是 Mac App Distribution）
   - Xcode 里 Cmd+, → Accounts → 选你的账号 → Manage Certificates → "+" → Developer ID Application
2. **导出证书 .p12**：钥匙串 → 找到证书 → 导出 → 设置密码
3. **本地签名命令**：
```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: <你的名字>" \
  --entitlements Mouthpiece/Mouthpiece.entitlements \
  build/Mouthpiece.app
```
4. **验证**：
```bash
codesign --verify --deep --strict --verbose=2 build/Mouthpiece.app
spctl -a -t exec -vvv build/Mouthpiece.app
```

**验收**：`spctl` 输出 `accepted` + `source=Notarized Developer ID`（公证后）。

---

## R-02: 公证脚本（notarytool）

**估时**: 3h

**步骤**：

1. **创建 App Specific Password**：
   - https://appleid.apple.com → Sign-In and Security → App-Specific Passwords → "+"
   - 名字 `mouthpiece-notarize`，保存密码

2. **保存凭证到 Keychain**：
```bash
xcrun notarytool store-credentials "mouthpiece-notary" \
  --apple-id "your-apple-id@example.com" \
  --team-id "ABCDE12345" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

3. **公证脚本** `scripts/notarize.sh`:
```bash
#!/bin/bash
set -e

APP="build/Mouthpiece.app"
DMG="build/Mouthpiece.dmg"

# 1. 压缩 zip 上传
ZIP="build/Mouthpiece.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

# 2. 提交公证
xcrun notarytool submit "$ZIP" \
  --keychain-profile "mouthpiece-notary" \
  --wait

# 3. 钉装 (stapler)
xcrun stapler staple "$APP"

# 4. 验证
xcrun stapler validate "$APP"

# 5. 打包 DMG
./scripts/build-dmg.sh
xcrun stapler staple "$DMG"

echo "✅ Notarized and stapled."
```

**验收**：公证返回 status=Accepted；stapler validate 通过；下载到别的 Mac 双击能开。

---

## R-03: DMG 打包脚本

**估时**: 2h

**步骤**：

1. **安装 create-dmg**：
```bash
brew install create-dmg
```

2. **脚本** `scripts/build-dmg.sh`:
```bash
#!/bin/bash
set -e

APP="build/Mouthpiece.app"
DMG="build/Mouthpiece.dmg"
TMP_DMG="build/Mouthpiece-tmp.dmg"

rm -f "$DMG" "$TMP_DMG"

create-dmg \
  --volname "Mouthpiece" \
  --volicon "Mouthpiece/Resources/Assets.xcassets/AppIcon.appiconset/icon-512.png" \
  --window-size 540 360 \
  --icon-size 100 \
  --icon "Mouthpiece.app" 130 180 \
  --app-drop-link 410 180 \
  --background "scripts/dmg-bg.png" \
  --no-internet-enable \
  "$DMG" \
  "$APP"

echo "✅ DMG: $DMG"
```

3. **DMG 背景图** `scripts/dmg-bg.png`：540×360px，提示用户拖到 Applications

**验收**：双击 DMG，出现拖拽窗口，拖进 Applications 完成安装。

---

## R-04: GitHub Actions 自动 release

**估时**: 4h

**步骤**：

`.github/workflows/release.yml`：
```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app

      - name: Import certificate
        env:
          CERT_P12_BASE64: ${{ secrets.CERT_P12_BASE64 }}
          CERT_PASSWORD: ${{ secrets.CERT_PASSWORD }}
        run: |
          KEYCHAIN=build.keychain
          security create-keychain -p "" $KEYCHAIN
          security default-keychain -s $KEYCHAIN
          security unlock-keychain -p "" $KEYCHAIN
          echo "$CERT_P12_BASE64" | base64 --decode > /tmp/cert.p12
          security import /tmp/cert.p12 -k $KEYCHAIN -P "$CERT_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" $KEYCHAIN

      - name: Build
        run: |
          xcodebuild -project Mouthpiece.xcodeproj \
            -scheme Mouthpiece \
            -configuration Release \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY="Developer ID Application: ..."

      - name: Notarize
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: ./scripts/notarize.sh

      - name: Create DMG
        run: |
          brew install create-dmg
          ./scripts/build-dmg.sh

      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/Mouthpiece.dmg
          generate_release_notes: true
```

**GitHub Secrets 要配**：
- `CERT_P12_BASE64`：`base64 -i cert.p12 | pbcopy`
- `CERT_PASSWORD`：导出 p12 时设的密码
- `APPLE_ID`、`APPLE_APP_PASSWORD`、`APPLE_TEAM_ID`

**验收**：`git tag v1.0.0 && git push --tags` → GitHub Actions 自动跑 → Release 页面有 DMG 下载。

---

## R-05: App Sandbox 适配（App Store 版）

**估时**: 6h

**关键不同**：
- App Store 版必须开 App Sandbox
- 但开了 Sandbox 后**全局 Hotkey 受限**——这是个矛盾

**解决方案**：
- macOS 14+ 允许有 Accessibility 权限的 sandbox app 注册 global hotkey
- 必须用 `NSEvent.addGlobalMonitorForEvents` 而非旧的 Carbon RegisterEventHotKey
- 在 entitlements 加：
```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.temporary-exception.apple-events</key>
<array>
  <string>com.apple.systemevents</string>
</array>
```

**模型存储**：
- Sandbox 下不能写 `~/Library/Caches/com.mouthpiece.app/`，要写 `Application Support`
- WhisperKit 默认下载路径要改成 sandbox 容器：`~/Library/Containers/com.mouthpiece.app/Data/Library/Application Support/Mouthpiece/Models/`

**验收**：sandbox 开启后所有功能依然正常。

---

## R-06: App Store Connect 元数据

**估时**: 3h

**到 https://appstoreconnect.apple.com 创建 app**：

| 字段 | 内容 |
|---|---|
| App Name | Mouthpiece（不超过 30 字符） |
| Subtitle | 嘴替 — 按住说话，文字自动出现 |
| Category | Productivity |
| Price | Free |
| Bundle ID | com.mouthpiece.app |
| SKU | mouthpiece-v1 |
| Primary Language | Simplified Chinese |
| Keywords | 语音输入, 听写, dictation, voice, whisper, 嘴替, AI |
| Support URL | https://github.com/<你的id>/mouthpiece |
| Privacy Policy URL | https://github.com/<你的id>/mouthpiece/blob/main/PRIVACY.md |

**描述**（中文）：
```
Mouthpiece（嘴替）是一款 macOS 语音输入工具。
按住 Fn 键说话，松开后文字自动出现在你的光标位置。
不管你正在写邮件、聊微信、还是写代码，都能用嘴打字。

✨ 完全本地：基于 OpenAI Whisper，识别全在你的 Mac 上完成
✨ 自动清洗：去掉"嗯/啊/那个"等口头禅
✨ 100+ 语言：支持中英文混合识别
✨ 开源免费：MIT 协议，代码完全开放

适合：
- 不想打字的时候
- 用 Cursor / VSCode 写代码注释
- 用微信/Slack 沟通
- 用 ChatGPT/Claude 输入长 prompt
```

**英文描述**（直译 + 优化，专门给 Apple 审核员看清楚）。

---

## R-07: App Store 截图（5 张）

**估时**: 4h

**要求**：1280×800 或 2560×1600（macOS Catalyst app 用更大）

**5 张推荐**：

| # | 内容 |
|---|---|
| 1 | 主窗口首页 — 标题 + 数据卡片 |
| 2 | 浮条录音中 — 显示在 Cursor 编辑器旁边 |
| 3 | 历史记录页 — 显示原始 / 清洗对比 |
| 4 | 设置面板 — 显示快捷键和清洗选项 |
| 5 | 多场景拼图 — 微信/邮件/Cursor 都能用 |

工具：用 Figma / Sketch 排版，screenshot 加阴影和说明文字。

---

## R-08: 隐私清单 PrivacyManifest

**估时**: 2h

**Files**: `Mouthpiece/PrivacyInfo.xcprivacy`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

**验收**：Xcode 提交时不再警告隐私清单缺失。

---

## R-09: Sparkle 自动更新（GitHub 分发版）

**估时**: 4h

**前提**：用 Sparkle 2 + EdDSA 签名

**步骤**：

1. Xcode 加 Sparkle 包：`https://github.com/sparkle-project/Sparkle`
2. 生成 EdDSA key pair：
```bash
brew install sparkle
generate_keys
```
公钥粘进 Info.plist `SUPublicEDKey`。私钥保密。

3. Info.plist 加：
```xml
<key>SUFeedURL</key>
<string>https://github.com/<你的id>/mouthpiece/releases/latest.xml</string>
<key>SUPublicEDKey</key>
<string>...</string>
```

4. release.yml 加：每次 release 生成 appcast.xml 上传

**验收**：装 v1.0.0 → 发布 v1.0.1 → 重启 App 看到更新提示

---

## R-10: 首次提审 + 反馈整改

**估时**: 8h+（不可预测）

**首次提审常见被拒原因**：

| 原因 | 应对 |
|---|---|
| Guideline 2.1 - 功能不完整/崩溃 | 提交前手动跑一遍所有流程 |
| 2.5.1 使用私有 API | Accessibility 调用要用公共 API（AX*） |
| 3.1.1 应用内购买未用 IAP | 我们暂时全免费，没问题 |
| 5.1.1 隐私 - 数据收集说明缺失 | 隐私清单 + Privacy Policy 网页齐全 |
| 4.0 设计 - 看起来像未完成 | 截图要精美，描述清晰 |
| 4.5.4 PUSH 通知滥用 | 我们不用 push |

**提审流程**：
1. Xcode Archive → Distribute → App Store Connect → Upload
2. App Store Connect 选 build → 填写 "what to test" + 添加 build
3. 提交 review，通常 1-3 天审完
4. 被拒了在 Resolution Center 看原因，整改后 resubmit
5. 通过后 manual release 或 auto release

**给审核员的备注**（很关键）：
```
This is an open-source voice dictation tool. Source code: https://github.com/...

Key features:
1. Press Fn → speak → release Fn → text appears at cursor
2. Uses WhisperKit for on-device speech recognition (no audio leaves device)
3. Uses Accessibility API to inject text at cursor (Cmd+V simulation)

Test instructions:
1. Open Mouthpiece, grant Microphone and Accessibility permissions when prompted
2. Open any text editor (TextEdit recommended)
3. Click in the text area
4. Press and HOLD Fn key, speak a sentence in English or Chinese
5. Release Fn key
6. Within 1-2 seconds, your speech will appear as text at the cursor

If Fn doesn't work, try Right Option key (System Settings → Keyboard).
```

---


# Part V: 计划自检

## 占位符检查
- 个别地方写 "略" 或 "stub"——属于详细 task 时按现有架构补足，不需要文档预先填完
- 字体颜色具体 hex 在 P0-12 段说 "TBD"——开干前一两 commit 内确定

## 类型一致性
- `TranscriptionResult` 在 P0-05 定义，P0-09 用 → ✅
- `FloatingBarState.kind` 4+ 种状态在 P0-06 定义，P0-09/P0-11 用 → ✅
- `CleanOptions` 在 P0-07 定义，AppCoordinator 持有 → ✅
- `HistoryStore` 在 P0-10 引入，但 P0-09 已经用了——**需要 P0-09 实现时先 stub 接口**，P0-10 来实现真接口 → 标注

## 跨任务依赖
依赖图：
```
P0-01 (scaffold)
  ├─ P0-02 (permission) → P0-04
  ├─ P0-03 (hotkey) ────┐
  ├─ P0-04 (audio) ─────┤
  ├─ P0-05 (whisper) ───┤
  │                     │
  ├─ P0-07 (cleaner) ───┤
  ├─ P0-08 (inject) ────┤
  │                     ├─→ P0-09 (coordinator)
  └─ P0-10 (history) ←──┘    └─→ P0-11 (menubar)
                              └─→ P0-12 (main win)
                              └─→ P0-13 (history view + dict)
  P0-14 (settings) ──┘
  P0-15 (errors) ←─所有
```

OK，无循环依赖。

## 风险二次评估

| 原始风险 | 现在评估 | 备注 |
|---|---|---|
| WhisperKit 中文质量 | 中等 | 已有 P1-03 词典 + P1-02 LLM 兜底 |
| App Store 审核 | 高 | Accessibility 用法要在 review notes 写清楚 |
| Fn 键兼容 | 中 | 提供 3 个备选键 |
| 模型 800MB 下载 | 高 | 首次进度条 + 异步不阻塞 |
| 中文 IME 干扰 | 中 | Cmd+V 不走 IME，应该 OK，需实测 |
| **新发现：SwiftData macOS 14+ 限制** | 中 | 把 deploy target 改成 14 已经处理 |

## 你需要并行做的事（提醒）

| # | 事 | 紧急度 |
|---|---|---|
| 1 | Apple Developer 注册（已在做） | 🔴 |
| 2 | 装 Xcode 15+（已在做） | 🔴 |
| 3 | 想好 GitHub 用户名 + 创建空仓库 `mouthpiece` | 🟡 |
| 4 | 想 5 张 App Store 截图的剧本 | 🟢（提审前） |
| 5 | 写一份 Privacy Policy 网页（GitHub Pages 即可） | 🟢 |

---

# 文档结束

