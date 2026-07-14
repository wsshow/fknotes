import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../debug/app_diagnostics.dart';
import '../../models/local_llm.dart';
import '../file_storage_service.dart';
import 'litert_lm_transport.dart';
import 'local_llm_engine.dart';

class LiteRtLmEngine implements LocalLlmEngine, LocalLlmRuntimeBackendProvider {
  final LiteRtLmTransport _transport;
  final String Function(String relativePath) _attachmentPathResolver;
  int _nextRequestId = 1;
  LocalLlmEngineState _state = LocalLlmEngineState.idle;
  LocalLlmModelDescriptor? _loadedModel;
  LocalLlmBackend? _activeBackend;
  int? _activeRequestId;
  Completer<void>? _activeDone;
  bool _timedOut = false;

  LiteRtLmEngine({
    LiteRtLmTransport? transport,
    String Function(String relativePath)? attachmentPathResolver,
  }) : _transport = transport ?? MethodChannelLiteRtLmTransport(),
       _attachmentPathResolver =
           attachmentPathResolver ?? FileStorageService.instance.absolutePath;

  @override
  String get id => 'litert_lm';

  @override
  LocalLlmEngineState get state => _state;

  @override
  LocalLlmModelDescriptor? get loadedModel => _loadedModel;

  @override
  LocalLlmBackend? get activeBackend => _activeBackend;

  @override
  Future<LocalLlmEngineAvailability> probe() async =>
      LocalLlmEngineAvailability(
        supported: _transport.available,
        engine: 'LiteRT-LM',
        version: _transport.version,
        unavailableReason: _transport.available
            ? null
            : 'LiteRT-LM 当前仅支持 Android arm64 设备',
        capabilities: const LocalLlmCapabilities(
          imageInput: true,
          audioInput: true,
          backends: {LocalLlmBackend.cpu, LocalLlmBackend.openCl},
        ),
      );

