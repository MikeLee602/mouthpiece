# 发布流程

发布一版 Mouthpiece 的标准动作。

## 0. 一次性配置

### 0.1 申请 Developer ID Application 证书

1. 浏览器：https://developer.apple.com/account 确认 Apple Developer 个人账号已激活
2. 打开 Xcode → Settings → Accounts → 选你的 Apple ID → Manage Certificates
3. 点左下 + → "Developer ID Application" → 等几秒
4. 关掉 Xcode，在 Terminal 验证：

```bash
security find-identity -v -p codesigning
```

应该至少 1 条 `"Developer ID Application: Your Name (TEAMID)"`。

### 0.2 生成 App-specific Password 给公证用

1. 浏览器：https://appleid.apple.com → 登录 → "App-Specific Passwords" → 生成
2. 名字写 `Mouthpiece notarytool`，记下密码 `xxxx-xxxx-xxxx-xxxx`
3. Terminal 把它存进 keychain（一次性）：

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "你的@email.com" \
  --team-id "TEAMID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

`TEAMID` 是 `security find-identity` 输出里证书括号中的那个 10 位字符串。

### 0.3（可选）安装 create-dmg 让 DMG 好看

```bash
brew install create-dmg
```

不装也行，会退化用 hdiutil 出朴素 DMG。

## 1. 改版本号

`project.yml`：

```yaml
settings:
  base:
    MARKETING_VERSION: "0.2.0"   # 改这个
    CURRENT_PROJECT_VERSION: "2"  # build 号也加 1
```

跑一次 `xcodegen generate` 生效。

## 2. 三步出 DMG

```bash
./scripts/release-build.sh   # archive + Developer ID 签名
./scripts/notarize.sh         # 公证 .app
./scripts/make-dmg.sh         # 打 DMG + 签名 + 公证 + staple
```

完成后产物在 `build/dist/Mouthpiece-<version>.dmg`。

## 3. 上 GitHub Release

```bash
gh release create v0.2.0 \
  --title "Mouthpiece 0.2.0" \
  --notes-file CHANGELOG-0.2.0.md \
  build/dist/Mouthpiece-0.2.0.dmg
```

如果当前是 main 之外的分支，先合到 main 再打 tag。

## 4. App Store 通道（暂未启用）

App Store 必须 sandbox=true，目前 whisper-cli subprocess 依赖 sandbox=false。
切到 App Store 之前要：

- whisper.cpp 改 C API 直接 link，去掉 subprocess
- 或者把 whisper-cli 包成 XPC helper service
- entitlements 改成 sandbox=true + 加 com.apple.security.files.user-selected.read-only（让用户选模型）

这块单独排期，不进 v0.x。

## 故障排查

### `xcodebuild archive` 报 "Code signing is required" 但脚本里设了 manual
检查 Keychain 里证书是否过期。Apple Developer 的 Developer ID 证书通常 5 年有效。

### `notarytool submit` 报 "Invalid"
拉日志：

```bash
xcrun notarytool log <submission-id> --keychain-profile AC_PASSWORD
```

常见问题：
- entitlement 漏了 `com.apple.security.cs.allow-jit` / `allow-unsigned-executable-memory`
  → 用 whisper-cli 时不需要这俩，但如果以后改成 link C API 跑 ML 推理可能要
- 没开 hardened runtime → `release-build.sh` 里设了 `--options=runtime`，应该已经开了
- 二进制里有 nested 框架未签名 → `release-build.sh` 加 `--deep` 重签

### DMG 双击没法打开 / 显示"已损坏"
- 检查 staple：`xcrun stapler validate Mouthpiece.dmg` 应该过
- 检查 Gatekeeper：`spctl -a -t open --context context:primary-signature -v Mouthpiece.dmg`
- 远程下载场景：浏览器 / curl 下载会带 `com.apple.quarantine` 属性，必须公证 + staple 才能直接双击
