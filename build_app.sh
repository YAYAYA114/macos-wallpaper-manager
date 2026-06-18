#!/bin/zsh
# 编译并打包成可双击运行的 Wallpaper.app
set -e
cd "$(dirname "$0")"

echo "==> 编译 (release)…"
swift build -c release

APP="build/Wallpaper.app"
BIN=".build/release/WallpaperManager"

echo "==> 组装 App Bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WallpaperManager"
# SPM 资源包(logo 等),Bundle.module 会在 Contents/Resources 下查找
cp -R ".build/release/WallpaperManager_WallpaperManager.bundle" "$APP/Contents/Resources/"
# 应用图标(白底玻璃感)。重新生成:
#   swift Scripts/make_icon.swift Assets/AppIcon-color.png color      # 或 graphite
#   Scripts/make_icns.sh Assets/AppIcon-color.png Assets/AppIcon.icns
cp "Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WallpaperManager</string>
    <key>CFBundleIdentifier</key>
    <string>local.wallpaper-manager</string>
    <key>CFBundleName</key>
    <string>Wallpaper</string>
    <key>CFBundleDisplayName</key>
    <string>Wallpaper</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc 签名…"
codesign --force --sign - "$APP"

echo "✅ 完成:$PWD/$APP"
echo "   双击运行,或执行: open \"$APP\""
