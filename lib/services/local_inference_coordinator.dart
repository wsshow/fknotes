import 'package:flutter/foundation.dart';

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
    if (active != null) throw LocalInferenceBusyException(active);
    final generation = ++_generation;
    _activity = LocalInferenceActivity(
      generation: generation,
      type: type,
      ownerId: ownerId,
      startedAt: DateTime.now(),
    );
    notifyListeners();
    return LocalInferenceLease._(this, generation);
  }

  void _release(int generation) {
    if (_activity?.generation != generation) return;
    _activity = null;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    _activity = null;
    notifyListeners();
  }
}
