import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'realtime_dictation_preferences_service.dart';
import 'realtime_dictation_text_policy.dart';
import 'speech_denoiser_model_service.dart';
import 'speech_transcription_service.dart';
import 'streaming_speech_model_service.dart';

enum RealtimeDictationStatus { idle, preparing, listening, stopping, failed }

const _initialSilenceEndpointSeconds = 15.0;
const _recognizedSpeechEndpointSeconds = 1.2;
const _maximumUtteranceSeconds = 20.0;
const _emptyStreamRecycleSeconds = 30.0;
const _stalledRecognizerRecoverySeconds = 10;
const _audibleSpeechRmsDb = -38.0;

/// Owns one device-local streaming dictation session.
///
/// Microphone capture stays on the platform recorder while all OnlineRecognizer
/// inference runs in a worker isolate, keeping editor gestures and animation
/// responsive as partial text changes.
class RealtimeDictationService extends ChangeNotifier {
  RealtimeDictationService._();
  static final RealtimeDictationService instance = RealtimeDictationService._();

  final _models = StreamingSpeechModelService.instance;
  final _preferences = RealtimeDictationPreferencesService.instance;
  final _denoiserModels = SpeechDenoiserModelService.instance;
  final _transcription = SpeechTranscriptionService.instance;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<dynamic>? _messageSubscription;
  StreamSubscription<dynamic>? _errorSubscription;
  StreamSubscription<dynamic>? _exitSubscription;
  ReceivePort? _messages;
  ReceivePort? _errors;
  ReceivePort? _exits;
  Isolate? _worker;
  SendPort? _commandPort;
  Completer<void>? _readyCompleter;
  Completer<String>? _resultCompleter;
  Timer? _timer;
  int _debugSamples = 0;
  int _debugNonZeroSamples = 0;
  double _debugSquares = 0;
  double _debugPeak = 0;
  double _debugSampleSum = 0;
  int _debugClippedSamples = 0;
  int _debugZeroCrossings = 0;
  int _debugTotalChunks = 0;
  int _debugTotalBytes = 0;
  int _debugTotalSamples = 0;
  double _debugLastRmsDb = -160;
  double _debugLastPeakDb = -160;
  double _debugLastNonZeroPercent = 0;
  double _debugLastDcOffsetPercent = 0;
  double _debugLastClippedPercent = 0;
  double _debugLastZeroCrossingPercent = 0;
  DateTime? _debugStartedAt;
  final List<String> _debugEvents = [];
  BytesBuilder _debugPcm = BytesBuilder(copy: false);
  bool _debugPcmTruncated = false;
  BytesBuilder _recoveryPcm = BytesBuilder(copy: true);
  bool _recoveryRequested = false;
  double _sessionMaxRms = 0;
  String _debugNativeRuntime = '-';
  String _debugNativeAbi = '-';
  String _debugCpuFingerprint = '-';
  String _debugModelId = '-';
  String _debugModelName = '-';
  int _debugHotwordsCount = 0;
  double _debugHotwordsScore = 0;
  int _debugWorkerChunks = 0;
  int _debugWorkerSamples = 0;
  int _debugAsrInputSamples = 0;
  int _debugDecodeCalls = 0;
  double _debugWorkerRmsDb = -160;
  double _debugWorkerPeakDb = -160;
  String _debugTwoPassStatus = '未请求';
  String _debugNoiseSuppressionStatus = '未请求';
  RandomAccessFile? _refinementWaveOutput;
  String? _refinementWavePath;
  Future<void> _refinementWrites = Future<void>.value();
  int _refinementPcmBytes = 0;
  Object? _refinementWriteError;

  static const _debugPcmLimitBytes = 16000 * 2 * 300;

  RealtimeDictationStatus status = RealtimeDictationStatus.idle;
  String committedText = '';
  String partialText = '';
  String? errorMessage;
  Duration elapsed = Duration.zero;
  double inputLevel = 0;

  bool get isActive => switch (status) {
    RealtimeDictationStatus.preparing ||
    RealtimeDictationStatus.listening ||
    RealtimeDictationStatus.stopping => true,
    _ => false,
  };

  bool get debugAudioAvailable => kDebugMode && _debugPcm.length > 0;

  String get text => '$committedText$partialText';

