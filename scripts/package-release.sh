#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" || ! -d "${DEVELOPER_DIR:-}" ]]; then
  for candidate in \
    "/Applications/Xcode-beta.app/Contents/Developer" \
    "/Applications/Xcode.app/Contents/Developer" \
    "$HOME/Downloads/Xcode-beta.app/Contents/Developer"
  do
    if [[ -d "$candidate" ]]; then
      export DEVELOPER_DIR="$candidate"
      break
    fi
  done
fi
if [[ -z "${DEVELOPER_DIR:-}" || ! -d "${DEVELOPER_DIR:-}" ]]; then
  echo "ERROR: 找不到 Xcode。请安装 Xcode 或设置 DEVELOPER_DIR。"
  exit 1
fi
echo "==> Using DEVELOPER_DIR=$DEVELOPER_DIR"

cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' zTools/Info.plist 2>/dev/null || echo "0.0.0")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' zTools/Info.plist 2>/dev/null || echo "0")
OUT_DIR="$ROOT/dist"
STAGE="$OUT_DIR/stage"
APP_NAME="zTools.app"
DMG_NAME="zTools-${VERSION}.dmg"
ZIP_NAME="zTools-${VERSION}.zip"

echo "==> Building Release ${VERSION} (${BUILD})..."
# 默认 arm64；若需 Intel 兼容可改为 ARCHS="arm64 x86_64"
ARCHS_ARG="${ARCHS:-arm64}"
xcodebuild \
  -project zTools.xcodeproj \
  -scheme zTools \
  -configuration Release \
  -derivedDataPath build \
  -destination "platform=macOS,arch=arm64" \
  ARCHS="$ARCHS_ARG" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  ENABLE_HARDENED_RUNTIME=NO \
  ENABLE_DEBUG_DYLIB=NO \
  build

APP_SRC="$ROOT/build/Build/Products/Release/zTools.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "ERROR: 构建产物不存在: $APP_SRC"
  exit 1
fi

rm -rf "$STAGE" "$OUT_DIR/$DMG_NAME" "$OUT_DIR/$ZIP_NAME"
mkdir -p "$STAGE"

echo "==> Staging..."
cp -R "$APP_SRC" "$STAGE/$APP_NAME"
xattr -cr "$STAGE/$APP_NAME" 2>/dev/null || true

echo "==> Codesign (identifier DR)..."
codesign --force --deep --sign - \
  --identifier "com.zeno.ztools" \
  -r='designated => identifier "com.zeno.ztools"' \
  "$STAGE/$APP_NAME"

codesign --verify --verbose=2 "$STAGE/$APP_NAME" 2>&1 | sed -n '1,15p' || true
echo "DR: $(codesign -d -r- "$STAGE/$APP_NAME" 2>&1 | grep designated || true)"

# 标准拖放安装：app + Applications 快捷方式；说明放到卷根隐藏区外
ln -sf /Applications "$STAGE/Applications"

BG_SRC="$ROOT/scripts/dmg/background.png"
if [[ ! -f "$BG_SRC" ]]; then
  echo "==> Generating DMG background..."
  xcrun swift "$ROOT/scripts/generate-dmg-background.swift" "$BG_SRC"
fi
mkdir -p "$STAGE/.background"
cp "$BG_SRC" "$STAGE/.background/background.png"

VOL_NAME="zTools"
RW_DMG="$OUT_DIR/.tmp-ztools.dmg"
rm -f "$RW_DMG"

echo "==> Creating install DMG..."
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDRW \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  "$RW_DMG" >/dev/null

MOUNT_DIR="/Volumes/${VOL_NAME}"
if [[ -d "$MOUNT_DIR" ]]; then
  hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
  sleep 0.4
fi

echo "==> Mounting and styling Finder window..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk '/\/dev\// { print $1; exit }')
for i in {1..40}; do
  [[ -d "$MOUNT_DIR" ]] && break
  sleep 0.15
done
if [[ ! -d "$MOUNT_DIR" ]]; then
  echo "ERROR: 无法挂载 $RW_DMG"
  exit 1
fi

# 隐藏背景文件夹
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "$MOUNT_DIR/.background" 2>/dev/null || true
fi
chflags hidden "$MOUNT_DIR/.background" 2>/dev/null || true

if ! osascript <<EOF
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set sidebar width of container window to 0
    set the bounds of container window to {420, 180, 1080, 600}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "$APP_NAME" of container window to {160, 188}
    set position of item "Applications" of container window to {500, 188}
    close
    open
    update without registering applications
    delay 1.2
  end tell
end tell
EOF
then
  echo "WARN: Finder 窗口样式未写入（可稍后手动打开 DMG 检查）。仍继续压缩。"
fi

sync
hdiutil detach "$DEVICE" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet
sleep 0.5

echo "==> Compressing DMG..."
rm -f "$OUT_DIR/$DMG_NAME"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DIR/$DMG_NAME" >/dev/null
rm -f "$RW_DMG"

echo "==> Creating ZIP (备用)..."
(
  cd "$STAGE"
  ditto -c -k --sequesterRsrc --keepParent "$APP_NAME" "$OUT_DIR/$ZIP_NAME"
)

# 同步到本机
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/zTools.app"
cp -R "$STAGE/$APP_NAME" "$HOME/Applications/zTools.app"
xattr -cr "$HOME/Applications/zTools.app" 2>/dev/null || true
codesign --force --deep --sign - \
  --identifier "com.zeno.ztools" \
  -r='designated => identifier "com.zeno.ztools"' \
  "$HOME/Applications/zTools.app"

echo ""
echo "========================================"
echo " 打包完成 zTools ${VERSION}"
echo "========================================"
echo "  DMG : $OUT_DIR/$DMG_NAME"
echo "  ZIP : $OUT_DIR/$ZIP_NAME"
echo "  本机: $HOME/Applications/zTools.app"
echo ""
ls -lh "$OUT_DIR/$DMG_NAME" "$OUT_DIR/$ZIP_NAME"
echo ""
echo "发给别人：直接发送 DMG 即可。"
echo "对方若无法打开：右键 → 打开，或 xattr -cr 后再 open。"
echo "========================================"
