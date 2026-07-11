import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'file_storage_service.dart';
import 'speech_model_service.dart';

class KokoroTtsModelInfo {
  final bool installed;
  final String rootPath;
  final int sizeBytes;
  final String? problem;

  const KokoroTtsModelInfo({
    required this.installed,
    this.rootPath = '',
    this.sizeBytes = 0,
    this.problem,
  });

  String get modelPath => p.join(rootPath, 'model.int8.onnx');
  String get voicesPath => p.join(rootPath, 'voices.bin');
  String get tokensPath => p.join(rootPath, 'tokens.txt');
  String get dataDir => p.join(rootPath, 'espeak-ng-data');
  String get dictDir => p.join(rootPath, 'dict');
  String get lexiconPath => [
    p.join(rootPath, 'lexicon-zh.txt'),
    p.join(rootPath, 'lexicon-us-en.txt'),
  ].join(',');
  String get ruleFsts => [
    p.join(rootPath, 'phone-zh.fst'),
    p.join(rootPath, 'date-zh.fst'),
    p.join(rootPath, 'number-zh.fst'),
  ].join(',');
}

class KokoroTtsModelService {
  KokoroTtsModelService._();
  static final KokoroTtsModelService instance = KokoroTtsModelService._();

  static const modelId = 'kokoro-int8-multi-lang-v1_1';
  static const downloadSizeBytes = 147031220;
  static const archiveFileName = '$modelId.tar.bz2';
  static const _sha256 =
      'a1e94694776049035c4f2c6529f003aaece993c76aae9a78995831c3c4dcafc6';
  static const _downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'tts-models/$archiveFileName';

  static const _requiredFiles = {
    'model.int8.onnx': 114299010,
    'voices.bin': 53790720,
    'tokens.txt': 1111,
    'lexicon-zh.txt': 2119465,
    'lexicon-us-en.txt': 5956885,
    'phone-zh.fst': 88630,
    'date-zh.fst': 59154,
    'number-zh.fst': 64482,
  };
  static const _requiredSha256 = {
    'model.int8.onnx':
        'bda15858163726a492d02a9a727bc263551b86ac77f90812c4b30ff41d380e26',
    'voices.bin':
        'e64a5a581d8c2a350d848f51c3121657cd83aa07ed6109172177345874a7244c',
    'tokens.txt':
        '931ab2df2400cd65d580a22402024c2347ced8ae9ea300e545144b1aacc48e14',
    'lexicon-zh.txt':
        '11111d8cd695fba2ace1367a1d0a708b586e6ef5c1f9be91da5d7eef129b651c',
    'lexicon-us-en.txt':
        '7daaab53a181be9885b853a8582bf1838186317e5dadacbcef9c426d6fa0da14',
    'phone-zh.fst':
        '1ac2b6fa56b1442320c4de7db08353bab8963a2b57f365eebcdd3a2d3562f8d7',
    'date-zh.fst':
        'eb8aa079ae3cb81d8f4404992f39d61a0cb990947512b5b8d1e54d1f6980e718',
    'number-zh.fst':
        '743f402181fcfebf76cc2f0546b71fa26476e626fbe4e460fb7b4c3a7a8bd5bd',
  };

  final _storage = FileStorageService.instance;
  bool _operationBusy = false;

  String get _root => p.join(_storage.baseDir, 'models', 'tts', modelId);
  String get _activeDir => p.join(_root, 'active');
  String get _downloadDir => p.join(_root, '.download');
  String get _partialPath => p.join(_downloadDir, '$archiveFileName.part');

  Future<KokoroTtsModelInfo> inspect({bool verifyIntegrity = false}) async {
    final active = Directory(_activeDir);
    final manifest = File(p.join(_activeDir, 'manifest.json'));
    if (!await active.exists() || !await manifest.exists()) {
      return const KokoroTtsModelInfo(
        installed: false,
        problem: 'Kokoro TTS 尚未安装',
      );
    }
    try {
      final metadata = jsonDecode(await manifest.readAsString());
      if (metadata is! Map || metadata['id'] != modelId) {
        return const KokoroTtsModelInfo(
          installed: false,
          problem: 'Kokoro TTS 版本不匹配，请重新下载',
        );
      }
      for (final entry in _requiredFiles.entries) {
        final file = File(p.join(_activeDir, entry.key));
        if (!await file.exists() || await file.length() != entry.value) {
          return KokoroTtsModelInfo(
            installed: false,
            problem: '${entry.key} 不完整，请重新下载',
          );
        }
      }
      for (final name in ['dict', 'espeak-ng-data']) {
        if (!await Directory(p.join(_activeDir, name)).exists()) {
          return KokoroTtsModelInfo(
            installed: false,
            problem: '$name 不完整，请重新下载',
          );
        }
      }
      if (verifyIntegrity) {
        final valid = await Isolate.run(() async {
          for (final entry in _requiredFiles.entries) {
            final file = File(p.join(_activeDir, entry.key));
            final digest = await sha256.bind(file.openRead()).first;
            if (digest.toString() != _requiredSha256[entry.key]) return false;
          }
          return true;
        });
        if (!valid) {
          return const KokoroTtsModelInfo(
            installed: false,
            problem: 'Kokoro TTS 完整性校验失败',
          );
        }
      }
      return KokoroTtsModelInfo(
        installed: true,
        rootPath: _activeDir,
        sizeBytes: await _directorySize(active),
      );
    } on FormatException {
      return const KokoroTtsModelInfo(
        installed: false,
        problem: 'Kokoro TTS 清单损坏，请重新下载',
      );
    } on FileSystemException {
      return const KokoroTtsModelInfo(
        installed: false,
        problem: '无法读取 Kokoro TTS 模型',
      );
    }
  }

