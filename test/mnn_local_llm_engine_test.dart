import 'dart:async';
import 'dart:io';

import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_llm/mnn_local_llm_engine.dart';
import 'package:fknotes/services/local_llm/mnn_native_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late File configFile;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('fknotes-mnn');
    configFile = File('${temporaryDirectory.path}/config.json');
    await configFile.writeAsString('{}');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  LocalLlmModelDescriptor model({
    LocalLlmCapabilities capabilities = const LocalLlmCapabilities(),
    LocalLlmGenerationOptions generationOptions =
        const LocalLlmGenerationOptions(),
  }) => LocalLlmModelDescriptor(
    id: 'test-model',
    name: 'Test Model',
    configPath: configFile.path,
    nativeContextTokens: 8192,
    capabilities: capabilities,
    generationOptions: generationOptions,
  );

  test('loads model and maps native generation metrics', () async {
    final transport = _FakeMnnTransport();
    final engine = MnnLocalLlmEngine(
      transport: transport,
      supportDirectoryProvider: () async => temporaryDirectory,
    );

    await engine.loadModel(model());
    final events = await engine
        .generate(
          LocalLlmGenerationRequest(
            messages: const [
              LocalLlmMessage(role: LocalLlmRole.user, content: '总结笔记'),
            ],
          ),
        )
        .toList();

    expect(engine.state, LocalLlmEngineState.ready);
    expect(events.whereType<LocalLlmTextDelta>().single.text, '摘要');
    final completed = events.whereType<LocalLlmGenerationCompleted>().single;
    expect(completed.reason, LocalLlmFinishReason.completed);
    expect(completed.metrics.promptTokens, 12);
    expect(completed.metrics.generatedTokens, 2);
    expect(completed.metrics.decodeTokensPerSecond, 10);
    expect(completed.metrics.visionTime, const Duration(milliseconds: 40));
    expect(completed.metrics.audioTime, const Duration(milliseconds: 30));
    expect(completed.metrics.imageMegapixels, 1.5);
    expect(completed.metrics.audioInputSeconds, 2.25);
    expect(engine.activeBackend, LocalLlmBackend.cpu);
  });

  test(
    'tries the other Android GPU backend before falling back to CPU',
    () async {
      final transport = _FakeMnnTransport(failAcceleratedLoad: true);
      final engine = MnnLocalLlmEngine(
        transport: transport,
        supportDirectoryProvider: () async => temporaryDirectory,
      );

      await engine.loadModel(
        model(),
        options: const LocalLlmLoadOptions(backend: LocalLlmBackend.openCl),
      );

      expect(transport.loadBackends, [
        LocalLlmBackend.openCl,
        LocalLlmBackend.vulkan,
        LocalLlmBackend.cpu,
      ]);
      expect(engine.activeBackend, LocalLlmBackend.cpu);
      expect(engine.state, LocalLlmEngineState.ready);
    },
  );

  test('keeps GPU acceleration when OpenCL fails but Vulkan works', () async {
    final transport = _FakeMnnTransport(
      failedBackends: const {LocalLlmBackend.openCl},
    );
    final engine = MnnLocalLlmEngine(
      transport: transport,
      supportDirectoryProvider: () async => temporaryDirectory,
    );

    await engine.loadModel(
      model(),
      options: const LocalLlmLoadOptions(backend: LocalLlmBackend.openCl),
    );

    expect(transport.loadBackends, [
      LocalLlmBackend.openCl,
      LocalLlmBackend.vulkan,
    ]);
    expect(engine.activeBackend, LocalLlmBackend.vulkan);
    expect(engine.state, LocalLlmEngineState.ready);
  });

  test('times out instead of holding the runtime forever', () async {
    final engine = MnnLocalLlmEngine(
      transport: _FakeMnnTransport(dropLifecycleEvents: true),
      supportDirectoryProvider: () async => temporaryDirectory,
      operationTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      engine.loadModel(
        model(),
        options: const LocalLlmLoadOptions(backend: LocalLlmBackend.cpu),
      ),
      throwsA(
        isA<LocalLlmException>().having(
          (error) => error.message,
          'message',
          contains('超时'),
        ),
      ),
    );
    expect(engine.state, LocalLlmEngineState.failed);
  });

  test('cancel waits for native terminal event', () async {
    final transport = _FakeMnnTransport(blockGeneration: true);
    final engine = MnnLocalLlmEngine(
      transport: transport,
      supportDirectoryProvider: () async => temporaryDirectory,
    );
    await engine.loadModel(model());
    final eventsFuture = engine
        .generate(
          LocalLlmGenerationRequest(
            messages: const [
              LocalLlmMessage(role: LocalLlmRole.user, content: '继续'),
            ],
          ),
        )
        .toList();
    await transport.generationStarted.future;

    await engine.cancel();
    final events = await eventsFuture;

    expect(transport.canceledRequestId, isNotNull);
    expect(
      events.whereType<LocalLlmGenerationCompleted>().single.reason,
      LocalLlmFinishReason.canceled,
    );
    expect(engine.state, LocalLlmEngineState.ready);
  });

  test('uses the selected model sampling profile', () async {
    final transport = _FakeMnnTransport();
    final engine = MnnLocalLlmEngine(
      transport: transport,
      supportDirectoryProvider: () async => temporaryDirectory,
    );
    await engine.loadModel(
      model(
        generationOptions: const LocalLlmGenerationOptions(
          temperature: 1,
          topP: 0.8,
          topK: 20,
        ),
      ),
    );

    await engine
        .generate(
          LocalLlmGenerationRequest(
            messages: const [
              LocalLlmMessage(role: LocalLlmRole.user, content: '继续'),
            ],
            options: const LocalLlmGenerationOptions(
              maxNewTokens: 96,
              timeout: Duration(seconds: 10),
            ),
          ),
        )
        .toList();

    expect(transport.lastRequest!.options.maxNewTokens, 96);
    expect(transport.lastRequest!.options.timeout, const Duration(seconds: 10));
    expect(transport.lastRequest!.options.temperature, 1);
    expect(transport.lastRequest!.options.topP, 0.8);
    expect(transport.lastRequest!.options.topK, 20);
  });

  test('rejects context larger than model capability', () async {
    final engine = MnnLocalLlmEngine(
      transport: _FakeMnnTransport(),
      supportDirectoryProvider: () async => temporaryDirectory,
    );

    await expectLater(
      engine.loadModel(
        model(),
        options: const LocalLlmLoadOptions(contextTokens: 16384),
      ),
      throwsA(isA<LocalLlmException>()),
    );
  });

  test('resolves and forwards supported image input', () async {
    final imageFile = File('${temporaryDirectory.path}/image.jpg');
    await imageFile.writeAsBytes([0xff, 0xd8, 0xff, 0xd9]);
    final transport = _FakeMnnTransport();
    final engine = MnnLocalLlmEngine(
      transport: transport,
      supportDirectoryProvider: () async => temporaryDirectory,
      attachmentPathResolver: (path) => '${temporaryDirectory.path}/$path',
    );
    await engine.loadModel(
      model(capabilities: const LocalLlmCapabilities(imageInput: true)),
    );

    await engine
        .generate(
          LocalLlmGenerationRequest(
            messages: const [
              LocalLlmMessage(
                role: LocalLlmRole.user,
                content: '分析图片',
                attachments: [
                  LocalLlmAttachment(path: 'image.jpg', mimeType: 'IMAGE/JPEG'),
                ],
              ),
            ],
          ),
        )
        .toList();

    final attachment =
        transport.lastRequest!.messages.single.attachments.single;
    expect(attachment.path, imageFile.path);
    expect(attachment.mimeType, 'image/jpeg');
    expect(engine.state, LocalLlmEngineState.ready);
  });

  test('rejects image input for a text-only model', () async {
    final engine = MnnLocalLlmEngine(
      transport: _FakeMnnTransport(),
      supportDirectoryProvider: () async => temporaryDirectory,
    );
    await engine.loadModel(model());

    await expectLater(
      engine
          .generate(
            LocalLlmGenerationRequest(
              messages: const [
                LocalLlmMessage(
                  role: LocalLlmRole.user,
                  content: '分析图片',
                  attachments: [
                    LocalLlmAttachment(
                      path: 'assistant/image.jpg',
                      mimeType: 'image/jpeg',
                    ),
                  ],
                ),
              ],
            ),
          )
          .toList(),
      throwsA(
        isA<LocalLlmException>().having(
          (error) => error.message,
          'message',
          contains('不支持图片输入'),
        ),
      ),
    );
    expect(engine.state, LocalLlmEngineState.ready);
  });

  test('rejects missing and unsafe multimodal files', () async {
    final engine = MnnLocalLlmEngine(
      transport: _FakeMnnTransport(),
      supportDirectoryProvider: () async => temporaryDirectory,
      attachmentPathResolver: (path) => '${temporaryDirectory.path}/$path',
    );
    await engine.loadModel(
      model(capabilities: const LocalLlmCapabilities(imageInput: true)),
    );

    await expectLater(
      engine
          .generate(
            LocalLlmGenerationRequest(
              messages: const [
                LocalLlmMessage(
                  role: LocalLlmRole.user,
                  content: '分析图片',
                  attachments: [
                    LocalLlmAttachment(
                      path: 'missing.jpg',
                      mimeType: 'image/jpeg',
                    ),
                  ],
                ),
              ],
            ),
          )
          .toList(),
      throwsA(
        isA<LocalLlmException>().having(
          (error) => error.message,
          'message',
          contains('不存在'),
        ),
      ),
    );
  });
}

