import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

enum NoteAudioPlaybackStatus { idle, loading, playing, paused, failed }

abstract interface class NoteAudioPlaybackDriver implements Listenable {
  String? get activeAssetId;

  NoteAudioPlaybackStatus get status;

  Duration get position;

  Duration get duration;

  String? get errorMessage;

  Future<void> toggle({required String assetId, required String filePath});

  Future<void> seek({required String assetId, required Duration position});

  Future<void> stop();

  void dispose();
}

final class LocalNoteAudioPlaybackDriver extends ChangeNotifier
    implements NoteAudioPlaybackDriver {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  var _generation = 0;
  bool _disposed = false;

  @override
  String? activeAssetId;

  @override
  NoteAudioPlaybackStatus status = NoteAudioPlaybackStatus.idle;

  @override
  Duration position = Duration.zero;

  @override
  Duration duration = Duration.zero;

  @override
  String? errorMessage;

  AudioPlayer get _activePlayer {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _player = player;
    _stateSubscription = player.playerStateStream.listen(_onPlayerState);
    _positionSubscription = player.positionStream.listen((value) {
      if (_disposed || activeAssetId == null) return;
      position = value > duration && duration > Duration.zero
          ? duration
          : value;
      notifyListeners();
    });
    _durationSubscription = player.durationStream.listen((value) {
      if (_disposed || value == null) return;
      duration = value;
      notifyListeners();
    });
    return player;
  }

  @override
  Future<void> toggle({
    required String assetId,
    required String filePath,
  }) async {
    if (_disposed) return;
    final player = _activePlayer;
    if (activeAssetId == assetId && status != NoteAudioPlaybackStatus.failed) {
      if (status == NoteAudioPlaybackStatus.playing) {
        await player.pause();
        return;
      }
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      status = NoteAudioPlaybackStatus.playing;
      errorMessage = null;
      notifyListeners();
      unawaited(_play(player, _generation));
      return;
    }

    final generation = ++_generation;
    activeAssetId = assetId;
    status = NoteAudioPlaybackStatus.loading;
    position = Duration.zero;
    duration = Duration.zero;
    errorMessage = null;
    notifyListeners();
    try {
      await player.stop();
      final discoveredDuration = await player.setFilePath(filePath);
      if (_disposed || generation != _generation || activeAssetId != assetId) {
        return;
      }
      duration = discoveredDuration ?? Duration.zero;
      status = NoteAudioPlaybackStatus.playing;
      notifyListeners();
      unawaited(_play(player, generation));
    } catch (error) {
      if (_disposed || generation != _generation) return;
      status = NoteAudioPlaybackStatus.failed;
      errorMessage = _readableError(error);
      notifyListeners();
    }
  }

  Future<void> _play(AudioPlayer player, int generation) async {
    try {
      await player.play();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      status = NoteAudioPlaybackStatus.failed;
      errorMessage = _readableError(error);
      notifyListeners();
    }
  }

  void _onPlayerState(PlayerState state) {
    if (_disposed || activeAssetId == null) return;
    if (state.processingState == ProcessingState.completed) {
      status = NoteAudioPlaybackStatus.paused;
      position = Duration.zero;
      unawaited(_player?.seek(Duration.zero));
    } else if (state.processingState == ProcessingState.loading ||
        state.processingState == ProcessingState.buffering) {
      status = NoteAudioPlaybackStatus.loading;
    } else {
      status = state.playing
          ? NoteAudioPlaybackStatus.playing
          : NoteAudioPlaybackStatus.paused;
    }
    notifyListeners();
  }

  @override
  Future<void> seek({
    required String assetId,
    required Duration position,
  }) async {
    if (_disposed || activeAssetId != assetId || _player == null) return;
    final bounded = position < Duration.zero
        ? Duration.zero
        : position > duration
        ? duration
        : position;
    await _player!.seek(bounded);
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _generation++;
    await _player?.stop();
    activeAssetId = null;
    status = NoteAudioPlaybackStatus.idle;
    position = Duration.zero;
    duration = Duration.zero;
    errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    unawaited(_stateSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  static String _readableError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Bad state: |StateError: |Exception: )'),
    '',
  );
}
