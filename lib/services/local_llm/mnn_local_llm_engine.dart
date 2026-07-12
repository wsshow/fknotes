import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/local_llm.dart';
import 'local_llm_engine.dart';
import 'mnn_native_transport.dart';

class MnnLocalLlmEngine implements LocalLlmEngine {
  final MnnNativeTransport _transport;
  final Future<Directory> Function() _supportDirectoryProvider;
  int _nextRequestId = 1;
  LocalLlmEngineState _state = LocalLlmEngineState.idle;
  LocalLlmModelDescriptor? _loadedModel;
  int? _activeGenerationRequestId;
  Completer<void>? _activeGenerationDone;

  MnnLocalLlmEngine({
    MnnNativeTransport? transport,
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _transport = transport ?? FfiMnnNativeTransport(),
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  @override
  String get id => 'mnn';

  @override
  LocalLlmModelDescriptor? get loadedModel => _loadedModel;

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
    final requestId = _newRequestId();
    try {
      await _runOperation(
        requestId: requestId,
        successType: MnnNativeEventType.loaded,
        start: () => _transport.load(
          requestId: requestId,
          configPath: model.configPath,
          cachePath: cache.path,
          options: options,
        ),
      );
      _loadedModel = model;
      _state = LocalLlmEngineState.ready;
    } catch (_) {
      _state = LocalLlmEngineState.failed;
      rethrow;
    }
  }

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
      if (!_transport.generate(requestId: requestId, request: request)) {
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
      _state = LocalLlmEngineState.idle;
    } catch (_) {
      _state = LocalLlmEngineState.failed;
      rethrow;
    }
  }

  Future<void> _runOperation({
    required int requestId,
    required MnnNativeEventType successType,
    required bool Function() start,
  }) async {
    final completer = Completer<void>();
    late final StreamSubscription<MnnNativeEvent> subscription;
    subscription = _transport.events
        .where((event) => event.requestId == requestId)
        .listen((event) {
          if (event.type == successType) {
            if (!completer.isCompleted) completer.complete();
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
      await completer.future;
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
        ),
      );
    } catch (_) {
      return const LocalLlmGenerationCompleted(
        reason: LocalLlmFinishReason.completed,
      );
    }
  }

  int _newRequestId() => _nextRequestId++;

  String _unsupportedReason() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return 'MNN 本地语言模型当前仅支持 Android 和 iOS';
    }
    return 'MNN 本地语言模型需要 arm64 设备';
  }
}