class _FakeMnnTransport implements MnnNativeTransport {
  final bool blockGeneration;
  final bool failAcceleratedLoad;
  final Set<LocalLlmBackend> failedBackends;
  final bool dropLifecycleEvents;
  final _events = StreamController<MnnNativeEvent>.broadcast();
  final generationStarted = Completer<void>();
  final loadBackends = <LocalLlmBackend>[];
  int? canceledRequestId;
  LocalLlmGenerationRequest? lastRequest;

  _FakeMnnTransport({
    this.blockGeneration = false,
    this.failAcceleratedLoad = false,
    this.failedBackends = const {},
    this.dropLifecycleEvents = false,
  });

  @override
  bool get available => true;

  @override
  Stream<MnnNativeEvent> get events => _events.stream;

  @override
  String get version => 'test';

  @override
  bool load({
    required int requestId,
    required String configPath,
    required String cachePath,
    required LocalLlmLoadOptions options,
  }) {
    loadBackends.add(options.backend);
    if (dropLifecycleEvents) return true;
    final loadFails =
        (failAcceleratedLoad && options.backend != LocalLlmBackend.cpu) ||
        failedBackends.contains(options.backend);
    scheduleMicrotask(
      () => _events.add(
        MnnNativeEvent(
          requestId: requestId,
          type: loadFails
              ? MnnNativeEventType.error
              : MnnNativeEventType.loaded,
          data: loadFails
              ? 'GPU unavailable'
              : options.backend.name.toLowerCase(),
        ),
      ),
    );
    return true;
  }

