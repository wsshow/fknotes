# FK Notes Flutter project shortcuts.
# Usage examples:
#   make package
#   make debug
#   make debug-overlay BUILD_NAME=1.0.3 BUILD_NUMBER=31
#   make run DEVICE=emulator-5554
#   make apk BUILD_NAME=1.2.0 BUILD_NUMBER=12

SHELL := /bin/sh

FLUTTER ?= flutter
DART ?= dart
DEVICE ?=
BUILD_NAME ?=
BUILD_NUMBER ?=
BUILD_TIME ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
DIST_DIR ?= dist

PUB_VERSION := $(shell sed -n 's/^version: //p' pubspec.yaml | head -n 1)
PUB_BUILD_NAME := $(word 1,$(subst +, ,$(PUB_VERSION)))
PUB_BUILD_NUMBER := $(word 2,$(subst +, ,$(PUB_VERSION)))
ARTIFACT_BUILD_NAME := $(if $(BUILD_NAME),$(BUILD_NAME),$(PUB_BUILD_NAME))
ARTIFACT_BUILD_NUMBER := $(if $(BUILD_NUMBER),$(BUILD_NUMBER),$(PUB_BUILD_NUMBER))
ARTIFACT_VERSION := $(ARTIFACT_BUILD_NAME)$(if $(ARTIFACT_BUILD_NUMBER),+$(ARTIFACT_BUILD_NUMBER))
BUILD_ARGS := $(if $(BUILD_NAME),--build-name=$(BUILD_NAME)) $(if $(BUILD_NUMBER),--build-number=$(BUILD_NUMBER))
BUILD_METADATA_ARGS := --dart-define=FKNOTES_BUILD_TIME=$(BUILD_TIME)
DEVICE_ARG := $(if $(DEVICE),-d $(DEVICE))

.DEFAULT_GOAL := help
.PHONY: help doctor get upgrade outdated format analyze test check \
	devices emulators run run-android run-ios run-macos clean clean-all \
	debug debug-overlay package apk-debug apk-debug-split apk apk-split aab ios macos linux windows web

help: ## 显示所有可用命令
	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\n可选参数：DEVICE=<设备 ID>，BUILD_NAME=<版本名>，BUILD_NUMBER=<构建号>，BUILD_TIME=<ISO 8601 时间>，DIST_DIR=<输出目录>\n'

doctor: ## 检查 Flutter 开发环境
	$(FLUTTER) doctor

get: ## 获取依赖
	$(FLUTTER) pub get

upgrade: ## 升级项目依赖
	$(FLUTTER) pub upgrade

outdated: ## 检查可升级的依赖
	$(FLUTTER) pub outdated

format: ## 格式化 Dart 源码
	$(DART) format lib test

analyze: get ## 执行静态分析
	$(FLUTTER) analyze

test: get ## 运行单元和组件测试
	$(FLUTTER) test

check: format analyze test ## 格式化、分析并测试

devices: ## 列出可用设备
	$(FLUTTER) devices

emulators: ## 列出可用 Android 模拟器
	$(FLUTTER) emulators

run: get ## 在指定设备上调试运行；可传 DEVICE=<设备 ID>
	$(FLUTTER) run $(DEVICE_ARG) $(BUILD_METADATA_ARGS)

run-android: get ## 在 Android 设备或模拟器上调试运行
	$(FLUTTER) run -d $(if $(DEVICE),$(DEVICE),android) $(BUILD_METADATA_ARGS)

run-ios: get ## 在 iOS 模拟器或设备上调试运行
	$(FLUTTER) run -d $(if $(DEVICE),$(DEVICE),ios) $(BUILD_METADATA_ARGS)

run-macos: get ## 在 macOS 上调试运行
	$(FLUTTER) run -d macos $(BUILD_METADATA_ARGS)

debug: apk-debug ## 打包默认 Android Debug APK

debug-overlay: ## 以 Release 签名构建可覆盖真机正式包的 arm64 Debug APK
	@test -n "$(BUILD_NAME)" || (echo "缺少 BUILD_NAME，例如：make debug-overlay BUILD_NAME=1.0.3 BUILD_NUMBER=31" >&2; exit 1)
	@test -n "$(BUILD_NUMBER)" || (echo "缺少 BUILD_NUMBER，例如：make debug-overlay BUILD_NAME=1.0.3 BUILD_NUMBER=31" >&2; exit 1)
	$(FLUTTER) pub get
	FKNOTES_SIGN_DEBUG_WITH_RELEASE=1 $(FLUTTER) build apk --debug --split-per-abi --target-platform android-arm64 $(BUILD_ARGS) $(BUILD_METADATA_ARGS)
	@mkdir -p $(DIST_DIR)
	@rm -f $(DIST_DIR)/fknotes-*-arm64-v8a-diagnostic-debug.apk
	@cp build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-arm64-v8a-diagnostic-debug.apk
	@echo "已生成：$(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-arm64-v8a-diagnostic-debug.apk"
	@echo "覆盖安装：adb install -r -t $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-arm64-v8a-diagnostic-debug.apk"

