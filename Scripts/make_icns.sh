#!/bin/zsh
# 把一张 1024x1024 PNG 转成 macOS 多尺寸 AppIcon.icns
# 用法: Scripts/make_icns.sh <源.png> <输出.icns>
set -e

SRC="$1"
OUT="$2"
if [[ -z "$SRC" || -z "$OUT" ]]; then
  echo "用法: make_icns.sh <源.png> <输出.icns>"
  exit 1
fi

WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  sips -z $size $size       "$SRC" --out "$ICONSET/icon_${size}x${size}.png"    >/dev/null
  d=$((size * 2))
  sips -z $d $d             "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$WORK"
echo "✅ 已生成 $OUT"
