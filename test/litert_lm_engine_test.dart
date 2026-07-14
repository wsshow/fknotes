import 'dart:async';
import 'dart:io';

import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_llm/litert_lm_engine.dart';
import 'package:fknotes/services/local_llm/litert_lm_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File modelFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fknotes_litert_lm_');
    modelFile = File('${directory.path}/model.litertlm');
    await modelFile.writeAsBytes([1, 2, 3]);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('loads and streams through the LiteRT-LM transport', () async {
    final transport = _FakeTransport();
    final engine = LiteRtLmEngine(transport: transport);
    await engine.loadModel(_descriptor(modelFile.path));

    final events = await engine
        .generate(
          LocalLlmGenerationRequest(
            messages: const [
              LocalLlmMessage(role: LocalLlmRole.user, content: '你好'),
            ],
          ),
        )
        .toList();

    expect(engine.state, LocalLlmEngineState.ready);
    expect(events.whereType<LocalLlmTextDelta>().single.text, '你好！');
    expect(
      events.whereType<LocalLlmGenerationCompleted>().single.reason,
      LocalLlmFinishReason.completed,
    );
    expect(transport.loadedModelPath, modelFile.path);
    expect(engine.activeBackend, LocalLlmBackend.cpu);
  });

  test('reports an isolated worker death without hanging', () async {
    final transport = _FakeTransport(crashOnGenerate: true);
    final engine = LiteRtLmEngine(transport: transport);
    await engine.loadModel(_descriptor(modelFile.path));

    await expectLater(
      engine.generate(
        LocalLlmGenerationRequest(
          messages: const [
            LocalLlmMessage(role: LocalLlmRole.user, content: '测试'),
          ],
        ),
      ),
      emitsError(
        isA<LocalLlmException>().having(
          (error) => error.message,
          'message',
          contains('进程'),
        ),
      ),
    );
    expect(engine.state, LocalLlmEngineState.failed);
  });

  test('falls back to CPU when the GPU backend cannot initialize', () async {
    final transport = _FakeTransport(failGpuLoad: true);
    final engine = LiteRtLmEngine(transport: transport);

    await engine.loadModel(
      _descriptor(modelFile.path),
      options: const LocalLlmLoadOptions(backend: LocalLlmBackend.openCl),
    );

    expect(transport.loadBackends, [
      LocalLlmBackend.openCl,
      LocalLlmBackend.cpu,
    ]);
    expect(engine.state, LocalLlmEngineState.ready);
    expect(engine.activeBackend, LocalLlmBackend.cpu);
  });

  test('enables multimodal pipelines only when explicitly requested', () async {
    final transport = _FakeTransport();
    final engine = LiteRtLmEngine(transport: transport);

    await engine.loadModel(
      _descriptor(modelFile.path),
      options: const LocalLlmLoadOptions(enableImageInput: true),
    );

    expect(transport.loadOptions.single.enableImageInput, isTrue);
    expect(transport.loadOptions.single.enableAudioInput, isFalse);
  });

  test(
    'retries once on CPU without leaking an error when workers die on load',
    () async {
      final transport = _FakeTransport(crashOnLoad: true);
      final engine = LiteRtLmEngine(transport: transport);
      final uncaught = <Object>[];

      await runZonedGuarded(() async {
        await expectLater(
          engine.loadModel(
            _descriptor(modelFile.path),
            options: const LocalLlmLoadOptions(backend: LocalLlmBackend.openCl),
          ),
          throwsA(
            isA<LocalLlmException>().having(
              (error) => error.message,
              'message',
              contains('当前设备'),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty);
      expect(transport.loadBackends, [
        LocalLlmBackend.openCl,
        LocalLlmBackend.cpu,
      ]);
      expect(engine.state, LocalLlmEngineState.failed);
    },
  );

  test('recovers on CPU after the GPU worker dies', () async {
    final transport = _FakeTransport(crashGpuWorker: true);
    final engine = LiteRtLmEngine(transport: transport);

    await engine.loadModel(
      _descriptor(modelFile.path),
      options: const LocalLlmLoadOptions(backend: LocalLlmBackend.openCl),
    );

    expect(transport.loadBackends, [
      LocalLlmBackend.openCl,
      LocalLlmBackend.cpu,
    ]);
    expect(engine.state, LocalLlmEngineState.ready);
  });
}

LocalLlmModelDescriptor _descriptor(String path) => LocalLlmModelDescriptor(
  engine: LocalLlmEngineKind.liteRtLm,
  id: 'gemma-test',
  name: 'Gemma test',
  configPath: path,
  nativeContextTokens: 32768,
  capabilities: const LocalLlmCapabilities(imageInput: true, audioInput: true),
);

class _FakeTransport implements LiteRtLmTransport {
  final bool crashOnGenerate;
  final bool crashOnLoad;
  final bool crashGpuWorker;
  final bool failGpuLoad;
  final _events = StreamController<LiteRtLmNativeEvent>.broadcast();
  String? loadedModelPath;
  final loadBackends = <LocalLlmBackend>[];
  final loadOptions = <LocalLlmLoadOptions>[];

  _FakeTransport({
    this.crashOnGenerate = false,
    this.crashOnLoad = false,
    this.crashGpuWorker = false,
    this.failGpuLoad = false,
  });

  @override
  bool get available => true;

  @override
  String get version => 'test';

  @override
  Stream<LiteRtLmNativeEvent> get events => _events.stream;

  @override
  Future<bool> load({
    required int requestId,
    required String modelPath,
    required LocalLlmLoadOptions options,
  }) async {
    loadedModelPath = modelPath;
    loadBackends.add(options.backend);
    loadOptions.add(options);
    if (crashOnLoad ||
        (crashGpuWorker && options.backend != LocalLlmBackend.cpu)) {
      scheduleMicrotask(
        () => _events.add(
          const LiteRtLmNativeEvent(
            requestId: -1,
            type: LiteRtLmNativeEventType.serviceDied,
            data: 'LiteRT-LM 推理进程意外终止',
          ),
        ),
      );
      return false;
    }
    scheduleMicrotask(
      () => _events.add(
        LiteRtLmNativeEvent(
          requestId: requestId,
          type: failGpuLoad && options.backend != LocalLlmBackend.cpu
              ? LiteRtLmNativeEventType.error
              : LiteRtLmNativeEventType.loaded,
          data: failGpuLoad && options.backend != LocalLlmBackend.cpu
              ? 'GPU unavailable'
              : options.backend == LocalLlmBackend.cpu
              ? 'cpu'
              : 'gpu',
        ),
      ),
    );
    return true;
  }

  @override
  Future<bool> generate({
    required int requestId,
    required LocalLlmGenerationRequest request,
  }) async {
    scheduleMicrotask(() {
      if (crashOnGenerate) {
        _events.add(
          const LiteRtLmNativeEvent(
            requestId: -1,
            type: LiteRtLmNativeEventType.serviceDied,
            data: 'LiteRT-LM 推理进程意外终止',
          ),
        );
      } else {
        _events
          ..add(
            LiteRtLmNativeEvent(
              requestId: requestId,
              type: LiteRtLmNativeEventType.textDelta,
              data: '你好！',
            ),
          )
          ..add(
            LiteRtLmNativeEvent(
              requestId: requestId,
              type: LiteRtLmNativeEventType.completed,
              data:
                  '{"promptTokens":2,"generatedTokens":3,'
                  '"prefillTokensPerSecond":10,"decodeTokensPerSecond":20}',
            ),
          );
      }
    });
    return true;
  }

  @override
  Future<bool> cancel(int requestId) async => true;

  @override
  Future<bool> unload(int requestId) async {
    scheduleMicrotask(
      () => _events.add(
        LiteRtLmNativeEvent(
          requestId: requestId,
          type: LiteRtLmNativeEventType.unloaded,
        ),
      ),
    );
    return true;
  }
}
