# 非空笔记（FK Notes）

一个本地优先、隐私优先的多媒体笔记应用。无需账号，笔记、附件与识别结果默认保存在用户自己的设备上。

> 当前处于内部测试阶段，主要验证 Android 版本。仓库保留了 iOS、macOS、Windows、Linux 和 Web 工程，其中非移动端的相机、录音与 OCR 能力仍需进一步适配和验证。

## 产品原则

- **本地优先**：核心数据存储在应用私有目录，识别过程不依赖远程服务。
- **隐私优先**：OCR 和语音转写均在设备上完成；网络只用于用户主动下载可选的离线模型。
- **操作可控**：拍照和选择图片只负责添加图片，OCR 由用户在图片详情中主动触发。
- **数据可迁移**：支持完整备份与恢复，用户可以自行保管备份文件。

## 核心能力

- 文字、图片、音频、视频和文档的统一管理
- 图片详情内按需执行本地中文 OCR，识别结果可复制和重新识别
- 音频详情内按需执行 SenseVoice 本地转写，支持后台进度、取消、编辑、复制和重新转写
- 笔记编辑器支持 Streaming Zipformer 本地实时听写，在光标位置边说边出字，可完成、取消及整体撤销
- 可选 MNN 本地语言模型，支持自由多轮聊天、自定义会话角色、受控本地图片理解，以及对当前笔记进行总结、提取待办和润色
- 离线语音模型可从 ModelScope 按需下载（断点续传与 SHA-256 校验），也可从文件手动导入
- 统一的“本地模型”页面，集中管理语音、OCR、TTS 和语言模型，支持下载续传、实时速度/字节进度、完整性校验、导入、切换和移除
- 可选系统应用锁，使用设备已有的指纹、人脸识别或锁屏密码保护应用访问
- 标题、正文、OCR、语音转写、文件名和标签的统一检索
- 音频、视频应用内预览，其他文档可交由本地应用打开
- Android 图片、音频、视频和文档均从系统内容 URI 后台流式写入应用目录，附件卡片显示实时进度且不阻断文字编辑
- 标签、收藏、置顶、归档、回收站和多维排序
- 块式富文本编辑（撤销/重做、加粗、下划线、字号、三级缩进、列表与待办）、附件引用与自动保存
- SQLite 数据库、原始附件和缩略图的统一管理
- `.fknotes.zip` 完整备份、安全校验与恢复
- 可选的手动云同步，支持 S3 与 WebDAV，并在双端变更时明确提示冲突

## 技术栈

- Flutter / Dart
- Provider：应用状态管理
- SQLite（sqflite）：本地结构化数据
- Google ML Kit：设备端中文文字识别
- sherpa-onnx / SenseVoice Small INT8：设备端中文及多语种语音转写
- MNN 3.6：Android / iOS arm64 设备端文本与多模态语言模型推理；Android 使用官方 MNN Chat 0.8.3 的 Gemma 4 验证运行库
- Android 原生内容 URI 导入通道，以及 image_picker / file_selector 跨平台回退
- just_audio / video_player / record：音视频播放与录音

## 项目结构

```text
lib/
├── models/       数据模型
├── pages/        主页、编辑器、搜索、媒体详情和模型管理
├── providers/    应用状态
├── services/     数据库、文件、OCR、语音转写、模型和备份服务
└── widgets/      通用界面组件

assets/brand/     品牌图标源文件
test/             单元测试与组件测试
android/          Android 工程与发布签名配置
ios/              iOS 工程
```

本地语言模型的接口分层、构建方式、资源策略和真机验收清单见
[`docs/local-llm.md`](docs/local-llm.md)。

## 开发环境

建议准备：

- Flutter stable（项目要求 Dart `>=3.12.2 <4.0.0`）
- Android Studio、Android SDK 36 和 JDK 17
- macOS + Xcode（仅构建 iOS/macOS 时需要）
- GNU Make 或兼容的 `make` 命令

检查本机环境：

```bash
make doctor
```

## 本地运行

获取依赖并完成质量检查：

```bash
make get
make check
```

查看可用设备并运行：

```bash
make devices
make run DEVICE=<设备 ID>
```

Android 设备或模拟器也可以直接运行：

```bash
make run-android DEVICE=<设备 ID>
```

不使用 Makefile 时，对应的 Flutter 命令为：

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## 常用 Make 命令

| 命令 | 用途 |
| --- | --- |
| `make help` | 显示全部命令和可选参数 |
| `make get` | 获取 Flutter 依赖 |
| `make format` | 格式化 `lib/` 与 `test/` |
| `make analyze` | 执行静态分析 |
| `make test` | 运行全部测试 |
| `make check` | 依次格式化、分析并测试 |
| `make run DEVICE=<id>` | 在指定设备上运行 |
| `make debug` | 生成带应用名和版本号的 Android 通用 Debug APK |
| `make apk-debug-split` | 按 ABI 生成带应用名和版本号的 Debug APK |
| `make package` | 生成 Android 通用 Release APK |
| `make apk-split` | 按 ABI 生成带应用名和版本号的 Android APK |
| `make aab` | 生成 Google Play 使用的 AAB |
| `make clean` | 清理构建缓存和 `dist/` |

## Android 调试包

需要将 Debug 版本安装到模拟器或真实设备时，执行：

```bash
make debug
```

版本默认读取 `pubspec.yaml`，也可以临时覆盖：

```bash
make debug BUILD_NAME=1.0.1 BUILD_NUMBER=2
```

通用 Debug APK 产物命名为：

```text
dist/fknotes-<版本号>+<构建号>-debug.apk
```

