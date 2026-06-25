# Changelog

## v0.1.2 — 2026-06-25

新功能：**AI 润色**（错字修正 + 自动排版）。

- 识别完成后调用 LLM（DeepSeek）做后处理，自动修同音错字、补标点、必要时
  markdown 排版（列表/标题/代码块）
- 配置文件路径：`~/.config/mouthpiece/config.json`，未配置自动 disable
  回退到原文，不影响其他功能
- 整段失败（超时 / 网络 / 5xx）静默回退原文，不阻塞 inject
- Floating bar 增加「润色中」状态（黄色 ✨ 图标）
- 设置 → 后处理 加 AI 润色状态展示 + 配置文件示例

实测延迟约 700-1000ms，质量良好（如「使用 vascode 进行测试」→「使用 VSCode
进行测试」）。

测试 83 → 93。

## v0.1.1 — 2026-06-21

修两个 v0.1.0 实测发现的 bug：

- **修复 app 偶尔被 macOS 自动 terminate**：菜单栏 app 长时间空闲被 AppKit
  AutomaticTermination 回收，按 Fn 没反应。Info.plist 加
  `NSSupportsAutomaticTermination=false` + `NSSupportsSuddenTermination=false`
- **扩展幻觉词表**：v0.1.0 漏过的幻觉句子「(字幕君:我看不懂...)」「感謝收看」
  「謝謝大家」等加进过滤；测试也加了对应 case

测试 83 → 仍全过。

## v0.1.0 — 2026-06-18 (initial release)

第一个公开版本。MVP + 主要功能都到位，签名是 ad-hoc（未公证），需用户手动绕 Gatekeeper。

### 功能

- 🎙️ **录音**：按住 `Fn` 或按一下切换录音状态（默认 toggle 模式）
- ⚡ **实时识别**：录音时滑动窗口跑 whisper-cli small，floating bar 实时蹦字
- 🎯 **最终识别**：停止后跑 whisper-cli medium 出高质量版本，自动粘贴到当前 App
- 🧹 **后处理**：去填充词、合并重复句、繁→简（OpenCC）、词典自动替换
- 📚 **历史**：SwiftData 持久化、搜索、JSON 导出、多选删除（自动 30 天清理）
- 📖 **词典**：识别错词的规则替换（启用/禁用 / 忽略大小写）
- 📊 **仪表盘**：今日 / 本周 / 累计字数 + 7 天柱图 + 最近 10 条
- ⚙️ **设置**：5 tab — 通用 / 录音 / 转写 / 后处理 / 关于

### 已知限制

- DMG 未经 Apple 公证，首次启动会触发 Gatekeeper 警告（README 有绕过方法）
- 实时识别需要额外下载 small 模型（466 MB），未装的话只有最终识别可用
- partial 末尾偶尔出现 2-4 字短重叠（whisper small 同窗多次识别细微漂移）—— final medium 不受影响
- App Store 通道暂未开（whisper-cli subprocess 依赖 sandbox=false）

### 测试

83 个单元测试全过。

---

合作 / 反馈 / Bug：[GitHub Issues](https://github.com/MikeLee602/mouthpiece/issues)
