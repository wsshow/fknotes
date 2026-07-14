import 'dart:async';

import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_assistant_service.dart';
import 'package:fknotes/services/local_inference_coordinator.dart';
import 'package:fknotes/services/local_llm/local_llm_coordinator.dart';
import 'package:fknotes/services/local_llm/local_llm_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final inference = LocalInferenceCoordinator.instance;
  const model = LocalLlmModelDescriptor(
    id: 'assistant-model',
    name: 'Assistant model',
    configPath: '/models/config.json',
    nativeContextTokens: 8192,
  );

  setUp(inference.resetForTesting);
  tearDown(inference.resetForTesting);

  test('a queued reload reacquires the lease after an older unload', () async {
    final engine = _BlockingUnloadEngine();
    final coordinator = LocalLlmCoordinator(engine);
    final service = LocalAssistantService.forTesting(
      coordinator: coordinator,
      selectedModelId: () async => model.id,
      descriptor: (_) async => model,
      inference: inference,
    );
    await service.loadSelectedModel();
    expect(inference.activity?.type, LocalInferenceTaskType.assistant);

    engine.blockNextUnload = true;
    final unloading = service.unload();
    await engine.unloadStarted.future;
    final reloading = service.loadSelectedModel();
    engine.releaseUnload.complete();

    await unloading;
    await reloading;

    expect(coordinator.snapshot.state, LocalLlmEngineState.ready);
    expect(coordinator.loadedModel, model);
    expect(inference.activity?.type, LocalInferenceTaskType.assistant);
    expect(engine.operations, [
      'load:assistant-model',
      'unload:assistant-model',
      'load:assistant-model',
    ]);

    await service.unload();
    await coordinator.dispose();
  });
}

class _BlockingUnloadEngine implements LocalLlmEngine {
  final operations = <String>[];
  final unloadStarted = Completer<void>();
  final releaseUnload = Completer<void>();
  bool blockNextUnload = false;
  LocalLlmModelDescriptor? _model;
  LocalLlmEngineState _state = LocalLlmEngineState.idle;

  @override
  String get id => 'blocking-test-engine';

  @override
  LocalLlmModelDescriptor? get loadedModel => _model;

  @override
  LocalLlmEngineState get state => _state;

  @override
  Future<LocalLlmEngineAvailability> probe() async =>
      const LocalLlmEngineAvailability(
        supported: true,
        engine: 'blocking-test-engine',
      );

  @override
  Future<void> loadModel(
    LocalLlmModelDescriptor model, {
    LocalLlmLoadOptions options = const LocalLlmLoadOptions(),
  }) async {
    operations.add('load:${model.id}');
    _model = model;
    _state = LocalLlmEngineState.ready;
  }

  @override
  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request) =>
      const Stream.empty();

  @override
  Future<void> cancel() async {}

  @override
  Future<void> unload() async {
    operations.add('unload:${_model?.id}');
    _state = LocalLlmEngineState.unloading;
    if (blockNextUnload) {
      blockNextUnload = false;
      if (!unloadStarted.isCompleted) unloadStarted.complete();
      await releaseUnload.future;
    }
    _model = null;
    _state = LocalLlmEngineState.idle;
  }
}