  @override
  bool generate({
    required int requestId,
    required LocalLlmGenerationRequest request,
  }) {
    lastRequest = request;
    if (!generationStarted.isCompleted) generationStarted.complete();
    scheduleMicrotask(() {
      _events.add(
        MnnNativeEvent(
          requestId: requestId,
          type: MnnNativeEventType.textDelta,
          data: '摘要',
        ),
      );
      if (!blockGeneration) {
        _complete(requestId);
      }
    });
    return true;
  }

  @override
  bool cancel(int requestId) {
    canceledRequestId = requestId;
    scheduleMicrotask(
      () => _events.add(
        MnnNativeEvent(requestId: requestId, type: MnnNativeEventType.canceled),
      ),
    );
    return true;
  }

  @override
  bool unload(int requestId) {
    scheduleMicrotask(
      () => _events.add(
        MnnNativeEvent(requestId: requestId, type: MnnNativeEventType.unloaded),
      ),
    );
    return true;
  }

  void _complete(int requestId) {
    _events.add(
      MnnNativeEvent(
        requestId: requestId,
        type: MnnNativeEventType.completed,
        data:
            '{"reason":"completed","promptTokens":12,'
            '"generatedTokens":2,"loadUs":1000,'
            '"prefillUs":100000,"decodeUs":200000,'
            '"visionUs":40000,"audioUs":30000,'
            '"imageMegapixels":1.5,"audioInputSeconds":2.25}',
      ),
    );
  }
}
