import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'file_storage_service.dart';
import 'model_download_source_policy.dart';
import 'model_download_transport.dart';
import 'model_install_coordinator.dart';
import 'speech_model_service.dart';

class SpeechDenoiserModelInfo {
  final bool installed;
  final String modelPath;
  final int sizeBytes;
  final String? problem;

  const SpeechDenoiserModelInfo({
    required this.installed,
    this.modelPath = '',
    this.sizeBytes = 0,
    this.problem,
  });
}

/// Owns the optional DPDFNet model used before live ASR decoding.
class SpeechDenoiserModelService {
  SpeechDenoiserModelService._();
  static final SpeechDenoiserModelService instance =
      SpeechDenoiserModelService._();

  static const modelId = 'dpdfnet-baseline-16khz';
  static const modelFileName = 'dpdfnet_baseline.onnx';
  static const downloadSizeBytes = 8791035;
  static const _sha256 =
      'debaf0e8893479fca91b8b4c1eae8db195aa8980ccc9012f5809fde2b738151a';
  static const _revision = 'speech-enhancement-models-2026-07-11';
  static const _downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'speech-enhancement-models/$modelFileName';
  static const _mirrorRevision = '0cf7920e73bbdf53456b8b7aeac7d4e3728cb697';
  static const _mirrorRepository = 'bitsydarel/dpdfnet-onnx';

  final _storage = FileStorageService.instance;
  bool _operationBusy = false;

  String get _root => p.join(_storage.baseDir, 'models', 'audio', modelId);
  String get _activeDir => p.join(_root, 'active');
  String get _downloadDir => p.join(_root, '.download');
  String get _partialPath => p.join(_downloadDir, '$modelFileName.part');

  Future<SpeechDenoiserModelInfo> inspect({
    bool verifyIntegrity = false,
  }) async {
    final model = File(p.join(_activeDir, modelFileName));
    final manifest = File(p.join(_activeDir, 'manifest.json'));
    if (!await model.exists() || !await manifest.exists()) {
      return const SpeechDenoiserModelInfo(
        installed: false,
        problem: '实时降噪模型尚未安装',
      );
    }
    try {
      final metadata = jsonDecode(await manifest.readAsString());
      if (metadata is! Map ||
          metadata['id'] != modelId ||
          metadata['revision'] != _revision) {
        return const SpeechDenoiserModelInfo(
          installed: false,
          problem: '实时降噪模型版本不匹配，请重新下载',
        );
      }
      if (await model.length() != downloadSizeBytes) {
        return const SpeechDenoiserModelInfo(
          installed: false,
          problem: '实时降噪模型文件大小异常，请重新下载',
        );
      }
      if (verifyIntegrity) {
        final valid = await Isolate.run(() async {
          final digest = await sha256.bind(model.openRead()).first;
          return digest.toString() == _sha256;
        });
        if (!valid) {
          return const SpeechDenoiserModelInfo(
            installed: false,
            problem: '实时降噪模型完整性校验失败，请重新下载',
          );
        }
      }
      return SpeechDenoiserModelInfo(
        installed: true,
        modelPath: model.path,
        sizeBytes: await model.length() + await manifest.length(),
      );
    } on FormatException {
      return const SpeechDenoiserModelInfo(
        installed: false,
        problem: '实时降噪模型清单损坏，请重新下载',
      );
    } on FileSystemException {
      return const SpeechDenoiserModelInfo(
        installed: false,
        problem: '无法读取实时降噪模型',
      );
    }
  }

  Future<int> partialDownloadBytes() async {
    final partial = File(_partialPath);
    if (!await partial.exists()) return 0;
    return (await partial.length()).clamp(0, downloadSizeBytes);
  }

  Future<SpeechDenoiserModelInfo?> pickAndImport({
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    const group = XTypeGroup(label: 'DPDFNet 降噪模型', extensions: ['onnx']);
    final selected = await openFile(acceptedTypeGroups: [group]);
    if (selected == null) return null;
    return _runExclusive(() async {
      if (await selected.length() != downloadSizeBytes) {
        throw const FormatException('DPDFNet 降噪模型大小不匹配');
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

  Future<SpeechDenoiserModelInfo> download({
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => _runExclusive(() async {
    await Directory(_downloadDir).create(recursive: true);
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _downloadOnce(onProgress, shouldCancel);
        return await _install(
          File(_partialPath),
          onProgress: onProgress,
          shouldCancel: shouldCancel,
        );
      } on SpeechModelDownloadCanceled {
        rethrow;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
    throw lastError ?? const HttpException('DPDFNet 降噪模型下载失败');
  });

  Future<void> _downloadOnce(
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  ) async {
    final sourcePolicy = ModelDownloadSourcePolicy.instance;
    await ModelDownloadTransport.instance.download(
      sources: sourcePolicy.order([
        ModelDownloadSource(
          uri: Uri.parse(
            'https://huggingface.co/$_mirrorRepository/resolve/'
            '$_mirrorRevision/$modelFileName?download=true',
          ),
          label: 'Hugging Face',
          kind: ModelDownloadSourceKind.official,
        ),
        ModelDownloadSource(
          uri: Uri.parse(
            'https://hf-mirror.com/$_mirrorRepository/resolve/'
            '$_mirrorRevision/$modelFileName?download=true',
          ),
          label: '第三方国内镜像',
          kind: ModelDownloadSourceKind.mainlandMirror,
        ),
        ModelDownloadSource(uri: Uri.parse(_downloadUrl), label: 'GitHub 官方源'),
      ]),
      partial: File(_partialPath),
      expectedBytes: downloadSizeBytes,
      userAgent: 'fknotes/$modelId',
      shouldCancel: shouldCancel,
      onSourceSelected: sourcePolicy.reportSuccessfulSource,
      onProgress: (event) => onProgress?.call(
        SpeechModelImportProgress(
          event.transferredBytes,
          downloadSizeBytes,
          connecting: event.connecting,
          sourceLabel: event.sourceLabel,
        ),
      ),
    );
  }

  Future<SpeechDenoiserModelInfo> _install(
    File source, {
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => ModelInstallCoordinator.instance.run(
    () => _installNow(source, onProgress: onProgress),
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

  Future<SpeechDenoiserModelInfo> _installNow(
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
      throw const FormatException('DPDFNet 降噪模型文件不完整');
    }
    final digest = await sha256.bind(source.openRead()).first;
    if (digest.toString() != _sha256) {
      await source.delete();
      throw const FormatException('DPDFNet 降噪模型完整性校验失败，请重新下载');
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
          'name': 'DPDFNet Baseline',
          'engine': 'sherpa-onnx',
          'revision': _revision,
          'source': _downloadUrl,
          'license': 'Apache-2.0',
          'sampleRate': 16000,
          'streaming': true,
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
    if (_operationBusy) throw StateError('DPDFNet 降噪模型正在下载或导入');
    for (final name in ['active', '.download', '.importing', '.installing']) {
      final directory = Directory(p.join(_root, name));
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    if (_operationBusy) throw StateError('DPDFNet 降噪模型已有任务正在进行');
    _operationBusy = true;
    try {
      return await operation();
    } finally {
      _operationBusy = false;
    }
  }
}
