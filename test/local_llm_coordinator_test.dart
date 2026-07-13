import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_llm/local_llm_coordinator.dart';
import 'package:fknotes/services/local_llm/local_llm_engine.dart';

void main() {
  const modelA = LocalLlmModelDescriptor(
    id: 'model-a',
    name: 'Model A',
    configPath: '/models/a/config.json',
    nativeContextTokens: 8192,
  );
  const modelB = LocalLlmModelDescriptor(
    id: 'model-b',
    name: 'Model B',
    configPath: '/models/b/config.json',
    nativeContextTokens: 8192,
  );

  test('switching models unloads the previous model first', () async {
    final engine = _FakeEngine();
    final coordinator = LocalLlmCoordinator(engine);

    await coordinator.loadModel(modelA);
    await coordinator.loadModel(modelB);

    expect(engine.operations, [
      'load:model-a',
      'unload:model-a',
      'load:model-b',
    ]);
    expect(coordinator.loadedModel?.id, 'model-b');
    expect(coordinator.snapshot.state, LocalLlmEngineState.ready);
    await coordinator.dispose();
  });

  test('generation streams deltas and returns to ready', () async {
    final engine = _FakeEngine();
    final coordinator = LocalLlmCoordinator(engine);
    await coordinator.loadModel(modelA);

    final events = await coordinator
        .generate(
          LocalLlmGenerationRequest(
            messages: const [
              LocalLlmMessage(role: LocalLlmRole.user, content: '你好'),
            ],
          ),
        )
        .toList();

    expect(events.whereType<LocalLlmTextDelta>().map((event) => event.text), [
      '你',
      '好',
    ]);
    expect(events.last, isA<LocalLlmGenerationCompleted>());
    expect(coordinator.snapshot.state, LocalLlmEngineState.ready);
    await coordinator.dispose();
  });

  test('unload cancels and waits for active generation', () async {
    final engine = _FakeEngine(blockGeneration: true);
    final coordinator = LocalLlmCoordinator(engine);
    await coordinator.loadModel(modelA);
    final events = coordinator
        .generate(
          LocalLlmGenerationRequest(
            messages: const [
              LocalLlmMessage(role: LocalLlmRole.user, content: '继续'),
            ],
          ),
        )
        .toList();
    await engine.generationStarted.future;

    await coordinator.unload();
    await events;

    expect(engine.operations, [
      'load:model-a',
      'generate:model-a',
      'cancel:model-a',
      'unload:model-a',
    ]);
    expect(coordinator.snapshot.state, LocalLlmEngineState.idle);
    await coordinator.dispose();
  });

  test('rejects generation before a model is loaded', () async {
    final coordinator = LocalLlmCoordinator(_FakeEngine());

    final stream = coordinator.generate(
      LocalLlmGenerationRequest(
        messages: const [
          LocalLlmMessage(role: LocalLlmRole.user, content: '你好'),
        ],
      ),
    );

    await expectLater(stream, emitsError(isA<LocalLlmException>()));
    await coordinator.dispose();
  });

  test('reloads only when a newly requested modality is missing', () async {
    final engine = _FakeEngine();
    final coordinator = LocalLlmCoordinator(engine);

    await coordinator.loadModel(modelA);
    await coordinator.loadModel(
      modelA,
      options: const LocalLlmLoadOptions(enableImageInput: true),
    );
    await coordinator.loadModel(modelA);

    expect(engine.operations, [
      'load:model-a',
      'unload:model-a',
      'load:model-a',
    ]);
    await coordinator.dispose();
  });
}

class _FakeEngine implements LocalLlmEngine {
  final bool blockGeneration;
  final operations = <String>[];
  final generationStarted = Completer<void>();
  final _releaseGeneration = Completer<void>();
  LocalLlmModelDescriptor? _model;
  LocalLlmEngineState _state = LocalLlmEngineState.idle;

  _FakeEngine({this.blockGeneration = false});

  @override
  String get id => 'fake';

  @override
  LocalLlmModelDescriptor? get loadedModel => _model;

  @override
  LocalLlmEngineState get state => _state;

  @override
  Future<LocalLlmEngineAvailability> probe() async =>
      const LocalLlmEngineAvailability(supported: true, engine: 'fake');

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
    operations.add('generate:${_model!.id}');
    _state = LocalLlmEngineState.generating;
    if (!generationStarted.isCompleted) generationStarted.complete();
    yield const LocalLlmTextDelta('你');
    if (blockGeneration) await _releaseGeneration.future;
    yield const LocalLlmTextDelta('好');
    yield const LocalLlmGenerationCompleted(
      reason: LocalLlmFinishReason.completed,
    );
    _state = LocalLlmEngineState.ready;
  }

  @override
  Future<void> cancel() async {
    operations.add('cancel:${_model!.id}');
    if (!_releaseGeneration.isCompleted) _releaseGeneration.complete();
  }

  @override
  Future<void> unload() async {
    operations.add('unload:${_model?.id}');
    _model = null;
    _state = LocalLlmEngineState.idle;
  }
}
