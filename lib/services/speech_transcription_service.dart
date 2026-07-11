import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/note_entry.dart';
import 'file_storage_service.dart';
import 'note_service.dart';
import 'speech_model_service.dart';
import 'voice_activity_model_service.dart';

enum TranscriptionStatus {
  preparing,
  decoding,
  recognizing,
  saving,
  completed,
  failed,
  canceled,
}

class TranscriptionJob {
  final String key;
  final int noteId;
  final String filePath;
  TranscriptionStatus status;
  double progress;
  String partialText;
  String? errorMessage;
  DateTime updatedAt;
  Isolate? worker;
  VoidCallback? cancelWorker;

  TranscriptionJob({
    required this.key,
    required this.noteId,
    required this.filePath,
    this.status = TranscriptionStatus.preparing,
    this.progress = 0,
    this.partialText = '',
  }) : updatedAt = DateTime.now();

  bool get isRunning => switch (status) {
    TranscriptionStatus.preparing ||
    TranscriptionStatus.decoding ||
    TranscriptionStatus.recognizing ||
    TranscriptionStatus.saving => true,
    _ => false,
  };
}

/// Owns transcription jobs so recognition continues when the detail page is
/// closed. The worker isolate performs all model inference and reports real
/// progress based on the number of decoded audio samples processed.
class SpeechTranscriptionService extends ChangeNotifier {
  SpeechTranscriptionService._();
  static final SpeechTranscriptionService instance =
      SpeechTranscriptionService._();

  static const _audioChannel = MethodChannel('fknotes/audio_decode');
  final _storage = FileStorageService.instance;
  final _models = SpeechModelService.instance;
  final _voiceActivityModels = VoiceActivityModelService.instance;
  final _notes = NoteService.instance;
  final Map<String, TranscriptionJob> _jobs = {};

  List<TranscriptionJob> get jobs => List.unmodifiable(_jobs.values);
  TranscriptionJob? jobFor(String filePath) => _jobs[filePath];

  Future<bool> realtimeRefinementAvailable() async =>
      (await _models.inspect()).installed;

  Future<void> start({
    required int noteId,
    required NoteAttachment attachment,
  }) async {
    if (attachment.type != NoteType.audio) {
      throw ArgumentError('只有音频附件可以转写');
    }
    final existing = _jobs[attachment.filePath];
    if (existing?.isRunning == true) return;
    final job = TranscriptionJob(
      key: '${attachment.filePath}:${DateTime.now().microsecondsSinceEpoch}',
      noteId: noteId,
      filePath: attachment.filePath,
    );
    _jobs[attachment.filePath] = job;
    notifyListeners();
    unawaited(_run(job));
  }

  Future<void> _run(TranscriptionJob job) async {
    String? temporaryWave;
    try {
      final model = await _models.inspect();
      if (!model.installed) throw StateError('请先导入离线语音识别模型');
      final voiceActivity = await _voiceActivityModels.inspect(
        verifyIntegrity: true,
      );
      final source = _storage.absolutePath(job.filePath);
      if (!await File(source).exists()) throw StateError('音频文件不存在');
      _update(job, status: TranscriptionStatus.decoding, progress: .04);
      temporaryWave = await _prepareWave(source, job);
      if (job.status == TranscriptionStatus.canceled) return;
      _update(job, status: TranscriptionStatus.recognizing, progress: .12);
      final text = await _recognizeInWorker(
        job,
        wavePath: temporaryWave,
        modelPath: model.modelPath,
        tokensPath: model.tokensPath,
        vadModelPath: voiceActivity.installed ? voiceActivity.modelPath : '',
      );
      if (job.status == TranscriptionStatus.canceled) return;
      final normalized = text.trim();
      if (normalized.isEmpty) throw StateError('没有识别到清晰语音');
      _update(job, status: TranscriptionStatus.saving, progress: .96);
      final now = DateTime.now();
      await _notes.updateAttachmentTranscript(
        noteId: job.noteId,
        filePath: job.filePath,
        transcript: normalized,
        model: SpeechModelService.modelId,
        transcribedAt: now,
      );
      job.partialText = normalized;
      _update(job, status: TranscriptionStatus.completed, progress: 1);
    } catch (error) {
      if (job.status != TranscriptionStatus.canceled) {
        job.errorMessage = _friendlyError(error);
        _update(job, status: TranscriptionStatus.failed);
      }
    } finally {
      job.worker = null;
      job.cancelWorker = null;
      if (temporaryWave != null &&
          temporaryWave != _storage.absolutePath(job.filePath)) {
        final file = File(temporaryWave);
        if (await file.exists()) await file.delete();
      }
    }
  }

