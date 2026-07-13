import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_llm/local_llm_engine.dart';
import 'package:fknotes/services/local_llm/routing_local_llm_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routes each model exclusively to its declared engine', () async {
    final mnn = _FakeEngine('mnn');
    final liteRt = _FakeEngine('litert_lm');
    final router = RoutingLocalLlmEngine(mnn: mnn, liteRtLm: liteRt);
    const mnnModel = LocalLlmModelDescriptor(
      id: 'qwen',
      name: 'Qwen',
      configPath: '/mnn/config.json',
      nativeContextTokens: 4096,
    );
    const gemma = LocalLlmModelDescriptor(
      engine: LocalLlmEngineKind.liteRtLm,
      id: 'gemma',
      name: 'Gemma',
      configPath: '/litert/model.litertlm',
      nativeContextTokens: 32768,
    );

    await router.loadModel(mnnModel);
    expect(mnn.loadedModel, mnnModel);
    expect(liteRt.loadedModel, isNull);

    await router.loadModel(gemma);
    expect(mnn.unloadCount, 1);
    expect(liteRt.loadedModel, gemma);
    expect(router.id, 'litert_lm');
  });
}

class _FakeEngine implements LocalLlmEngine {
  @override
  final String id;
  @override
  LocalLlmEngineState state = LocalLlmEngineState.idle;
  @override
  LocalLlmModelDescriptor? loadedModel;
  int unloadCount = 0;

  _FakeEngine(this.id);

  @override
  Future<LocalLlmEngineAvailability> probe() async =>
      LocalLlmEngineAvailability(supported: true, engine: id);

  @override
  Future<void> loadModel(
    LocalLlmModelDescriptor model, {
    LocalLlmLoadOptions options = const LocalLlmLoadOptions(),
  }) async {
    loadedModel = model;
    state = LocalLlmEngineState.ready;
  }

  @override
  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request) =>
      const Stream.empty();

  @override
  Future<void> cancel() async {}

  @override
  Future<void> unload() async {
    unloadCount++;
    loadedModel = null;
    state = LocalLlmEngineState.idle;
  }
}
