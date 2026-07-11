import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'file_storage_service.dart';
import 'speech_model_service.dart';

class VoiceActivityModelInfo {
  final bool installed;
  final String modelPath;
  final int sizeBytes;
  final String? problem;

  const VoiceActivityModelInfo({
    required this.installed,
    this.modelPath = '',
    this.sizeBytes = 0,
    this.problem,
  });
}

/// Owns the optional Silero VAD model used to segment long recordings.
class VoiceActivityModelService {
  VoiceActivityModelService._();
  static final VoiceActivityModelService instance =
      VoiceActivityModelService._();

  static const modelId = 'silero-vad-int8-16khz';
  static const modelFileName = 'silero_vad.int8.onnx';
  static const downloadSizeBytes = 212860;
  static const _sha256 =
      'c36d490aff5ab924ca6c7aeec4d8f6bd3d22db6fa17611b9c5b17eae58ac3a20';
  static const _revision = 'k2-fsa-asr-models-2026-07-11';
  static const _downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'asr-models/$modelFileName';

  final _storage = FileStorageService.instance;
  bool _operationBusy = false;

  String get _root =>
      p.join(_storage.baseDir, 'models', 'audio', 'silero-vad-int8-16khz');
  String get _activeDir => p.join(_root, 'active');
  String get _downloadDir => p.join(_root, '.download');
  String get _partialPath => p.join(_downloadDir, '$modelFileName.part');

  Future<VoiceActivityModelInfo> inspect({bool verifyIntegrity = false}) async {
    final model = File(p.join(_activeDir, modelFileName));
    final manifest = File(p.join(_activeDir, 'manifest.json'));
    if (!model.existsSync() || !manifest.existsSync()) {
      return const VoiceActivityModelInfo(
        installed: false,
        problem: 'Silero VAD 尚未安装',
      );
    }
    try {
      final metadata = jsonDecode(await manifest.readAsString());
      if (metadata is! Map ||
          metadata['id'] != modelId ||
          metadata['revision'] != _revision) {
        return const VoiceActivityModelInfo(
          installed: false,
          problem: 'Silero VAD 版本不匹配，请删除后重新下载',
        );
      }
      if (await model.length() != downloadSizeBytes) {
        return const VoiceActivityModelInfo(
          installed: false,
          problem: 'Silero VAD 文件大小异常，请删除后重新下载',
        );
      }
      if (verifyIntegrity) {
        final valid = await Isolate.run(() async {
          final digest = await sha256.bind(model.openRead()).first;
          return digest.toString() == _sha256;
        });
        if (!valid) {
          return const VoiceActivityModelInfo(
            installed: false,
            problem: 'Silero VAD 完整性校验失败，请重新下载',
          );
        }
      }
      return VoiceActivityModelInfo(
        installed: true,
        modelPath: model.path,
        sizeBytes: await model.length() + await manifest.length(),
      );
    } on FormatException {
      return const VoiceActivityModelInfo(
        installed: false,
        problem: 'Silero VAD 清单损坏，请重新下载',
      );
    } on FileSystemException {
      return const VoiceActivityModelInfo(
        installed: false,
        problem: '无法读取 Silero VAD 模型',
      );
    }
  }

  Future<int> partialDownloadBytes() async {
    final partial = File(_partialPath);
    if (!await partial.exists()) return 0;
    return (await partial.length()).clamp(0, downloadSizeBytes);
  }

