#!/usr/bin/env bash
# scripts/release-build.sh
# 用 Developer ID 证书做 Release archive + 签名。
#
# 用法：
#   ./scripts/release-build.sh
#
# 前置条件：
#   - Keychain 有 "Developer ID Application: <Your Name> (<TEAMID>)" 证书
#     （在 Xcode → Settings → Accounts → Manage Certificates 申请 + 下载）
#   - 项目 entitlements 里 hardened runtime 已开（项目里默认开了）

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Workaround for Xcode SwiftPM + git
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.bareRepository
export GIT_CONFIG_VALUE_0=all

BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE="$BUILD_DIR/Mouthpiece.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Mouthpiece.app"

echo "▶ 检查 Developer ID 证书..."
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 || true)
if [[ -z "$IDENTITY" ]]; then
  echo "❌ 找不到 Developer ID Application 证书。"
  echo "   先在 Xcode → Settings → Accounts → Manage Certificates 申请 + 下载。"
  exit 1
fi
echo "  ↳ $IDENTITY"

# 提取 CN 和 TeamID（CSV 字段）
CN=$(echo "$IDENTITY" | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/')
TEAM_ID=$(echo "$CN" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')
echo "  ↳ Team ID: $TEAM_ID"

echo ""
echo "▶ 清理旧 archive..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo ""
echo "▶ 生成 .xcodeproj..."
xcodegen generate >/dev/null

echo ""
echo "▶ Archive (Release, Developer ID)..."
xcodebuild archive \
  -project Mouthpiece.xcodeproj \
  -scheme Mouthpiece \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CN" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  | tail -5

echo ""
echo "▶ Export..."
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  | tail -5

echo ""
echo "▶ 验证签名..."
codesign --verify --strict --verbose=2 "$APP"
echo ""
codesign -dvvv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|Authority|Timestamp"

echo ""
echo "▶ 检查 hardened runtime..."
codesign -d --entitlements - "$APP" 2>&1 | head -20

echo ""
echo "✓ 签名完成: $APP"
echo "  下一步: ./scripts/notarize.sh"
