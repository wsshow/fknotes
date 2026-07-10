import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'streaming_speech_model_service.dart';

enum RealtimeDictationStatus { idle, preparing, listening, stopping, failed }

/// Owns one device-local streaming dictation session.
///
/// Microphone capture stays on the platform recorder while all OnlineRecognizer
/// inference runs in a worker isolate, keeping editor gestures and animation
/// responsive as partial text changes.
class RealtimeDictationService extends ChangeNotifier {
  RealtimeDictationService._();
  static final RealtimeDictationService instance = RealtimeDictationService._();

  final _models = StreamingSpeechModelService.instance;
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

  String get text => '$committedText$partialText';

  Future<void> start() async {
    if (isActive) return;
    status = RealtimeDictationStatus.preparing;
    committedText = '';
    partialText = '';
    errorMessage = null;
    elapsed = Duration.zero;
    inputLevel = 0;
    notifyListeners();
    try {
      final model = await _models.inspect();
      if (!model.installed) throw StateError('请先下载实时语音输入模型');
      var permission = await Permission.microphone.status;
      if (!permission.isGranted) {
        permission = await Permission.microphone.request();
      }
      if (!permission.isGranted) throw StateError('需要麦克风权限才能实时听写');
      await _startWorker(model);
      final recorder = AudioRecorder();
      _recorder = recorder;
      final supported = await recorder.isEncoderSupported(
        AudioEncoder.pcm16bits,
      );
      if (!supported) throw UnsupportedError('当前设备不支持 PCM 实时录音');
      final audio = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
          streamBufferSize: 3200,
        ),
      );
      _audioSubscription = audio.listen(
        _sendAudio,
        onError: (Object error) => _fail(error),
      );
      status = RealtimeDictationStatus.listening;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsed += const Duration(seconds: 1);
        notifyListeners();
      });
      notifyListeners();
    } catch (error) {
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
    _timer?.cancel();
    notifyListeners();
    try {
      await _recorder?.stop();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _commandPort?.send(const {'type': 'stop'});
      final result = await (_resultCompleter?.future ?? Future.value(text))
          .timeout(const Duration(seconds: 12));
      committedText = result.trim();
      partialText = '';
      status = RealtimeDictationStatus.idle;
      return committedText;
    } catch (error) {
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

  Future<void> _startWorker(StreamingSpeechModelInfo model) async {
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
        _commandPort = message['commandPort'] as SendPort?;
        if (!(_readyCompleter?.isCompleted ?? true)) {
          _readyCompleter!.complete();
        }
        return;
      case 'update':
        committedText = message['committed'] as String? ?? committedText;
        partialText = message['partial'] as String? ?? partialText;
        notifyListeners();
        return;
      case 'done':
        final result = message['text'] as String? ?? text;
        if (!(_resultCompleter?.isCompleted ?? true)) {
          _resultCompleter!.complete(result);
        }
        return;
      case 'error':
        _fail(StateError(message['message'] as String? ?? '实时语音识别失败'));
        return;
    }
  }

  void _sendAudio(Uint8List bytes) {
    if (status != RealtimeDictationStatus.listening || bytes.isEmpty) return;
    inputLevel = _pcmLevel(bytes);
    _commandPort?.send({
      'type': 'audio',
      'data': TransferableTypedData.fromList([bytes]),
    });
    notifyListeners();
  }

  void _fail(Object error) {
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
  }

  double _pcmLevel(Uint8List bytes) {
    final evenLength = bytes.length - bytes.length.remainder(2);
    if (evenLength < 2) return 0;
    final data = ByteData.sublistView(bytes, 0, evenLength);
    var squares = 0.0;
    final samples = evenLength ~/ 2;
    for (var offset = 0; offset < evenLength; offset += 2) {
      final value = data.getInt16(offset, Endian.little) / 32768.0;
      squares += value * value;
    }
    final rms = math.sqrt(squares / samples);
    return (rms * 5).clamp(0.0, 1.0);
  }

  String _friendlyError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Bad state: |StateError: |Exception: |Unsupported operation: )'),
    '',
  );
}

@pragma('vm:entry-point')
void _realtimeRecognitionWorker(Map<String, Object> args) {
  final sendPort = args['sendPort'] as SendPort;
  final commands = ReceivePort();
  sherpa.OnlineRecognizer? recognizer;
  sherpa.OnlineStream? stream;
  var committed = '';
  var lastPartial = '';

  void sendUpdate(String partial) {
    if (partial == lastPartial && partial.isNotEmpty) return;
    lastPartial = partial;
    sendPort.send({
      'type': 'update',
      'committed': committed,
      'partial': partial,
    });
  }

  void finishSegment(String value) {
    final segment = value.trim();
    if (segment.isEmpty) return;
    committed = _joinDictationSegments(committed, segment);
    lastPartial = '';
  }

  try {
    sherpa.initBindings();
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
          modelType: 'zipformer',
        ),
        enableEndpoint: true,
        rule1MinTrailingSilence: 2.0,
        rule2MinTrailingSilence: 0.9,
        rule3MinUtteranceLength: 20,
      ),
    );
    stream = recognizer.createStream();
    sendPort.send({'type': 'ready', 'commandPort': commands.sendPort});
    commands.listen((dynamic raw) {
      if (raw is! Map) return;
      try {
        if (raw['type'] == 'audio') {
          final payload = raw['data'] as TransferableTypedData;
          final samples = _pcm16ToFloat(payload.materialize().asUint8List());
          stream!.acceptWaveform(samples: samples, sampleRate: 16000);
          while (recognizer!.isReady(stream!)) {
            recognizer!.decode(stream!);
          }
          final result = recognizer!.getResult(stream!).text.trim();
          if (recognizer!.isEndpoint(stream!)) {
            finishSegment(result);
            recognizer!.reset(stream!);
            sendUpdate('');
          } else {
            sendUpdate(result);
          }
          return;
        }
        if (raw['type'] == 'stop') {
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
  }
}

Float32List _pcm16ToFloat(Uint8List bytes) {
  final evenLength = bytes.length - bytes.length.remainder(2);
  final data = ByteData.sublistView(bytes, 0, evenLength);
  final samples = Float32List(evenLength ~/ 2);
  for (var index = 0; index < samples.length; index++) {
    samples[index] = data.getInt16(index * 2, Endian.little) / 32768.0;
  }
  return samples;
}

String _joinDictationSegments(String current, String segment) {
  if (current.isEmpty) return segment;
  if (RegExp(r'[。！？!?；;，,\n]$').hasMatch(current)) {
    return '$current$segment';
  }
  return '$current。$segment';
}
