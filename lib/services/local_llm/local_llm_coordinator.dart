import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../debug/app_diagnostics.dart';
import '../../models/local_llm.dart';
import 'local_llm_engine.dart';

/// Owns the single local-LLM runtime and enforces its memory lifecycle.
///
/// The application talks to this coordinator instead of a concrete inference
/// framework. Only one model and one generation may be active at a time.
class LocalLlmCoordinator {
  final LocalLlmEngine _engine;
  final _snapshots = StreamController<LocalLlmRuntimeSnapshot>.broadcast();

  LocalLlmRuntimeSnapshot _snapshot = const LocalLlmRuntimeSnapshot(
    state: LocalLlmEngineState.idle,
  );
  Future<void> _lifecycle = Future.value();
  Completer<void>? _generationDone;
  LocalLlmLoadOptions? _loadedOptions;
  bool _disposed = false;

  LocalLlmCoordinator(this._engine);

  LocalLlmRuntimeSnapshot get snapshot => _snapshot;
  Stream<LocalLlmRuntimeSnapshot> get snapshots => _snapshots.stream;
  LocalLlmModelDescriptor? get loadedModel => _snapshot.model;
  bool get isGenerating =>
      _snapshot.state == LocalLlmEngineState.generating ||
      _snapshot.state == LocalLlmEngineState.canceling;

  Future<LocalLlmEngineAvailability> probe() => _engine.probe();