  /// Runs the optional final pass for live dictation without creating a note
  /// transcription job. A missing SenseVoice model simply disables the pass.
  Future<String?> refineRealtimeWave(
    String wavePath, {
    @visibleForTesting String nativeLibDir = '',
  }) async {
    if (!await File(wavePath).exists()) return null;
    final model = await _models.inspect();
    if (!model.installed) return null;
    final voiceActivity = await _voiceActivityModels.inspect(
      verifyIntegrity: true,
    );
    final text = await _recognizeInWorker(
      null,
      wavePath: wavePath,
      modelPath: model.modelPath,
      tokensPath: model.tokensPath,
      vadModelPath: voiceActivity.installed ? voiceActivity.modelPath : '',
      nativeLibDir: nativeLibDir,
    );
    final normalized = text.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Future<String> _prepareWave(String source, TranscriptionJob job) async {
    if (p.extension(source).toLowerCase() == '.wav') return source;
    if (!Platform.isAndroid) {
      throw UnsupportedError('当前平台暂时只支持转写 WAV 音频');
    }
    final output = p.join(
      _storage.baseDir,
      'transcription_temp',
      '${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final decoded = await _audioChannel.invokeMethod<String>('decodeToWav', {
      'sourcePath': source,
      'outputPath': output,
    });
    if (decoded == null || !await File(decoded).exists()) {
      throw StateError('无法解码这个音频格式');
    }
    return decoded;
  }

  Future<String> _recognizeInWorker(
    TranscriptionJob? job, {
    required String wavePath,
    required String modelPath,
    required String tokensPath,
    required String vadModelPath,
    String nativeLibDir = '',
  }) async {
    final messages = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final completer = Completer<String>();
    StreamSubscription<dynamic>? messageSubscription;
    StreamSubscription<dynamic>? errorSubscription;
    StreamSubscription<dynamic>? exitSubscription;
    Isolate? worker;

    void completeError(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
    }

    messageSubscription = messages.listen((dynamic message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'progress':
          final fraction = (message['progress'] as num?)?.toDouble() ?? 0;
          if (job != null) {
            job.partialText = message['text'] as String? ?? job.partialText;
            _update(job, progress: .12 + fraction * .82);
          }
          return;
        case 'result':
          if (!completer.isCompleted) {
            completer.complete(message['text'] as String? ?? '');
          }
          return;
        case 'error':
          completeError(StateError(message['message'] as String? ?? '语音识别失败'));
          return;
      }
    });
    errorSubscription = errors.listen((dynamic error) {
      completeError(StateError(error.toString()));
    });
    exitSubscription = exits.listen((_) {
      if (!completer.isCompleted &&
          job?.status != TranscriptionStatus.canceled) {
        completeError(StateError('语音识别进程意外结束'));
      }
    });

