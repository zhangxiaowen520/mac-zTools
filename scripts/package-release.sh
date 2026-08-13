#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" || ! -d "${DEVELOPER_DIR:-}" ]]; then
  for candidate in \
    "/Applications/Xcode-beta.app/Contents/Developer" \
    "/Applications/Xcode.app/Contents/Developer" \
    "/Users/zeno/Downloads/Xcode-beta.app/Contents/Developer"
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

cat > "$STAGE/安装说明.txt" <<EOF
zTools ${VERSION} (build ${BUILD})
================================

【安装步骤】
1. 打开本 DMG
2. 将 zTools.app 拖到「应用程序」(Applications) 文件夹
   （推荐：/Applications 或 ~/Applications）
3. 首次打开：若提示「无法验证开发者」——
   · 方法 A：在 Finder 中对 zTools.app 点右键 →「打开」→ 再点「打开」
   · 方法 B：终端执行：
       xattr -cr /Applications/zTools.app
       open /Applications/zTools.app
4. 首次截图时，在系统弹窗中允许「屏幕录制」
5. 若需要剪贴板粘贴 / 划词翻译，请在
   系统设置 → 隐私与安全性 → 辅助功能 中打开 zTools

【权限异常（开关已开仍失败）】
1. 确认只运行一份 zTools（不要用下载目录里的临时副本）
2. 系统设置 → 录屏 / 辅助功能：删除全部旧 zTools
3. 重新添加「应用程序」里的 zTools.app 并打开开关
4. 完全退出 zTools 后再打开

【翻译】
设置 → AI 翻译：填写 DeepSeek 等 OpenAI 兼容接口的 API Key

【URL 唤起示例】
  open 'ztools://screenshot'
  open 'ztools://fullscreen'
  open 'ztools://translate?text=hello'
  open 'ztools://palette'

【架构】
当前包主要为 Apple Silicon (arm64)。
Intel Mac 请联系发布者索取通用/ x86_64 构建。

【签名说明】
本包为本地 ad-hoc 签名（未使用 Apple Developer ID 公证）。
分发给熟人可用；若需 App Store / 无警告分发，需 Developer ID + 公证。

Copyright © 2026 zeno
EOF

# 拖放安装体验
ln -sf /Applications "$STAGE/Applications"

echo "==> Creating DMG..."
hdiutil create \
  -volname "zTools ${VERSION}" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -fs HFS+ \
  "$OUT_DIR/$DMG_NAME"

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
