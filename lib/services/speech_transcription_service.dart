import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../debug/app_diagnostics.dart';
import '../models/note_entry.dart';
import 'file_storage_service.dart';
import 'local_inference_coordinator.dart';
import 'note_service.dart';
import 'speech_model_service.dart';
import 'speaker_diarization_model_service.dart';
import 'voice_activity_model_service.dart';

enum TranscriptionStatus {
  preparing,
  decoding,
  diarizing,
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
  final int? speakerCount;
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
    this.speakerCount,
  }) : updatedAt = DateTime.now();

  bool get isRunning => switch (status) {
    TranscriptionStatus.preparing ||
    TranscriptionStatus.decoding ||
    TranscriptionStatus.diarizing ||
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
  final _speakerDiarizationModels = SpeakerDiarizationModelService.instance;
  final _notes = NoteService.instance;
  final _inference = LocalInferenceCoordinator.instance;
  final Map<String, TranscriptionJob> _jobs = {};

  List<TranscriptionJob> get jobs => List.unmodifiable(_jobs.values);
  TranscriptionJob? jobFor(String filePath) => _jobs[filePath];

  Future<bool> realtimeRefinementAvailable() async =>
      (await _models.inspect()).installed;

  Future<void> start({
    required int noteId,
    required NoteAttachment attachment,
    int? speakerCount,
  }) async {
    if (attachment.type != NoteType.audio) {
      throw ArgumentError('只有音频附件可以转写');
    }
    if (speakerCount != null &&
        speakerCount != -1 &&
        (speakerCount < 2 || speakerCount > 8)) {
      throw ArgumentError.value(speakerCount, 'speakerCount', '必须为自动或 2–8 人');
    }
    final existing = _jobs[attachment.filePath];
    if (existing?.isRunning == true) return;
    final job = TranscriptionJob(
      key: '${attachment.filePath}:${DateTime.now().microsecondsSinceEpoch}',
      noteId: noteId,
      filePath: attachment.filePath,
      speakerCount: speakerCount,
    );
    _jobs[attachment.filePath] = job;
    notifyListeners();
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.speech,
        'audio_transcription_started',
        data: {
          'noteId': noteId,
          'speakerMode': speakerCount != null,
          'speakerCount': speakerCount,
          'fileSizeBytes': attachment.fileSize,
          'durationMs': attachment.durationMs,
        },
        traceId: job.key,
      );
    }
    unawaited(_run(job));
  }

  Future<void> _run(TranscriptionJob job) async {
    String? temporaryWave;
    LocalInferenceLease? inferenceLease;
    final stopwatch = Stopwatch()..start();
    try {
      inferenceLease = _inference.acquire(
        type: LocalInferenceTaskType.transcription,
        ownerId: job.key,
      );
      final model = await _models.inspect();
      if (!model.installed) throw StateError('请先导入离线语音识别模型');
      final voiceActivity = await _voiceActivityModels.inspect(
        verifyIntegrity: true,
      );
      final diarization = job.speakerCount == null
          ? const SpeakerDiarizationModelInfo(installed: false)
          : await _speakerDiarizationModels.inspect(verifyIntegrity: true);
      if (job.speakerCount != null && !diarization.installed) {
        throw StateError(diarization.problem ?? '请先下载说话人分离模型');
      }
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
        segmentationModelPath: diarization.segmentationPath,
        embeddingModelPath: diarization.embeddingPath,
        speakerCount: job.speakerCount,
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
        model: job.speakerCount == null
            ? SpeechModelService.modelId
            : '${SpeechModelService.modelId}+${SpeakerDiarizationModelService.modelId}',
        transcribedAt: now,
      );
      job.partialText = normalized;
      _update(job, status: TranscriptionStatus.completed, progress: 1);
      if (kDebugMode) {
        AppDiagnostics.info(
          AppLogCategory.speech,
          'audio_transcription_completed',
          data: {
            'durationMs': stopwatch.elapsedMilliseconds,
            'characterCount': normalized.length,
            'speakerMode': job.speakerCount != null,
          },
          traceId: job.key,
        );
      }
    } catch (error, stackTrace) {
      if (job.status != TranscriptionStatus.canceled) {
        job.errorMessage = _friendlyError(error);
        _update(job, status: TranscriptionStatus.failed);
        if (kDebugMode) {
          AppDiagnostics.error(
            AppLogCategory.speech,
            'audio_transcription_failed',
            data: {
              'durationMs': stopwatch.elapsedMilliseconds,
              'status': job.status.name,
              'speakerMode': job.speakerCount != null,
            },
            error: error,
            stackTrace: stackTrace,
            traceId: job.key,
          );
        }
      }
    } finally {
      inferenceLease?.release();
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
    String segmentationModelPath = '',
    String embeddingModelPath = '',
    int? speakerCount,
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
            job.status = message['stage'] == 'diarizing'
                ? TranscriptionStatus.diarizing
                : TranscriptionStatus.recognizing;
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
        'segmentationModelPath': segmentationModelPath,
        'embeddingModelPath': embeddingModelPath,
        'speakerCount': speakerCount ?? 0,
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
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.speech,
        'audio_transcription_cancel_requested',
        traceId: job.key,
      );
    }
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
  sherpa.OfflineSpeakerDiarization? diarizer;
  _Pcm16WaveReader? wave;
  try {
    final nativeLibDir = args['nativeLibDir'] as String? ?? '';
    sherpa.initBindings(nativeLibDir.isEmpty ? null : nativeLibDir);
    final activeWave = _Pcm16WaveReader.open(args['wavePath'] as String);
    wave = activeWave;
    final segmentationModelPath =
        args['segmentationModelPath'] as String? ?? '';
    final embeddingModelPath = args['embeddingModelPath'] as String? ?? '';
    final speakerMode =
        segmentationModelPath.isNotEmpty && embeddingModelPath.isNotEmpty;

    sherpa.OfflineRecognizer createRecognizer() => sherpa.OfflineRecognizer(
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
    late sherpa.OfflineRecognizer activeRecognizer;
    if (!speakerMode) {
      activeRecognizer = createRecognizer();
      recognizer = activeRecognizer;
    }
    final pieces = <String>[];

    String recognize(Float32List samples, {int? sampleRate}) {
      if (samples.isEmpty) return '';
      final stream = activeRecognizer.createStream();
      try {
        stream.acceptWaveform(
          samples: samples,
          sampleRate: sampleRate ?? activeWave.sampleRate,
        );
        activeRecognizer.decode(stream);
        return activeRecognizer.getResult(stream).text.trim();
      } finally {
        stream.free();
      }
    }

    void recognizeAndAppend(Float32List samples) {
      final text = recognize(samples);
      if (text.isNotEmpty) pieces.add(text);
    }

    void report(int completedFrames) {
      sendPort.send({
        'type': 'progress',
        'progress': completedFrames / activeWave.totalFrames,
        'text': pieces.join('\n'),
        'stage': 'recognizing',
      });
    }

    final vadModelPath = args['vadModelPath'] as String? ?? '';
    if (speakerMode) {
      var samples = activeWave.readSamples(activeWave.totalFrames);
      if (activeWave.sampleRate != 16000) {
        samples = _resampleLinear(samples, activeWave.sampleRate, 16000);
      }
      if (samples.length > 16000 * 60 * 30) {
        throw StateError('区分说话人的录音暂时不能超过 30 分钟，请先拆分音频');
      }
      final activeDiarizer = sherpa.OfflineSpeakerDiarization(
        sherpa.OfflineSpeakerDiarizationConfig(
          segmentation: sherpa.OfflineSpeakerSegmentationModelConfig(
            pyannote: sherpa.OfflineSpeakerSegmentationPyannoteModelConfig(
              model: segmentationModelPath,
            ),
            numThreads: 1,
            debug: false,
          ),
          embedding: sherpa.SpeakerEmbeddingExtractorConfig(
            model: embeddingModelPath,
            numThreads: 1,
            debug: false,
          ),
          clustering: sherpa.FastClusteringConfig(
            numClusters: args['speakerCount'] as int? ?? -1,
            threshold: 0.75,
          ),
          minDurationOn: 0.3,
          minDurationOff: 0.5,
        ),
      );
      diarizer = activeDiarizer;
      if (activeDiarizer.sampleRate != 16000) {
        throw StateError('说话人分离模型采样率必须为 16000 Hz');
      }
      final rawSegments = activeDiarizer.processWithCallback(
        samples: samples,
        callback: (processed, total) {
          sendPort.send({
            'type': 'progress',
            'progress': total <= 0 ? 0.0 : processed / total * 0.55,
            'text': pieces.join('\n\n'),
            'stage': 'diarizing',
          });
          return 0;
        },
      );
      activeDiarizer.free();
      diarizer = null;
      final segments = _mergeDiarizationSegments(rawSegments);
      if (segments.isEmpty) {
        throw StateError('没有检测到可区分的说话区间');
      }
      activeRecognizer = createRecognizer();
      recognizer = activeRecognizer;
      for (var index = 0; index < segments.length; index++) {
        final segment = segments[index];
        final start = (segment.start * 16000).floor().clamp(0, samples.length);
        final end = (segment.end * 16000).ceil().clamp(start, samples.length);
        final text = recognize(
          Float32List.sublistView(samples, start, end),
          sampleRate: 16000,
        );
        if (text.isNotEmpty) {
          pieces.add(
            '说话人 ${segment.speaker + 1}'
            '（${_formatSegmentTime(segment.start)}–'
            '${_formatSegmentTime(segment.end)}）：$text',
          );
        }
        sendPort.send({
          'type': 'progress',
          'progress': segments.isEmpty
              ? 1.0
              : 0.55 + (index + 1) / segments.length * 0.45,
          'text': pieces.join('\n\n'),
          'stage': 'recognizing',
        });
      }
    } else if (vadModelPath.isNotEmpty && activeWave.sampleRate == 16000) {
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
          recognizeAndAppend(segment.samples);
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
        recognizeAndAppend(samples);
        completedFrames += samples.length;
        report(completedFrames);
      }
    }
    sendPort.send({
      'type': 'result',
      'text': pieces.join(segmentationModelPath.isEmpty ? '\n' : '\n\n'),
    });
  } catch (error) {
    sendPort.send({'type': 'error', 'message': error.toString()});
  } finally {
    wave?.close();
    vad?.free();
    diarizer?.free();
    recognizer?.free();
  }
}

