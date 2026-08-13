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
APP_DST="$HOME/Applications/zTools.app"

echo "==> Stopping old zTools..."
pkill -x zTools 2>/dev/null || true
sleep 0.4

echo "==> Building Release (arm64 only, stable)..."
xcodebuild \
  -project zTools.xcodeproj \
  -scheme zTools \
  -configuration Release \
  -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  ENABLE_HARDENED_RUNTIME=NO \
  ENABLE_DEBUG_DYLIB=NO \
  build

APP_SRC="$ROOT/build/Build/Products/Release/zTools.app"

echo "==> Installing to $APP_DST"
mkdir -p "$HOME/Applications"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
xattr -cr "$APP_DST" 2>/dev/null || true

# 关键：用 Bundle ID 作为 designated requirement（不随每次编译 CDHash 变化）
# 否则系统设置里开关是开的，但运行中的二进制对不上，会反复弹权限。
echo "==> Codesign with stable identifier requirement..."
codesign --force --deep --sign - \
  --identifier "com.zeno.ztools" \
  -r='designated => identifier "com.zeno.ztools"' \
  "$APP_DST"

echo "==> Verify signature / DR:"
codesign -dv --verbose=2 "$APP_DST" 2>&1 | sed -n '1,25p'
echo "---"
codesign -d -r- "$APP_DST" 2>&1

echo ""
echo "==> Launching $APP_DST"
open "$APP_DST"

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
已安装并启动：$APP_DST
签名 DR：identifier "com.zeno.ztools"（重建后权限可保持）

若截图仍要权限：
  tccutil reset ScreenCapture com.zeno.ztools
  然后在系统设置中重新添加上述路径。
请只从此路径启动，不要运行 build/ 副本。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