  Future<int> partialDownloadBytes() async {
    final file = File(_partialPath);
    if (!await file.exists()) return 0;
    return (await file.length()).clamp(0, downloadSizeBytes);
  }

  Future<KokoroTtsModelInfo?> pickAndImport({
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    const group = XTypeGroup(label: 'Kokoro TTS 模型归档', extensions: ['bz2']);
    final selected = await openFile(acceptedTypeGroups: [group]);
    if (selected == null) return null;
    return _runExclusive(() async {
      if (await selected.length() != downloadSizeBytes) {
        throw const FormatException('Kokoro TTS 模型归档大小不匹配');
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
          onProgress?.call(
            SpeechModelImportProgress(copied, downloadSizeBytes),
          );
        }
      } finally {
        await output.close();
      }
      try {
        return await _install(archive, onProgress: onProgress);
      } finally {
        if (await importing.exists()) await importing.delete(recursive: true);
      }
    });
  }

  Future<KokoroTtsModelInfo> download({
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => _runExclusive(() async {
    await Directory(_downloadDir).create(recursive: true);
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await _downloadOnce(onProgress, shouldCancel);
        return await _install(File(_partialPath), onProgress: onProgress);
      } on SpeechModelDownloadCanceled {
        rethrow;
      } catch (error) {
        lastError = error;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
    throw lastError ?? const HttpException('Kokoro TTS 下载失败');
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
    if (existing == downloadSizeBytes) return;
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
      final resumable = response.statusCode == HttpStatus.partialContent;
      if (response.statusCode != HttpStatus.ok && !resumable) {
        throw HttpException('Kokoro TTS 下载失败（${response.statusCode}）');
      }
      if (existing > 0 && !resumable) {
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
          throw const FormatException('Kokoro TTS 下载大小异常');
        }
        onProgress?.call(
          SpeechModelImportProgress(received, downloadSizeBytes),
        );
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != downloadSizeBytes) {
        throw const FormatException('Kokoro TTS 下载中断，将自动续传');
      }
    } finally {
      await output?.close();
      client.close(force: true);
    }
  }

  Future<KokoroTtsModelInfo> _install(
    File archive, {
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
        await archive.length() != downloadSizeBytes) {
      throw const FormatException('Kokoro TTS 模型归档不完整');
    }
    final digest = await sha256.bind(archive.openRead()).first;
    if (digest.toString() != _sha256) {
      await archive.delete();
      throw const FormatException('Kokoro TTS 完整性校验失败，请重新下载');
    }
    final extracting = Directory(p.join(_root, '.installing'));
    if (await extracting.exists()) await extracting.delete(recursive: true);
    await extracting.create(recursive: true);
    final extractionArchive = File(p.join(_root, '.installing.tar.bz2'));
    if (await extractionArchive.exists()) await extractionArchive.delete();
    await archive.rename(extractionArchive.path);
    try {
      await Isolate.run(
        () => extractFileToDisk(extractionArchive.path, extracting.path),
      );
      final modelRoot = Directory(p.join(extracting.path, modelId));
      if (!await modelRoot.exists()) {
        throw const FormatException('Kokoro TTS 归档目录异常');
      }
      for (final entry in _requiredFiles.entries) {
        final file = File(p.join(modelRoot.path, entry.key));
        if (!await file.exists() || await file.length() != entry.value) {
          throw FormatException('${entry.key} 解压不完整');
        }
      }
      await File(p.join(modelRoot.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'id': modelId,
          'engine': 'sherpa-onnx-kokoro',
          'source': _downloadUrl,
          'license': 'Apache-2.0',
          'sampleRate': 24000,
          'speakers': 103,
        }),
        flush: true,
      );
      await _activate(modelRoot);
      final download = Directory(_downloadDir);
      if (await download.exists()) await download.delete(recursive: true);
      return inspect();
    } catch (_) {
      if (await extractionArchive.exists() && !await archive.exists()) {
        await extractionArchive.rename(archive.path);
      }
      rethrow;
    } finally {
      if (await extractionArchive.exists()) await extractionArchive.delete();
      if (await extracting.exists()) await extracting.delete(recursive: true);
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
    if (_operationBusy) throw StateError('Kokoro TTS 正在下载或导入');
    for (final name in ['active', '.download', '.importing', '.installing']) {
      final directory = Directory(p.join(_root, name));
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    final extractionArchive = File(p.join(_root, '.installing.tar.bz2'));
    if (await extractionArchive.exists()) await extractionArchive.delete();
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    if (_operationBusy) throw StateError('Kokoro TTS 已有任务正在进行');
    _operationBusy = true;
    try {
      return await operation();
    } finally {
      _operationBusy = false;
    }
  }
}

Future<int> _directorySize(Directory directory) async {
  var total = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) total += await entity.length();
  }
  return total;
}