  String get debugReport {
    if (!kDebugMode) return '';
    final now = DateTime.now();
    final sessionSeconds = _debugStartedAt == null
        ? 0.0
        : now.difference(_debugStartedAt!).inMilliseconds / 1000;
    return [
      'FKNotes 实时听写诊断',
      '生成时间: ${_debugTimestamp(now)}',
      '平台: ${defaultTargetPlatform.name}',
      '构建模式: debug',
      '状态: ${status.name}',
      '会话时长: ${sessionSeconds.toStringAsFixed(1)} s',
      '界面计时: ${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s',
      '错误: ${errorMessage ?? '-'}',
      '',
      '[模型]',
      'ID: $_debugModelId',
      '名称: $_debugModelName',
      '类型: zipformer2',
      '线程数: 2',
      '端点规则: 15.0 / 1.2 / 20 s',
      '空流回收: 30 s（仅无任何 token 时）',
      '原生运行库: $_debugNativeRuntime',
      '原生 ABI: $_debugNativeAbi',
      'CPU 指纹: $_debugCpuFingerprint',
      '热词: ${_debugHotwordsCount == 0 ? "未启用" : "$_debugHotwordsCount 个"}',
      if (_debugHotwordsCount > 0)
        '热词增强强度: ${_debugHotwordsScore.toStringAsFixed(1)}',
      '',
      '[录音配置]',
      '编码: PCM16 little-endian',
      '采样率: 16000 Hz',
      '声道: mono',
      'Android 音源: VOICE_RECOGNITION',
      '分块: 3200 bytes / 100 ms',
      '自动蓝牙路由: false',
      '软件增益: false',
      '',
      '[实时统计]',
      '音频块: $_debugTotalChunks',
      '音频字节: $_debugTotalBytes',
      '音频采样: $_debugTotalSamples',
      '收到音频时长: ${(_debugTotalSamples / 16000).toStringAsFixed(2)} s',
      '最近 RMS: ${_debugLastRmsDb.toStringAsFixed(1)} dBFS',
      '最近峰值: ${_debugLastPeakDb.toStringAsFixed(1)} dBFS',
      '最近非零采样: ${_debugLastNonZeroPercent.toStringAsFixed(1)}%',
      '最近直流偏置: ${_debugLastDcOffsetPercent.toStringAsFixed(3)}%',
      '最近削波采样: ${_debugLastClippedPercent.toStringAsFixed(3)}%',
      '最近过零率: ${_debugLastZeroCrossingPercent.toStringAsFixed(1)}%',
      '当前音量值: ${inputLevel.toStringAsFixed(3)}',
      '诊断录音: ${(_debugPcm.length / 32000).toStringAsFixed(2)} s'
          '${_debugPcmTruncated ? '（已截断至 5 分钟）' : ''}',
      'Worker 音频块: $_debugWorkerChunks',
      'Worker 音频采样: $_debugWorkerSamples',
      'ASR 输入采样: $_debugAsrInputSamples',
      'Worker 最近 RMS: ${_debugWorkerRmsDb.toStringAsFixed(1)} dBFS',
      'Worker 最近峰值: ${_debugWorkerPeakDb.toStringAsFixed(1)} dBFS',
      '原生 decode 调用: $_debugDecodeCalls',
      '自动恢复重放: ${_recoveryRequested ? "已触发" : "未触发"}',
      '实时降噪: $_debugNoiseSuppressionStatus',
      '结束后精修: $_debugTwoPassStatus',
      '已提交文本: ${committedText.isEmpty ? '-' : committedText}',
      '临时文本: ${partialText.isEmpty ? '-' : partialText}',
      '',
      '[事件时间线]',
      if (_debugEvents.isEmpty) '- 暂无事件' else ..._debugEvents,
    ].join('\n');
  }

  void clearDebugDiagnostics() {
    if (!kDebugMode) return;
    _debugEvents.clear();
    _debugEvent('诊断时间线已清空');
    notifyListeners();
  }

