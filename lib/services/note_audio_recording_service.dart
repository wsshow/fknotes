import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

final class RecordedNoteAudio {
  const RecordedNoteAudio({required this.path});

  final String path;
}

final class NoteMicrophonePermissionDenied implements Exception {
  const NoteMicrophonePermissionDenied();
}

abstract interface class NoteAudioRecordingDriver {
  Stream<double> get amplitudes;

  Future<void> start();

  Future<void> pause();

  Future<void> resume();

  Future<RecordedNoteAudio> stop();

  Future<void> cancel();

  Future<void> dispose();
}

final class LocalNoteAudioRecordingDriver implements NoteAudioRecordingDriver {
  LocalNoteAudioRecordingDriver({
    Future<Directory> Function()? temporaryDirectory,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  AudioRecorder? _recorder;
  final Future<Directory> Function() _temporaryDirectory;
  final StreamController<double> _amplitudes =
      StreamController<double>.broadcast();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  String? _activePath;
  bool _disposed = false;

  AudioRecorder get _activeRecorder => _recorder ??= AudioRecorder();

  @override
  Stream<double> get amplitudes => _amplitudes.stream;

  @override
  Future<void> start() async {
    if (_disposed) throw StateError('录音器已经释放');
    if (_activePath != null) throw StateError('已经有正在进行的录音');
    final recorder = _activeRecorder;
    if (!await recorder.hasPermission()) {
      throw const NoteMicrophonePermissionDenied();
    }
    final directory = Directory(
      p.join((await _temporaryDirectory()).path, 'fknotes_recordings'),
    );
    await directory.create(recursive: true);
    final path = p.join(
      directory.path,
      'recording-${DateTime.now().microsecondsSinceEpoch}.m4a',
    );
    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
          numChannels: 1,
          autoGain: true,
          noiseSuppress: true,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.mic,
          ),
        ),
        path: path,
      );
      _activePath = path;
      _amplitudeSubscription = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((sample) {
            if (_amplitudes.isClosed) return;
            final normalized = ((sample.current + 60) / 60).clamp(.06, 1.0);
            _amplitudes.add(normalized.toDouble());
          });
    } catch (_) {
      final output = File(path);
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    if (_activePath == null) return;
    await _activeRecorder.pause();
  }

  @override
  Future<void> resume() async {
    if (_activePath == null) return;
    await _activeRecorder.resume();
  }

  @override
  Future<RecordedNoteAudio> stop() async {
    final fallbackPath = _activePath;
    if (fallbackPath == null) throw StateError('当前没有正在进行的录音');
    await _stopAmplitude();
    final output = await _activeRecorder.stop() ?? fallbackPath;
    _activePath = null;
    final file = File(output);
    if (!await file.exists() || await file.length() <= 0) {
      throw const FileSystemException('录音文件没有生成');
    }
    return RecordedNoteAudio(path: output);
  }

  @override
  Future<void> cancel() async {
    final path = _activePath;
    _activePath = null;
    await _stopAmplitude();
    if (path != null) {
      try {
        await _activeRecorder.cancel();
      } finally {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<void> _stopAmplitude() async {
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancel();
    await _recorder?.dispose();
    _recorder = null;
    await _amplitudes.close();
  }
}
