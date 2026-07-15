import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../debug/app_diagnostics.dart';
import '../../models/local_llm.dart';
import '../file_storage_service.dart';
import 'local_llm_engine.dart';
import 'mnn_native_transport.dart';

class MnnMultimodalLimits {
  static const maxImages = 4;
  static const maxAudioFiles = 1;
  static const maxImageBytes = 20 * 1024 * 1024;
  static const maxAudioBytes = 100 * 1024 * 1024;

  const MnnMultimodalLimits._();
}

class MnnLocalLlmEngine
    implements
        LocalLlmEngine,
        LocalLlmRuntimeBackendProvider,
        LocalLlmRuntimeProgressProvider {
  final MnnNativeTransport _transport;
  final Future<Directory> Function() _supportDirectoryProvider;
  final String Function(String relativePath) _attachmentPathResolver;
  final Duration _operationTimeout;
  final _runtimeProgresses =
      StreamController<LocalLlmRuntimeProgress>.broadcast();
  int _nextRequestId = 1;
  LocalLlmEngineState _state = LocalLlmEngineState.idle;
  LocalLlmModelDescriptor? _loadedModel;
  LocalLlmBackend? _activeBackend;
  LocalLlmRuntimeProgress? _runtimeProgress;
  int? _activeGenerationRequestId;
  Completer<void>? _activeGenerationDone;

  MnnLocalLlmEngine({
    MnnNativeTransport? transport,
    Future<Directory> Function()? supportDirectoryProvider,
    String Function(String relativePath)? attachmentPathResolver,
    Duration? operationTimeout,
  }) : _transport = transport ?? FfiMnnNativeTransport(),
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _attachmentPathResolver =
           attachmentPathResolver ?? FileStorageService.instance.absolutePath,
       _operationTimeout = operationTimeout ?? const Duration(minutes: 2);

  @override
  String get id => 'mnn';

  @override
  LocalLlmModelDescriptor? get loadedModel => _loadedModel;

  @override
  LocalLlmBackend? get activeBackend => _activeBackend;

  @override
  LocalLlmRuntimeProgress? get runtimeProgress => _runtimeProgress;

  @override
  Stream<LocalLlmRuntimeProgress> get runtimeProgresses =>
      _runtimeProgresses.stream;

  @override
  LocalLlmEngineState get state => _state;

  @override
  Future<LocalLlmEngineAvailability> probe() async {
    final supported = _transport.available;
    return LocalLlmEngineAvailability(
      supported: supported,
      engine: 'MNN',
      version: _transport.version,
      unavailableReason: supported ? null : _unsupportedReason(),
      capabilities: LocalLlmCapabilities(
        thinking: true,
        toolCalling: true,
        imageInput: true,
        audioInput: true,
        backends: Platform.isAndroid
            ? const {
                LocalLlmBackend.cpu,
                LocalLlmBackend.openCl,
                LocalLlmBackend.vulkan,
              }
            : Platform.isIOS
            ? const {LocalLlmBackend.cpu, LocalLlmBackend.metal}
            : const {},
      ),
    );
  }

  @override
  Future<void> loadModel(
    LocalLlmModelDescriptor model, {
    LocalLlmLoadOptions options = const LocalLlmLoadOptions(),
  }) async {
    if (!_transport.available) {
      throw LocalLlmException(_unsupportedReason());
    }
    if (_state == LocalLlmEngineState.generating ||
        _state == LocalLlmEngineState.canceling) {
      throw const LocalLlmException('正在生成内容，无法加载模型');
    }
    if (options.contextTokens > model.nativeContextTokens) {
      throw LocalLlmException(
        '上下文长度 ${options.contextTokens} 超过模型上限 ${model.nativeContextTokens}',
      );
    }
    final config = File(model.configPath);
    if (!await FileSystemEntity.isFile(config.path)) {
      throw const LocalLlmException('模型配置文件不存在或已被移除');
    }
    final support = await _supportDirectoryProvider();
    final cache = Directory(p.join(support.path, 'mnn-cache', model.id));
    await cache.create(recursive: true);

    _state = LocalLlmEngineState.loading;
    _activeBackend = null;
    _reportRuntimeProgress(
      LocalLlmRuntimeProgress(
        kind: LocalLlmRuntimeProgressKind.starting,
        backend: options.backend,
      ),
    );
    try {
      final candidates = _backendCandidates(options.backend);
      Object? lastError;
      StackTrace? lastStackTrace;
      for (var index = 0; index < candidates.length; index++) {
        final backend = candidates[index];
        try {
          _activeBackend = await _load(
            model,
            cache.path,
            _optionsForBackend(options, backend),
          );
          break;
        } catch (error, stackTrace) {
          lastError = error;
          lastStackTrace = stackTrace;
          if (index + 1 >= candidates.length) break;
          _reportRuntimeProgress(
            LocalLlmRuntimeProgress(
              kind: LocalLlmRuntimeProgressKind.switching,
              backend: candidates[index + 1],
              previousBackend: backend,
            ),
          );
          if (kDebugMode) {
            AppDiagnostics.warning(
              AppLogCategory.inference,
              'mnn_backend_fallback_started',
              data: {
                'modelId': model.id,
                'fromBackend': backend.name,
                'toBackend': candidates[index + 1].name,
                'reason': error.toString(),
              },
              traceId: model.id,
            );
          }
        }
      }
      if (_activeBackend == null) {
        Error.throwWithStackTrace(
          lastError ?? const LocalLlmException('MNN 没有可用的推理后端'),
          lastStackTrace ?? StackTrace.current,
        );
      }
      _loadedModel = model;
      _state = LocalLlmEngineState.ready;
      _clearRuntimeProgress();
    } catch (_) {
      _activeBackend = null;
      _state = LocalLlmEngineState.failed;
      _clearRuntimeProgress();
      rethrow;
    }
  }

  Future<LocalLlmBackend> _load(
    LocalLlmModelDescriptor model,
    String cachePath,
    LocalLlmLoadOptions options,
  ) async {
    final requestId = _newRequestId();
    final backendName = await _runOperation(
      requestId: requestId,
      successType: MnnNativeEventType.loaded,
      start: () => _transport.load(
        requestId: requestId,
        configPath: model.configPath,
        cachePath: cachePath,
        options: options,
      ),
    );
    return switch (backendName) {
      'cpu' => LocalLlmBackend.cpu,
      'opencl' => LocalLlmBackend.openCl,
      'vulkan' => LocalLlmBackend.vulkan,
      'metal' => LocalLlmBackend.metal,
      _ => options.backend,
    };
  }

  List<LocalLlmBackend> _backendCandidates(LocalLlmBackend requested) =>
      switch (requested) {
        LocalLlmBackend.cpu => const [LocalLlmBackend.cpu],
        LocalLlmBackend.openCl => const [
          LocalLlmBackend.openCl,
          LocalLlmBackend.vulkan,
          LocalLlmBackend.cpu,
        ],
        LocalLlmBackend.vulkan => const [
          LocalLlmBackend.vulkan,
          LocalLlmBackend.openCl,
          LocalLlmBackend.cpu,
        ],
        LocalLlmBackend.metal => const [
          LocalLlmBackend.metal,
          LocalLlmBackend.cpu,
        ],
      };

  LocalLlmLoadOptions _optionsForBackend(
    LocalLlmLoadOptions options,
    LocalLlmBackend backend,
  ) => LocalLlmLoadOptions(
    backend: backend,
    threads: options.threads,
    contextTokens: options.contextTokens,
    enableThinking: options.enableThinking,
    enablePromptCache: options.enablePromptCache,
    enableImageInput: options.enableImageInput,
    enableAudioInput: options.enableAudioInput,
  );

  void _reportRuntimeProgress(LocalLlmRuntimeProgress progress) {
    _runtimeProgress = progress;
    if (!_runtimeProgresses.isClosed) _runtimeProgresses.add(progress);
  }

  void _clearRuntimeProgress() => _runtimeProgress = null;

  @override
  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request) {
    late StreamController<LocalLlmGenerationEvent> controller;
    StreamSubscription<MnnNativeEvent>? subscription;
    var started = false;

    Future<void> start() async {
      if (started) return;
      started = true;
      if (_state != LocalLlmEngineState.ready || _loadedModel == null) {
        controller.addError(const LocalLlmException('MNN 模型尚未加载'));
        await controller.close();
        return;
      }
      const defaults = LocalLlmGenerationOptions();
      if (request.options.temperature != defaults.temperature ||
          request.options.topP != defaults.topP ||
          request.options.topK != defaults.topK) {
        controller.addError(const LocalLlmException('当前版本的 MNN 引擎仅支持默认采样参数'));
        await controller.close();
        return;
      }
      late final LocalLlmGenerationRequest preparedRequest;
      try {
        preparedRequest = await _prepareRequest(request, _loadedModel!);
      } on Object catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        await controller.close();
        return;
      }
      final requestId = _newRequestId();
      final done = Completer<void>();
      _activeGenerationRequestId = requestId;
      _activeGenerationDone = done;
      _state = LocalLlmEngineState.generating;
      subscription = _transport.events
          .where((event) => event.requestId == requestId)
          .listen((event) {
            switch (event.type) {
              case MnnNativeEventType.textDelta:
                if (!controller.isClosed && event.data.isNotEmpty) {
                  controller.add(LocalLlmTextDelta(event.data));
                }
              case MnnNativeEventType.completed:
                if (!controller.isClosed) {
                  controller.add(_completedEvent(event.data));
                }
                unawaited(_finishGeneration(controller, subscription, done));
              case MnnNativeEventType.canceled:
                if (!controller.isClosed) {
                  controller.add(
                    const LocalLlmGenerationCompleted(
                      reason: LocalLlmFinishReason.canceled,
                    ),
                  );
                }
                unawaited(_finishGeneration(controller, subscription, done));
              case MnnNativeEventType.error:
                if (!controller.isClosed) {
                  controller.addError(
                    LocalLlmException(
                      event.data.isEmpty ? 'MNN 推理失败' : event.data,
                    ),
                  );
                }
                _state = LocalLlmEngineState.failed;
                unawaited(_finishGeneration(controller, subscription, done));
              case MnnNativeEventType.loaded || MnnNativeEventType.unloaded:
                break;
            }
          });
      if (!_transport.generate(
        requestId: requestId,
        request: preparedRequest,
      )) {
        controller.addError(const LocalLlmException('MNN 当前无法开始新的生成任务'));
        await _finishGeneration(controller, subscription, done);
      }
    }

    controller = StreamController<LocalLlmGenerationEvent>(
      onListen: start,
      onCancel: cancel,
    );
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    final requestId = _activeGenerationRequestId;
    final done = _activeGenerationDone;
    if (requestId == null || done == null) return;
    _state = LocalLlmEngineState.canceling;
    _transport.cancel(requestId);
    await done.future;
  }

  @override
  Future<void> unload() async {
    if (_activeGenerationDone != null) await cancel();
    if (_loadedModel == null && _state == LocalLlmEngineState.idle) return;
    _state = LocalLlmEngineState.unloading;
    final requestId = _newRequestId();
    try {
      await _runOperation(
        requestId: requestId,
        successType: MnnNativeEventType.unloaded,
        start: () => _transport.unload(requestId),
      );
      _loadedModel = null;
      _activeBackend = null;
      _state = LocalLlmEngineState.idle;
    } catch (_) {
      _activeBackend = null;
      _state = LocalLlmEngineState.failed;
      rethrow;
    }
  }

  Future<String> _runOperation({
    required int requestId,
    required MnnNativeEventType successType,
    required bool Function() start,
  }) async {
    final completer = Completer<String>();
    late final StreamSubscription<MnnNativeEvent> subscription;
    subscription = _transport.events
        .where((event) => event.requestId == requestId)
        .listen((event) {
          if (event.type == successType) {
            if (!completer.isCompleted) completer.complete(event.data);
          } else if (event.type == MnnNativeEventType.error) {
            if (!completer.isCompleted) {
              completer.completeError(
                LocalLlmException(event.data.isEmpty ? 'MNN 操作失败' : event.data),
              );
            }
          }
        });
    if (!start()) {
      await subscription.cancel();
      throw const LocalLlmException('MNN 正在执行其他任务');
    }
    try {
      return await completer.future.timeout(
        _operationTimeout,
        onTimeout: () => throw const LocalLlmException('MNN 操作超时，请重试'),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _finishGeneration(
    StreamController<LocalLlmGenerationEvent> controller,
    StreamSubscription<MnnNativeEvent>? subscription,
    Completer<void> done,
  ) async {
    await subscription?.cancel();
    if (!done.isCompleted) done.complete();
    if (identical(_activeGenerationDone, done)) {
      _activeGenerationDone = null;
      _activeGenerationRequestId = null;
      if (_state != LocalLlmEngineState.failed) {
        _state = LocalLlmEngineState.ready;
      }
    }
    if (!controller.isClosed) await controller.close();
  }

  LocalLlmGenerationCompleted _completedEvent(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final reason = switch (json['reason']) {
        'completed' => LocalLlmFinishReason.completed,
        'timeout' => LocalLlmFinishReason.timeout,
        _ => LocalLlmFinishReason.maxTokens,
      };
      return LocalLlmGenerationCompleted(
        reason: reason,
        metrics: LocalLlmGenerationMetrics(
          promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
          generatedTokens: (json['generatedTokens'] as num?)?.toInt() ?? 0,
          loadTime: Duration(
            microseconds: (json['loadUs'] as num?)?.toInt() ?? 0,
          ),
          prefillTime: Duration(
            microseconds: (json['prefillUs'] as num?)?.toInt() ?? 0,
          ),
          decodeTime: Duration(
            microseconds: (json['decodeUs'] as num?)?.toInt() ?? 0,
          ),
          visionTime: Duration(
            microseconds: (json['visionUs'] as num?)?.toInt() ?? 0,
          ),
          audioTime: Duration(
            microseconds: (json['audioUs'] as num?)?.toInt() ?? 0,
          ),
          imageMegapixels: (json['imageMegapixels'] as num?)?.toDouble() ?? 0,
          audioInputSeconds:
              (json['audioInputSeconds'] as num?)?.toDouble() ?? 0,
        ),
      );
    } catch (_) {
      return const LocalLlmGenerationCompleted(
        reason: LocalLlmFinishReason.completed,
      );
    }
  }

  Future<LocalLlmGenerationRequest> _prepareRequest(
    LocalLlmGenerationRequest request,
    LocalLlmModelDescriptor model,
  ) async {
    var imageCount = 0;
    var audioCount = 0;
    final messages = <LocalLlmMessage>[];
    for (final message in request.messages) {
      if (message.attachments.isNotEmpty && message.role != LocalLlmRole.user) {
        throw const LocalLlmException('多模态附件只能附加在用户消息中');
      }
      final attachments = <LocalLlmAttachment>[];
      for (final attachment in message.attachments) {
        final kind = attachment.kind;
        switch (kind) {
          case LocalLlmAttachmentKind.image:
            if (!model.capabilities.imageInput) {
              throw LocalLlmException('${model.name} 不支持图片输入');
            }
            imageCount++;
            if (imageCount > MnnMultimodalLimits.maxImages) {
              throw const LocalLlmException('每次最多可以发送 4 张图片');
            }
          case LocalLlmAttachmentKind.audio:
            if (!model.capabilities.audioInput) {
              throw LocalLlmException('${model.name} 不支持音频理解');
            }
            audioCount++;
            if (audioCount > MnnMultimodalLimits.maxAudioFiles) {
              throw const LocalLlmException('每次最多可以发送 1 个音频文件');
            }
          case LocalLlmAttachmentKind.unsupported:
            throw LocalLlmException('不支持的多模态附件类型：${attachment.mimeType}');
        }
        final mimeType = attachment.mimeType.trim().toLowerCase();
        if (kind == LocalLlmAttachmentKind.image &&
            !_supportedImageMimeTypes.contains(mimeType)) {
          throw LocalLlmException('暂不支持这种图片格式：${attachment.mimeType}');
        }
        if (kind == LocalLlmAttachmentKind.audio &&
            !_supportedAudioMimeTypes.contains(mimeType)) {
          throw const LocalLlmException('音频理解目前仅支持 WAV 文件');
        }
        late final String absolutePath;
        try {
          absolutePath = _attachmentPathResolver(attachment.path);
        } on FormatException catch (error) {
          throw LocalLlmException('多模态附件路径不安全', cause: error);
        }
        final file = File(absolutePath);
        if (await FileSystemEntity.type(absolutePath, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const LocalLlmException('多模态附件不存在或不是普通文件');
        }
        final length = await file.length();
        final limit = kind == LocalLlmAttachmentKind.image
            ? MnnMultimodalLimits.maxImageBytes
            : MnnMultimodalLimits.maxAudioBytes;
        if (length <= 0 || length > limit) {
          throw LocalLlmException(
            kind == LocalLlmAttachmentKind.image
                ? '图片文件为空或超过 20 MB'
                : '音频文件为空或超过 100 MB',
          );
        }
        attachments.add(
          LocalLlmAttachment(path: absolutePath, mimeType: mimeType),
        );
      }
      messages.add(
        LocalLlmMessage(
          role: message.role,
          content: message.content,
          attachments: attachments,
        ),
      );
    }
    return LocalLlmGenerationRequest(
      messages: messages,
      options: LocalLlmGenerationOptions(
        maxNewTokens: request.options.maxNewTokens,
        temperature: model.generationOptions.temperature,
        topP: model.generationOptions.topP,
        topK: model.generationOptions.topK,
        timeout: request.options.timeout,
      ),
    );
  }

  static const _supportedImageMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/bmp',
  };
  static const _supportedAudioMimeTypes = {'audio/wav', 'audio/x-wav'};

  int _newRequestId() => _nextRequestId++;

  String _unsupportedReason() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return 'MNN 本地语言模型当前仅支持 Android 和 iOS';
    }
    return 'MNN 本地语言模型需要 arm64 设备';
  }
}
