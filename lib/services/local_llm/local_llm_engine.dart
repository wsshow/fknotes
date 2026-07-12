import '../../models/local_llm.dart';

abstract interface class LocalLlmEngine {
  String get id;

  LocalLlmEngineState get state;

  LocalLlmModelDescriptor? get loadedModel;

  Future<LocalLlmEngineAvailability> probe();

  Future<void> loadModel(
    LocalLlmModelDescriptor model, {
    LocalLlmLoadOptions options = const LocalLlmLoadOptions(),
  });

  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request);

  Future<void> cancel();

  Future<void> unload();
}
