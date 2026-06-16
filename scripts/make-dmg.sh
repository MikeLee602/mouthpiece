#!/usr/bin/env bash
# scripts/make-dmg.sh
# 把已签名 + 已 staple 的 .app 打包成 DMG。
#
# 用法：
#   ./scripts/make-dmg.sh
#
# 用 create-dmg（如果装了）走美化路线；没装就退化用 hdiutil 直接做。
#   brew install create-dmg

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP="$PROJECT_DIR/build/export/Mouthpiece.app"
DIST_DIR="$PROJECT_DIR/build/dist"
VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.1.0")
DMG="$DIST_DIR/Mouthpiece-$VERSION.dmg"

if [[ ! -d "$APP" ]]; then
  echo "❌ 找不到 $APP — 先跑 release-build.sh + notarize.sh"
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG"

if command -v create-dmg >/dev/null; then
  echo "▶ 用 create-dmg 制作美化 DMG..."
  create-dmg \
    --volname "Mouthpiece $VERSION" \
    --window-pos 200 120 \
    --window-size 600 380 \
    --icon-size 100 \
    --icon "Mouthpiece.app" 175 190 \
    --hide-extension "Mouthpiece.app" \
    --app-drop-link 425 190 \
    --no-internet-enable \
    "$DMG" \
    "$APP" 2>&1 | tail -8
else
  echo "▶ create-dmg 没装，退化使用 hdiutil（功能能用，外观朴素）..."
  STAGE="$DIST_DIR/dmg-stage"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create \
    -volname "Mouthpiece $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG"
  rm -rf "$STAGE"
fi

echo ""
echo "▶ 给 DMG 也签名..."
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/')
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --verbose=2 "$DMG"

echo ""
echo "▶ 公证 DMG（短链路 — 如果只发 DMG，必须给 DMG 也公证一次）..."
PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo ""
echo "✓ DMG 完成: $DMG"
ls -lh "$DMG"
