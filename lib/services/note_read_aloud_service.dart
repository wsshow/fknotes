import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'kokoro_tts_model_service.dart';

enum ReadAloudStatus { idle, generating, playing, paused, failed }

class NoteReadAloudService extends ChangeNotifier {
  NoteReadAloudService._() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(stop());
      } else if (state.playing && status != ReadAloudStatus.playing) {
        status = ReadAloudStatus.playing;
        notifyListeners();
      }
    });
  }

  static final NoteReadAloudService instance = NoteReadAloudService._();

  final _models = KokoroTtsModelService.instance;
  final AudioPlayer _player = AudioPlayer();
  Isolate? _worker;
  ReceivePort? _messages;
  ReceivePort? _errors;
  ReceivePort? _exits;
  StreamSubscription<dynamic>? _messageSubscription;
  StreamSubscription<dynamic>? _errorSubscription;
  StreamSubscription<dynamic>? _exitSubscription;
  Completer<String>? _generation;
  String? _temporaryWavePath;
  int _requestGeneration = 0;

  ReadAloudStatus status = ReadAloudStatus.idle;
  String? errorMessage;

  bool get isActive =>
      status != ReadAloudStatus.idle && status != ReadAloudStatus.failed;

  Future<void> speak(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) throw StateError('笔记中没有可朗读的文字');
    await stop();
    final requestGeneration = ++_requestGeneration;
    status = ReadAloudStatus.generating;
    errorMessage = null;
    notifyListeners();
    try {
      final model = await _models.inspect(verifyIntegrity: true);
      _ensureCurrent(requestGeneration);
      if (!model.installed) {
        throw StateError(model.problem ?? '请先下载离线朗读模型');
      }
      final directory = Directory(
        p.join((await getTemporaryDirectory()).path, 'fknotes_tts'),
      );
      await directory.create(recursive: true);
      _ensureCurrent(requestGeneration);
      final output = p.join(
        directory.path,
        'read-${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      _temporaryWavePath = output;
      await _generate(
        text.length > 3000 ? text.substring(0, 3000) : text,
        model,
        output,
      );
      _ensureCurrent(requestGeneration);
      await _player.setFilePath(output);
      _ensureCurrent(requestGeneration);
      status = ReadAloudStatus.playing;
      notifyListeners();
      await _player.play();
    } catch (error) {
      await _cleanupWorker();
      await _deleteTemporaryWave();
      if (error is _ReadAloudCanceled) {
        status = ReadAloudStatus.idle;
        errorMessage = null;
        notifyListeners();
        return;
      }
      status = ReadAloudStatus.failed;
      errorMessage = error.toString().replaceFirst(
        RegExp(r'^(Bad state: |StateError: |Exception: )'),
        '',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> pause() async {
    if (status != ReadAloudStatus.playing) return;
    await _player.pause();
    status = ReadAloudStatus.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    if (status != ReadAloudStatus.paused) return;
    status = ReadAloudStatus.playing;
    notifyListeners();
    await _player.play();
  }

  Future<void> stop() async {
    _requestGeneration++;
    await _player.stop();
    if (!(_generation?.isCompleted ?? true)) {
      _generation!.completeError(const _ReadAloudCanceled());
    }
    await _cleanupWorker();
    await _deleteTemporaryWave();
    status = ReadAloudStatus.idle;
    errorMessage = null;
    notifyListeners();
  }

  void _ensureCurrent(int generation) {
    if (generation != _requestGeneration) throw const _ReadAloudCanceled();
  }

  Future<void> _generate(
    String text,
    KokoroTtsModelInfo model,
    String output,
  ) async {
    _messages = ReceivePort();
    _errors = ReceivePort();
    _exits = ReceivePort();
    _generation = Completer<String>();
    _messageSubscription = _messages!.listen((dynamic message) {
      if (message is! Map) return;
      if (message['type'] == 'result' && !(_generation?.isCompleted ?? true)) {
        _generation!.complete(message['path'] as String? ?? '');
      } else if (message['type'] == 'error' &&
          !(_generation?.isCompleted ?? true)) {
        _generation!.completeError(
          StateError(message['message'] as String? ?? '语音合成失败'),
        );
      }
    });
    _errorSubscription = _errors!.listen((dynamic error) {
      if (!(_generation?.isCompleted ?? true)) {
        _generation!.completeError(StateError(error.toString()));
      }
    });
    _exitSubscription = _exits!.listen((_) {
      if (!(_generation?.isCompleted ?? true)) {
        _generation!.completeError(StateError('语音合成进程意外结束'));
      }
    });
    _worker = await Isolate.spawn<Map<String, Object>>(
      _ttsWorker,
      {
        'sendPort': _messages!.sendPort,
        'text': text,
        'output': output,
        'model': model.modelPath,
        'voices': model.voicesPath,
        'tokens': model.tokensPath,
        'dataDir': model.dataDir,
        'dictDir': model.dictDir,
        'lexicon': model.lexiconPath,
        'ruleFsts': model.ruleFsts,
      },
      onError: _errors!.sendPort,
      onExit: _exits!.sendPort,
    );
    try {
      final path = await _generation!.future;
      if (path.isEmpty || !await File(path).exists()) {
        throw StateError('语音合成没有生成音频');
      }
    } finally {
      await _cleanupWorker();
    }
  }

  Future<void> _cleanupWorker() async {
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    await _messageSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _exitSubscription?.cancel();
    _messageSubscription = null;
    _errorSubscription = null;
    _exitSubscription = null;
    _messages?.close();
    _errors?.close();
    _exits?.close();
    _messages = null;
    _errors = null;
    _exits = null;
    _generation = null;
  }

  Future<void> _deleteTemporaryWave() async {
    final path = _temporaryWavePath;
    _temporaryWavePath = null;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException {
        // The audio backend may release its file handle asynchronously.
      }
    }
  }
}

class _ReadAloudCanceled implements Exception {
  const _ReadAloudCanceled();
}

@pragma('vm:entry-point')
void _ttsWorker(Map<String, Object> args) {
  final sendPort = args['sendPort'] as SendPort;
  sherpa.OfflineTts? tts;
  try {
    sherpa.initBindings();
    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        kokoro: sherpa.OfflineTtsKokoroModelConfig(
          model: args['model'] as String,
          voices: args['voices'] as String,
          tokens: args['tokens'] as String,
          dataDir: args['dataDir'] as String,
          dictDir: args['dictDir'] as String,
          lexicon: args['lexicon'] as String,
        ),
        numThreads: 2,
        debug: false,
      ),
      ruleFsts: args['ruleFsts'] as String,
      maxNumSenetences: 1,
    );
    tts = sherpa.OfflineTts(config);
    final audio = tts.generate(text: args['text'] as String, sid: 3, speed: 1);
    if (audio.samples.isEmpty || audio.sampleRate <= 0) {
      throw StateError('语音合成没有生成采样');
    }
    sherpa.writeWave(
      filename: args['output'] as String,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    sendPort.send({'type': 'result', 'path': args['output']});
  } catch (error) {
    sendPort.send({'type': 'error', 'message': error.toString()});
  } finally {
    tts?.free();
  }
}
