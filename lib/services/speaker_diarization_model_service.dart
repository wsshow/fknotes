import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'file_storage_service.dart';
import 'model_download_transport.dart';
import 'model_install_coordinator.dart';
import 'speech_model_service.dart';

class SpeakerDiarizationModelInfo {
  final bool installed;
  final String segmentationPath;
  final String embeddingPath;
  final int sizeBytes;
  final String? problem;

  const SpeakerDiarizationModelInfo({
    required this.installed,
    this.segmentationPath = '',
    this.embeddingPath = '',
    this.sizeBytes = 0,
    this.problem,
  });
}

/// Owns the Pyannote INT8 segmentation and Chinese 3D-Speaker models.
class SpeakerDiarizationModelService {
  SpeakerDiarizationModelService._();
  static final SpeakerDiarizationModelService instance =
      SpeakerDiarizationModelService._();

  static const modelId = 'pyannote-int8-3dspeaker-zh-16khz';
  static const segmentationArchiveName =
      'sherpa-onnx-pyannote-segmentation-3-0.tar.bz2';
  static const embeddingFileName =
      '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';
  static const segmentationFileName = 'segmentation.int8.onnx';
  static const segmentationArchiveBytes = 6958444;
  static const embeddingBytes = 39593761;
  static const segmentationBytes = 1540506;
  static const downloadSizeBytes = segmentationArchiveBytes + embeddingBytes;
  static const _segmentationArchiveSha256 =
      '24615ee884c897d9d2ba09bb4d30da6bb1b15e685065962db5b02e76e4996488';
  static const _segmentationSha256 =
      'd582f4b4c6b48205de7e0643c57df0df5615a3c176189be3fc461e9d18827b5d';
  static const _embeddingSha256 =
      '1a331345f04805badbb495c775a6ddffcdd1a732567d5ec8b3d5749e3c7a5e4b';
  static const _revision = 'official-models-2026-07-11';
  static const _segmentationUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'speaker-segmentation-models/$segmentationArchiveName';
  static const _embeddingUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'speaker-recongition-models/$embeddingFileName';
  static const _embeddingMirrorRepository =
      'csukuangfj/speaker-embedding-models';
  static const _embeddingMirrorRevision =
      '0743f301363dec56491a490f6d6cbc9d67f9a3bf';

  final _storage = FileStorageService.instance;
  bool _operationBusy = false;

  String get _root => p.join(_storage.baseDir, 'models', 'audio', modelId);
  String get _activeDir => p.join(_root, 'active');
  String get _downloadDir => p.join(_root, '.download');
  String get _segmentationPartial =>
      p.join(_downloadDir, '$segmentationArchiveName.part');
  String get _embeddingPartial =>
      p.join(_downloadDir, '$embeddingFileName.part');

  Future<SpeakerDiarizationModelInfo> inspect({
    bool verifyIntegrity = false,
  }) async {
    final segmentation = File(p.join(_activeDir, segmentationFileName));
    final embedding = File(p.join(_activeDir, embeddingFileName));
    final manifest = File(p.join(_activeDir, 'manifest.json'));
    if (!await segmentation.exists() ||
        !await embedding.exists() ||
        !await manifest.exists()) {
      return const SpeakerDiarizationModelInfo(
        installed: false,
        problem: '说话人分离模型尚未安装',
      );
    }
    try {
      final metadata = jsonDecode(await manifest.readAsString());
      if (metadata is! Map ||
          metadata['id'] != modelId ||
          metadata['revision'] != _revision) {
        return const SpeakerDiarizationModelInfo(
          installed: false,
          problem: '说话人分离模型版本不匹配，请重新下载',
        );
      }
      if (await segmentation.length() != segmentationBytes ||
          await embedding.length() != embeddingBytes) {
        return const SpeakerDiarizationModelInfo(
          installed: false,
          problem: '说话人分离模型文件不完整，请重新下载',
        );
      }
      if (verifyIntegrity) {
        final valid = await Isolate.run(() async {
          final segmentationDigest = await sha256
              .bind(segmentation.openRead())
              .first;
          final embeddingDigest = await sha256.bind(embedding.openRead()).first;
          return segmentationDigest.toString() == _segmentationSha256 &&
              embeddingDigest.toString() == _embeddingSha256;
        });
        if (!valid) {
          return const SpeakerDiarizationModelInfo(
            installed: false,
            problem: '说话人分离模型完整性校验失败，请重新下载',
          );
        }
      }
      return SpeakerDiarizationModelInfo(
        installed: true,
        segmentationPath: segmentation.path,
        embeddingPath: embedding.path,
        sizeBytes:
            await segmentation.length() +
            await embedding.length() +
            await manifest.length(),
      );
    } on FormatException {
      return const SpeakerDiarizationModelInfo(
        installed: false,
        problem: '说话人分离模型清单损坏，请重新下载',
      );
    } on FileSystemException {
      return const SpeakerDiarizationModelInfo(
        installed: false,
        problem: '无法读取说话人分离模型',
      );
    }
  }

