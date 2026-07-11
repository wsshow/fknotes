import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'file_storage_service.dart';
import 'model_install_coordinator.dart';
import 'speech_model_service.dart';

class StreamingSpeechModelInfo {
  final String modelId;
  final String displayName;
  final bool installed;
  final String? problem;
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final String modelingUnit;
  final String bpeVocabPath;
  final int sizeBytes;

  const StreamingSpeechModelInfo({
    required this.modelId,
    required this.displayName,
    required this.installed,
    this.problem,
    this.encoderPath = '',
    this.decoderPath = '',
    this.joinerPath = '',
    this.tokensPath = '',
    this.modelingUnit = '',
    this.bpeVocabPath = '',
    this.sizeBytes = 0,
  });
}

class _RemoteModelFile {
  final String localName;
  final String remotePath;
  final int sizeBytes;
  final String sha256;

  const _RemoteModelFile(
    this.localName,
    this.remotePath,
    this.sizeBytes,
    this.sha256,
  );

  String get sourceName => p.basename(remotePath);
}

class _StreamingModelSpec {
  final String id;
  final String displayName;
  final String storageFolder;
  final String repository;
  final String revision;
  final String runtimeLayout;
  final String modelingUnit;
  final List<_RemoteModelFile> files;

  const _StreamingModelSpec({
    required this.id,
    required this.displayName,
    required this.storageFolder,
    required this.repository,
    required this.revision,
    required this.runtimeLayout,
    required this.modelingUnit,
    required this.files,
  });

  int get downloadSizeBytes =>
      files.fold(0, (total, definition) => total + definition.sizeBytes);
}

/// Installs, verifies and selects device-local streaming ASR models.
///
/// Every model has an isolated transactional directory. Selection is stored
/// separately, so users can keep multiple models installed and switch the one
/// used by the next dictation session without moving model files.
class StreamingSpeechModelService {
  StreamingSpeechModelService._();
  static final StreamingSpeechModelService instance =
      StreamingSpeechModelService._();

  static const modelId = 'streaming-zipformer-zh-int8-2025-06-30';
  static const bilingualModelId =
      'streaming-zipformer-bilingual-zh-en-int8-2023-02-20';
  static const downloadSizeBytes = 167360920;
  static const bilingualDownloadSizeBytes = 198283357;
  static const supportedModelIds = [modelId, bilingualModelId];

  static const _encoderFileName = 'encoder.int8.onnx';
  static const _decoderFileName = 'decoder.onnx';
  static const _joinerFileName = 'joiner.int8.onnx';
  static const _tokensFileName = 'tokens.txt';
  static const _bpeVocabFileName = 'bpe.vocab';
  static const _manifestFileName = 'manifest.json';