  Future<void> start() async {
    if (isActive) return;
    status = RealtimeDictationStatus.preparing;
    committedText = '';
    partialText = '';
    errorMessage = null;
    elapsed = Duration.zero;
    inputLevel = 0;
    if (kDebugMode) {
      _debugStartedAt = DateTime.now();
      _debugEvents.clear();
      _debugTotalChunks = 0;
      _debugTotalBytes = 0;
      _debugTotalSamples = 0;
      _debugLastRmsDb = -160;
      _debugLastPeakDb = -160;
      _debugLastNonZeroPercent = 0;
      _debugLastDcOffsetPercent = 0;
      _debugLastClippedPercent = 0;
      _debugLastZeroCrossingPercent = 0;
      _debugPcm = BytesBuilder(copy: false);
      _debugPcmTruncated = false;
      _debugNativeRuntime = '-';
      _debugNativeAbi = '-';
      _debugCpuFingerprint = '-';
      _debugModelId = '-';
      _debugModelName = '-';
      _debugHotwordsCount = 0;
      _debugHotwordsScore = 0;
      _debugWorkerChunks = 0;
      _debugWorkerSamples = 0;
      _debugAsrInputSamples = 0;
      _debugDecodeCalls = 0;
      _debugWorkerRmsDb = -160;
      _debugWorkerPeakDb = -160;
      _debugTwoPassStatus = '未请求';
      _debugNoiseSuppressionStatus = '未请求';
      _debugEvent('开始准备实时听写');
    }
    _recoveryPcm = BytesBuilder(copy: true);
    _recoveryRequested = false;
    _sessionMaxRms = 0;
    _resetDebugAudioWindow();
    notifyListeners();
    try {
      final model = await _models.inspect(verifyIntegrity: true);
      _debugModelId = model.modelId;
      _debugModelName = model.displayName;
      _debugEvent(
        '模型完整性检查: id=${model.modelId}, '
        'installed=${model.installed}, problem=${model.problem ?? "-"}',
      );
      if (!model.installed) {
        throw StateError(model.problem ?? '请先下载实时语音输入模型');
      }
      final preferences = await _preferences.load();
      _debugHotwordsCount = preferences.hotwords.length;
      _debugHotwordsScore = preferences.hotwordsScore;
      _debugEvent(
        preferences.hotwordsEnabled
            ? '热词配置: ${preferences.hotwords.length} 个，'
                  'score=${preferences.hotwordsScore.toStringAsFixed(1)}'
            : '热词配置: 未启用',
      );
      var denoiserModelPath = '';
      if (preferences.noiseSuppressionEnabled) {
        final denoiser = await _denoiserModels.inspect(verifyIntegrity: true);
        if (!denoiser.installed) {
          throw StateError(denoiser.problem ?? '请先下载实时降噪模型');
        }
        denoiserModelPath = denoiser.modelPath;
        _debugNoiseSuppressionStatus = '已启用';
        _debugEvent('实时降噪: DPDFNet Baseline 完整性检查通过');
      } else {
        _debugNoiseSuppressionStatus = '已关闭';
        _debugEvent('实时降噪: 已关闭');
      }
      if (preferences.twoPassEnabled &&
          await _transcription.realtimeRefinementAvailable()) {
        try {
          await _prepareRefinementCapture();
          _debugTwoPassStatus = '等待录音完成';
          _debugEvent('结束后精修: 已启用，SenseVoice 可用');
        } catch (error) {
          _debugTwoPassStatus = '录音初始化失败，已跳过';
          _debugEvent('结束后精修初始化失败: $error');
        }
      } else {
        _debugTwoPassStatus = preferences.twoPassEnabled ? '模型未安装' : '已关闭';
        _debugEvent('结束后精修: $_debugTwoPassStatus');
      }
      var permission = await Permission.microphone.status;
      if (!permission.isGranted) {
        permission = await Permission.microphone.request();
      }
      if (!permission.isGranted) throw StateError('需要麦克风权限才能实时听写');
      _debugEvent('麦克风权限: granted');
      await _startWorker(model, preferences, denoiserModelPath);
      final recorder = AudioRecorder();
      _recorder = recorder;
      final supported = await recorder.isEncoderSupported(
        AudioEncoder.pcm16bits,
      );
      if (!supported) throw UnsupportedError('当前设备不支持 PCM 实时录音');
      _debugEvent('PCM16 编码支持: true');
      final audio = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          // Select the physical microphone explicitly. Keep Bluetooth routing
          // disabled until the editor offers an input device picker, otherwise
          // a connected headset can silently replace the phone microphone.
          androidConfig: AndroidRecordConfig(
            manageBluetooth: false,
            // Android defines this source specifically for speech recognition.
            // It lets the device select its ASR-tuned microphone path without
            // adding any FKNotes-side software gain.
            audioSource: AndroidAudioSource.voiceRecognition,
          ),
          // 100 ms of mono PCM16 at 16 kHz. Fixed, frame-aligned chunks keep
          // streaming latency predictable across Android vendors.
          streamBufferSize: 3200,
        ),
      );
      _audioSubscription = audio.listen(
        _sendAudio,
        onError: (Object error) => _fail(error),
      );
      status = RealtimeDictationStatus.listening;
      _debugEvent('录音流已启动，进入 listening');
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsed += const Duration(seconds: 1);
        _recoverStalledRecognizerIfNeeded();
        notifyListeners();
      });
      notifyListeners();
    } catch (error) {
      _debugEvent('启动失败: $error');
      await _cleanup(killWorker: true);
      status = RealtimeDictationStatus.failed;
      errorMessage = _friendlyError(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<String> stop() async {
    if (!isActive) return text;
    status = RealtimeDictationStatus.stopping;
    _debugEvent('用户请求完成，进入 stopping');
    _timer?.cancel();
    notifyListeners();
    try {
      await _recorder?.stop();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _commandPort?.send(const {'type': 'stop'});
      final streamingResult =
          await (_resultCompleter?.future ?? Future.value(text)).timeout(
            const Duration(seconds: 12),
          );
      committedText = streamingResult.trim();
      partialText = '';
      final refinementWave = await _finalizeRefinementCapture();
      if (refinementWave != null) {
        _debugTwoPassStatus = '正在精修';
        _debugEvent('开始 SenseVoice 结束后精修');
        notifyListeners();
        try {
          final refined = await _transcription.refineRealtimeWave(
            refinementWave,
          );
          if (refined != null) {
            final decision = chooseRealtimeRefinement(
              streamingText: streamingResult,
              refinedText: refined,
            );
            committedText = decision.text;
            if (decision.accepted) {
              _debugTwoPassStatus = '已采用 · ${decision.reason}';
              _debugEvent(
                '结束后精修已采用: reason=${decision.reason}, '
                'streaming="$streamingResult", refined="$refined"',
              );
            } else {
              _debugTwoPassStatus = '已拒绝，保留流式结果';
              _debugEvent(
                '结束后精修已拒绝: reason=${decision.reason}, '
                'streaming="$streamingResult", refined="$refined"',
              );
            }
          } else {
            _debugTwoPassStatus = '无有效文本，保留流式结果';
            _debugEvent('结束后精修未产生文本，保留流式结果');
          }
        } catch (error) {
          _debugTwoPassStatus = '失败，已保留流式结果';
          _debugEvent('结束后精修失败，保留流式结果: $error');
        }
      }
      if (committedText.isEmpty &&
          _amplitudeDb(_sessionMaxRms) >= _audibleSpeechRmsDb) {
        throw StateError(
          '识别器已收到清晰语音并执行解码，但没有产生 token；'
          '请导出诊断报告（其中已包含原生版本、ABI 和 Worker 输入统计）',
        );
      }
      status = RealtimeDictationStatus.idle;
      _debugEvent('识别完成: ${committedText.isEmpty ? "无文本" : committedText}');
      return committedText;
    } catch (error) {
      _debugEvent('停止失败: $error');
      status = RealtimeDictationStatus.failed;
      errorMessage = _friendlyError(error);
      rethrow;
    } finally {
      await _cleanup(killWorker: true);
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    if (!isActive && status != RealtimeDictationStatus.failed) return;
    _timer?.cancel();
    try {
      _debugEvent('用户取消实时听写');
      await _recorder?.cancel();
    } finally {
      committedText = '';
      partialText = '';
      errorMessage = null;
      elapsed = Duration.zero;
      inputLevel = 0;
      status = RealtimeDictationStatus.idle;
      await _cleanup(killWorker: true);
      notifyListeners();
    }
  }

  Future<void> _startWorker(
    StreamingSpeechModelInfo model,
    RealtimeDictationPreferences preferences,
    String denoiserModelPath,
  ) async {
    _messages = ReceivePort();
    _errors = ReceivePort();
    _exits = ReceivePort();
    _readyCompleter = Completer<void>();
    _resultCompleter = Completer<String>();
    // A runtime worker error can arrive before the user presses Stop. Attach a
    // listener immediately so the zone never treats that delayed result as an
    // unhandled asynchronous error; stop() still observes the original future.
    unawaited(_resultCompleter!.future.catchError((_) => text));
    _messageSubscription = _messages!.listen(_handleWorkerMessage);
    _errorSubscription = _errors!.listen((dynamic error) => _fail(error));
    _exitSubscription = _exits!.listen((_) {
      _debugEvent('识别工作线程退出');
      if (isActive && !(_resultCompleter?.isCompleted ?? true)) {
        _fail(StateError('实时语音识别进程意外结束'));
      }
    });
    _worker = await Isolate.spawn<Map<String, Object>>(
      _realtimeRecognitionWorker,
      {
        'sendPort': _messages!.sendPort,
        'encoderPath': model.encoderPath,
        'decoderPath': model.decoderPath,
        'joinerPath': model.joinerPath,
        'tokensPath': model.tokensPath,
        'modelingUnit': model.modelingUnit,
        'bpeVocabPath': model.bpeVocabPath,
        'hotwordsFilePath': preferences.hotwordsEnabled
            ? _preferences.hotwordsFilePath
            : '',
        'hotwordsScore': preferences.hotwordsScore,
        'denoiserModelPath': denoiserModelPath,
      },
      onError: _errors!.sendPort,
      onExit: _exits!.sendPort,
    );
    await _readyCompleter!.future.timeout(const Duration(seconds: 20));
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is! Map) return;
    switch (message['type']) {
      case 'ready':
        _debugNativeRuntime = message['runtime'] as String? ?? '-';
        _debugNativeAbi = message['abi'] as String? ?? '-';
        _debugCpuFingerprint = message['cpu'] as String? ?? '-';
        if (message['denoiserEnabled'] == true) {
          _debugNoiseSuppressionStatus =
              '已启用 · frameShift=${message['denoiserFrameShift']} samples';
        }
        _debugEvent(
          '识别工作线程已就绪: runtime=$_debugNativeRuntime, '
          'abi=$_debugNativeAbi, cpu=$_debugCpuFingerprint',
        );
        _commandPort = message['commandPort'] as SendPort?;
        if (!(_readyCompleter?.isCompleted ?? true)) {
          _readyCompleter!.complete();
        }
        return;
      case 'update':
        committedText = message['committed'] as String? ?? committedText;
        partialText = message['partial'] as String? ?? partialText;
        _debugEvent('文本更新: committed="$committedText", partial="$partialText"');
        notifyListeners();
        return;
      case 'done':
        final result = message['text'] as String? ?? text;
        _debugEvent('工作线程完成: "$result"');
        if (!(_resultCompleter?.isCompleted ?? true)) {
          _resultCompleter!.complete(result);
        }
        return;
      case 'error':
        _debugEvent('工作线程错误: ${message['message']}');
        _fail(StateError(message['message'] as String? ?? '实时语音识别失败'));
        return;
      case 'debug':
        final details = [
          if (message['reason'] != null) 'reason=${message['reason']}',
          if (message['droppedPrefixLength'] != null)
            'dropped=${message['droppedPrefixLength']}',
          if (message['merged'] != null) 'merged="${message['merged']}"',
        ].join(', ');
        _debugEvent(
          '解码事件: ${message['event']}, text="${message['text'] ?? ''}"'
          '${details.isEmpty ? '' : ', $details'}',
        );
        return;
      case 'telemetry':
        _debugWorkerChunks = message['chunks'] as int? ?? _debugWorkerChunks;
        _debugWorkerSamples = message['samples'] as int? ?? _debugWorkerSamples;
        _debugAsrInputSamples =
            message['asrInputSamples'] as int? ?? _debugAsrInputSamples;
        _debugDecodeCalls = message['decodeCalls'] as int? ?? _debugDecodeCalls;
        _debugWorkerRmsDb =
            (message['rmsDb'] as num?)?.toDouble() ?? _debugWorkerRmsDb;
        _debugWorkerPeakDb =
            (message['peakDb'] as num?)?.toDouble() ?? _debugWorkerPeakDb;
        _debugEvent(
          'Worker PCM: chunks=$_debugWorkerChunks, '
          'samples=$_debugWorkerSamples, '
          'asrInputSamples=$_debugAsrInputSamples, '
          'rms=${_debugWorkerRmsDb.toStringAsFixed(1)} dBFS, '
          'peak=${_debugWorkerPeakDb.toStringAsFixed(1)} dBFS, '
          'decodeCalls=$_debugDecodeCalls',
        );
        return;
    }
  }

  void _sendAudio(Uint8List bytes) {
    if (status != RealtimeDictationStatus.listening || bytes.isEmpty) return;
    _queueRefinementAudio(bytes);
    final stats = _pcmStats(bytes);
    inputLevel = stats.level;
    _sessionMaxRms = math.max(
      _sessionMaxRms,
      stats.samples == 0 ? 0 : math.sqrt(stats.squares / stats.samples),
    );
    final recoveryRemaining = _debugPcmLimitBytes - _recoveryPcm.length;
    if (recoveryRemaining > 0) {
      _recoveryPcm.add(
        recoveryRemaining >= bytes.length
            ? bytes
            : bytes.sublist(0, recoveryRemaining),
      );
    }
    if (kDebugMode) {
      final remaining = _debugPcmLimitBytes - _debugPcm.length;
      if (remaining > 0) {
        _debugPcm.add(
          remaining >= bytes.length ? bytes : bytes.sublist(0, remaining),
        );
      }
      if (remaining < bytes.length) _debugPcmTruncated = true;
      _debugTotalChunks++;
      _debugTotalBytes += bytes.length;
      _debugTotalSamples += stats.samples;
      _debugSamples += stats.samples;
      _debugNonZeroSamples += stats.nonZeroSamples;
      _debugSquares += stats.squares;
      _debugPeak = math.max(_debugPeak, stats.peak);
      _debugSampleSum += stats.sampleSum;
      _debugClippedSamples += stats.clippedSamples;
      _debugZeroCrossings += stats.zeroCrossings;
      if (_debugSamples >= 16000) {
        final rms = math.sqrt(_debugSquares / _debugSamples);
        final nonZeroRatio = _debugNonZeroSamples / _debugSamples;
        _debugLastRmsDb = _amplitudeDb(rms);
        _debugLastPeakDb = _amplitudeDb(_debugPeak);
        _debugLastNonZeroPercent = nonZeroRatio * 100;
        _debugLastDcOffsetPercent =
            (_debugSampleSum / _debugSamples).abs() * 100;
        _debugLastClippedPercent = _debugClippedSamples / _debugSamples * 100;
        _debugLastZeroCrossingPercent =
            _debugZeroCrossings / _debugSamples * 100;
        _debugEvent(
          'PCM: samples=$_debugSamples, '
          'rms=${_debugLastRmsDb.toStringAsFixed(1)} dBFS, '
          'peak=${_debugLastPeakDb.toStringAsFixed(1)} dBFS, '
          'nonZero=${_debugLastNonZeroPercent.toStringAsFixed(1)}%, '
          'dc=${_debugLastDcOffsetPercent.toStringAsFixed(3)}%, '
          'clip=${_debugLastClippedPercent.toStringAsFixed(3)}%, '
          'zcr=${_debugLastZeroCrossingPercent.toStringAsFixed(1)}%',
        );
        _resetDebugAudioWindow();
      }
    }
    _commandPort?.send({
      'type': 'audio',
      'data': TransferableTypedData.fromList([bytes]),
    });
    notifyListeners();
  }

  Future<void> _prepareRefinementCapture() async {
    await _discardRefinementCapture();
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'fknotes_asr_refinement'),
    );
    await directory.create(recursive: true);
    final path = p.join(
      directory.path,
      'live-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final output = await File(path).open(mode: FileMode.write);
    await output.writeFrom(_pcm16WaveHeader(0));
    _refinementWaveOutput = output;
    _refinementWavePath = path;
    _refinementWrites = Future<void>.value();
    _refinementPcmBytes = 0;
    _refinementWriteError = null;
  }

  void _queueRefinementAudio(Uint8List bytes) {
    final output = _refinementWaveOutput;
    if (output == null || _refinementWriteError != null) return;
    final ownedBytes = Uint8List.fromList(bytes);
    _refinementWrites = _refinementWrites
        .then((_) async {
          await output.writeFrom(ownedBytes);
          _refinementPcmBytes += ownedBytes.length;
        })
        .catchError((Object error) {
          _refinementWriteError = error;
        });
  }

  Future<String?> _finalizeRefinementCapture() async {
    final output = _refinementWaveOutput;
    final path = _refinementWavePath;
    if (output == null || path == null) return null;
    try {
      await _refinementWrites;
      final error = _refinementWriteError;
      if (error != null) throw FileSystemException('无法保存精修录音', path);
      await output.setPosition(0);
      await output.writeFrom(_pcm16WaveHeader(_refinementPcmBytes));
      await output.flush();
      await output.close();
      _refinementWaveOutput = null;
      return _refinementPcmBytes == 0 ? null : path;
    } catch (error) {
      _debugTwoPassStatus = '录音保存失败，已跳过';
      _debugEvent('结束后精修录音失败: $error');
      try {
        await output.close();
      } catch (_) {
        // The original capture failure may already have closed the handle.
      }
      _refinementWaveOutput = null;
      return null;
    }
  }

  Future<void> _discardRefinementCapture() async {
    try {
      await _refinementWrites;
    } catch (_) {
      // The streaming result remains usable when temporary capture fails.
    }
    try {
      await _refinementWaveOutput?.close();
    } catch (_) {
      // Cleanup is best-effort after recorder or worker failures.
    }
    _refinementWaveOutput = null;
    final path = _refinementWavePath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } on FileSystemException {
          // A concurrent platform cleanup may already have removed the file.
        }
      }
    }
    _refinementWavePath = null;
    _refinementWrites = Future<void>.value();
    _refinementPcmBytes = 0;
    _refinementWriteError = null;
  }

  void _recoverStalledRecognizerIfNeeded() {
    if (_recoveryRequested ||
        status != RealtimeDictationStatus.listening ||
        elapsed.inSeconds < _stalledRecognizerRecoverySeconds ||
        text.isNotEmpty ||
        _amplitudeDb(_sessionMaxRms) < _audibleSpeechRmsDb ||
        _recoveryPcm.isEmpty) {
      return;
    }
    _recoveryRequested = true;
    final pcm = _recoveryPcm.toBytes();
    _debugEvent(
      '检测到有声输入但持续零 token，重建解码流并重放 '
      '${(pcm.length / 32000).toStringAsFixed(2)} s 音频',
    );
    _commandPort?.send({
      'type': 'replay',
      'data': TransferableTypedData.fromList([pcm]),
    });
  }

  void _fail(Object error) {
    _debugEvent('会话失败: $error');
    if (!(_readyCompleter?.isCompleted ?? true)) {
      _readyCompleter!.completeError(error);
    }
    if (!(_resultCompleter?.isCompleted ?? true)) {
      _resultCompleter!.completeError(error);
    }
    errorMessage = _friendlyError(error);
    status = RealtimeDictationStatus.failed;
    notifyListeners();
    unawaited(_cleanup(killWorker: true));
  }

  Future<void> _cleanup({required bool killWorker}) async {
    _timer?.cancel();
    _timer = null;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _messageSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _exitSubscription?.cancel();
    _messageSubscription = null;
    _errorSubscription = null;
    _exitSubscription = null;
    if (killWorker) _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _commandPort = null;
    _messages?.close();
    _errors?.close();
    _exits?.close();
    _messages = null;
    _errors = null;
    _exits = null;
    await _recorder?.dispose();
    _recorder = null;
    _recoveryPcm = BytesBuilder(copy: true);
    await _discardRefinementCapture();
  }

  _PcmStats _pcmStats(Uint8List bytes) {
    final evenLength = bytes.length - bytes.length.remainder(2);
    if (evenLength < 2) return const _PcmStats.empty();
    final data = ByteData.sublistView(bytes, 0, evenLength);
    var squares = 0.0;
    var peak = 0.0;
    var nonZeroSamples = 0;
    var sampleSum = 0.0;
    var clippedSamples = 0;
    var zeroCrossings = 0;
    double? previous;
    final samples = evenLength ~/ 2;
    for (var offset = 0; offset < evenLength; offset += 2) {
      final value = data.getInt16(offset, Endian.little) / 32768.0;
      squares += value * value;
      sampleSum += value;
      peak = math.max(peak, value.abs());
      if (value != 0) nonZeroSamples++;
      if (value.abs() >= 0.999) clippedSamples++;
      if (previous != null &&
          ((previous < 0 && value >= 0) || (previous >= 0 && value < 0))) {
        zeroCrossings++;
      }
      previous = value;
    }
    final rms = math.sqrt(squares / samples);
    return _PcmStats(
      samples: samples,
      nonZeroSamples: nonZeroSamples,
      squares: squares,
      peak: peak,
      sampleSum: sampleSum,
      clippedSamples: clippedSamples,
      zeroCrossings: zeroCrossings,
      level: (rms * 5).clamp(0.0, 1.0),
    );
  }

  void _resetDebugAudioWindow() {
    _debugSamples = 0;
    _debugNonZeroSamples = 0;
    _debugSquares = 0;
    _debugPeak = 0;
    _debugSampleSum = 0;
    _debugClippedSamples = 0;
    _debugZeroCrossings = 0;
  }

  Future<File?> createDebugAudioExport() async {
    if (!debugAudioAvailable) return null;
    final now = DateTime.now();
    final stamp = now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'fknotes_asr_diagnostics'),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'fknotes-asr-debug-$stamp.wav'));
    await file.writeAsBytes(_pcm16Wave(_debugPcm.toBytes()), flush: true);
    _debugEvent('已导出模型输入录音: ${file.path}');
    notifyListeners();
    return file;
  }

  void _debugEvent(String message) {
    if (!kDebugMode) return;
    final line = '${_debugTimestamp(DateTime.now())}  $message';
    _debugEvents.add(line);
    if (_debugEvents.length > 300) _debugEvents.removeAt(0);
    debugPrint('FKNOTES_ASR $line');
  }

  String _friendlyError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Bad state: |StateError: |Exception: |Unsupported operation: )'),
    '',
  );
}

