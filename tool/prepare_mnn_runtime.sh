#!/bin/sh
set -eu

MNN_VERSION="3.6.0"
ANDROID_APP_VERSION="0_8_3"
ANDROID_SHA256="eb249cabbf73b8b1567d7611715cad8f1cbf4df7be75cb447ea206f12f94ab14"
IOS_SHA256="8dd885740672d2b22d35bb25b15fba5bdba20a4767791bf699fa61c28b1d3c3d"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 OUTPUT_DIRECTORY" >&2
  exit 64
fi

OUTPUT_DIR="$1"
CACHE_DIR="$OUTPUT_DIR/downloads"
ANDROID_APK="$CACHE_DIR/mnn-chat-$ANDROID_APP_VERSION.apk"
IOS_ZIP="$CACHE_DIR/mnn-ios-$MNN_VERSION.zip"
READY_FILE="$OUTPUT_DIR/.ready-android-$ANDROID_APP_VERSION-ios-$MNN_VERSION-v3"

sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

download_verified() {
  url="$1"
  destination="$2"
  expected="$3"
  if [ -f "$destination" ] && [ "$(sha256 "$destination")" = "$expected" ]; then
    return
  fi
  rm -f "$destination"
  curl --fail --location --retry 3 --connect-timeout 20 \
    --output "$destination.tmp" "$url"
  actual="$(sha256 "$destination.tmp")"
  if [ "$actual" != "$expected" ]; then
    rm -f "$destination.tmp"
    echo "MNN runtime checksum mismatch: expected $expected, got $actual" >&2
    exit 65
  fi
  mv "$destination.tmp" "$destination"
}

if [ -f "$READY_FILE" ]; then
  exit 0
fi

mkdir -p "$CACHE_DIR"
download_verified \
  "https://meta.alicdn.com/data/mnn/apks/mnn_chat_${ANDROID_APP_VERSION}.apk" \
  "$ANDROID_APK" "$ANDROID_SHA256"
download_verified \
  "https://github.com/alibaba/MNN/releases/download/$MNN_VERSION/mnn_${MNN_VERSION}_ios_armv82_cpu_metal_coreml.zip" \
  "$IOS_ZIP" "$IOS_SHA256"

rm -rf "$OUTPUT_DIR/android" "$OUTPUT_DIR/ios" "$OUTPUT_DIR/extracted"
mkdir -p "$OUTPUT_DIR/android/jni/arm64-v8a" "$OUTPUT_DIR/android/include" \
  "$OUTPUT_DIR/ios" "$OUTPUT_DIR/extracted/ios"
unzip -q "$IOS_ZIP" -d "$OUTPUT_DIR/extracted/ios"

IOS_RELEASE_DIR="$OUTPUT_DIR/extracted/ios/MNN-iOS-CPU-GPU/Static"
# The generic 3.6.0 Android SDK crashes while lazily materializing Gemma 4
# external weights on some arm64 devices. MNN Chat 0.8.3 is the upstream
# Android runtime packaged and exercised with the Gemma 4 catalog. It is a
# monolithic build, so extract its verified libMNN.so instead of mixing it with
# the generic SDK's split libraries.
unzip -p "$ANDROID_APK" lib/arm64-v8a/libMNN.so \
  > "$OUTPUT_DIR/android/jni/arm64-v8a/libMNN.so"
cp -R "$IOS_RELEASE_DIR/MNN.framework" "$OUTPUT_DIR/ios/MNN.framework"
ln -s "../../ios/MNN.framework/Headers" "$OUTPUT_DIR/android/include/MNN"
ln -s "../../ios/MNN.framework/Headers/llm" "$OUTPUT_DIR/android/include/llm"

touch "$READY_FILE"
