#!/usr/bin/env bash
# scripts/notarize.sh
# 把签名好的 .app 提交给 Apple 公证，等审核完毕，stapling 票据到本地。
#
# 用法：
#   首次：先存 keychain profile（一次性）：
#     xcrun notarytool store-credentials "AC_PASSWORD" \
#       --apple-id "your@email.com" \
#       --team-id "ABCDE12345" \
#       --password "app-specific-password"
#     （app-specific-password 在 https://appleid.apple.com 生成）
#
#   然后：./scripts/notarize.sh
#
# 跑这个之前，必须先跑 release-build.sh。

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP="$PROJECT_DIR/build/export/Mouthpiece.app"
BUILD_DIR="$PROJECT_DIR/build"
ZIP="$BUILD_DIR/Mouthpiece-notarize.zip"
PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

if [[ ! -d "$APP" ]]; then
  echo "❌ 找不到 $APP — 先跑 ./scripts/release-build.sh"
  exit 1
fi

echo "▶ 打包 zip 用于上传..."
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
ls -lh "$ZIP"

echo ""
echo "▶ 提交公证 (profile=$PROFILE)..."
echo "   等 Apple 审核——通常 1-5 分钟。"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$PROFILE" \
  --wait

echo ""
echo "▶ 把公证票据 staple 到 .app..."
xcrun stapler staple "$APP"

echo ""
echo "▶ 验证 stapling..."
xcrun stapler validate "$APP"
spctl -a -vvv -t install "$APP" 2>&1 || true

echo ""
echo "✓ 公证完成: $APP"
echo "  下一步: ./scripts/make-dmg.sh"