    worker = await Isolate.spawn<Map<String, Object>>(
      _transcriptionWorker,
      {
        'sendPort': messages.sendPort,
        'wavePath': wavePath,
        'modelPath': modelPath,
        'tokensPath': tokensPath,
        'vadModelPath': vadModelPath,
        'nativeLibDir': nativeLibDir,
      },
      onError: errors.sendPort,
      onExit: exits.sendPort,
    );
    if (job != null) {
      job.worker = worker;
      job.cancelWorker = () {
        worker?.kill(priority: Isolate.immediate);
        if (!completer.isCompleted) {
          completer.completeError(const _TranscriptionCanceled());
        }
      };
    }
    try {
      return await completer.future;
    } finally {
      await messageSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      messages.close();
      errors.close();
      exits.close();
      worker.kill(priority: Isolate.immediate);
    }
  }

  void cancel(String filePath) {
    final job = _jobs[filePath];
    if (job == null || !job.isRunning) return;
    job.status = TranscriptionStatus.canceled;
    job.updatedAt = DateTime.now();
    job.cancelWorker?.call();
    notifyListeners();
  }

  void dismiss(String filePath) {
    final job = _jobs[filePath];
    if (job == null || job.isRunning) return;
    _jobs.remove(filePath);
    notifyListeners();
  }

  void _update(
    TranscriptionJob job, {
    TranscriptionStatus? status,
    double? progress,
  }) {
    if (status != null) job.status = status;
    if (progress != null) job.progress = progress.clamp(0, 1);
    job.updatedAt = DateTime.now();
    notifyListeners();
  }

  String _friendlyError(Object error) {
    if (error is _TranscriptionCanceled) return '已取消转写';
    final text = error.toString().replaceFirst(
      RegExp(r'^(StateError|Exception):\s*'),
      '',
    );
    if (text.contains('Failed to create offline recognizer')) {
      return '模型无法加载，请确认导入的是 SenseVoice INT8 模型';
    }
    return text;
  }
}

class _TranscriptionCanceled implements Exception {
  const _TranscriptionCanceled();
}

@pragma('vm:entry-point')
void _transcriptionWorker(Map<String, Object> args) {
  final sendPort = args['sendPort'] as SendPort;
  sherpa.OfflineRecognizer? recognizer;
  sherpa.VoiceActivityDetector? vad;
  _Pcm16WaveReader? wave;
  try {
    final nativeLibDir = args['nativeLibDir'] as String? ?? '';
    sherpa.initBindings(nativeLibDir.isEmpty ? null : nativeLibDir);
    final activeWave = _Pcm16WaveReader.open(args['wavePath'] as String);
    wave = activeWave;
    final activeRecognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: args['modelPath'] as String,
            language: '',
            useInverseTextNormalization: true,
          ),
          tokens: args['tokensPath'] as String,
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    recognizer = activeRecognizer;
    final pieces = <String>[];

    void recognize(Float32List samples) {
      if (samples.isEmpty) return;
      final stream = activeRecognizer.createStream();
      try {
        stream.acceptWaveform(
          samples: samples,
          sampleRate: activeWave.sampleRate,
        );
        activeRecognizer.decode(stream);
        final text = activeRecognizer.getResult(stream).text.trim();
        if (text.isNotEmpty) pieces.add(text);
      } finally {
        stream.free();
      }
    }

    void report(int completedFrames) {
      sendPort.send({
        'type': 'progress',
        'progress': completedFrames / activeWave.totalFrames,
        'text': pieces.join('\n'),
      });
    }

    final vadModelPath = args['vadModelPath'] as String? ?? '';
    if (vadModelPath.isNotEmpty && activeWave.sampleRate == 16000) {
      final activeVad = sherpa.VoiceActivityDetector(
        config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: vadModelPath,
            // Mobile microphone recordings can be much quieter than studio
            // test audio. 0.5 missed a clearly intelligible phrase in the
            // exported FKNotes diagnostic WAV; 0.3 retained every utterance
            // while still removing the long silent gaps.
            threshold: 0.3,
            minSilenceDuration: 0.5,
            minSpeechDuration: 0.25,
            windowSize: 512,
            maxSpeechDuration: 25,
          ),
          sampleRate: 16000,
          numThreads: 1,
          debug: false,
        ),
        bufferSizeInSeconds: 60,
      );
      vad = activeVad;
      var completedFrames = 0;

      void recognizeQueuedSegments() {
        while (!activeVad.isEmpty()) {
          final segment = activeVad.front();
          activeVad.pop();
          recognize(segment.samples);
        }
      }

      while (true) {
        final samples = activeWave.readSamples(activeWave.sampleRate);
        if (samples.isEmpty) break;
        activeVad.acceptWaveform(samples);
        completedFrames += samples.length;
        recognizeQueuedSegments();
        report(completedFrames);
      }
      activeVad.flush();
      recognizeQueuedSegments();
      report(activeWave.totalFrames);
    } else {
      const chunkSeconds = 25;
      var completedFrames = 0;
      while (true) {
        final samples = activeWave.readSamples(
          activeWave.sampleRate * chunkSeconds,
        );
        if (samples.isEmpty) break;
        recognize(samples);
        completedFrames += samples.length;
        report(completedFrames);
      }
    }
    sendPort.send({'type': 'result', 'text': pieces.join('\n')});
  } catch (error) {
    sendPort.send({'type': 'error', 'message': error.toString()});
  } finally {
    wave?.close();
    vad?.free();
    recognizer?.free();
  }
}