如需按 CPU 架构分别打包：

```bash
make apk-debug-split
```

对应产物命名为：

```text
dist/fknotes-<版本号>+<构建号>-<ABI>-debug.apk
```

## Android 正式包

### 1. 配置发布签名

首次发布前，将示例配置复制为本机配置：

```bash
cp android/key.properties.example android/key.properties
```

准备发布密钥 `android/app/fknotes-release.jks`，并填写 `android/key.properties`：

```properties
storePassword=<密钥库密码>
keyPassword=<密钥密码>
keyAlias=fknotes
storeFile=fknotes-release.jks
```

`key.properties` 和密钥文件已经由 `.gitignore` 排除，不应提交或公开。请将发布密钥安全备份；后续版本必须使用同一密钥，才能覆盖安装并保留用户数据。

### 2. 设置版本

正式版本建议修改 `pubspec.yaml`：

```yaml
version: 1.0.1+2
```

- `1.0.1` 是用户看到的版本号。
- `2` 是内部构建号，每次向用户分发或上传商店时都必须递增。

也可以在构建时临时覆盖：

```bash
make apk BUILD_NAME=1.0.1 BUILD_NUMBER=2
```

### 3. 生成内测 APK

```bash
make check
make package
```

产物位于：

```text
dist/fknotes-<版本号>+<构建号>-release.apk
```

如需按 CPU 架构分别打包，执行 `make apk-split`，产物命名为：

```text
dist/fknotes-<版本号>+<构建号>-<ABI>-release.apk
```

连接真实设备后可以覆盖安装：

```bash
adb install -r dist/fknotes-1.0.1+2-release.apk
```

如果设备上安装的是 Debug 版本或其他密钥签名的版本，第一次安装正式包前需要先卸载旧版本；卸载会清除该版本的本地数据。

### 4. 生成商店包

Google Play 内部测试或正式发布使用 AAB：

```bash
make aab BUILD_NAME=1.0.1 BUILD_NUMBER=2
```

产物位于 `dist/`。AAB 不能直接安装到手机，需要上传到 Google Play Console。

## GitHub 自动发布

仓库内置了 tag 驱动的 Android 发布工作流。首次使用前，在 GitHub 仓库的
`Settings > Secrets and variables > Actions` 中添加以下 Repository secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 发布密钥库文件的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | 密钥库密码，对应 `storePassword` |
| `ANDROID_KEY_PASSWORD` | 密钥密码，对应 `keyPassword` |
| `ANDROID_KEY_ALIAS` | 密钥别名，对应 `keyAlias` |

在 macOS 上可用以下命令生成待粘贴的密钥库 Base64 文本：

```bash
base64 -i android/app/fknotes-release.jks -o /tmp/fknotes-release.jks.base64
```

配置完成后，创建并推送符合语义化版本格式的 tag：

```bash
git tag -a v1.0.1 -m "FKNotes v1.0.1"
git push origin v1.0.1
```

GitHub Actions 会执行格式检查、静态分析和测试，构建已签名的通用 APK 与
AAB，生成 SHA-256 校验文件，并创建带自动发行说明的 GitHub Release。
构建时间会同时写入应用的“关于”区域；`v1.0.1-beta.1` 一类 tag 会自动标记为预发布版本。

tag 去掉前缀 `v` 后作为 Android `versionName`，工作流运行序号作为递增的
`versionCode`，不会修改 `pubspec.yaml`。后续发布必须继续使用同一发布密钥，
否则无法覆盖安装旧版本。

## iOS 构建

先在 Xcode 中为 Runner 配置 Apple Developer Team 和签名，再执行：

```bash
make ios BUILD_NAME=1.0.1 BUILD_NUMBER=2
```

生成的 IPA 位于 Flutter 默认的 `build/ios/ipa/` 目录，可通过 TestFlight 分发测试。iOS 发布前仍需在真实设备上完整验证相机、相册、录音、文件选择和 OCR 权限流程。

## 数据与隐私

- 笔记数据库、附件和缩略图保存在系统分配的应用私有支持目录。
- 拍照和选择图片不会自动进行 OCR；只有用户主动点击“识别文字”时才会执行。
- Android 申请相机、录音和网络权限。网络仅在用户明确点击下载模型或手动云同步时使用；未配置云同步时，笔记、附件、OCR 和转写内容不会上传。
- 在线模型固定到经过校验的仓库版本，支持断点续传，并在 SHA-256 校验通过后才会启用。
- 实时听写使用 16 kHz 单声道 PCM 和本地 INT8 Zipformer；麦克风数据只传入应用内的识别 Isolate，不会作为录音附件保存或上传。
- 应用锁仅调用系统身份验证界面，应用不会读取或保存用户的指纹、人脸等生物特征。
- 离线模型保存在独立的 `models/` 目录，不会写入笔记备份；移除应用时会由系统一并清理。
- 云同步复用完整备份的数据边界，不包含模型、推理缓存、应用锁或云端账号配置。
- 默认模型来自 [ModelScope 的 sherpa 模型集合](https://modelscope.cn/models/gomodels/sherpa)。运行库与模型是独立组件，发布时应同时保留各自的许可证和来源说明。
- iOS 仅在使用相机、相册和麦克风时请求相应系统权限。
- 备份文件包含笔记数据库和附件，应像个人文档一样妥善保管。
- 恢复备份前会校验文件结构和路径，恢复失败时会尝试回滚原数据。

## 提交前检查

```bash
make check
git status --short
```

本地签名、构建产物、数据库、备份文件和开发工具缓存均应保持在 Git 忽略范围内。