  @override
  Future<void> loadModel(
    LocalLlmModelDescriptor model, {
    LocalLlmLoadOptions options = const LocalLlmLoadOptions(),
  }) async {
    if (model.engine != LocalLlmEngineKind.liteRtLm) {
      throw const LocalLlmException('该模型不是 LiteRT-LM 模型');
    }
    if (!_transport.available) {
      throw const LocalLlmException('LiteRT-LM 当前仅支持 Android arm64 设备');
    }
    if (options.contextTokens > model.nativeContextTokens) {
      throw LocalLlmException(
        '上下文长度 ${options.contextTokens} 超过模型上限 ${model.nativeContextTokens}',
      );
    }
    if (!await FileSystemEntity.isFile(model.configPath)) {
      throw const LocalLlmException('LiteRT-LM 模型文件不存在或已被移除');
    }
    if (options.enableImageInput && !model.capabilities.imageInput) {
      throw const LocalLlmException('当前 LiteRT-LM 模型不支持图片输入');
    }
    if (options.enableAudioInput && !model.capabilities.audioInput) {
      throw const LocalLlmException('当前 LiteRT-LM 模型不支持音频输入');
    }
    _state = LocalLlmEngineState.loading;
    _activeBackend = null;
    try {
      try {
        _activeBackend = await _load(model, options);
      } catch (error) {
        if (options.backend == LocalLlmBackend.cpu) rethrow;
        if (kDebugMode) {
          AppDiagnostics.warning(
            AppLogCategory.inference,
            'litert_cpu_fallback_started',
            data: {
              'modelId': model.id,
              'reason': error is _LiteRtLmWorkerDiedException
                  ? 'workerDied'
                  : 'gpuInitializationFailed',
            },
            traceId: model.id,
          );
        }
        if (error is _LiteRtLmWorkerDiedException) {
          // Let Android fully reap the failed GPU worker before binding a clean
          // CPU-only process. The worker boundary keeps the Flutter UI safe.
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        _activeBackend = await _load(
          model,
          LocalLlmLoadOptions(
            backend: LocalLlmBackend.cpu,
            threads: options.threads,
            contextTokens: options.contextTokens,
            enableThinking: options.enableThinking,
            enablePromptCache: options.enablePromptCache,
            enableImageInput: options.enableImageInput,
            enableAudioInput: options.enableAudioInput,
          ),
        );
      }
      _loadedModel = model;
      _state = LocalLlmEngineState.ready;
    } catch (_) {
      _activeBackend = null;
      _state = LocalLlmEngineState.failed;
      rethrow;
    }
  }

  Future<LocalLlmBackend> _load(
    LocalLlmModelDescriptor model,
    LocalLlmLoadOptions options,
  ) async {
    final requestId = _newRequestId();
    final backendName = await _runOperation(
      requestId: requestId,
      successType: LiteRtLmNativeEventType.loaded,
      start: () => _transport.load(
        requestId: requestId,
        modelPath: model.configPath,
        options: options,
      ),
    );
    return switch (backendName) {
      'cpu' => LocalLlmBackend.cpu,
      'gpu' => LocalLlmBackend.openCl,
      _ => options.backend,
    };
  }

  @override
  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request) {
    late StreamController<LocalLlmGenerationEvent> controller;
    StreamSubscription<LiteRtLmNativeEvent>? subscription;
    Timer? timeout;

    Future<void> start() async {
      if (_state != LocalLlmEngineState.ready || _loadedModel == null) {
        controller.addError(const LocalLlmException('LiteRT-LM 模型尚未加载'));
        await controller.close();
        return;
      }
      late final LocalLlmGenerationRequest prepared;
      try {
        prepared = await _prepareRequest(request, _loadedModel!);
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        await controller.close();
        return;
      }
      final requestId = _newRequestId();
      final done = Completer<void>();
      _activeRequestId = requestId;
      _activeDone = done;
      _timedOut = false;
      _state = LocalLlmEngineState.generating;
      subscription = _transport.events
          .where(
            (event) =>
                event.requestId == requestId ||
                event.type == LiteRtLmNativeEventType.serviceDied,
          )
          .listen((event) {
            switch (event.type) {
              case LiteRtLmNativeEventType.textDelta:
                if (!controller.isClosed && event.data.isNotEmpty) {
                  controller.add(LocalLlmTextDelta(event.data));
                }
              case LiteRtLmNativeEventType.completed:
                if (!controller.isClosed) {
                  controller.add(_completed(event.data));
                }
                unawaited(_finish(controller, subscription, done, timeout));
              case LiteRtLmNativeEventType.canceled:
                if (!controller.isClosed) {
                  controller.add(
                    LocalLlmGenerationCompleted(
                      reason: _timedOut
                          ? LocalLlmFinishReason.timeout
                          : LocalLlmFinishReason.canceled,
                    ),
                  );
                }
                unawaited(_finish(controller, subscription, done, timeout));
              case LiteRtLmNativeEventType.error ||
                  LiteRtLmNativeEventType.serviceDied:
                _state = LocalLlmEngineState.failed;
                if (!controller.isClosed) {
                  controller.addError(
                    LocalLlmException(
                      event.data.isEmpty ? 'LiteRT-LM 推理进程意外终止' : event.data,
                    ),
                  );
                }
                unawaited(_finish(controller, subscription, done, timeout));
              case LiteRtLmNativeEventType.loaded ||
                  LiteRtLmNativeEventType.unloaded:
                break;
            }
          });
      timeout = Timer(prepared.options.timeout, () {
        _timedOut = true;
        unawaited(_transport.cancel(requestId));
      });
      if (!await _transport.generate(requestId: requestId, request: prepared)) {
        timeout?.cancel();
        controller.addError(const LocalLlmException('LiteRT-LM 当前无法开始生成任务'));
        await _finish(controller, subscription, done, timeout);
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
    final requestId = _activeRequestId;
    final done = _activeDone;
    if (requestId == null || done == null) return;
    _state = LocalLlmEngineState.canceling;
    await _transport.cancel(requestId);
    await done.future;
  }

  @override
  Future<void> unload() async {
    if (_activeDone != null) await cancel();
    if (_loadedModel == null && _state == LocalLlmEngineState.idle) return;
    _state = LocalLlmEngineState.unloading;
    final requestId = _newRequestId();
    try {
      await _runOperation(
        requestId: requestId,
        successType: LiteRtLmNativeEventType.unloaded,
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
    required LiteRtLmNativeEventType successType,
    required Future<bool> Function() start,
  }) async {
    final completer = Completer<_LiteRtLmOperationResult>();
    _LiteRtLmOperationResult? observedResult;
    late final StreamSubscription<LiteRtLmNativeEvent> subscription;
    subscription = _transport.events.listen((event) {
      if (event.requestId == requestId && event.type == successType) {
        final result = _LiteRtLmOperationResult.success(event.data);
        observedResult = result;
        if (!completer.isCompleted) completer.complete(result);
      } else if ((event.requestId == requestId &&
              event.type == LiteRtLmNativeEventType.error) ||
          event.type == LiteRtLmNativeEventType.serviceDied) {
        final result = _LiteRtLmOperationResult.failure(
          event.data.isEmpty ? 'LiteRT-LM 操作失败' : event.data,
          workerDied: event.type == LiteRtLmNativeEventType.serviceDied,
        );
        observedResult = result;
        if (!completer.isCompleted) {
          // Complete with a value, not an asynchronous error. The native event
          // can arrive while the MethodChannel invocation is still pending; an
          // error future without a listener would otherwise escape to the root
          // zone and be reported as a second, unrelated fatal Dart exception.
          completer.complete(result);
        }
      }
    });
    try {
      final accepted = await start();
      if (!accepted) {
        // Give a queued service-death event one turn to reach the listener so
        // the caller receives the real failure instead of a generic IPC error.
        await Future<void>.delayed(Duration.zero);
        _throwIfFailed(observedResult);
        throw const LocalLlmException('无法连接 LiteRT-LM 推理进程');
      }
      final result = await completer.future.timeout(const Duration(minutes: 2));
      _throwIfFailed(result);
      return result.data;
    } finally {
      await subscription.cancel();
    }
  }

  void _throwIfFailed(_LiteRtLmOperationResult? result) {
    if (result?.success == true) return;
    if (result?.workerDied == true) {
      throw _LiteRtLmWorkerDiedException(result!.message);
    }
    if (result != null) throw LocalLlmException(result.message);
    throw const LocalLlmException('无法连接 LiteRT-LM 推理进程');
  }

  Future<void> _finish(
    StreamController<LocalLlmGenerationEvent> controller,
    StreamSubscription<LiteRtLmNativeEvent>? subscription,
    Completer<void> done,
    Timer? timeout,
  ) async {
    timeout?.cancel();
    await subscription?.cancel();
    if (!done.isCompleted) done.complete();
    if (identical(_activeDone, done)) {
      _activeDone = null;
      _activeRequestId = null;
      if (_state != LocalLlmEngineState.failed) {
        _state = LocalLlmEngineState.ready;
      }
    }
    if (!controller.isClosed) await controller.close();
  }

  LocalLlmGenerationCompleted _completed(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final prefillRate =
          (json['prefillTokensPerSecond'] as num?)?.toDouble() ?? 0;
      final decodeRate =
          (json['decodeTokensPerSecond'] as num?)?.toDouble() ?? 0;
      final promptTokens = (json['promptTokens'] as num?)?.toInt() ?? 0;
      final generatedTokens = (json['generatedTokens'] as num?)?.toInt() ?? 0;
      return LocalLlmGenerationCompleted(
        reason: LocalLlmFinishReason.completed,
        metrics: LocalLlmGenerationMetrics(
          promptTokens: promptTokens,
          generatedTokens: generatedTokens,
          prefillTime: prefillRate > 0
              ? Duration(
                  microseconds:
                      (promptTokens *
                              Duration.microsecondsPerSecond /
                              prefillRate)
                          .round(),
                )
              : Duration.zero,
          decodeTime: decodeRate > 0
              ? Duration(
                  microseconds:
                      (generatedTokens *
                              Duration.microsecondsPerSecond /
                              decodeRate)
                          .round(),
                )
              : Duration.zero,
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
        switch (attachment.kind) {
          case LocalLlmAttachmentKind.image:
            if (!model.capabilities.imageInput) {
              throw LocalLlmException('${model.name} 不支持图片输入');
            }
            if (++imageCount > 4) {
              throw const LocalLlmException('每次最多可以发送 4 张图片');
            }
          case LocalLlmAttachmentKind.audio:
            if (!model.capabilities.audioInput) {
              throw LocalLlmException('${model.name} 不支持音频理解');
            }
            if (++audioCount > 1) {
              throw const LocalLlmException('每次最多可以发送 1 个音频文件');
            }
          case LocalLlmAttachmentKind.unsupported:
            throw LocalLlmException('不支持的附件类型：${attachment.mimeType}');
        }
        final absolutePath = p.isAbsolute(attachment.path)
            ? attachment.path
            : _attachmentPathResolver(attachment.path);
        final file = File(absolutePath);
        if (await FileSystemEntity.type(absolutePath, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const LocalLlmException('多模态附件不存在或不是普通文件');
        }
        final length = await file.length();
        final limit = attachment.kind == LocalLlmAttachmentKind.image
            ? 20 * 1024 * 1024
            : 100 * 1024 * 1024;
        if (length <= 0 || length > limit) {
          throw const LocalLlmException('多模态附件为空或超过大小限制');
        }
        attachments.add(
          LocalLlmAttachment(
            path: absolutePath,
            mimeType: attachment.mimeType.trim().toLowerCase(),
          ),
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

  int _newRequestId() => _nextRequestId++;
}

class _LiteRtLmOperationResult {
  final bool success;
  final bool workerDied;
  final String message;
  final String data;

  const _LiteRtLmOperationResult.success(this.data)
    : success = true,
      workerDied = false,
      message = '';

  const _LiteRtLmOperationResult.failure(
    this.message, {
    required this.workerDied,
  }) : success = false,
       data = '';
}

class _LiteRtLmWorkerDiedException extends LocalLlmException {
  const _LiteRtLmWorkerDiedException(Object cause)
    : super(
        'LiteRT-LM 在当前设备上加载模型时异常终止；这通常是系统或推理运行库兼容性问题，请导出 Debug 诊断包',
        cause: cause,
      );
}
