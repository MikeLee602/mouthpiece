#!/usr/bin/env bash
# scripts/dev-rebuild.sh
# 一键重新 build + ad-hoc 签名 + 启动。
#
# 用法：
#   ./scripts/dev-rebuild.sh         # build + sign + restart
#   ./scripts/dev-rebuild.sh --tcc   # 同时 reset TCC（强制重新授权）
#
# 用稳定的 --identifier 让 TCC 数据库认账（com.mouthpiece.app）。
# 但 ad-hoc CDHash 每次 build 都变，所以新 build 之后 TCC 也可能失效。
# 没辙——除非买 Apple Developer ID 证书做真签名。

set -euo pipefail

PROJECT_DIR="/Users/liyang60/projects/mouthpiece"
APP="/Users/liyang60/Library/Developer/Xcode/DerivedData/Mouthpiece-fngzsafxkcshtpbuicsmtpkxhzml/Build/Products/Debug/Mouthpiece.app"
ENT="$PROJECT_DIR/Mouthpiece/Mouthpiece.entitlements"
BUNDLE_ID="com.mouthpiece.app"

cd "$PROJECT_DIR"

# Workaround for Xcode 26 git issue with SwiftPM
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.bareRepository
export GIT_CONFIG_VALUE_0=all

echo "▶ Building..."
xcodebuild build \
  -project Mouthpiece.xcodeproj \
  -scheme Mouthpiece \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tail -3

echo ""
echo "▶ Re-signing with stable identifier=$BUNDLE_ID..."
codesign --force --deep --sign - \
  --identifier "$BUNDLE_ID" \
  --entitlements "$ENT" \
  "$APP" 2>&1 | tail -1

if [[ "${1:-}" == "--tcc" ]]; then
  echo ""
  echo "▶ Resetting TCC permissions..."
  tccutil reset Accessibility "$BUNDLE_ID" || true
  tccutil reset ListenEvent "$BUNDLE_ID" || true
  tccutil reset Microphone "$BUNDLE_ID" || true
  echo "  ↳ Don't forget to re-grant Accessibility permission in System Settings."
fi

echo ""
echo "▶ Killing old Mouthpiece..."
killall -9 Mouthpiece 2>/dev/null || true
sleep 1

echo ""
echo "▶ Cleaning stale temp WAVs..."
rm -f /var/folders/*/*/T/mouthpiece-*.wav 2>/dev/null || true

echo ""
echo "▶ Launching..."
open "$APP"
sleep 2

PID=$(pgrep -x Mouthpiece || echo "?")
echo "  ↳ PID: $PID"

echo ""
echo "▶ 自检 TCC（dev rebuild 后通常会失效）..."
sleep 1
TRUSTED=$(/usr/bin/log show --predicate 'subsystem == "com.mouthpiece.app" && category == "Injector"' --last 30s --info --debug 2>/dev/null | grep "AXIsProcessTrusted" | tail -1 || true)
if [[ -z "$TRUSTED" ]]; then
  echo "  ↳ 还没 inject 过，AXIsProcessTrusted 状态未知（按一次 Fn 验证）"
fi
echo ""
echo "✓ Ready. Watch logs: log stream --predicate 'subsystem == \"$BUNDLE_ID\"' --info --debug"
