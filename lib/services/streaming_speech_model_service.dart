import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
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

/// Installs the optional streaming Zipformer model used by live dictation.
///
/// The downloaded archive is version-pinned and verified before extraction.
/// Only the INT8 runtime files are retained, and activation is transactional.
class StreamingSpeechModelService {
  StreamingSpeechModelService._();
  static final StreamingSpeechModelService instance =
      StreamingSpeechModelService._();

  static const modelId = 'streaming-zipformer-zh-14m-2023-02-23';
  static const archiveFileName =
      'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23.tar.bz2';
  static const encoderFileName = 'encoder-epoch-99-avg-1.int8.onnx';
  static const decoderFileName = 'decoder-epoch-99-avg-1.int8.onnx';
  static const joinerFileName = 'joiner-epoch-99-avg-1.int8.onnx';
  static const tokensFileName = 'tokens.txt';
  static const downloadSizeBytes = 74004050;

  static const _archiveSha256 =
      '2cbd71b640d9c37d3784f29367333a4577b0398b62e9deeed418170b081cba8b';
  static const _encoderSha256 =
      '1c556ea57cec304e55ec4b72e52c1cc098bb01476ed7d90f3de939fe126487b1';
  static const _decoderSha256 =
      '22f123bb8cba9b38974b3df18a3f45e7081f4985ebb2e075d9f21f618c468bbf';
  static const _joinerSha256 =
      'a7cf9d82757bdcf786059454495a9ca95e4bd7347f72473fc08d794475c36169';
  static const _tokensSha256 =
      '8b294db9045d6e5f94647f4c1eec1af4da143a75053c399611444b378ff966ac';
  static const _revision = '3cbf71ce03da659cb468344012519c4d2ff7b62e';
  static const _remoteUrl =
      'https://modelscope.cn/models/zhaochaoqun/sherpa-onnx-asr-models/'
      'resolve/$_revision/$archiveFileName';

  final _storage = FileStorageService.instance;
  bool _operationBusy = false;

  String get _root =>
      p.join(_storage.baseDir, 'models', 'asr', 'streaming-zipformer-zh-14m');
  String get _activeDir => p.join(_root, 'active');
  String get _downloadDir => p.join(_root, '.download');
  String get _archivePart => p.join(_downloadDir, '$archiveFileName.part');

