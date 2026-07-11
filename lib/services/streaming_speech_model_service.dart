import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'file_storage_service.dart';
import 'speech_model_service.dart';

class StreamingSpeechModelInfo {
  final bool installed;
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final int sizeBytes;

  const StreamingSpeechModelInfo({
    required this.installed,
    this.encoderPath = '',
    this.decoderPath = '',
    this.joinerPath = '',
    this.tokensPath = '',
    this.sizeBytes = 0,
  });
}

class _RemoteModelFile {
  final String name;
  final String remotePath;
  final int sizeBytes;
  final String sha256;

  const _RemoteModelFile(
    this.name,
    this.remotePath,
    this.sizeBytes,
    this.sha256,
  );
}

/// Installs the official 2025 streaming Chinese Zipformer model.
///
/// Files are fetched individually from the pinned Hugging Face repository via
/// the domestic mirror. Every file supports resume and is verified before a
/// transactional activation.
class StreamingSpeechModelService {
  StreamingSpeechModelService._();
  static final StreamingSpeechModelService instance =
      StreamingSpeechModelService._();

  static const modelId = 'streaming-zipformer-zh-int8-2025-06-30';
  static const encoderFileName = 'encoder.int8.onnx';
  static const decoderFileName = 'decoder.onnx';
  static const joinerFileName = 'joiner.int8.onnx';
  static const tokensFileName = 'tokens.txt';
  static const _manifestFileName = 'manifest.json';
  static const _runtimeLayout = 'int8-encoder + fp32-decoder + int8-joiner';
  static const _revision = 'ad658fa0201659a09ea3c176129a191c77ecae8f';
  static const _repository =
      'csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30';
  static const _mirrorBase =
      'https://hf-mirror.com/$_repository/resolve/$_revision';

  static const _files = <_RemoteModelFile>[
    _RemoteModelFile(
      encoderFileName,
      encoderFileName,
      161141793,
      '5ac51e27981bb4dab01bb9be4958453ba50c3b61c063ddda0eab23fd3671aa4f',
    ),
    _RemoteModelFile(
      decoderFileName,
      decoderFileName,
      5165083,
      '06522ad63cec0fdf6809f4e1db9bb4f7d710c34582e3b35db62ac60eccafac7e',
    ),
    _RemoteModelFile(
      joinerFileName,
      joinerFileName,
      1033416,
      'b34584dc6f561089e1d747fedebb3765f2caa72c927ef54d7ca55e5ae40a814b',
    ),
    _RemoteModelFile(
      tokensFileName,
      tokensFileName,
      20628,
      '6193c7ea1c96d0d9a1e9652789b40d13a8a913b434a5451e93158f5a09fd6652',
    ),
  ];

  static const downloadSizeBytes = 167360920;
  static const _runtimeSizeBytes = 167360920;

  final _storage = FileStorageService.instance;
  bool _operationBusy = false;

  String get _root =>
      p.join(_storage.baseDir, 'models', 'asr', 'streaming-zipformer-zh-14m');
  String get _activeDir => p.join(_root, 'active');
  String get _downloadDir => p.join(_root, '.download');
  String _partialPath(_RemoteModelFile file) =>
      p.join(_downloadDir, '${file.name}.part');

