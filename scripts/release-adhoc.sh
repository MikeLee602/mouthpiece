#!/usr/bin/env bash
# scripts/release-adhoc.sh
# Ad-hoc 签名版的发布流程。无需 Apple Developer 证书，但用户首次打开
# 会被 Gatekeeper 拦截，需要手动绕一次。
#
# 用法：
#   ./scripts/release-adhoc.sh [version]
#
#   version 默认从 project.yml 的 MARKETING_VERSION 读，传参可覆盖。
#
# 产出：
#   build/dist/Mouthpiece-<version>.dmg
#   build/dist/Mouthpiece-<version>.dmg.sha256

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Workaround for Xcode SwiftPM + git
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.bareRepository
export GIT_CONFIG_VALUE_0=all

VERSION="${1:-$(grep MARKETING_VERSION project.yml | head -1 | awk -F'"' '{print $2}')}"
if [[ -z "$VERSION" ]]; then
  echo "❌ 找不到 version。要么传参，要么 project.yml 里改 MARKETING_VERSION"
  exit 1
fi

echo "▶ Building Mouthpiece v$VERSION (ad-hoc)"
echo ""

BUILD_DIR="$PROJECT_DIR/build"
DERIVED="$BUILD_DIR/derived"
ARCHIVE="$BUILD_DIR/Mouthpiece.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Mouthpiece.app"
DIST_DIR="$BUILD_DIR/dist"
DMG="$DIST_DIR/Mouthpiece-$VERSION.dmg"
ENT="$PROJECT_DIR/Mouthpiece/Mouthpiece.entitlements"
BUNDLE_ID="com.mouthpiece.app"

rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

echo "▶ xcodegen..."
xcodegen generate >/dev/null

echo ""
echo "▶ Archive (Release, ad-hoc, no signing)..."
xcodebuild archive \
  -project Mouthpiece.xcodeproj \
  -scheme Mouthpiece \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  | tail -3

# 直接从 archive 里拿 .app（不走 export，避免 Apple Developer 检查）
ARCHIVED_APP="$ARCHIVE/Products/Applications/Mouthpiece.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
  echo "❌ 找不到 archived .app: $ARCHIVED_APP"
  exit 1
fi

mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVED_APP" "$EXPORT_DIR/"

echo ""
echo "▶ Ad-hoc 签名 (identifier=${BUNDLE_ID})..."
codesign --force --deep --sign - \
  --identifier "$BUNDLE_ID" \
  --entitlements "$ENT" \
  "$APP" 2>&1 | tail -1
codesign --verify --strict --verbose=2 "$APP" 2>&1 | head -3

echo ""
echo "▶ 制作 DMG..."
if command -v create-dmg >/dev/null; then
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
    "$APP" 2>&1 | tail -5
else
  echo "  ↳ create-dmg 没装，使用 hdiutil（外观朴素，brew install create-dmg 可升级）"
  STAGE="$DIST_DIR/dmg-stage"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create \
    -volname "Mouthpiece $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null
  rm -rf "$STAGE"
fi

echo ""
echo "▶ 算 SHA256..."
shasum -a 256 "$DMG" | tee "$DMG.sha256"

echo ""
echo "▶ DMG 大小..."
ls -lh "$DMG"

echo ""
echo "✓ 完成: $DMG"
echo ""
echo "  上 Release：gh release create v$VERSION \"$DMG\" \"$DMG.sha256\" --notes-file CHANGELOG.md"