class _PcmStats {
  final int samples;
  final int nonZeroSamples;
  final double squares;
  final double peak;
  final double sampleSum;
  final int clippedSamples;
  final int zeroCrossings;
  final double level;

  const _PcmStats({
    required this.samples,
    required this.nonZeroSamples,
    required this.squares,
    required this.peak,
    required this.sampleSum,
    required this.clippedSamples,
    required this.zeroCrossings,
    required this.level,
  });

  const _PcmStats.empty()
    : samples = 0,
      nonZeroSamples = 0,
      squares = 0,
      peak = 0,
      sampleSum = 0,
      clippedSamples = 0,
      zeroCrossings = 0,
      level = 0;
}

Uint8List _pcm16Wave(Uint8List pcm) {
  final output = Uint8List(44 + pcm.length)
    ..setRange(0, 44, _pcm16WaveHeader(pcm.length))
    ..setRange(44, 44 + pcm.length, pcm);
  return output;
}

Uint8List _pcm16WaveHeader(int pcmBytes) {
  final output = Uint8List(44);
  final data = ByteData.sublistView(output);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      output[offset + index] = value.codeUnitAt(index);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + pcmBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, pcmBytes, Endian.little);
  return output;
}

double _amplitudeDb(double amplitude) {
  if (amplitude <= 0) return -160;
  return 20 * math.log(amplitude) / math.ln10;
}

