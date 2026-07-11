import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'file_storage_service.dart';
import 'model_download_transport.dart';
import 'model_install_coordinator.dart';

class SpeechModelInfo {
  final bool installed;
  final String modelPath;
  final String tokensPath;
  final int sizeBytes;
  final String displayName;

  const SpeechModelInfo({
    required this.installed,
    this.modelPath = '',
    this.tokensPath = '',
    this.sizeBytes = 0,
    this.displayName = 'SenseVoice Small INT8',
  });
}

typedef SpeechModelDownloadCanceled = ModelDownloadCanceled;

class SpeechModelImportProgress {
  final int copiedBytes;
  final int totalBytes;
  final bool verifying;
  final bool waitingForInstall;
  final bool connecting;
  final String sourceLabel;
  const SpeechModelImportProgress(
    this.copiedBytes,
    this.totalBytes, {
    this.verifying = false,
    this.waitingForInstall = false,
    this.connecting = false,
    this.sourceLabel = '',
  });

  double get fraction =>
      totalBytes <= 0 ? 0 : (copiedBytes / totalBytes).clamp(0.0, 1.0);
}

/// Manages the optional, user-supplied local ASR model.
///
/// Models deliberately live outside BackupService's allow-list: restoring a
/// note backup must not unexpectedly copy hundreds of megabytes of runtime
/// data. Import is transactional, so an interrupted import never replaces a
/// working model.
class SpeechModelService {
  SpeechModelService._();
  static final SpeechModelService instance = SpeechModelService._();

  static const modelFileName = 'model.int8.onnx';
  static const tokensFileName = 'tokens.txt';
  static const modelId = 'sensevoice-small-int8-2024-07-17';
  static const downloadSizeBytes = 239549806;
  static const _modelSizeBytes = 239233841;
  static const _tokensSizeBytes = 315894;
  static const _licenseSizeBytes = 71;
  static const _modelSha256 =
      'c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51';
  static const _tokensSha256 =
      'f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc';
  static const _licenseSha256 =
      '221c6df10b0931a5629adad671ea48fb7747e034c414b6d2bfa275bc3dd4ea17';
  static const _revision = 'b1bc3fb60fdafcb26f301f306f72beb19498ffc4';
  static const _remoteRoot =
      'https://modelscope.cn/models/gomodels/sherpa/resolve/$_revision/'
      'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17';

  final _storage = FileStorageService.instance;
  bool _operationBusy = false;

  String get _root => p.join(_storage.baseDir, 'models', 'asr');
  String get _activeDir => p.join(_root, 'sensevoice');

  Future<SpeechModelInfo> inspect() async {
    final model = File(p.join(_activeDir, modelFileName));
    final tokens = File(p.join(_activeDir, tokensFileName));
    if (!await model.exists() || !await tokens.exists()) {
      return const SpeechModelInfo(installed: false);
    }
    final modelSize = await model.length();
    final tokensSize = await tokens.length();
    if (modelSize < 1024 * 1024 || tokensSize < 100) {
      return const SpeechModelInfo(installed: false);
    }
    return SpeechModelInfo(
      installed: true,
      modelPath: model.path,
      tokensPath: tokens.path,
      sizeBytes: modelSize + tokensSize,
    );
  }

  Future<int> partialDownloadBytes() async {
    final staging = p.join(_root, '.sensevoice-download');
    var total = 0;
    for (final name in [
      '$modelFileName.part',
      '$tokensFileName.part',
      'MODEL_LICENSE.txt.part',
    ]) {
      final partial = File(p.join(staging, name));
      if (await partial.exists()) total += await partial.length();
    }
    return total;
  }