  Future<StreamingSpeechModelInfo> inspect() async {
    final encoder = File(p.join(_activeDir, encoderFileName));
    final decoder = File(p.join(_activeDir, decoderFileName));
    final joiner = File(p.join(_activeDir, joinerFileName));
    final tokens = File(p.join(_activeDir, tokensFileName));
    final manifest = File(p.join(_activeDir, _manifestFileName));
    final files = [encoder, decoder, joiner, tokens, manifest];
    if (files.any((file) => !file.existsSync())) {
      return const StreamingSpeechModelInfo(installed: false);
    }
    try {
      final metadata = jsonDecode(await manifest.readAsString());
      if (metadata is! Map ||
          metadata['id'] != modelId ||
          metadata['revision'] != _revision ||
          metadata['runtimeFiles'] != _runtimeLayout) {
        return const StreamingSpeechModelInfo(installed: false);
      }
    } on FormatException {
      return const StreamingSpeechModelInfo(installed: false);
    } on FileSystemException {
      return const StreamingSpeechModelInfo(installed: false);
    }
    var size = 0;
    for (final file in files) {
      size += await file.length();
    }
    if (size < _runtimeSizeBytes) {
      return const StreamingSpeechModelInfo(installed: false);
    }
    return StreamingSpeechModelInfo(
      installed: true,
      encoderPath: encoder.path,
      decoderPath: decoder.path,
      joinerPath: joiner.path,
      tokensPath: tokens.path,
      sizeBytes: size,
    );
  }

  Future<int> partialDownloadBytes() async {
    var total = 0;
    for (final definition in _files) {
      final file = File(_partialPath(definition));
      if (!await file.exists()) continue;
      total += (await file.length()).clamp(0, definition.sizeBytes);
    }
    return total;
  }

