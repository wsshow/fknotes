#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ICON_SVG="$ROOT/assets/brand/fknotes_icon.svg"
MARK_SVG="$ROOT/assets/brand/fknotes_mark.svg"
WORDMARK_SVG="$ROOT/assets/brand/fknotes_wordmark.svg"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/fknotes-icons.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

command -v qlmanage >/dev/null 2>&1 || {
  echo "需要 macOS qlmanage 才能渲染 SVG 图标" >&2
  exit 1
}
command -v sips >/dev/null 2>&1 || {
  echo "需要 macOS sips 才能生成平台尺寸" >&2
  exit 1
}

qlmanage -t -s 1024 -o "$TMP" "$ICON_SVG" >/dev/null
qlmanage -t -s 1024 -o "$TMP" "$MARK_SVG" >/dev/null
ICON_PNG="$TMP/$(basename "$ICON_SVG").png"
MARK_PNG="$TMP/$(basename "$MARK_SVG").png"

# Quick Look 总是输出方形缩略图。把横向字标临时置于方形画布中央，
# 再由 sips 居中裁切，得到无额外留白的 640x192 启动字标。
WORDMARK_RENDER_SVG="$TMP/fknotes_wordmark_render.svg"
sed \
  -e 's/height="192" viewBox="0 0 640 192"/height="640" viewBox="0 -224 640 640"/' \
  -e 's/<rect width="640" height="192"/<rect y="-224" width="640" height="640"/' \
  "$WORDMARK_SVG" > "$WORDMARK_RENDER_SVG"
qlmanage -t -s 640 -o "$TMP" "$WORDMARK_RENDER_SVG" >/dev/null
WORDMARK_PNG="$TMP/$(basename "$WORDMARK_RENDER_SVG").png"

resize() {
  size="$1"
  source="$2"
  destination="$3"
  sips -z "$size" "$size" "$source" --out "$destination" >/dev/null
}

cp "$ICON_PNG" "$ROOT/assets/brand/fknotes_icon.png"
cp "$MARK_PNG" "$ROOT/assets/brand/fknotes_mark.png"
sips -c 192 640 "$WORDMARK_PNG" \
  --out "$ROOT/android/app/src/main/res/drawable-nodpi/splash_wordmark.png" >/dev/null

resize 48  "$MARK_PNG" "$ROOT/android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
resize 72  "$MARK_PNG" "$ROOT/android/app/src/main/res/mipmap-hdpi/ic_launcher.png"
resize 96  "$MARK_PNG" "$ROOT/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png"
resize 144 "$MARK_PNG" "$ROOT/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"
resize 192 "$MARK_PNG" "$ROOT/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

IOS="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
resize 20   "$ICON_PNG" "$IOS/Icon-App-20x20@1x.png"
resize 40   "$ICON_PNG" "$IOS/Icon-App-20x20@2x.png"
resize 60   "$ICON_PNG" "$IOS/Icon-App-20x20@3x.png"
resize 29   "$ICON_PNG" "$IOS/Icon-App-29x29@1x.png"
resize 58   "$ICON_PNG" "$IOS/Icon-App-29x29@2x.png"
resize 87   "$ICON_PNG" "$IOS/Icon-App-29x29@3x.png"
resize 40   "$ICON_PNG" "$IOS/Icon-App-40x40@1x.png"
resize 80   "$ICON_PNG" "$IOS/Icon-App-40x40@2x.png"
resize 120  "$ICON_PNG" "$IOS/Icon-App-40x40@3x.png"
resize 120  "$ICON_PNG" "$IOS/Icon-App-60x60@2x.png"
resize 180  "$ICON_PNG" "$IOS/Icon-App-60x60@3x.png"
resize 76   "$ICON_PNG" "$IOS/Icon-App-76x76@1x.png"
resize 152  "$ICON_PNG" "$IOS/Icon-App-76x76@2x.png"
resize 167  "$ICON_PNG" "$IOS/Icon-App-83.5x83.5@2x.png"
resize 1024 "$ICON_PNG" "$IOS/Icon-App-1024x1024@1x.png"

LAUNCH="$ROOT/ios/Runner/Assets.xcassets/LaunchImage.imageset"
resize 88  "$MARK_PNG" "$LAUNCH/LaunchImage.png"
resize 176 "$MARK_PNG" "$LAUNCH/LaunchImage@2x.png"
resize 264 "$MARK_PNG" "$LAUNCH/LaunchImage@3x.png"

MAC="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"
for size in 16 32 64 128 256 512 1024; do
  resize "$size" "$MARK_PNG" "$MAC/app_icon_$size.png"
done
cp "$MARK_PNG" "$MAC/fknotes_icon.svg.png"

resize 32  "$MARK_PNG" "$ROOT/web/favicon.png"
resize 192 "$MARK_PNG" "$ROOT/web/icons/Icon-192.png"
resize 512 "$MARK_PNG" "$ROOT/web/icons/Icon-512.png"
resize 192 "$ICON_PNG" "$ROOT/web/icons/Icon-maskable-192.png"
resize 512 "$ICON_PNG" "$ROOT/web/icons/Icon-maskable-512.png"

resize 256 "$MARK_PNG" "$TMP/windows-icon.png"
sips -s format ico "$TMP/windows-icon.png" \
  --out "$ROOT/windows/runner/resources/app_icon.ico" >/dev/null

echo "已从 assets/brand/fknotes_icon.svg 生成全平台应用图标"
