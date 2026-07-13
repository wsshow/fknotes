import 'package:flutter/foundation.dart';

import '../debug/app_diagnostics.dart';

enum LocalInferenceTaskType {
  liveDictation,
  transcription,
  readAloud,
  assistant,
}

extension LocalInferenceTaskTypeInfo on LocalInferenceTaskType {
  String get label => switch (this) {
    LocalInferenceTaskType.liveDictation => '实时听写',
    LocalInferenceTaskType.transcription => '音频转写',
    LocalInferenceTaskType.readAloud => '笔记朗读',
    LocalInferenceTaskType.assistant => '本地助手',
  };
}

class LocalInferenceActivity {
  final int generation;
  final LocalInferenceTaskType type;
  final String ownerId;
  final DateTime startedAt;

  const LocalInferenceActivity({
    required this.generation,
    required this.type,
    required this.ownerId,
    required this.startedAt,
  });
}

class LocalInferenceBusyException implements Exception {
  final LocalInferenceActivity activity;

  const LocalInferenceBusyException(this.activity);

  @override
  String toString() => '正在进行${activity.type.label}，请先结束后再试';
}

class LocalInferenceLease {
  final LocalInferenceCoordinator _coordinator;
  final int _generation;
  bool _released = false;

  LocalInferenceLease._(this._coordinator, this._generation);

  void release() {
    if (_released) return;
    _released = true;
    _coordinator._release(_generation);
  }
}

class LocalInferenceCoordinator extends ChangeNotifier {
  LocalInferenceCoordinator._();

  static final LocalInferenceCoordinator instance =
      LocalInferenceCoordinator._();

  LocalInferenceActivity? _activity;
  int _generation = 0;

  LocalInferenceActivity? get activity => _activity;
  bool get isBusy => _activity != null;

  LocalInferenceLease acquire({
    required LocalInferenceTaskType type,
    required String ownerId,
  }) {
    final active = _activity;
    if (active != null) {
      if (kDebugMode) {
        AppDiagnostics.warning(
          AppLogCategory.inference,
          'inference_lease_rejected',
          data: {
            'requestedType': type.name,
            'requestedOwnerHash': ownerId.hashCode,
            'activeType': active.type.name,
            'activeOwnerHash': active.ownerId.hashCode,
          },
        );
      }
      throw LocalInferenceBusyException(active);
    }
    final generation = ++_generation;
    _activity = LocalInferenceActivity(
      generation: generation,
      type: type,
      ownerId: ownerId,
      startedAt: DateTime.now(),
    );
    notifyListeners();
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.inference,
        'inference_lease_acquired',
        data: {'type': type.name, 'ownerHash': ownerId.hashCode},
        traceId: 'lease-$generation',
      );
    }
    return LocalInferenceLease._(this, generation);
  }

  void _release(int generation) {
    if (_activity?.generation != generation) return;
    final activity = _activity;
    _activity = null;
    notifyListeners();
    if (kDebugMode && activity != null) {
      AppDiagnostics.info(
        AppLogCategory.inference,
        'inference_lease_released',
        data: {
          'type': activity.type.name,
          'ownerHash': activity.ownerId.hashCode,
          'durationMs': DateTime.now()
              .difference(activity.startedAt)
              .inMilliseconds,
        },
        traceId: 'lease-$generation',
      );
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _activity = null;
    notifyListeners();
  }
}
