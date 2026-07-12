#!/bin/sh
set -eu

MNN_VERSION="3.6.0"
ANDROID_SHA256="3ff2b92e11531f5a9d820b6bf6a8aede3e124e098a3645d8f6a23dcbc862015f"
IOS_SHA256="8dd885740672d2b22d35bb25b15fba5bdba20a4767791bf699fa61c28b1d3c3d"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 OUTPUT_DIRECTORY" >&2
  exit 64
fi

OUTPUT_DIR="$1"
CACHE_DIR="$OUTPUT_DIR/downloads"
ANDROID_ZIP="$CACHE_DIR/mnn-android-$MNN_VERSION.zip"
IOS_ZIP="$CACHE_DIR/mnn-ios-$MNN_VERSION.zip"
READY_FILE="$OUTPUT_DIR/.ready-$MNN_VERSION-v2"

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
  "https://github.com/alibaba/MNN/releases/download/$MNN_VERSION/mnn_${MNN_VERSION}_android_armv7_armv8_cpu_opencl_vulkan.zip" \
  "$ANDROID_ZIP" "$ANDROID_SHA256"
download_verified \
  "https://github.com/alibaba/MNN/releases/download/$MNN_VERSION/mnn_${MNN_VERSION}_ios_armv82_cpu_metal_coreml.zip" \
  "$IOS_ZIP" "$IOS_SHA256"

rm -rf "$OUTPUT_DIR/android" "$OUTPUT_DIR/ios" "$OUTPUT_DIR/extracted"
mkdir -p "$OUTPUT_DIR/android/jni/arm64-v8a" "$OUTPUT_DIR/android/include" \
  "$OUTPUT_DIR/ios" \
  "$OUTPUT_DIR/extracted/android" "$OUTPUT_DIR/extracted/ios"
unzip -q "$ANDROID_ZIP" -d "$OUTPUT_DIR/extracted/android"
unzip -q "$IOS_ZIP" -d "$OUTPUT_DIR/extracted/ios"

ANDROID_RELEASE_DIR="$OUTPUT_DIR/extracted/android/mnn_${MNN_VERSION}_android_armv7_armv8_cpu_opencl_vulkan"
IOS_RELEASE_DIR="$OUTPUT_DIR/extracted/ios/MNN-iOS-CPU-GPU/Static"
cp "$ANDROID_RELEASE_DIR/arm64-v8a/"*.so "$OUTPUT_DIR/android/jni/arm64-v8a/"
cp -R "$IOS_RELEASE_DIR/MNN.framework" "$OUTPUT_DIR/ios/MNN.framework"
ln -s "../../ios/MNN.framework/Headers" "$OUTPUT_DIR/android/include/MNN"
ln -s "../../ios/MNN.framework/Headers/llm" "$OUTPUT_DIR/android/include/llm"

touch "$READY_FILE"
