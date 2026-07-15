import 'dart:async';

import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_assistant_service.dart';
import 'package:fknotes/services/local_inference_coordinator.dart';
import 'package:fknotes/services/local_llm/local_llm_coordinator.dart';
import 'package:fknotes/services/local_llm/local_llm_engine.dart';
import 'package:flutter/widgets.dart';
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

  test('pausing preserves a loaded model and its idle deadline', () async {
    var now = DateTime.utc(2026, 7, 15, 12);
    final engine = _BlockingUnloadEngine();
    final coordinator = LocalLlmCoordinator(engine);
    final service = LocalAssistantService.forTesting(
      coordinator: coordinator,
      selectedModelId: () async => model.id,
      descriptor: (_) async => model,
      inference: inference,
      clock: () => now,
    );
    await service.loadSelectedModel();

    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.snapshot.state, LocalLlmEngineState.ready);
    expect(engine.operations, isNot(contains('unload:assistant-model')));

    now = now.add(const Duration(minutes: 1));
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.snapshot.state, LocalLlmEngineState.ready);
    expect(engine.operations, isNot(contains('unload:assistant-model')));

    await service.unload();
    await coordinator.dispose();
  });

  test(
    'background generation continues and idles only after completion',
    () async {
      var now = DateTime.utc(2026, 7, 15, 12);
      final engine = _BlockingUnloadEngine()..blockNextGeneration = true;
      final coordinator = LocalLlmCoordinator(engine);
      final service = LocalAssistantService.forTesting(
        coordinator: coordinator,
        selectedModelId: () async => model.id,
        descriptor: (_) async => model,
        inference: inference,
        clock: () => now,
      );
      await service.loadSelectedModel();

      final generation = service
          .generate(
            LocalLlmGenerationRequest(
              messages: const [
                LocalLlmMessage(role: LocalLlmRole.user, content: '你好'),
              ],
            ),
          )
          .toList();
      await engine.generationStarted.future;

      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 5));
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.snapshot.state, LocalLlmEngineState.generating);
      expect(engine.operations, isNot(contains('cancel:assistant-model')));
      expect(engine.operations, isNot(contains('unload:assistant-model')));

      engine.releaseGeneration.complete();
      await generation;
      expect(coordinator.snapshot.state, LocalLlmEngineState.ready);

      now = now.add(const Duration(minutes: 1));
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.snapshot.state, LocalLlmEngineState.ready);

      now = now.add(const Duration(minutes: 2));
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await engine.unloadStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.snapshot.state, LocalLlmEngineState.idle);

      await coordinator.dispose();
    },
  );

  test('detaching still releases the loaded model immediately', () async {
    final engine = _BlockingUnloadEngine();
    final coordinator = LocalLlmCoordinator(engine);
    final service = LocalAssistantService.forTesting(
      coordinator: coordinator,
      selectedModelId: () async => model.id,
      descriptor: (_) async => model,
      inference: inference,
    );
    await service.loadSelectedModel();

    service.didChangeAppLifecycleState(AppLifecycleState.detached);
    await engine.unloadStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.snapshot.state, LocalLlmEngineState.idle);
    expect(inference.activity, isNull);
    await coordinator.dispose();
  });
}

class _BlockingUnloadEngine implements LocalLlmEngine {
  final operations = <String>[];
  final unloadStarted = Completer<void>();
  final releaseUnload = Completer<void>();
  final generationStarted = Completer<void>();
  final releaseGeneration = Completer<void>();
  bool blockNextUnload = false;
  bool blockNextGeneration = false;
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
  Stream<LocalLlmGenerationEvent> generate(
    LocalLlmGenerationRequest request,
  ) async* {
    operations.add('generate:${_model?.id}');
    _state = LocalLlmEngineState.generating;
    if (!generationStarted.isCompleted) generationStarted.complete();
    if (blockNextGeneration) {
      blockNextGeneration = false;
      await releaseGeneration.future;
    }
    yield const LocalLlmTextDelta('你好');
    yield const LocalLlmGenerationCompleted(
      reason: LocalLlmFinishReason.completed,
    );
    _state = LocalLlmEngineState.ready;
  }

  @override
  Future<void> cancel() async {
    operations.add('cancel:${_model?.id}');
    if (!releaseGeneration.isCompleted) releaseGeneration.complete();
    _state = LocalLlmEngineState.ready;
  }

  @override
  Future<void> unload() async {
    operations.add('unload:${_model?.id}');
    _state = LocalLlmEngineState.unloading;
    if (!unloadStarted.isCompleted) unloadStarted.complete();
    if (blockNextUnload) {
      blockNextUnload = false;
      await releaseUnload.future;
    }
    _model = null;
    _state = LocalLlmEngineState.idle;
  }
}