package: apk ## 打包默认 Android 发布 APK

apk-debug: get ## 打包 Android Debug APK，产物放入 dist/
	$(FLUTTER) build apk --debug $(BUILD_ARGS) $(BUILD_METADATA_ARGS)
	@mkdir -p $(DIST_DIR)
	@rm -f $(DIST_DIR)/fknotes-debug.apk
	@cp build/app/outputs/flutter-apk/app-debug.apk $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-debug.apk
	@echo "已生成：$(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-debug.apk"

apk-debug-split: get ## 按 ABI 打包 Android Debug APK，产物放入 dist/
	$(FLUTTER) build apk --debug --split-per-abi $(BUILD_ARGS) $(BUILD_METADATA_ARGS)
	@mkdir -p $(DIST_DIR)
	@rm -f $(DIST_DIR)/app-*-debug.apk $(DIST_DIR)/fknotes-debug.apk
	@cp build/app/outputs/flutter-apk/app-armeabi-v7a-debug.apk $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-armeabi-v7a-debug.apk
	@cp build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-arm64-v8a-debug.apk
	@cp build/app/outputs/flutter-apk/app-x86_64-debug.apk $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-x86_64-debug.apk
	@echo "已生成：$(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-armeabi-v7a-debug.apk"
	@echo "已生成：$(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-arm64-v8a-debug.apk"
	@echo "已生成：$(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-x86_64-debug.apk"

apk: get ## 打包 Android 发布 APK，产物放入 dist/
	$(FLUTTER) build apk --release $(BUILD_ARGS) $(BUILD_METADATA_ARGS)
	@mkdir -p $(DIST_DIR)
	@rm -f $(DIST_DIR)/fknotes-release.apk
	@cp build/app/outputs/flutter-apk/app-release.apk $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-release.apk
	@echo "已生成：$(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-release.apk"

apk-split: get ## 按 ABI 打包 Android 发布 APK，产物放入 dist/
	$(FLUTTER) build apk --release --split-per-abi $(BUILD_ARGS) $(BUILD_METADATA_ARGS)
	@mkdir -p $(DIST_DIR)
	@rm -f $(DIST_DIR)/app-*-release.apk $(DIST_DIR)/fknotes-release.apk
	@cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-armeabi-v7a-release.apk
	@cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-arm64-v8a-release.apk
	@cp build/app/outputs/flutter-apk/app-x86_64-release.apk $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-x86_64-release.apk
	@echo "已生成：$(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-armeabi-v7a-release.apk"
	@echo "已生成：$(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-arm64-v8a-release.apk"
	@echo "已生成：$(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-x86_64-release.apk"

aab: get ## 打包 Android 发布 AAB，产物放入 dist/
	$(FLUTTER) build appbundle --release $(BUILD_ARGS) $(BUILD_METADATA_ARGS)
	@mkdir -p $(DIST_DIR)
	@rm -f $(DIST_DIR)/fknotes-release.aab
	@cp build/app/outputs/bundle/release/app-release.aab $(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-release.aab
	@echo "已生成：$(DIST_DIR)/fknotes-$(ARTIFACT_VERSION)-release.aab"

ios: get ## 打包 iOS Release（需 Xcode 签名配置）
	$(FLUTTER) build ipa --release $(BUILD_ARGS) $(BUILD_METADATA_ARGS)

macos: get ## 打包 macOS Release
	$(FLUTTER) build macos --release $(BUILD_ARGS) $(BUILD_METADATA_ARGS)

linux: get ## 打包 Linux Release
	$(FLUTTER) build linux --release $(BUILD_ARGS) $(BUILD_METADATA_ARGS)

windows: get ## 打包 Windows Release
	$(FLUTTER) build windows --release $(BUILD_ARGS) $(BUILD_METADATA_ARGS)

web: get ## 打包 Web Release
	$(FLUTTER) build web --release $(BUILD_ARGS) $(BUILD_METADATA_ARGS)

clean: ## 清理 Flutter 构建缓存和 dist/ 产物
	$(FLUTTER) clean
	rm -rf $(DIST_DIR)

clean-all: clean ## 清理后重新获取依赖
	$(FLUTTER) pub get