  Future<void> loadModel(
    LocalLlmModelDescriptor model, {
    LocalLlmLoadOptions options = const LocalLlmLoadOptions(),
  }) => _serializeLifecycle(() async {
    final stopwatch = Stopwatch()..start();
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.inference,
        'llm_model_load_started',
        data: {
          'modelId': model.id,
          'engine': model.engine.name,
          'backend': options.backend.name,
          'threads': options.threads,
          'contextTokens': options.contextTokens,
          'imageInput': model.capabilities.imageInput,
          'audioInput': model.capabilities.audioInput,
          'enableImageInput': options.enableImageInput,
          'enableAudioInput': options.enableAudioInput,
        },
        traceId: model.id,
      );
    }
    _ensureNotDisposed();
    if (isGenerating) {
      throw const LocalLlmException('正在生成内容，暂时不能切换模型');
    }
    if (_snapshot.model?.id == model.id &&
        _snapshot.state == LocalLlmEngineState.ready &&
        _canReuseLoadedOptions(_loadedOptions, options)) {
      return;
    }
    if (_snapshot.model != null) {
      await _unloadInternal();
    }
    _emit(
      LocalLlmEngineState.loading,
      model: model,
      requestedBackend: options.backend,
    );
    try {
      await _engine.loadModel(model, options: options);
      _loadedOptions = options;
      _emit(LocalLlmEngineState.ready, model: model);
      if (kDebugMode) {
        AppDiagnostics.info(
          AppLogCategory.inference,
          'llm_model_load_completed',
          data: {'durationMs': stopwatch.elapsedMilliseconds},
          traceId: model.id,
        );
      }
    } catch (error, stackTrace) {
      _loadedOptions = null;
      _emit(
        LocalLlmEngineState.failed,
        model: model,
        requestedBackend: options.backend,
        error: error,
      );
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.inference,
          'llm_model_load_failed',
          data: {'durationMs': stopwatch.elapsedMilliseconds},
          error: error,
          stackTrace: stackTrace,
          traceId: model.id,
        );
      }
      rethrow;
    }
  });

  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request) {
    late StreamController<LocalLlmGenerationEvent> controller;
    var started = false;

    Future<void> start() async {
      if (started) return;
      started = true;
      final stopwatch = Stopwatch()..start();
      final modelId = _snapshot.model?.id ?? 'not-loaded';
      var outputCharacters = 0;
      if (kDebugMode) {
        AppDiagnostics.info(
          AppLogCategory.inference,
          'llm_generation_started',
          data: {
            'modelId': modelId,
            'messageCount': request.messages.length,
            'attachmentCount': request.messages.fold<int>(
              0,
              (total, message) => total + message.attachments.length,
            ),
            'maxNewTokens': request.options.maxNewTokens,
            'timeoutMs': request.options.timeout.inMilliseconds,
          },
          traceId: modelId,
        );
      }
      try {
        _ensureNotDisposed();
        if (_snapshot.state != LocalLlmEngineState.ready ||
            _snapshot.model == null) {
          throw const LocalLlmException('请先加载本地语言模型');
        }
        if (_generationDone != null) {
          throw const LocalLlmException('已有生成任务正在运行');
        }
        final done = Completer<void>();
        _generationDone = done;
        _emit(LocalLlmEngineState.generating, model: _snapshot.model);
        try {
          await for (final event in _engine.generate(request)) {
            if (event is LocalLlmTextDelta) {
              outputCharacters += event.text.length;
            }
            if (kDebugMode && event is LocalLlmGenerationCompleted) {
              AppDiagnostics.info(
                AppLogCategory.inference,
                'llm_generation_completed',
                data: {
                  'durationMs': stopwatch.elapsedMilliseconds,
                  'outputCharacters': outputCharacters,
                  'finishReason': event.reason.name,
                  'promptTokens': event.metrics.promptTokens,
                  'generatedTokens': event.metrics.generatedTokens,
                  'prefillTokensPerSecond':
                      event.metrics.prefillTokensPerSecond,
                  'decodeTokensPerSecond': event.metrics.decodeTokensPerSecond,
                  'visionTimeMs': event.metrics.visionTime.inMilliseconds,
                  'audioTimeMs': event.metrics.audioTime.inMilliseconds,
                },
                traceId: modelId,
              );
            }
            if (!controller.isClosed) controller.add(event);
          }
        } finally {
          if (!done.isCompleted) done.complete();
          if (identical(_generationDone, done)) _generationDone = null;
          if (!_disposed &&
              _snapshot.state != LocalLlmEngineState.unloading &&
              _snapshot.state != LocalLlmEngineState.failed) {
            _emit(LocalLlmEngineState.ready, model: _snapshot.model);
          }
        }
      } catch (error, stackTrace) {
        if (kDebugMode) {
          AppDiagnostics.error(
            AppLogCategory.inference,
            'llm_generation_failed',
            data: {
              'durationMs': stopwatch.elapsedMilliseconds,
              'outputCharacters': outputCharacters,
            },
            error: error,
            stackTrace: stackTrace,
            traceId: modelId,
          );
        }
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }

    controller = StreamController<LocalLlmGenerationEvent>(
      onListen: start,
      onCancel: () async {
        if (isGenerating) await cancel();
      },
    );
    return controller.stream;
  }

  Future<void> cancel() async {
    _ensureNotDisposed();
    final done = _generationDone;
    if (done == null) return;
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.inference,
        'llm_generation_cancel_requested',
        traceId: _snapshot.model?.id,
      );
    }
    _emit(LocalLlmEngineState.canceling, model: _snapshot.model);
    await _engine.cancel();
    await done.future;
  }

  Future<void> unload() => _serializeLifecycle(_unloadInternal);

  Future<void> _unloadInternal() async {
    _ensureNotDisposed();
    if (_generationDone != null) await cancel();
    if (_snapshot.model == null &&
        _snapshot.state == LocalLlmEngineState.idle) {
      return;
    }
    _emit(LocalLlmEngineState.unloading, model: _snapshot.model);
    final modelId = _snapshot.model?.id;
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.inference,
        'llm_model_unload_started',
        traceId: modelId,
      );
    }
    try {
      await _engine.unload();
      _loadedOptions = null;
      _emit(LocalLlmEngineState.idle);
      if (kDebugMode) {
        AppDiagnostics.info(
          AppLogCategory.inference,
          'llm_model_unload_completed',
          traceId: modelId,
        );
      }
    } catch (error, stackTrace) {
      _emit(LocalLlmEngineState.failed, error: error);
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.inference,
          'llm_model_unload_failed',
          error: error,
          stackTrace: stackTrace,
          traceId: modelId,
        );
      }
      rethrow;
    }
  }

  bool _canReuseLoadedOptions(
    LocalLlmLoadOptions? loaded,
    LocalLlmLoadOptions requested,
  ) =>
      loaded != null &&
      loaded.backend == requested.backend &&
      loaded.threads == requested.threads &&
      loaded.contextTokens == requested.contextTokens &&
      loaded.enableThinking == requested.enableThinking &&
      loaded.enablePromptCache == requested.enablePromptCache &&
      (!requested.enableImageInput || loaded.enableImageInput) &&
      (!requested.enableAudioInput || loaded.enableAudioInput);

  Future<void> dispose() async {
    if (_disposed) return;
    await unload();
    _disposed = true;
    await _snapshots.close();
  }

  Future<void> _serializeLifecycle(Future<void> Function() operation) {
    final result = _lifecycle.then((_) => operation());
    _lifecycle = result.catchError((_) {});
    return result;
  }

  void _emit(
    LocalLlmEngineState state, {
    LocalLlmModelDescriptor? model,
    LocalLlmBackend? requestedBackend,
    Object? error,
  }) {
    final backendProvider = _engine is LocalLlmRuntimeBackendProvider
        ? _engine as LocalLlmRuntimeBackendProvider
        : null;
    _snapshot = LocalLlmRuntimeSnapshot(
      state: state,
      model: model,
      requestedBackend: requestedBackend ?? _loadedOptions?.backend,
      activeBackend: backendProvider?.activeBackend,
      error: error,
    );
    if (kDebugMode) {
      AppDiagnostics.debug(
        AppLogCategory.inference,
        'llm_runtime_state_changed',
        data: {
          'state': state.name,
          'modelId': model?.id,
          'requestedBackend': _snapshot.requestedBackend?.name,
          'activeBackend': _snapshot.activeBackend?.name,
        },
        traceId: model?.id,
      );
    }
    if (!_snapshots.isClosed) _snapshots.add(_snapshot);
  }

  void _ensureNotDisposed() {
    if (_disposed) throw const LocalLlmException('本地语言模型服务已关闭');
  }
}
