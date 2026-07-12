import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/local_llm.dart';
import 'language_model_service.dart';
import 'local_inference_coordinator.dart';
import 'local_llm/local_llm_coordinator.dart';
import 'local_llm/mnn_local_llm_engine.dart';

/// Application-level entry point for all future local assistant features.
class LocalAssistantService with WidgetsBindingObserver {
  LocalAssistantService._({LocalLlmCoordinator? coordinator})
    : _coordinator = coordinator ?? LocalLlmCoordinator(MnnLocalLlmEngine()) {
    WidgetsBinding.instance.addObserver(this);
  }

  static final LocalAssistantService instance = LocalAssistantService._();

  final LocalLlmCoordinator _coordinator;
  final _models = LanguageModelService.instance;
  static const _idleTimeout = Duration(minutes: 2);
  Timer? _idleUnloadTimer;
  final _inference = LocalInferenceCoordinator.instance;
  LocalInferenceLease? _inferenceLease;

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
    _idleUnloadTimer?.cancel();
    _inferenceLease ??= _inference.acquire(
      type: LocalInferenceTaskType.assistant,
      ownerId: 'local-assistant',
    );
    try {
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
    } catch (_) {
      await _coordinator.unload();
      _inferenceLease?.release();
      _inferenceLease = null;
      rethrow;
    }
    _scheduleIdleUnload();
  }

  Stream<LocalLlmGenerationEvent> generate(
    LocalLlmGenerationRequest request,
  ) async* {
    _idleUnloadTimer?.cancel();
    try {
      yield* _coordinator.generate(request);
    } finally {
      _scheduleIdleUnload();
    }
  }

  Future<void> cancel() => _coordinator.cancel();

  Future<void> unload() async {
    _idleUnloadTimer?.cancel();
    _idleUnloadTimer = null;
    try {
      await _coordinator.unload();
    } finally {
      _inferenceLease?.release();
      _inferenceLease = null;
    }
  }

  @override
  void didHaveMemoryPressure() {
    unawaited(unload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(unload());
    }
  }

  void _scheduleIdleUnload() {
    _idleUnloadTimer?.cancel();
    _idleUnloadTimer = Timer(_idleTimeout, () => unawaited(unload()));
  }
}
