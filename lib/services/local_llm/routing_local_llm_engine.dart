import '../../models/local_llm.dart';
import 'local_llm_engine.dart';

class RoutingLocalLlmEngine
    implements LocalLlmEngine, LocalLlmRuntimeBackendProvider {
  final Map<LocalLlmEngineKind, LocalLlmEngine> _engines;
  LocalLlmEngine? _active;

  RoutingLocalLlmEngine({
    required LocalLlmEngine mnn,
    required LocalLlmEngine liteRtLm,
  }) : _engines = {
         LocalLlmEngineKind.mnn: mnn,
         LocalLlmEngineKind.liteRtLm: liteRtLm,
       };

  @override
  String get id => _active?.id ?? 'local_llm_router';

  @override
  LocalLlmEngineState get state => _active?.state ?? LocalLlmEngineState.idle;

  @override
  LocalLlmModelDescriptor? get loadedModel => _active?.loadedModel;

  @override
  LocalLlmBackend? get activeBackend {
    final active = _active;
    if (active is! LocalLlmRuntimeBackendProvider) return null;
    return (active as LocalLlmRuntimeBackendProvider).activeBackend;
  }

  @override
  Future<LocalLlmEngineAvailability> probe() async {
    final results = await Future.wait(
      _engines.values.map((engine) => engine.probe()),
    );
    final supported = results.where((result) => result.supported).toList();
    return LocalLlmEngineAvailability(
      supported: supported.isNotEmpty,
      engine: supported.map((result) => result.engine).join(' / '),
      version: supported.map((result) => result.version).join(' / '),
      unavailableReason: supported.isEmpty ? '当前设备不支持本地语言模型推理' : null,
      capabilities: LocalLlmCapabilities(
        thinking: supported.any((result) => result.capabilities.thinking),
        toolCalling: supported.any((result) => result.capabilities.toolCalling),
        imageInput: supported.any((result) => result.capabilities.imageInput),
        audioInput: supported.any((result) => result.capabilities.audioInput),
        backends: supported.fold(
          <LocalLlmBackend>{},
          (all, result) => all..addAll(result.capabilities.backends),
        ),
      ),
    );
  }

  @override
  Future<void> loadModel(
    LocalLlmModelDescriptor model, {
    LocalLlmLoadOptions options = const LocalLlmLoadOptions(),
  }) async {
    final target = _engines[model.engine];
    if (target == null) throw const LocalLlmException('缺少模型所需的推理引擎');
    if (_active != null && !identical(_active, target)) await _active!.unload();
    _active = target;
    try {
      await target.loadModel(model, options: options);
    } catch (_) {
      _active = null;
      rethrow;
    }
  }

  @override
  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request) {
    final active = _active;
    if (active == null) {
      return Stream.error(const LocalLlmException('请先加载本地语言模型'));
    }
    return active.generate(request);
  }

  @override
  Future<void> cancel() async => _active?.cancel();

  @override
  Future<void> unload() async {
    final active = _active;
    if (active == null) return;
    try {
      await active.unload();
    } finally {
      _active = null;
    }
  }
}
