import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/local_llm.dart';
import 'language_model_service.dart';
import 'local_llm/local_llm_coordinator.dart';
import 'local_llm/mnn_local_llm_engine.dart';
import 'note_read_aloud_service.dart';
import 'realtime_dictation_service.dart';
import 'speech_transcription_service.dart';

/// Application-level entry point for all future local assistant features.
class LocalAssistantService with WidgetsBindingObserver {
  LocalAssistantService._({LocalLlmCoordinator? coordinator})
    : _coordinator = coordinator ?? LocalLlmCoordinator(MnnLocalLlmEngine()) {
    WidgetsBinding.instance.addObserver(this);
  }

  static final LocalAssistantService instance = LocalAssistantService._();

  final LocalLlmCoordinator _coordinator;
  final _models = LanguageModelService.instance;

  LocalLlmRuntimeSnapshot get snapshot => _coordinator.snapshot;
  Stream<LocalLlmRuntimeSnapshot> get snapshots => _coordinator.snapshots;
  bool get isActive => snapshot.state != LocalLlmEngineState.idle;
  String? get loadedModelId => snapshot.model?.id;

  Future<LocalLlmEngineAvailability> probe() => _coordinator.probe();

  Future<void> loadSelectedModel({
    int contextTokens = 4096,
    bool enableThinking = false,
    LocalLlmBackend backend = LocalLlmBackend.cpu,
  }) async {
    _ensureHeavyAudioWorkIsIdle();
    final selectedId = await _models.selectedModelId();
    final descriptor = await _models.descriptor(selectedId);
    await _coordinator.loadModel(
      descriptor,
      options: LocalLlmLoadOptions(
        backend: backend,
        threads: math.min(4, math.max(2, Platform.numberOfProcessors ~/ 2)),
        contextTokens: contextTokens,
        enableThinking: enableThinking,
        enablePromptCache: true,
      ),
    );
  }

  Stream<LocalLlmGenerationEvent> generate(LocalLlmGenerationRequest request) {
    try {
      _ensureHeavyAudioWorkIsIdle();
      return _coordinator.generate(request);
    } catch (error, stackTrace) {
      return Stream.error(error, stackTrace);
    }
  }

  Future<void> cancel() => _coordinator.cancel();
  Future<void> unload() => _coordinator.unload();

  @override
  void didHaveMemoryPressure() {
    unawaited(unload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) unawaited(unload());
  }

  void _ensureHeavyAudioWorkIsIdle() {
    if (RealtimeDictationService.instance.isActive) {
      throw const LocalLlmException('请先结束正在进行的实时听写');
    }
    if (SpeechTranscriptionService.instance.jobs.any((job) => job.isRunning)) {
      throw const LocalLlmException('请先等待正在进行的音频转写结束');
    }
    if (NoteReadAloudService.instance.isActive) {
      throw const LocalLlmException('请先停止正在进行的笔记朗读');
    }
  }
}