String _debugTimestamp(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  String three(int number) => number.toString().padLeft(3, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}.'
      '${three(value.millisecond)}';
}

@pragma('vm:entry-point')
void _realtimeRecognitionWorker(Map<String, Object> args) {
  final sendPort = args['sendPort'] as SendPort;
  final commands = ReceivePort();
  sherpa.OnlineRecognizer? recognizer;
  sherpa.OnlineStream? stream;
  sherpa.OnlineSpeechDenoiser? denoiser;
  var committed = '';
  var lastPartial = '';
  var lastSentCommitted = '';
  var lastSentPartial = '';
  var emptyEndpointReported = false;
  var streamSamples = 0;
  var pcmDecoder = _Pcm16StreamDecoder();
  var workerChunks = 0;
  var workerSamples = 0;
  var asrInputSamples = 0;
  var decodeCalls = 0;
  var telemetrySamples = 0;
  var telemetrySquares = 0.0;
  var telemetryPeak = 0.0;
  var denoiserFrameShift = 0;
  var denoiserPending = Float32List(0);

  void sendUpdate(String partial) {
    if (committed == lastSentCommitted && partial == lastSentPartial) return;
    lastPartial = partial;
    lastSentCommitted = committed;
    lastSentPartial = partial;
    sendPort.send({
      'type': 'update',
      'committed': committed,
      'partial': partial,
    });
  }

  void finishSegment(String value) {
    final segment = value.trim();
    if (segment.isEmpty) return;
    final merge = mergeDictationSegment(committed, segment);
    committed = merge.text;
    if (kDebugMode && (merge.droppedPrefixLength > 0 || !merge.changed)) {
      sendPort.send({
        'type': 'debug',
        'event': 'segment_merge',
        'text': segment,
        'reason': merge.reason,
        'droppedPrefixLength': merge.droppedPrefixLength,
        'merged': committed,
      });
    }
    lastPartial = '';
  }

  void sendTelemetry() {
    if (telemetrySamples == 0) return;
    final rms = math.sqrt(telemetrySquares / telemetrySamples);
    sendPort.send({
      'type': 'telemetry',
      'chunks': workerChunks,
      'samples': workerSamples,
      'asrInputSamples': asrInputSamples,
      'decodeCalls': decodeCalls,
      'rmsDb': _amplitudeDb(rms),
      'peakDb': _amplitudeDb(telemetryPeak),
    });
    telemetrySamples = 0;
    telemetrySquares = 0;
    telemetryPeak = 0;
  }

  void decodeSamples(Float32List samples) {
    if (samples.isEmpty) return;
    asrInputSamples += samples.length;
    streamSamples += samples.length;
    stream!.acceptWaveform(samples: samples, sampleRate: 16000);
    while (recognizer!.isReady(stream!)) {
      recognizer!.decode(stream!);
      decodeCalls++;
    }
    final result = recognizer!.getResult(stream!).text.trim();
    if (kDebugMode && result != lastPartial) {
      sendPort.send({'type': 'debug', 'event': 'partial', 'text': result});
    }
    final isEndpoint = recognizer!.isEndpoint(stream!);
    if (isEndpoint && result.isNotEmpty) {
      if (kDebugMode) {
        sendPort.send({'type': 'debug', 'event': 'endpoint', 'text': result});
      }
      finishSegment(result);
      stream!.free();
      stream = recognizer!.createStream();
      streamSamples = 0;
      emptyEndpointReported = false;
      sendUpdate('');
    } else if (isEndpoint &&
        result.isEmpty &&
        streamSamples >= 16000 * _emptyStreamRecycleSeconds) {
      if (kDebugMode) {
        sendPort.send({
          'type': 'debug',
          'event': 'empty_stream_recycled',
          'text': '',
        });
      }
      stream!.free();
      stream = recognizer!.createStream();
      streamSamples = 0;
      emptyEndpointReported = false;
    } else {
      if (isEndpoint && !emptyEndpointReported && kDebugMode) {
        sendPort.send({
          'type': 'debug',
          'event': 'empty_endpoint_ignored',
          'text': '',
        });
        emptyEndpointReported = true;
      }
      if (!isEndpoint) emptyEndpointReported = false;
      sendUpdate(result);
    }
  }

  Float32List denoiseSamples(Float32List samples) {
    final activeDenoiser = denoiser;
    if (activeDenoiser == null || samples.isEmpty) return samples;
    final combined = Float32List(denoiserPending.length + samples.length)
      ..setAll(0, denoiserPending)
      ..setAll(denoiserPending.length, samples);
    final completeLength =
        combined.length - combined.length.remainder(denoiserFrameShift);
    denoiserPending = completeLength == combined.length
        ? Float32List(0)
        : Float32List.fromList(combined.sublist(completeLength));
    if (completeLength == 0) return Float32List(0);
    final output = <double>[];
    for (
      var offset = 0;
      offset < completeLength;
      offset += denoiserFrameShift
    ) {
      final enhanced = activeDenoiser.run(
        samples: Float32List.sublistView(
          combined,
          offset,
          offset + denoiserFrameShift,
        ),
        sampleRate: 16000,
      );
      if (enhanced.sampleRate != 0 && enhanced.sampleRate != 16000) {
        throw StateError('实时降噪输出采样率异常: ${enhanced.sampleRate}');
      }
      output.addAll(enhanced.samples);
    }
    return Float32List.fromList(output);
  }

  void processSamples(Float32List samples, {required bool liveInput}) {
    if (samples.isEmpty) return;
    if (liveInput) {
      workerChunks++;
      workerSamples += samples.length;
      telemetrySamples += samples.length;
      for (final sample in samples) {
        telemetrySquares += sample * sample;
        telemetryPeak = math.max(telemetryPeak, sample.abs());
      }
    }
    decodeSamples(denoiseSamples(samples));
    if (liveInput && telemetrySamples >= 16000) sendTelemetry();
  }

  try {
    sherpa.initBindings();
    final denoiserModelPath = args['denoiserModelPath'] as String? ?? '';
    if (denoiserModelPath.isNotEmpty) {
      denoiser = sherpa.OnlineSpeechDenoiser(
        sherpa.OnlineSpeechDenoiserConfig(
          model: sherpa.OfflineSpeechDenoiserModelConfig(
            dpdfnet: sherpa.OfflineSpeechDenoiserDpdfNetModelConfig(
              model: denoiserModelPath,
            ),
            numThreads: 1,
            debug: false,
          ),
        ),
      );
      if (denoiser.sampleRate != 16000) {
        throw StateError('实时降噪模型采样率必须为 16000 Hz');
      }
      denoiserFrameShift = denoiser.frameShiftInSamples;
      if (denoiserFrameShift <= 0) {
        throw StateError('实时降噪模型没有提供有效帧步长');
      }
    }
    recognizer = sherpa.OnlineRecognizer(
      sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: args['encoderPath'] as String,
            decoder: args['decoderPath'] as String,
            joiner: args['joinerPath'] as String,
          ),
          tokens: args['tokensPath'] as String,
          numThreads: 2,
          debug: false,
          // Match this model's official sherpa-onnx configuration exactly:
          // model type is inferred from ONNX metadata and tokens are CJK chars.
          modelType: '',
          modelingUnit: args['modelingUnit'] as String? ?? '',
          bpeVocab: args['bpeVocabPath'] as String? ?? '',
        ),
        decodingMethod: (args['hotwordsFilePath'] as String? ?? '').isNotEmpty
            ? 'modified_beam_search'
            : 'greedy_search',
        maxActivePaths: 4,
        hotwordsFile: args['hotwordsFilePath'] as String? ?? '',
        hotwordsScore: args['hotwordsScore'] as double? ?? 2.0,
        enableEndpoint: true,
        // Treat leading silence, recognized-speech pauses, and long
        // utterances as separate concerns. This mirrors mature continuous
        // dictation systems instead of using one silence timeout for all.
        rule1MinTrailingSilence: _initialSilenceEndpointSeconds,
        rule2MinTrailingSilence: _recognizedSpeechEndpointSeconds,
        rule3MinUtteranceLength: _maximumUtteranceSeconds,
      ),
    );
    stream = recognizer.createStream();
    sendPort.send({
      'type': 'ready',
      'commandPort': commands.sendPort,
      'runtime':
          '${sherpa.getVersion()} (${sherpa.getGitSha1()}, '
          '${sherpa.getGitDate()})',
      'abi': ffi.Abi.current().toString(),
      'cpu': _androidCpuFingerprint(),
      'denoiserEnabled': denoiser != null,
      'denoiserFrameShift': denoiserFrameShift,
    });
    commands.listen((dynamic raw) {
      if (raw is! Map) return;
      try {
        if (raw['type'] == 'audio') {
          final payload = raw['data'] as TransferableTypedData;
          final samples = pcmDecoder.add(payload.materialize().asUint8List());
          processSamples(samples, liveInput: true);
          return;
        }
        if (raw['type'] == 'replay') {
          sendPort.send({
            'type': 'debug',
            'event': 'stalled_stream_replay_started',
            'text': '',
          });
          stream!.free();
          stream = recognizer!.createStream();
          streamSamples = 0;
          emptyEndpointReported = false;
          pcmDecoder = _Pcm16StreamDecoder();
          denoiser?.reset();
          denoiserPending = Float32List(0);
          committed = '';
          lastPartial = '';
          lastSentCommitted = '';
          lastSentPartial = '';
          final payload = raw['data'] as TransferableTypedData;
          final bytes = payload.materialize().asUint8List();
          for (var offset = 0; offset < bytes.length; offset += 3200) {
            final end = math.min(offset + 3200, bytes.length);
            processSamples(
              pcmDecoder.add(Uint8List.sublistView(bytes, offset, end)),
              liveInput: false,
            );
          }
          sendPort.send({
            'type': 'debug',
            'event': 'stalled_stream_replay_finished',
            'text': '$committed$lastPartial',
          });
          return;
        }
        if (raw['type'] == 'stop') {
          sendTelemetry();
          final activeDenoiser = denoiser;
          if (activeDenoiser != null) {
            if (denoiserPending.isNotEmpty) {
              final enhanced = activeDenoiser.run(
                samples: denoiserPending,
                sampleRate: 16000,
              );
              decodeSamples(enhanced.samples);
              denoiserPending = Float32List(0);
            }
            decodeSamples(activeDenoiser.flush().samples);
          }
          stream!.inputFinished();
          while (recognizer!.isReady(stream!)) {
            recognizer!.decode(stream!);
          }
          finishSegment(recognizer!.getResult(stream!).text);
          sendPort.send({'type': 'done', 'text': committed});
          commands.close();
          stream?.free();
          stream = null;
          recognizer?.free();
          recognizer = null;
          denoiser?.free();
          denoiser = null;
        }
      } catch (error) {
        sendPort.send({'type': 'error', 'message': error.toString()});
      }
    });
  } catch (error) {
    sendPort.send({'type': 'error', 'message': error.toString()});
    commands.close();
    stream?.free();
    recognizer?.free();
    denoiser?.free();
  }
}