  Future<int> partialDownloadBytes() async {
    final segmentation = File(_segmentationPartial);
    final embedding = File(_embeddingPartial);
    final first = await segmentation.exists()
        ? (await segmentation.length()).clamp(0, segmentationArchiveBytes)
        : 0;
    final second = await embedding.exists()
        ? (await embedding.length()).clamp(0, embeddingBytes)
        : 0;
    return first + second;
  }

  Future<SpeakerDiarizationModelInfo?> pickAndImport({
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    const archiveGroup = XTypeGroup(
      label: 'Pyannote 分段模型归档',
      extensions: ['bz2'],
    );
    const embeddingGroup = XTypeGroup(
      label: '3D-Speaker 嵌入模型',
      extensions: ['onnx'],
    );
    final archive = await openFile(acceptedTypeGroups: [archiveGroup]);
    if (archive == null) return null;
    final embedding = await openFile(acceptedTypeGroups: [embeddingGroup]);
    if (embedding == null) return null;
    return _runExclusive(() async {
      if (await archive.length() != segmentationArchiveBytes ||
          await embedding.length() != embeddingBytes) {
        throw const FormatException('说话人分离模型文件大小不匹配');
      }
      final importing = Directory(p.join(_root, '.importing'));
      if (await importing.exists()) await importing.delete(recursive: true);
      await importing.create(recursive: true);
      final localArchive = File(
        p.join(importing.path, segmentationArchiveName),
      );
      final localEmbedding = File(p.join(importing.path, embeddingFileName));
      try {
        await _copyImportFile(
          archive,
          localArchive,
          baseBytes: 0,
          totalFileBytes: segmentationArchiveBytes,
          onProgress: onProgress,
        );
        await _copyImportFile(
          embedding,
          localEmbedding,
          baseBytes: segmentationArchiveBytes,
          totalFileBytes: embeddingBytes,
          onProgress: onProgress,
        );
        return await _install(
          localArchive,
          localEmbedding,
          onProgress: onProgress,
        );
      } finally {
        if (await importing.exists()) await importing.delete(recursive: true);
      }
    });
  }

  Future<void> _copyImportFile(
    XFile source,
    File destination, {
    required int baseBytes,
    required int totalFileBytes,
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    final output = await destination.open(mode: FileMode.write);
    var copied = 0;
    try {
      await for (final chunk in source.openRead()) {
        await output.writeFrom(chunk);
        copied += chunk.length;
        onProgress?.call(
          SpeechModelImportProgress(baseBytes + copied, downloadSizeBytes),
        );
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if (copied != totalFileBytes) {
      throw const FormatException('说话人分离模型导入不完整');
    }
  }

  Future<SpeakerDiarizationModelInfo> download({
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => _runExclusive(() async {
    await Directory(_downloadDir).create(recursive: true);
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _downloadAsset(
          sources: [
            ModelDownloadSource(
              uri: Uri.parse(_segmentationUrl),
              label: 'GitHub 官方源',
            ),
          ],
          path: _segmentationPartial,
          expectedBytes: segmentationArchiveBytes,
          baseBytes: 0,
          onProgress: onProgress,
          shouldCancel: shouldCancel,
        );
        await _downloadAsset(
          sources: [
            ModelDownloadSource(
              uri: Uri.parse(
                'https://hf-mirror.com/$_embeddingMirrorRepository/resolve/'
                '$_embeddingMirrorRevision/$embeddingFileName?download=true',
              ),
              label: 'Hugging Face 国内镜像',
            ),
            ModelDownloadSource(
              uri: Uri.parse(
                'https://huggingface.co/$_embeddingMirrorRepository/resolve/'
                '$_embeddingMirrorRevision/$embeddingFileName?download=true',
              ),
              label: 'Hugging Face',
            ),
            ModelDownloadSource(
              uri: Uri.parse(_embeddingUrl),
              label: 'GitHub 官方源',
            ),
          ],
          path: _embeddingPartial,
          expectedBytes: embeddingBytes,
          baseBytes: segmentationArchiveBytes,
          onProgress: onProgress,
          shouldCancel: shouldCancel,
        );
        return await _install(
          File(_segmentationPartial),
          File(_embeddingPartial),
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
    throw lastError ?? const HttpException('说话人分离模型下载失败');
  });

  Future<void> _downloadAsset({
    required List<ModelDownloadSource> sources,
    required String path,
    required int expectedBytes,
    required int baseBytes,
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    await ModelDownloadTransport.instance.download(
      sources: sources,
      partial: File(path),
      expectedBytes: expectedBytes,
      userAgent: 'fknotes/$modelId',
      shouldCancel: shouldCancel,
      onProgress: (event) => onProgress?.call(
        SpeechModelImportProgress(
          baseBytes + event.transferredBytes,
          downloadSizeBytes,
          connecting: event.connecting,
          sourceLabel: event.sourceLabel,
        ),
      ),
    );
  }

  Future<SpeakerDiarizationModelInfo> _install(
    File archive,
    File embedding, {
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => ModelInstallCoordinator.instance.run(
    () => _installNow(archive, embedding, onProgress: onProgress),
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

  Future<SpeakerDiarizationModelInfo> _installNow(
    File archive,
    File embedding, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const SpeechModelImportProgress(
        downloadSizeBytes,
        downloadSizeBytes,
        verifying: true,
      ),
    );
    if (!await archive.exists() ||
        await archive.length() != segmentationArchiveBytes ||
        !await embedding.exists() ||
        await embedding.length() != embeddingBytes) {
      throw const FormatException('说话人分离模型文件不完整');
    }
    final archiveDigest = await sha256.bind(archive.openRead()).first;
    final embeddingDigest = await sha256.bind(embedding.openRead()).first;
    final archiveValid = archiveDigest.toString() == _segmentationArchiveSha256;
    final embeddingValid = embeddingDigest.toString() == _embeddingSha256;
    if (!archiveValid || !embeddingValid) {
      if (!archiveValid) await archive.delete();
      if (!embeddingValid) await embedding.delete();
      throw const FormatException('说话人分离模型完整性校验失败，请重新下载');
    }
    final staging = Directory(p.join(_root, '.installing'));
    final extractionArchive = File(p.join(_root, '.installing.tar.bz2'));
    if (await staging.exists()) await staging.delete(recursive: true);
    if (await extractionArchive.exists()) await extractionArchive.delete();
    await staging.create(recursive: true);
    try {
      await archive.copy(extractionArchive.path);
      final extracted = Directory(p.join(staging.path, 'extracted'));
      await Isolate.run(
        () => extractFileToDisk(extractionArchive.path, extracted.path),
      );
      final sourceSegmentation = File(
        p.join(
          extracted.path,
          'sherpa-onnx-pyannote-segmentation-3-0',
          'model.int8.onnx',
        ),
      );
      if (!await sourceSegmentation.exists() ||
          await sourceSegmentation.length() != segmentationBytes) {
        throw const FormatException('Pyannote INT8 模型解压不完整');
      }
      final segmentationDigest = await sha256
          .bind(sourceSegmentation.openRead())
          .first;
      if (segmentationDigest.toString() != _segmentationSha256) {
        throw const FormatException('Pyannote INT8 模型校验失败');
      }
      await sourceSegmentation.copy(p.join(staging.path, segmentationFileName));
      final pyannoteLicense = File(
        p.join(
          extracted.path,
          'sherpa-onnx-pyannote-segmentation-3-0',
          'LICENSE',
        ),
      );
      if (await pyannoteLicense.exists()) {
        await pyannoteLicense.copy(
          p.join(staging.path, 'PYANNOTE_LICENSE.txt'),
        );
      }
      await embedding.copy(p.join(staging.path, embeddingFileName));
      await extracted.delete(recursive: true);
      await File(p.join(staging.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'id': modelId,
          'revision': _revision,
          'segmentation': 'Pyannote segmentation 3.0 INT8',
          'embedding': '3D-Speaker ERes2Net Base zh-cn 16k',
          'segmentationSource': _segmentationUrl,
          'embeddingSource': _embeddingUrl,
          'licenses': ['MIT', 'Apache-2.0'],
          'sampleRate': 16000,
        }),
        flush: true,
      );
      await _activate(staging);
      final download = Directory(_downloadDir);
      if (await download.exists()) await download.delete(recursive: true);
      return inspect();
    } finally {
      if (await extractionArchive.exists()) await extractionArchive.delete();
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
    if (_operationBusy) throw StateError('说话人分离模型正在下载或导入');
    for (final name in ['active', '.download', '.importing', '.installing']) {
      final directory = Directory(p.join(_root, name));
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    final extractionArchive = File(p.join(_root, '.installing.tar.bz2'));
    if (await extractionArchive.exists()) await extractionArchive.delete();
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    if (_operationBusy) throw StateError('说话人分离模型已有任务正在进行');
    _operationBusy = true;
    try {
      return await operation();
    } finally {
      _operationBusy = false;
    }
  }
}