  Future<StreamingSpeechModelInfo> inspect() async {
    final encoder = File(p.join(_activeDir, encoderFileName));
    final decoder = File(p.join(_activeDir, decoderFileName));
    final joiner = File(p.join(_activeDir, joinerFileName));
    final tokens = File(p.join(_activeDir, tokensFileName));
    final files = [encoder, decoder, joiner, tokens];
    if (files.any((file) => !file.existsSync())) {
      return const StreamingSpeechModelInfo(installed: false);
    }
    var size = 0;
    for (final file in files) {
      size += await file.length();
    }
    if (size < 20 * 1024 * 1024) {
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
    final file = File(_archivePart);
    return await file.exists() ? file.length() : 0;
  }

  Future<StreamingSpeechModelInfo?> pickAndImport({
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    const group = XTypeGroup(
      label: 'Streaming Zipformer 模型包',
      extensions: ['bz2'],
      mimeTypes: ['application/x-bzip2', 'application/octet-stream'],
    );
    final selected = await openFile(acceptedTypeGroups: [group]);
    if (selected == null) return null;
    return _runExclusive(() async {
      final size = await selected.length();
      if (size != downloadSizeBytes) {
        throw const FormatException('模型包大小不匹配，请选择官方完整的 tar.bz2 文件');
      }
      final importing = Directory(p.join(_root, '.importing'));
      if (await importing.exists()) await importing.delete(recursive: true);
      await importing.create(recursive: true);
      final archive = File(p.join(importing.path, archiveFileName));
      final output = await archive.open(mode: FileMode.write);
      var copied = 0;
      try {
        await for (final chunk in selected.openRead()) {
          await output.writeFrom(chunk);
          copied += chunk.length;
          onProgress?.call(SpeechModelImportProgress(copied, size));
        }
        await output.flush();
      } finally {
        await output.close();
      }
      try {
        return await _installArchive(archive, onProgress: onProgress);
      } finally {
        if (await importing.exists()) await importing.delete(recursive: true);
      }
    });
  }

  Future<StreamingSpeechModelInfo> downloadFromModelScope({
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => _runExclusive(() async {
    await Directory(_downloadDir).create(recursive: true);
    final partial = File(_archivePart);
    await _downloadArchive(
      partial,
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
    if (shouldCancel?.call() == true) {
      throw const SpeechModelDownloadCanceled();
    }
    return _installArchive(partial, onProgress: onProgress);
  });

  Future<void> _downloadArchive(
    File partial, {
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _downloadArchiveOnce(
          partial,
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
    throw lastError ?? const HttpException('实时语音模型下载失败');
  }

  Future<void> _downloadArchiveOnce(
    File partial, {
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
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
      final request = await client.getUrl(Uri.parse(_remoteUrl));
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      request.headers.set(HttpHeaders.userAgentHeader, 'fknotes/$modelId');
      final response = await request.close();
      final canResume = response.statusCode == HttpStatus.partialContent;
      if (response.statusCode != HttpStatus.ok && !canResume) {
        throw HttpException('实时语音模型下载失败（${response.statusCode}）');
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
        onProgress?.call(
          SpeechModelImportProgress(received, downloadSizeBytes),
        );
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != downloadSizeBytes) {
        throw const FormatException('模型下载不完整，将在下次继续下载');
      }
    } finally {
      await output?.close();
      client.close(force: true);
    }
  }

  Future<StreamingSpeechModelInfo> _installArchive(
    File archive, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    final total = await archive.length();
    onProgress?.call(SpeechModelImportProgress(total, total, verifying: true));
    final archiveHash = await Isolate.run(
      () async => (await sha256.bind(archive.openRead()).first).toString(),
    );
    if (archiveHash != _archiveSha256) {
      if (await archive.exists()) await archive.delete();
      throw const FormatException('实时语音模型完整性校验失败，请重新下载');
    }
    final staging = Directory(p.join(_root, '.installing'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      await Isolate.run(() => _extractInt8Model(archive.path, staging.path));
      final files = {
        encoderFileName: _encoderSha256,
        decoderFileName: _decoderSha256,
        joinerFileName: _joinerSha256,
        tokensFileName: _tokensSha256,
      };
      for (final entry in files.entries) {
        final file = File(p.join(staging.path, entry.key));
        if (!await file.exists()) {
          throw FormatException('模型包缺少 ${entry.key}');
        }
        final digest = await sha256.bind(file.openRead()).first;
        if (digest.toString() != entry.value) {
          throw FormatException('${entry.key} 校验失败');
        }
      }
      await File(p.join(staging.path, 'LICENSE.txt')).writeAsString(
        'Streaming Zipformer model: Apache License 2.0\n'
        'Upstream: csukuangfj/sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23\n',
        flush: true,
      );
      await File(p.join(staging.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'id': modelId,
          'name': 'Streaming Zipformer 中文 INT8',
          'engine': 'sherpa-onnx',
          'source': 'modelscope',
          'revision': _revision,
          'license': 'Apache-2.0',
        }),
        flush: true,
      );
      await _activate(staging);
      if (await archive.exists()) await archive.delete();
      final downloadDir = Directory(_downloadDir);
      if (await downloadDir.exists()) await downloadDir.delete(recursive: true);
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
    final active = Directory(_activeDir);
    if (await active.exists()) await active.delete(recursive: true);
    final download = Directory(_downloadDir);
    if (await download.exists()) await download.delete(recursive: true);
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

void _extractInt8Model(String archivePath, String outputPath) {
  final temporaryTar = '$archivePath.unpacked.tar';
  InputFileStream? compressedInput;
  OutputFileStream? tarOutput;
  InputFileStream? tarInput;
  Archive? decoded;
  try {
    compressedInput = InputFileStream(archivePath);
    tarOutput = OutputFileStream(temporaryTar);
    BZip2Decoder().decodeStream(compressedInput, tarOutput);
    compressedInput.closeSync();
    compressedInput = null;
    tarOutput.closeSync();
    tarOutput = null;

    tarInput = InputFileStream(temporaryTar);
    decoded = TarDecoder().decodeStream(tarInput);
    const wanted = {
      StreamingSpeechModelService.encoderFileName,
      StreamingSpeechModelService.decoderFileName,
      StreamingSpeechModelService.joinerFileName,
      StreamingSpeechModelService.tokensFileName,
    };
    final extracted = <String>{};
    for (final entry in decoded) {
      final name = p.basename(entry.name);
      if (!entry.isFile || !wanted.contains(name)) continue;
      final output = OutputFileStream(p.join(outputPath, name));
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
      extracted.add(name);
    }
    if (extracted.length != wanted.length) {
      throw const FormatException('模型包内的 INT8 文件不完整');
    }
  } finally {
    compressedInput?.closeSync();
    tarOutput?.closeSync();
    tarInput?.closeSync();
    decoded?.clearSync();
    final tar = File(temporaryTar);
    if (tar.existsSync()) tar.deleteSync();
  }
}