String _androidCpuFingerprint() {
  if (!Platform.isAndroid) return '-';
  try {
    const usefulKeys = {
      'hardware',
      'model name',
      'cpu implementer',
      'cpu architecture',
      'cpu variant',
      'cpu part',
      'cpu revision',
      'features',
    };
    final values = <String>{};
    for (final rawLine in File('/proc/cpuinfo').readAsLinesSync()) {
      final separator = rawLine.indexOf(':');
      if (separator < 0) continue;
      final key = rawLine.substring(0, separator).trim();
      if (!usefulKeys.contains(key.toLowerCase())) continue;
      final value = rawLine.substring(separator + 1).trim();
      if (value.isNotEmpty) values.add('$key=$value');
    }
    return ['cores=${Platform.numberOfProcessors}', ...values].join('; ');
  } catch (error) {
    return 'unavailable ($error)';
  }
}

class _Pcm16StreamDecoder {
  int? _pendingLowByte;

  Float32List add(Uint8List bytes) {
    if (bytes.isEmpty) return Float32List(0);
    final hasPendingByte = _pendingLowByte != null;
    final byteCount = bytes.length + (hasPendingByte ? 1 : 0);
    final sampleCount = byteCount ~/ 2;
    final samples = Float32List(sampleCount);
    var inputIndex = 0;
    var outputIndex = 0;

    if (hasPendingByte && bytes.isNotEmpty) {
      samples[outputIndex++] = _pcm16Sample(_pendingLowByte!, bytes[0]);
      _pendingLowByte = null;
      inputIndex = 1;
    }
    while (inputIndex + 1 < bytes.length) {
      samples[outputIndex++] = _pcm16Sample(
        bytes[inputIndex],
        bytes[inputIndex + 1],
      );
      inputIndex += 2;
    }
    if (inputIndex < bytes.length) {
      _pendingLowByte = bytes[inputIndex];
    }
    return samples;
  }
}

double _pcm16Sample(int lowByte, int highByte) {
  final unsigned = lowByte | (highByte << 8);
  final signed = unsigned >= 0x8000 ? unsigned - 0x10000 : unsigned;
  return signed / 32768.0;
}