Float32List _resampleLinear(Float32List input, int sourceRate, int targetRate) {
  if (input.isEmpty || sourceRate == targetRate) return input;
  if (sourceRate <= 0 || targetRate <= 0) {
    throw const FormatException('音频采样率无效');
  }
  final outputLength = (input.length * targetRate / sourceRate).round();
  final output = Float32List(outputLength);
  final ratio = sourceRate / targetRate;
  for (var index = 0; index < outputLength; index++) {
    final position = index * ratio;
    final lower = position.floor().clamp(0, input.length - 1);
    final upper = (lower + 1).clamp(0, input.length - 1);
    final fraction = position - lower;
    output[index] = input[lower] * (1 - fraction) + input[upper] * fraction;
  }
  return output;
}

List<sherpa.OfflineSpeakerDiarizationSegment> _mergeDiarizationSegments(
  List<sherpa.OfflineSpeakerDiarizationSegment> segments,
) {
  if (segments.isEmpty) return const [];
  final merged = <sherpa.OfflineSpeakerDiarizationSegment>[];
  for (final segment in segments) {
    if (segment.end <= segment.start) continue;
    final previous = merged.isEmpty ? null : merged.last;
    if (previous != null &&
        previous.speaker == segment.speaker &&
        segment.start <= previous.end + 0.35) {
      merged[merged.length - 1] = sherpa.OfflineSpeakerDiarizationSegment(
        start: previous.start,
        end: math.max(previous.end, segment.end),
        speaker: previous.speaker,
      );
    } else {
      merged.add(segment);
    }
  }
  return merged;
}

String _formatSegmentTime(double seconds) {
  final total = seconds.round().clamp(0, 24 * 60 * 60 - 1);
  final minutes = total ~/ 60;
  final remainingSeconds = total.remainder(60);
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainingSeconds.toString().padLeft(2, '0')}';
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
