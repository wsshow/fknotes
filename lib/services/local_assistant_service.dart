import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/local_llm.dart';
import 'language_model_service.dart';
import 'local_inference_coordinator.dart';
import 'local_llm/local_llm_coordinator.dart';
import 'local_llm/litert_lm_engine.dart';
import 'local_llm/mnn_local_llm_engine.dart';
import 'local_llm/routing_local_llm_engine.dart';

/// Application-level entry point for all future local assistant features.
class LocalAssistantBackendPolicy {
  const LocalAssistantBackendPolicy._();

  static LocalLlmBackend preferredFor(
    LocalLlmEngineKind engine, {
    required bool isAndroid,
    required bool isIOS,
  }) => switch (engine) {
    LocalLlmEngineKind.liteRtLm => LocalLlmBackend.openCl,
    LocalLlmEngineKind.mnn when isAndroid => LocalLlmBackend.openCl,
    LocalLlmEngineKind.mnn when isIOS => LocalLlmBackend.metal,
    LocalLlmEngineKind.mnn => LocalLlmBackend.cpu,
  };
}

class LocalAssistantService with WidgetsBindingObserver {
  LocalAssistantService._({
    LocalLlmCoordinator? coordinator,
    Future<String> Function()? selectedModelId,
    Future<LocalLlmModelDescriptor> Function(String id)? descriptor,
    LocalInferenceCoordinator? inference,
    this._idleTimeout = const Duration(minutes: 2),
    DateTime Function()? clock,
    bool observeLifecycle = true,
  }) : _coordinator =
           coordinator ??
           LocalLlmCoordinator(
             RoutingLocalLlmEngine(
               mnn: MnnLocalLlmEngine(),
               liteRtLm: LiteRtLmEngine(),
             ),
           ),
       _selectedModelId =
           selectedModelId ?? LanguageModelService.instance.selectedModelId,
       _descriptor = descriptor ?? LanguageModelService.instance.descriptor,
       _inference = inference ?? LocalInferenceCoordinator.instance,
       _clock = clock ?? DateTime.now {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  static final LocalAssistantService instance = LocalAssistantService._();

  @visibleForTesting
  factory LocalAssistantService.forTesting({
    required LocalLlmCoordinator coordinator,
    required Future<String> Function() selectedModelId,
    required Future<LocalLlmModelDescriptor> Function(String id) descriptor,
    LocalInferenceCoordinator? inference,
    Duration idleTimeout = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) => LocalAssistantService._(
    coordinator: coordinator,
    selectedModelId: selectedModelId,
    descriptor: descriptor,
    inference: inference,
    idleTimeout: idleTimeout,
    clock: clock,
    observeLifecycle: false,
  );

  final LocalLlmCoordinator _coordinator;
  final Future<String> Function() _selectedModelId;
  final Future<LocalLlmModelDescriptor> Function(String id) _descriptor;
  final LocalInferenceCoordinator _inference;
  final Duration _idleTimeout;
  final DateTime Function() _clock;
  Timer? _idleUnloadTimer;
  DateTime? _idleSince;
  LocalInferenceLease? _inferenceLease;
  Future<void> _lifecycle = Future.value();

  LocalLlmRuntimeSnapshot get snapshot => _coordinator.snapshot;
  Stream<LocalLlmRuntimeSnapshot> get snapshots => _coordinator.snapshots;
  bool get isActive => snapshot.state != LocalLlmEngineState.idle;
  String? get loadedModelId => snapshot.model?.id;

  Future<LocalLlmEngineAvailability> probe() => _coordinator.probe();

  Future<void> loadSelectedModel({
    int contextTokens = 4096,
    bool enableThinking = false,
    LocalLlmBackend? backend,
    bool enableImageInput = false,
    bool enableAudioInput = false,
  }) {
    _markBusy();
    return _serializeLifecycle(() async {
      final alreadyOwnedLease = _inferenceLease != null;
      _inferenceLease ??= _inference.acquire(
        type: LocalInferenceTaskType.assistant,
        ownerId: 'local-assistant',
      );
      if (_coordinator.isGenerating) {
        if (!alreadyOwnedLease) _releaseInferenceLease();
        throw const LocalLlmException('已有生成任务正在运行');
      }
      try {
        final selectedId = await _selectedModelId();
        final descriptor = await _descriptor(selectedId);
        final selectedBackend =
            backend ??
            LocalAssistantBackendPolicy.preferredFor(
              descriptor.engine,
              isAndroid: Platform.isAndroid,
              isIOS: Platform.isIOS,
            );
        await _coordinator.loadModel(
          descriptor,
          options: LocalLlmLoadOptions(
            backend: selectedBackend,
            threads: math.min(4, math.max(2, Platform.numberOfProcessors ~/ 2)),
            contextTokens: contextTokens,
            enableThinking: enableThinking,
            // A chat request contains the complete conversation. Reusing MNN's
            // native prompt cache across complete-history requests is unsafe for
            // some chat templates and can corrupt the next turn's KV state.
            enablePromptCache: false,
            enableImageInput: enableImageInput,
            enableAudioInput: enableAudioInput,
          ),
        );
      } catch (error, stackTrace) {
        try {
          await _coordinator.unload();
        } catch (_) {
          // Preserve the load failure. The coordinator has already recorded the
          // cleanup failure, while the global lease must never remain stuck.
        } finally {
          _releaseInferenceLease();
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      _beginIdleWindow();
    });
  }

  Stream<LocalLlmGenerationEvent> generate(
    LocalLlmGenerationRequest request,
  ) async* {
    _markBusy();
    try {
      yield* _coordinator.generate(request);
    } finally {
      _beginIdleWindow();
    }
  }

  Future<void> cancel() => _coordinator.cancel();

  Future<void> unload() {
    _idleUnloadTimer?.cancel();
    _idleUnloadTimer = null;
    _idleSince = null;
    return _serializeLifecycle(() async {
      _idleUnloadTimer?.cancel();
      _idleUnloadTimer = null;
      _idleSince = null;
      try {
        await _coordinator.unload();
      } finally {
        _releaseInferenceLease();
      }
    });
  }

  @override
  void didHaveMemoryPressure() {
    unawaited(unload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(unload());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // A brief app switch is not a cancellation request. Generation may keep
      // running in the background, while ready models retain their original
      // idle deadline. Reconcile on resume because Android may suspend Dart
      // timers while the app is backgrounded.
      _resumeIdleCountdown();
    }
  }

  void _markBusy() {
    _idleUnloadTimer?.cancel();
    _idleUnloadTimer = null;
    _idleSince = null;
  }

  void _beginIdleWindow() {
    if (snapshot.model == null ||
        snapshot.state == LocalLlmEngineState.idle ||
        snapshot.state == LocalLlmEngineState.unavailable ||
        snapshot.state == LocalLlmEngineState.unloading) {
      _markBusy();
      return;
    }
    _idleSince = _clock();
    _resumeIdleCountdown();
  }

  void _resumeIdleCountdown() {
    final idleSince = _idleSince;
    if (idleSince == null ||
        _coordinator.isGenerating ||
        snapshot.model == null) {
      return;
    }
    _idleUnloadTimer?.cancel();
    final elapsed = _clock().difference(idleSince);
    final remaining = elapsed.isNegative
        ? _idleTimeout
        : _idleTimeout - elapsed;
    if (remaining <= Duration.zero) {
      _idleUnloadTimer = null;
      unawaited(unload());
      return;
    }
    _idleUnloadTimer = Timer(remaining, () => unawaited(unload()));
  }

  Future<void> _serializeLifecycle(Future<void> Function() operation) {
    final result = _lifecycle.then((_) => operation());
    _lifecycle = result.catchError((_) {});
    return result;
  }

  void _releaseInferenceLease() {
    _inferenceLease?.release();
    _inferenceLease = null;
  }
}
