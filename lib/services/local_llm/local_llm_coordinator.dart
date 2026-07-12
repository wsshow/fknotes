import 'dart:async';

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
    _ensureNotDisposed();
    if (isGenerating) {
      throw const LocalLlmException('正在生成内容，暂时不能切换模型');
    }
    if (_snapshot.model?.id == model.id &&
        _snapshot.state == LocalLlmEngineState.ready) {
      return;
    }
    if (_snapshot.model != null) {
      await _unloadInternal();
    }
    _emit(LocalLlmEngineState.loading, model: model);
    try {
      await _engine.loadModel(model, options: options);
      _emit(LocalLlmEngineState.ready, model: model);
    } catch (error) {
      _emit(LocalLlmEngineState.failed, model: model, error: error);
      rethrow;
    }
  });

  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request) {
    late StreamController<LocalLlmGenerationEvent> controller;
    var started = false;

    Future<void> start() async {
      if (started) return;
      started = true;
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
    try {
      await _engine.unload();
      _emit(LocalLlmEngineState.idle);
    } catch (error) {
      _emit(LocalLlmEngineState.failed, error: error);
      rethrow;
    }
  }

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
    Object? error,
  }) {
    _snapshot = LocalLlmRuntimeSnapshot(
      state: state,
      model: model,
      error: error,
    );
    if (!_snapshots.isClosed) _snapshots.add(_snapshot);
  }

  void _ensureNotDisposed() {
    if (_disposed) throw const LocalLlmException('本地语言模型服务已关闭');
  }
}
