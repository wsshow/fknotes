# FKNotes 本地语言模型架构

## 目标与边界

FKNotes 的本地助手遵循以下约束：

- 笔记和提示词不上传，推理完全在用户设备上进行。
- 模型必须由用户在“本地模型”页面主动下载、导入、选择或移除。
- Dart 业务层只依赖统一接口，不直接依赖 MNN 的类或配置格式。
- 当前只维护 MNN 一个推理后端，避免同时携带多套运行库和重复维护生命周期。
- 笔记处理结果必须先预览，只有用户确认后才会作为一次可撤销编辑写入笔记。

当前产品能力包括自由多轮聊天、每个会话独立的系统提示词、会话历史，以及总结笔记、提取待办和润色内容。统一接口还保留能力声明、后端选择、流式事件、取消、指标和结束原因，可继续承载选中文本处理及图片理解等功能。

## 分层

```text
本地聊天 / 笔记助手 / 后续 AI 功能
        │
        ▼
LocalAssistantService
  资源互斥、模型选择、空闲与后台释放
        │
        ▼
LocalLlmCoordinator
  单任务状态机、切换模型、取消与卸载顺序
        │
        ▼
LocalLlmEngine（统一接口）
        │
        ▼
MnnLocalLlmEngine → FFI transport → C++ bridge → MNN 3.6.0
```

主要文件：

- `lib/models/local_llm.dart`：与引擎无关的请求、事件、能力、指标和状态模型。
- `lib/services/local_llm/local_llm_engine.dart`：推理引擎接口。
- `lib/services/local_llm/local_llm_coordinator.dart`：运行时状态与并发控制。
- `lib/services/local_llm/mnn_local_llm_engine.dart`：MNN 适配器。
- `lib/services/local_assistant_service.dart`：应用级入口与资源策略。
- `lib/services/language_model_service.dart`：模型下载、校验、安装、选择和移除。
- `lib/services/local_chat_store.dart`：SQLite 会话与消息持久化。
- `lib/services/local_chat_prompt_builder.dart`：系统提示词与最近对话上下文预算。
- `native/mnn/fknotes_mnn_bridge.cpp`：Android / iOS 共用的原生桥接层。

## 当前模型

| 模型 | 下载量 | 建议设备内存 | 定位 |
| --- | ---: | ---: | --- |
| MiniCPM5 1B MNN INT4 | 约 597 MB | 4 GB 及以上 | 更小、更适合轻量设备 |
| Qwen3.5 2B MNN INT4 | 约 1.3 GB | 6 GB 及以上 | 默认选择，文本质量优先 |

模型仓库和 revision 均固定，所有文件也固定长度与 SHA-256。下载优先使用 Hugging Face 国内镜像，失败后回退到 Hugging Face 官方源；中断后按文件续传，只有完整校验通过才会原子切换为可用版本。

Qwen3.5 模型包虽然包含视觉模型文件，但当前产品入口只启用文本生成。不要在没有完成图片预处理、内存预算和真机验证之前宣称支持图片理解。

## 运行与资源策略

- 目前仅支持 Android arm64 和 iOS arm64 真机；其他平台由运行时探测明确返回不支持。
- 默认使用 CPU、4096 token 上下文、关闭思考模式，并限制为 2 到 4 个线程。
- 笔记提示词和聊天历史按移动端上下文保守截断；聊天优先保留系统提示词与最近消息。
- 同一时间只允许一个生成任务；切换模型时先卸载旧模型。
- 本地助手与实时听写、后台音频转写、笔记朗读互斥，避免多个重计算任务争抢内存和 CPU。
- 生成结束后保留模型 2 分钟以便重试，随后自动卸载；应用进入后台或收到内存压力时立即卸载。
- 用户可停止生成。取消或超时的结果只能复制或重试，不能直接插入笔记。
- `<think>` 推理片段在进入界面和编辑器前会被过滤。
- 模型生成的附件标记会转成普通文字，不能伪造本地文件引用。
- 聊天会话、消息与系统提示词保存在 SQLite，并进入用户备份；模型文件和推理缓存不计入“资料占用”。

MNN 3.6.0 的采样配置在模型加载时生效。当前产品固定使用 `temperature=0.7`、`topP=0.95`、`topK=40`；统一接口保留这些字段，但 MNN 适配器会明确拒绝非默认值，避免界面声称参数生效而原生层实际忽略。

## 原生运行库

`tool/prepare_mnn_runtime.sh` 固定下载 MNN 3.6.0 官方 Android 和 iOS 运行库，并在解压前校验 SHA-256。运行库只进入构建缓存，不提交到 Git。

Android Gradle / CMake 和 iOS Xcode 构建已接入该脚本。首次构建需要联网下载固定运行库；后续构建命中校验通过的缓存。更新 MNN 时必须同时完成：

1. 修改固定版本和两个平台压缩包的 SHA-256。
2. 验证 C++ bridge 对新头文件和 ABI 的兼容性。
3. 运行全量测试并重新构建 Android release。
4. 分别在 Android arm64 与 iOS arm64 真机完成下方验收。

## 验证

提交前至少执行：

```bash
flutter analyze
flutter test
flutter build apk --release
```

原生库和 Dart 单元测试不能替代真机推理。发布前需要在每个支持的平台完成：

1. 下载 MiniCPM5，验证暂停、续传、校验、选择和移除。
2. 首次加载后分别运行自由聊天、总结、待办和润色，记录首 token 时间与生成速度。
3. 生成中停止，确认不再追加 token 且部分内容不能直接插入。
4. 生成完成后插入，确认结果位于笔记末尾且一次撤销可以完整移除。
5. 切换到 Qwen3.5 后重复生成，确认旧模型已释放。
6. 在生成过程中切到后台，确认任务停止且模型内存被回收。
7. 分别启动听写、音频转写和朗读，确认助手给出清晰的资源冲突提示。
8. 连续执行三次生成，观察峰值内存、温度、耗电和系统是否发生低内存终止。
9. 新建两个使用不同系统提示词的对话，重启应用后确认角色设定和消息历史分别恢复。