  static const _specs = <_StreamingModelSpec>[
    _StreamingModelSpec(
      id: modelId,
      displayName: 'Streaming Zipformer 中文',
      // Keep the original path so existing installations remain valid.
      storageFolder: 'streaming-zipformer-zh-14m',
      repository:
          'csukuangfj/sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30',
      revision: 'ad658fa0201659a09ea3c176129a191c77ecae8f',
      runtimeLayout: 'int8-encoder + fp32-decoder + int8-joiner',
      modelingUnit: 'cjkchar',
      files: [
        _RemoteModelFile(
          _encoderFileName,
          _encoderFileName,
          161141793,
          '5ac51e27981bb4dab01bb9be4958453ba50c3b61c063ddda0eab23fd3671aa4f',
        ),
        _RemoteModelFile(
          _decoderFileName,
          _decoderFileName,
          5165083,
          '06522ad63cec0fdf6809f4e1db9bb4f7d710c34582e3b35db62ac60eccafac7e',
        ),
        _RemoteModelFile(
          _joinerFileName,
          _joinerFileName,
          1033416,
          'b34584dc6f561089e1d747fedebb3765f2caa72c927ef54d7ca55e5ae40a814b',
        ),
        _RemoteModelFile(
          _tokensFileName,
          _tokensFileName,
          20628,
          '6193c7ea1c96d0d9a1e9652789b40d13a8a913b434a5451e93158f5a09fd6652',
        ),
      ],
    ),
    _StreamingModelSpec(
      id: bilingualModelId,
      displayName: 'Streaming Zipformer 中英双语',
      storageFolder: 'streaming-zipformer-bilingual-zh-en-2023-02-20',
      repository:
          'csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20',
      revision: '98590b7ed6443e77b714204da2757d75e1a642f4',
      runtimeLayout: 'int8-encoder + int8-decoder + int8-joiner',
      modelingUnit: 'cjkchar+bpe',
      files: [
        _RemoteModelFile(
          _encoderFileName,
          'encoder-epoch-99-avg-1.int8.onnx',
          181895032,
          '8fa764187a261844f859d7143ebaa563af5d10adfece4c18a8f414c88cba2a9b',
        ),
        _RemoteModelFile(
          _decoderFileName,
          'decoder-epoch-99-avg-1.int8.onnx',
          13091040,
          '1a70c593d71e53f023f5f55b0b4cfff5055abb786ee3992e5f63dc2e273cc4fa',
        ),
        _RemoteModelFile(
          _joinerFileName,
          'joiner-epoch-99-avg-1.int8.onnx',
          3228404,
          '1ed689c5ed19dbaa725d9d191bb4822b5f4855a39e1ffd28cbc1f340d25b2ee0',
        ),
        _RemoteModelFile(
          _tokensFileName,
          _tokensFileName,
          56317,
          'a8e0e4ec53810e433789b54a5c0134a7eaa2ffca595a6334d54c00da858841d3',
        ),
        _RemoteModelFile(
          _bpeVocabFileName,
          _bpeVocabFileName,
          12564,
          'd0b642f3a2eacd5fadefdeff9e0e1358cab729647cbb7fe58cf738e1f7407029',
        ),
      ],
    ),
  ];

  final _storage = FileStorageService.instance;
  final Set<String> _busyModelIds = {};

  String get _selectionPath =>
      p.join(_storage.baseDir, 'models', 'asr', 'live-dictation.json');

  _StreamingModelSpec _spec(String id) =>
      _specs.firstWhere((definition) => definition.id == id);

  String _root(_StreamingModelSpec spec) =>
      p.join(_storage.baseDir, 'models', 'asr', spec.storageFolder);
  String _activeDir(_StreamingModelSpec spec) => p.join(_root(spec), 'active');
  String _downloadDir(_StreamingModelSpec spec) =>
      p.join(_root(spec), '.download');
  String _partialPath(_StreamingModelSpec spec, _RemoteModelFile file) =>
      p.join(_downloadDir(spec), '${file.localName}.part');

  String displayName(String id) => _spec(id).displayName;

  Future<String> selectedModelId() async {
    final selection = File(_selectionPath);
    if (!selection.existsSync()) return modelId;
    try {
      final metadata = jsonDecode(selection.readAsStringSync());
      final value = metadata is Map ? metadata['modelId'] : null;
      final id = value is String ? value : null;
      return supportedModelIds.contains(id) ? id! : modelId;
    } on FormatException {
      return modelId;
    } on FileSystemException {
      return modelId;
    }
  }