  Future<StreamingSpeechModelInfo?> pickAndImport({
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    const group = XTypeGroup(
      label: 'Streaming Zipformer 模型文件',
      extensions: ['onnx', 'txt'],
    );
    final selected = await openFiles(acceptedTypeGroups: [group]);
    if (selected.isEmpty) return null;
    return _runExclusive(() async {
      final byName = {for (final file in selected) file.name: file};
      if (_files.any((definition) => !byName.containsKey(definition.name))) {
        throw const FormatException(
          '请选择 encoder.int8.onnx、decoder.onnx、joiner.int8.onnx 和 tokens.txt',
        );
      }
      final importing = Directory(p.join(_root, '.importing'));
      if (await importing.exists()) await importing.delete(recursive: true);
      await importing.create(recursive: true);
      var copiedTotal = 0;
      final sources = <String, File>{};
      try {
        for (final definition in _files) {
          final selectedFile = byName[definition.name]!;
          if (await selectedFile.length() != definition.sizeBytes) {
            throw FormatException('${definition.name} 大小不匹配');
          }
          final destination = File(
            p.join(importing.path, '${definition.name}.part'),
          );
          final output = await destination.open(mode: FileMode.write);
          try {
            await for (final chunk in selectedFile.openRead()) {
              await output.writeFrom(chunk);
              copiedTotal += chunk.length;
              onProgress?.call(
                SpeechModelImportProgress(copiedTotal, downloadSizeBytes),
              );
            }
            await output.flush();
          } finally {
            await output.close();
          }
          sources[definition.name] = destination;
        }
        return await _installFiles(sources, onProgress: onProgress);
      } finally {
        if (await importing.exists()) await importing.delete(recursive: true);
      }
    });
  }

  Future<StreamingSpeechModelInfo> downloadFromHuggingFaceMirror({
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => _runExclusive(() async {
    await Directory(_downloadDir).create(recursive: true);
    final currentBytes = <String, int>{};
    for (final definition in _files) {
      final partial = File(_partialPath(definition));
      var size = await partial.exists() ? await partial.length() : 0;
      if (size > definition.sizeBytes) {
        await partial.delete();
        size = 0;
      }
      currentBytes[definition.name] = size;
    }

    void report(String name, int bytes) {
      currentBytes[name] = bytes;
      onProgress?.call(
        SpeechModelImportProgress(
          currentBytes.values.fold(0, (sum, value) => sum + value),
          downloadSizeBytes,
        ),
      );
    }

    for (final definition in _files) {
      await _downloadFile(
        definition,
        onProgress: (bytes) => report(definition.name, bytes),
        shouldCancel: shouldCancel,
      );
    }
    if (shouldCancel?.call() == true) {
      throw const SpeechModelDownloadCanceled();
    }
    final sources = {
      for (final definition in _files)
        definition.name: File(_partialPath(definition)),
    };
    return _installFiles(sources, onProgress: onProgress);
  });

  Future<void> _downloadFile(
    _RemoteModelFile definition, {
    required void Function(int bytes) onProgress,
    bool Function()? shouldCancel,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _downloadFileOnce(
          definition,
          onProgress: onProgress,
          shouldCancel: shouldCancel,
        );
        return;
      } on SpeechModelDownloadCanceled {
        rethrow;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
    throw lastError ?? HttpException('${definition.name} 下载失败');
  }

  Future<void> _downloadFileOnce(
    _RemoteModelFile definition, {
    required void Function(int bytes) onProgress,
    bool Function()? shouldCancel,
  }) async {
    final partial = File(_partialPath(definition));
    var existing = await partial.exists() ? await partial.length() : 0;
    if (existing == definition.sizeBytes) {
      onProgress(existing);
      return;
    }
    if (shouldCancel?.call() == true) {
      throw const SpeechModelDownloadCanceled();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    RandomAccessFile? output;
    try {
      final uri = Uri.parse(
        '$_mirrorBase/${definition.remotePath}?download=true',
      );
      final request = await client.getUrl(uri);
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      request.headers.set(HttpHeaders.userAgentHeader, 'fknotes/$modelId');
      final response = await request.close();
      final canResume = response.statusCode == HttpStatus.partialContent;
      if (response.statusCode != HttpStatus.ok && !canResume) {
        throw HttpException('${definition.name} 下载失败（${response.statusCode}）');
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
        if (received > definition.sizeBytes) {
          throw FormatException('${definition.name} 下载大小异常');
        }
        onProgress(received);
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != definition.sizeBytes) {
        throw FormatException('${definition.name} 下载不完整，将在下次继续');
      }
    } finally {
      await output?.close();
      client.close(force: true);
    }
  }

  Future<StreamingSpeechModelInfo> _installFiles(
    Map<String, File> sources, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const SpeechModelImportProgress(
        downloadSizeBytes,
        downloadSizeBytes,
        verifying: true,
      ),
    );
    for (final definition in _files) {
      final source = sources[definition.name];
      if (source == null || !await source.exists()) {
        throw FormatException('缺少 ${definition.name}');
      }
      if (await source.length() != definition.sizeBytes) {
        throw FormatException('${definition.name} 大小不匹配');
      }
      final digest = await sha256.bind(source.openRead()).first;
      if (digest.toString() != definition.sha256) {
        await source.delete();
        throw const FormatException('模型文件不完整，请重新下载');
      }
    }

    final staging = Directory(p.join(_root, '.installing'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      for (final definition in _files) {
        final source = sources[definition.name]!;
        final destination = File(p.join(staging.path, definition.name));
        try {
          await source.rename(destination.path);
        } on FileSystemException {
          await source.copy(destination.path);
          await source.delete();
        }
      }
      await File(p.join(staging.path, 'LICENSE.txt')).writeAsString(
        'Streaming Zipformer model: Apache License 2.0\n'
        'Upstream: https://huggingface.co/$_repository\n',
        flush: true,
      );
      await File(p.join(staging.path, _manifestFileName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'id': modelId,
          'name': 'Streaming Zipformer 中文 2025 INT8',
          'engine': 'sherpa-onnx',
          'source': 'huggingface-official-via-hf-mirror',
          'repository': _repository,
          'revision': _revision,
          'license': 'Apache-2.0',
          'runtimeFiles': _runtimeLayout,
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
    if (_operationBusy) throw StateError('实时语音模型正在下载或导入');
    for (final name in ['active', '.download', '.importing', '.installing']) {
      final directory = Directory(p.join(_root, name));
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    if (_operationBusy) throw StateError('实时语音模型已有任务正在进行');
    _operationBusy = true;
    try {
      return await operation();
    } finally {
      _operationBusy = false;
    }
  }
}