class _Pcm16WaveReader {
  final RandomAccessFile _file;
  final int sampleRate;
  final int channels;
  final int totalFrames;
  int _remainingBytes;

  _Pcm16WaveReader(
    this._file, {
    required this.sampleRate,
    required this.channels,
    required this.totalFrames,
    required this._remainingBytes,
  });

  static _Pcm16WaveReader open(String path) {
    final file = File(path).openSync();
    try {
      final header = file.readSync(12);
      if (header.length != 12 ||
          String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(header.sublist(8, 12)) != 'WAVE') {
        throw const FormatException('音频不是有效的 WAV 文件');
      }
      var audioFormat = 0;
      var channels = 0;
      var sampleRate = 0;
      var bitsPerSample = 0;
      var dataSize = 0;
      while (file.positionSync() + 8 <= file.lengthSync()) {
        final chunkHeader = file.readSync(8);
        if (chunkHeader.length < 8) break;
        final id = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final size = ByteData.sublistView(
          chunkHeader,
        ).getUint32(4, Endian.little);
        if (id == 'fmt ') {
          final format = file.readSync(size);
          if (format.length < 16) throw const FormatException('WAV 格式信息不完整');
          final data = ByteData.sublistView(format);
          audioFormat = data.getUint16(0, Endian.little);
          channels = data.getUint16(2, Endian.little);
          sampleRate = data.getUint32(4, Endian.little);
          bitsPerSample = data.getUint16(14, Endian.little);
        } else if (id == 'data') {
          dataSize = size;
          break;
        } else {
          file.setPositionSync(file.positionSync() + size);
        }
        if (size.isOdd) file.setPositionSync(file.positionSync() + 1);
      }
      if (audioFormat != 1 ||
          bitsPerSample != 16 ||
          channels <= 0 ||
          sampleRate <= 0 ||
          dataSize <= 0) {
        throw const FormatException('仅支持 PCM16 WAV 音频');
      }
      final bytesPerFrame = channels * 2;
      return _Pcm16WaveReader(
        file,
        sampleRate: sampleRate,
        channels: channels,
        totalFrames: dataSize ~/ bytesPerFrame,
        remainingBytes: dataSize,
      );
    } catch (_) {
      file.closeSync();
      rethrow;
    }
  }

  Float32List readSamples(int maxFrames) {
    if (_remainingBytes <= 0) return Float32List(0);
    final bytesPerFrame = channels * 2;
    final wanted = (maxFrames * bytesPerFrame).clamp(0, _remainingBytes);
    final bytes = _file.readSync(wanted);
    _remainingBytes -= bytes.length;
    final frames = bytes.length ~/ bytesPerFrame;
    final samples = Float32List(frames);
    final data = ByteData.sublistView(bytes);
    for (var frame = 0; frame < frames; frame++) {
      var mixed = 0;
      final start = frame * bytesPerFrame;
      for (var channel = 0; channel < channels; channel++) {
        mixed += data.getInt16(start + channel * 2, Endian.little);
      }
      samples[frame] = (mixed / channels) / 32768.0;
    }
    return samples;
  }

  void close() => _file.closeSync();
}
