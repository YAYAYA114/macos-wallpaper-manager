#!/bin/zsh
# 打包 DMG 安装包:先运行 build_app.sh,再生成 build/Wallpaper-<版本>.dmg
set -e
cd "$(dirname "$0")"

VERSION="1.0"
APP="build/Wallpaper.app"
DMG="build/Wallpaper-${VERSION}.dmg"

./build_app.sh

echo "==> 生成 DMG…"
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Wallpaper" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "✅ 安装包:$PWD/$DMG"
echo "   分发后用户打开 DMG,把 Wallpaper 拖入 Applications 即完成安装。"