  Future<SpeechModelInfo?> pickAndImport({
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    const group = XTypeGroup(
      label: 'SenseVoice 模型文件',
      extensions: ['onnx', 'txt'],
      mimeTypes: ['application/octet-stream', 'text/plain'],
    );
    final selected = await openFiles(acceptedTypeGroups: [group]);
    if (selected.isEmpty) return null;
    return importFiles(selected, onProgress: onProgress);
  }

  Future<SpeechModelInfo> importFiles(
    List<XFile> files, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) => _runExclusive(() => _importFiles(files, onProgress: onProgress));

  Future<SpeechModelInfo> _importFiles(
    List<XFile> files, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) => ModelInstallCoordinator.instance.run(
    () => _importFilesNow(files, onProgress: onProgress),
    onWaiting: () => onProgress?.call(
      const SpeechModelImportProgress(
        downloadSizeBytes,
        downloadSizeBytes,
        waitingForInstall: true,
      ),
    ),
  );

  Future<SpeechModelInfo> _importFilesNow(
    List<XFile> files, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    XFile? model;
    XFile? tokens;
    for (final file in files) {
      final name = file.name.toLowerCase();
      if (name.endsWith('.onnx')) {
        if (model != null) throw const FormatException('请选择一个 ONNX 模型文件');
        model = file;
      } else if (name == tokensFileName || name.endsWith('tokens.txt')) {
        tokens = file;
      }
    }
    if (model == null || tokens == null) {
      throw const FormatException('请同时选择 model.int8.onnx 和 tokens.txt');
    }

    final modelLength = await model.length();
    final tokensLength = await tokens.length();
    if (modelLength < 1024 * 1024 || tokensLength < 100) {
      throw const FormatException('模型文件不完整，请重新选择');
    }

    final staging = Directory(p.join(_root, '.sensevoice-importing'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    final total = modelLength + tokensLength;
    var copied = 0;
    try {
      copied += await _copyStream(
        model,
        File(p.join(staging.path, modelFileName)),
        copiedBefore: copied,
        total: total,
        onProgress: onProgress,
      );
      copied += await _copyStream(
        tokens,
        File(p.join(staging.path, tokensFileName)),
        copiedBefore: copied,
        total: total,
        onProgress: onProgress,
      );
      await _writeManifest(staging, source: 'manual-import');
      await _activate(staging);
      onProgress?.call(SpeechModelImportProgress(total, total));
      return (await inspect());
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<SpeechModelInfo> downloadFromModelScope({
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => _runExclusive(
    () => _downloadFromModelScope(
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    ),
  );

  Future<SpeechModelInfo> _downloadFromModelScope({
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final staging = Directory(p.join(_root, '.sensevoice-download'));
    await staging.create(recursive: true);
    final modelPart = File(p.join(staging.path, '$modelFileName.part'));
    final tokensPart = File(p.join(staging.path, '$tokensFileName.part'));
    final licensePart = File(p.join(staging.path, 'MODEL_LICENSE.txt.part'));
    try {
      await _downloadFile(
        Uri.parse('$_remoteRoot/$modelFileName'),
        modelPart,
        expectedSize: _modelSizeBytes,
        completedBefore: 0,
        totalSize: downloadSizeBytes,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );
      await _downloadFile(
        Uri.parse('$_remoteRoot/$tokensFileName'),
        tokensPart,
        expectedSize: _tokensSizeBytes,
        completedBefore: _modelSizeBytes,
        totalSize: downloadSizeBytes,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );
      await _downloadFile(
        Uri.parse('$_remoteRoot/LICENSE'),
        licensePart,
        expectedSize: _licenseSizeBytes,
        completedBefore: _modelSizeBytes + _tokensSizeBytes,
        totalSize: downloadSizeBytes,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );
      return ModelInstallCoordinator.instance.run(
        () async {
          if (shouldCancel?.call() == true) {
            throw const SpeechModelDownloadCanceled();
          }
          onProgress?.call(
            const SpeechModelImportProgress(
              downloadSizeBytes,
              downloadSizeBytes,
              verifying: true,
            ),
          );
          final paths = [modelPart.path, tokensPart.path, licensePart.path];
          final hashes = await Isolate.run(() async {
            final results = <String>[];
            for (final path in paths) {
              results.add(
                (await sha256.bind(File(path).openRead()).first).toString(),
              );
            }
            return results;
          });
          if (hashes[0] != _modelSha256 ||
              hashes[1] != _tokensSha256 ||
              hashes[2] != _licenseSha256) {
            await modelPart.delete();
            await tokensPart.delete();
            await licensePart.delete();
            throw const FormatException('模型完整性校验失败，请重新下载');
          }
          await modelPart.rename(p.join(staging.path, modelFileName));
          await tokensPart.rename(p.join(staging.path, tokensFileName));
          await licensePart.rename(p.join(staging.path, 'MODEL_LICENSE.txt'));
          await _writeManifest(staging, source: 'modelscope');
          await _activate(staging);
          return inspect();
        },
        onWaiting: () => onProgress?.call(
          const SpeechModelImportProgress(
            downloadSizeBytes,
            downloadSizeBytes,
            waitingForInstall: true,
          ),
        ),
        isCanceled: shouldCancel,
        cancellationError: () => const SpeechModelDownloadCanceled(),
      );
    } on SpeechModelDownloadCanceled {
      rethrow;
    } catch (_) {
      // Keep valid partial files for a later Range request. Invalid files are
      // explicitly deleted above after checksum verification.
      rethrow;
    }
  }

  Future<void> _downloadFile(
    Uri uri,
    File partial, {
    required int expectedSize,
    required int completedBefore,
    required int totalSize,
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _downloadFileOnce(
          uri,
          partial,
          expectedSize: expectedSize,
          completedBefore: completedBefore,
          totalSize: totalSize,
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
    throw lastError ?? const HttpException('模型下载失败');
  }

  Future<void> _downloadFileOnce(
    Uri uri,
    File partial, {
    required int expectedSize,
    required int completedBefore,
    required int totalSize,
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    await ModelDownloadTransport.instance.download(
      sources: [ModelDownloadSource(uri: uri, label: 'ModelScope 魔搭')],
      partial: partial,
      expectedBytes: expectedSize,
      userAgent: 'fknotes/$modelId',
      shouldCancel: shouldCancel,
      onProgress: (event) => onProgress?.call(
        SpeechModelImportProgress(
          completedBefore + event.transferredBytes,
          totalSize,
          connecting: event.connecting,
          sourceLabel: event.sourceLabel,
        ),
      ),
    );
  }

  Future<void> _writeManifest(
    Directory directory, {
    required String source,
  }) async {
    final license = File(p.join(directory.path, 'MODEL_LICENSE.txt'));
    if (!await license.exists()) {
      await license.writeAsString(
        'SenseVoice model license: '
        'https://github.com/modelscope/FunASR?tab=readme-ov-file#license\n',
        flush: true,
      );
    }
    await File(p.join(directory.path, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'id': modelId,
        'name': 'SenseVoice Small INT8',
        'engine': 'sherpa-onnx',
        'source': source,
        'revision': _revision,
      }),
      flush: true,
    );
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

  Future<int> _copyStream(
    XFile source,
    File destination, {
    required int copiedBefore,
    required int total,
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    final output = await destination.open(mode: FileMode.write);
    var copied = 0;
    try {
      await for (final chunk in source.openRead()) {
        await output.writeFrom(chunk);
        copied += chunk.length;
        onProgress?.call(
          SpeechModelImportProgress(copiedBefore + copied, total),
        );
      }
      await output.flush();
      return copied;
    } finally {
      await output.close();
    }
  }

  Future<void> remove() async {
    if (_operationBusy) throw StateError('已有模型下载或导入任务正在进行');
    final active = Directory(_activeDir);
    if (await active.exists()) await active.delete(recursive: true);
    final partial = Directory(p.join(_root, '.sensevoice-download'));
    if (await partial.exists()) await partial.delete(recursive: true);
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    if (_operationBusy) throw StateError('已有模型下载或导入任务正在进行');
    _operationBusy = true;
    try {
      return await operation();
    } finally {
      _operationBusy = false;
    }
  }
}