  Future<void> selectModel(String id) async {
    final info = await inspect(modelId: id);
    if (!info.installed) {
      throw StateError('${info.displayName}尚未安装');
    }
    final destination = File(_selectionPath);
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent(' ').convert({'modelId': id}),
      flush: true,
    );
    try {
      await temporary.rename(destination.path);
    } on FileSystemException {
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    }
  }

  Future<void> resetSelection() async {
    final selection = File(_selectionPath);
    if (await selection.exists()) await selection.delete();
  }

  Future<StreamingSpeechModelInfo> inspect({
    String? modelId,
    bool verifyIntegrity = false,
  }) async {
    final spec = _spec(modelId ?? await selectedModelId());
    StreamingSpeechModelInfo unavailable(String problem) =>
        StreamingSpeechModelInfo(
          modelId: spec.id,
          displayName: spec.displayName,
          installed: false,
          problem: problem,
          modelingUnit: spec.modelingUnit,
        );

    final active = _activeDir(spec);
    final encoder = File(p.join(active, _encoderFileName));
    final decoder = File(p.join(active, _decoderFileName));
    final joiner = File(p.join(active, _joinerFileName));
    final tokens = File(p.join(active, _tokensFileName));
    final bpeVocab = File(p.join(active, _bpeVocabFileName));
    final manifest = File(p.join(active, _manifestFileName));
    final runtimeFilesByName = {
      _encoderFileName: encoder,
      _decoderFileName: decoder,
      _joinerFileName: joiner,
      _tokensFileName: tokens,
      if (spec.files.any((file) => file.localName == _bpeVocabFileName))
        _bpeVocabFileName: bpeVocab,
    };
    final runtimeFiles = [
      for (final definition in spec.files)
        runtimeFilesByName[definition.localName]!,
    ];
    final files = [...runtimeFiles, manifest];
    if (!manifest.existsSync() ||
        runtimeFiles.any((file) => !file.existsSync())) {
      if (spec.modelingUnit == 'cjkchar+bpe' && !bpeVocab.existsSync()) {
        return unavailable('中英模型需补充热词词表，请继续下载完成增量升级');
      }
      return unavailable('实时语音模型尚未安装');
    }
    try {
      final metadata = jsonDecode(await manifest.readAsString());
      if (metadata is! Map ||
          metadata['id'] != spec.id ||
          metadata['revision'] != spec.revision ||
          metadata['runtimeFiles'] != spec.runtimeLayout) {
        return unavailable('实时语音模型版本不匹配，请删除后重新下载');
      }
    } on FormatException {
      return unavailable('实时语音模型清单损坏，请删除后重新下载');
    } on FileSystemException {
      return unavailable('无法读取实时语音模型，请检查存储空间');
    }
    for (var index = 0; index < runtimeFiles.length; index++) {
      if (await runtimeFiles[index].length() != spec.files[index].sizeBytes) {
        return unavailable('${spec.files[index].localName} 大小异常，请删除模型后重新下载');
      }
    }
    if (verifyIntegrity) {
      final checks = [
        for (var index = 0; index < runtimeFiles.length; index++)
          _ModelHashCheck(runtimeFiles[index].path, spec.files[index].sha256),
      ];
      final valid = await Isolate.run(() => _verifyModelHashes(checks));
      if (!valid) {
        return unavailable('实时语音模型完整性校验失败，请删除模型后重新下载');
      }
    }
    var size = 0;
    for (final file in files) {
      size += await file.length();
    }
    return StreamingSpeechModelInfo(
      modelId: spec.id,
      displayName: spec.displayName,
      installed: true,
      encoderPath: encoder.path,
      decoderPath: decoder.path,
      joinerPath: joiner.path,
      tokensPath: tokens.path,
      modelingUnit: spec.modelingUnit,
      bpeVocabPath: spec.modelingUnit.contains('bpe') ? bpeVocab.path : '',
      sizeBytes: size,
    );
  }

  Future<int> partialDownloadBytes(String modelId) async {
    final spec = _spec(modelId);
    var total = 0;
    for (final definition in spec.files) {
      final partial = File(_partialPath(spec, definition));
      if (await partial.exists()) {
        total += (await partial.length()).clamp(0, definition.sizeBytes);
        continue;
      }
      // Count reusable files from a previous model layout so the model manager
      // accurately presents a tiny metadata upgrade instead of a full re-download.
      final active = File(p.join(_activeDir(spec), definition.localName));
      if (await active.exists() &&
          await active.length() == definition.sizeBytes) {
        total += definition.sizeBytes;
      }
    }
    return total;
  }

  Future<StreamingSpeechModelInfo?> pickAndImport(
    String modelId, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    final spec = _spec(modelId);
    const group = XTypeGroup(
      label: 'Streaming Zipformer 模型文件',
      extensions: ['onnx', 'txt', 'vocab'],
    );
    final selected = await openFiles(acceptedTypeGroups: [group]);
    if (selected.isEmpty) return null;
    return _runExclusive(modelId, () async {
      final byName = {for (final file in selected) file.name: file};
      final sourcesByDefinition = <_RemoteModelFile, XFile>{};
      for (final definition in spec.files) {
        final selectedFile =
            byName[definition.localName] ?? byName[definition.sourceName];
        if (selectedFile == null) {
          throw FormatException(
            '请选择 ${spec.files.map((file) => file.sourceName).join('、')}',
          );
        }
        sourcesByDefinition[definition] = selectedFile;
      }
      final importing = Directory(p.join(_root(spec), '.importing'));
      if (await importing.exists()) await importing.delete(recursive: true);
      await importing.create(recursive: true);
      var copiedTotal = 0;
      final sources = <String, File>{};
      try {
        for (final definition in spec.files) {
          final selectedFile = sourcesByDefinition[definition]!;
          if (await selectedFile.length() != definition.sizeBytes) {
            throw FormatException('${definition.sourceName} 大小不匹配');
          }
          final destination = File(
            p.join(importing.path, '${definition.localName}.part'),
          );
          final output = await destination.open(mode: FileMode.write);
          try {
            await for (final chunk in selectedFile.openRead()) {
              await output.writeFrom(chunk);
              copiedTotal += chunk.length;
              onProgress?.call(
                SpeechModelImportProgress(copiedTotal, spec.downloadSizeBytes),
              );
            }
            await output.flush();
          } finally {
            await output.close();
          }
          sources[definition.localName] = destination;
        }
        return await _installFiles(spec, sources, onProgress: onProgress);
      } finally {
        if (await importing.exists()) await importing.delete(recursive: true);
      }
    });
  }

  Future<StreamingSpeechModelInfo> downloadFromHuggingFaceMirror(
    String modelId, {
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => _runExclusive(modelId, () async {
    final spec = _spec(modelId);
    await Directory(_downloadDir(spec)).create(recursive: true);
    final currentBytes = <String, int>{};
    for (final definition in spec.files) {
      final partial = File(_partialPath(spec, definition));
      var size = await partial.exists() ? await partial.length() : 0;
      if (size > definition.sizeBytes) {
        await partial.delete();
        size = 0;
      }
      if (size == 0) {
        final reusable = File(p.join(_activeDir(spec), definition.localName));
        if (await _matchesDefinition(reusable, definition)) {
          await reusable.copy(partial.path);
          size = definition.sizeBytes;
        }
      }
      currentBytes[definition.localName] = size;
    }

    void report(String name, int bytes) {
      currentBytes[name] = bytes;
      onProgress?.call(
        SpeechModelImportProgress(
          currentBytes.values.fold(0, (sum, value) => sum + value),
          spec.downloadSizeBytes,
        ),
      );
    }

    for (final definition in spec.files) {
      await _downloadFile(
        spec,
        definition,
        onProgress: (bytes) => report(definition.localName, bytes),
        shouldCancel: shouldCancel,
      );
    }
    if (shouldCancel?.call() == true) {
      throw const SpeechModelDownloadCanceled();
    }
    final sources = {
      for (final definition in spec.files)
        definition.localName: File(_partialPath(spec, definition)),
    };
    return _installFiles(
      spec,
      sources,
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
  });

  Future<bool> _matchesDefinition(
    File file,
    _RemoteModelFile definition,
  ) async {
    if (!await file.exists() || await file.length() != definition.sizeBytes) {
      return false;
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == definition.sha256;
  }

  Future<void> _downloadFile(
    _StreamingModelSpec spec,
    _RemoteModelFile definition, {
    required void Function(int bytes) onProgress,
    bool Function()? shouldCancel,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _downloadFileOnce(
          spec,
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
    throw lastError ?? HttpException('${definition.sourceName} 下载失败');
  }

  Future<void> _downloadFileOnce(
    _StreamingModelSpec spec,
    _RemoteModelFile definition, {
    required void Function(int bytes) onProgress,
    bool Function()? shouldCancel,
  }) async {
    final partial = File(_partialPath(spec, definition));
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
        'https://hf-mirror.com/${spec.repository}/resolve/'
        '${spec.revision}/${definition.remotePath}?download=true',
      );
      final request = await client.getUrl(uri);
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      request.headers.set(HttpHeaders.userAgentHeader, 'fknotes/${spec.id}');
      final response = await request.close();
      final canResume = response.statusCode == HttpStatus.partialContent;
      if (response.statusCode != HttpStatus.ok && !canResume) {
        throw HttpException(
          '${definition.sourceName} 下载失败（${response.statusCode}）',
        );
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
          throw FormatException('${definition.sourceName} 下载大小异常');
        }
        onProgress(received);
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != definition.sizeBytes) {
        throw FormatException('${definition.sourceName} 下载不完整，将在下次继续');
      }
    } finally {
      await output?.close();
      client.close(force: true);
    }
  }

  Future<StreamingSpeechModelInfo> _installFiles(
    _StreamingModelSpec spec,
    Map<String, File> sources, {
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => ModelInstallCoordinator.instance.run(
    () => _installFilesNow(spec, sources, onProgress: onProgress),
    onWaiting: () => onProgress?.call(
      SpeechModelImportProgress(
        spec.downloadSizeBytes,
        spec.downloadSizeBytes,
        waitingForInstall: true,
      ),
    ),
    isCanceled: shouldCancel,
    cancellationError: () => const SpeechModelDownloadCanceled(),
  );

  Future<StreamingSpeechModelInfo> _installFilesNow(
    _StreamingModelSpec spec,
    Map<String, File> sources, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      SpeechModelImportProgress(
        spec.downloadSizeBytes,
        spec.downloadSizeBytes,
        verifying: true,
      ),
    );
    for (final definition in spec.files) {
      final source = sources[definition.localName];
      if (source == null || !await source.exists()) {
        throw FormatException('缺少 ${definition.sourceName}');
      }
      if (await source.length() != definition.sizeBytes) {
        throw FormatException('${definition.sourceName} 大小不匹配');
      }
      final digest = await sha256.bind(source.openRead()).first;
      if (digest.toString() != definition.sha256) {
        await source.delete();
        throw FormatException('${definition.sourceName} 文件不完整，请重新下载');
      }
    }

    final staging = Directory(p.join(_root(spec), '.installing'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      for (final definition in spec.files) {
        final source = sources[definition.localName]!;
        final destination = File(p.join(staging.path, definition.localName));
        try {
          await source.rename(destination.path);
        } on FileSystemException {
          await source.copy(destination.path);
          await source.delete();
        }
      }
      await File(p.join(staging.path, 'LICENSE.txt')).writeAsString(
        'Streaming Zipformer model: Apache License 2.0\n'
        'Upstream: https://huggingface.co/${spec.repository}\n',
        flush: true,
      );
      await File(p.join(staging.path, _manifestFileName)).writeAsString(
        const JsonEncoder.withIndent(' ').convert({
          'id': spec.id,
          'name': spec.displayName,
          'engine': 'sherpa-onnx',
          'source': 'huggingface-official-via-hf-mirror',
          'repository': spec.repository,
          'revision': spec.revision,
          'license': 'Apache-2.0',
          'runtimeFiles': spec.runtimeLayout,
        }),
        flush: true,
      );
      await _activate(spec, staging);
      final download = Directory(_downloadDir(spec));
      if (await download.exists()) await download.delete(recursive: true);
      return inspect(modelId: spec.id);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _activate(_StreamingModelSpec spec, Directory staging) async {
    final activePath = _activeDir(spec);
    final active = Directory(activePath);
    final previous = Directory('$activePath.previous');
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

  Future<void> remove(String modelId) async {
    if (_busyModelIds.contains(modelId)) {
      throw StateError('实时语音模型正在下载或导入');
    }
    final spec = _spec(modelId);
    for (final name in ['active', '.download', '.importing', '.installing']) {
      final directory = Directory(p.join(_root(spec), name));
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  Future<T> _runExclusive<T>(
    String modelId,
    Future<T> Function() operation,
  ) async {
    if (_busyModelIds.contains(modelId)) {
      throw StateError('该实时语音模型已有任务正在进行');
    }
    _busyModelIds.add(modelId);
    try {
      return await operation();
    } finally {
      _busyModelIds.remove(modelId);
    }
  }
}

class _ModelHashCheck {
  final String path;
  final String sha256Hex;

  const _ModelHashCheck(this.path, this.sha256Hex);
}

Future<bool> _verifyModelHashes(List<_ModelHashCheck> checks) async {
  for (final check in checks) {
    final digest = await sha256.bind(File(check.path).openRead()).first;
    if (digest.toString() != check.sha256Hex) return false;
  }
  return true;
}