  Future<VoiceActivityModelInfo?> pickAndImport({
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    const group = XTypeGroup(label: 'Silero VAD 模型', extensions: ['onnx']);
    final selected = await openFile(acceptedTypeGroups: [group]);
    if (selected == null) return null;
    return _runExclusive(() async {
      if (await selected.length() != downloadSizeBytes) {
        throw const FormatException('Silero VAD 模型大小不匹配');
      }
      final importing = Directory(p.join(_root, '.importing'));
      if (await importing.exists()) await importing.delete(recursive: true);
      await importing.create(recursive: true);
      final destination = File(p.join(importing.path, '$modelFileName.part'));
      final output = await destination.open(mode: FileMode.write);
      var copied = 0;
      try {
        await for (final chunk in selected.openRead()) {
          await output.writeFrom(chunk);
          copied += chunk.length;
          onProgress?.call(
            SpeechModelImportProgress(copied, downloadSizeBytes),
          );
        }
        await output.flush();
      } finally {
        await output.close();
      }
      try {
        return await _install(destination, onProgress: onProgress);
      } finally {
        if (await importing.exists()) await importing.delete(recursive: true);
      }
    });
  }

  Future<VoiceActivityModelInfo> download({
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => _runExclusive(() async {
    await Directory(_downloadDir).create(recursive: true);
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _downloadOnce(onProgress, shouldCancel);
        final partial = File(_partialPath);
        return await _install(partial, onProgress: onProgress);
      } on SpeechModelDownloadCanceled {
        rethrow;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
    throw lastError ?? const HttpException('Silero VAD 下载失败');
  });

  Future<void> _downloadOnce(
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  ) async {
    final partial = File(_partialPath);
    var existing = await partial.exists() ? await partial.length() : 0;
    if (existing > downloadSizeBytes) {
      await partial.delete();
      existing = 0;
    }
    if (existing == downloadSizeBytes) {
      onProgress?.call(
        const SpeechModelImportProgress(downloadSizeBytes, downloadSizeBytes),
      );
      return;
    }
    if (shouldCancel?.call() == true) {
      throw const SpeechModelDownloadCanceled();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    RandomAccessFile? output;
    try {
      final request = await client.getUrl(Uri.parse(_downloadUrl));
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      request.headers.set(HttpHeaders.userAgentHeader, 'fknotes/$modelId');
      final response = await request.close();
      final canResume = response.statusCode == HttpStatus.partialContent;
      if (response.statusCode != HttpStatus.ok && !canResume) {
        throw HttpException('Silero VAD 下载失败（${response.statusCode}）');
      }
      if (existing > 0 && !canResume) {
        await partial.delete();
        existing = 0;
      }
      output = await partial.open(
        mode: existing > 0 ? FileMode.append : FileMode.write,
      );
      var received = existing;
      await for (final chunk in response) {
        if (shouldCancel?.call() == true) {
          throw const SpeechModelDownloadCanceled();
        }
        await output.writeFrom(chunk);
        received += chunk.length;
        if (received > downloadSizeBytes) {
          throw const FormatException('Silero VAD 下载大小异常');
        }
        onProgress?.call(
          SpeechModelImportProgress(received, downloadSizeBytes),
        );
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != downloadSizeBytes) {
        throw const FormatException('Silero VAD 下载不完整，将在下次继续');
      }
    } finally {
      await output?.close();
      client.close(force: true);
    }
  }

  Future<VoiceActivityModelInfo> _install(
    File source, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const SpeechModelImportProgress(
        downloadSizeBytes,
        downloadSizeBytes,
        verifying: true,
      ),
    );
    if (!await source.exists() || await source.length() != downloadSizeBytes) {
      throw const FormatException('Silero VAD 模型文件不完整');
    }
    final digest = await sha256.bind(source.openRead()).first;
    if (digest.toString() != _sha256) {
      await source.delete();
      throw const FormatException('Silero VAD 完整性校验失败，请重新下载');
    }
    final staging = Directory(p.join(_root, '.installing'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      final model = File(p.join(staging.path, modelFileName));
      try {
        await source.rename(model.path);
      } on FileSystemException {
        await source.copy(model.path);
        await source.delete();
      }
      await File(p.join(staging.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'id': modelId,
          'name': 'Silero VAD INT8',
          'engine': 'sherpa-onnx',
          'revision': _revision,
          'source': _downloadUrl,
          'license': 'MIT',
          'sampleRate': 16000,
        }),
        flush: true,
      );
      await _activate(staging);
      final download = Directory(_downloadDir);
      if (await download.exists()) await download.delete(recursive: true);
      return inspect();
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _activate(Directory staging) async {
    final active = Directory(_activeDir);
    final previous = Directory('$_activeDir.previous');
    if (await previous.exists()) await previous.delete(recursive: true);
    if (await active.exists()) await active.rename(previous.path);
    try {
      await staging.rename(active.path);
      if (await previous.exists()) await previous.delete(recursive: true);
    } catch (_) {
      if (await active.exists()) await active.delete(recursive: true);
      if (await previous.exists()) await previous.rename(active.path);
      rethrow;
    }
  }

  Future<void> remove() async {
    if (_operationBusy) throw StateError('Silero VAD 正在下载或导入');
    for (final name in ['active', '.download', '.importing', '.installing']) {
      final directory = Directory(p.join(_root, name));
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    if (_operationBusy) throw StateError('Silero VAD 已有任务正在进行');
    _operationBusy = true;
    try {
      return await operation();
    } finally {
      _operationBusy = false;
    }
  }
}
