import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../models/local_llm.dart';
import 'file_storage_service.dart';
import 'model_download_transport.dart';
import 'model_install_coordinator.dart';
import 'speech_model_service.dart';

class LanguageModelInfo {
  final String modelId;
  final bool installed;
  final String? problem;
  final String configPath;
  final int sizeBytes;

  const LanguageModelInfo({
    required this.modelId,
    required this.installed,
    this.problem,
    this.configPath = '',
    this.sizeBytes = 0,
  });
}

class _LanguageModelFile {
  final String name;
  final int sizeBytes;
  final String sha256;

  const _LanguageModelFile(this.name, this.sizeBytes, this.sha256);
}

class _LanguageModelSpec {
  final String id;
  final String displayName;
  final String storageFolder;
  final String repository;
  final String revision;
  final int nativeContextTokens;
  final int minimumMemoryBytes;
  final LocalLlmCapabilities capabilities;
  final List<_LanguageModelFile> files;

  const _LanguageModelSpec({
    required this.id,
    required this.displayName,
    required this.storageFolder,
    required this.repository,
    required this.revision,
    required this.nativeContextTokens,
    required this.minimumMemoryBytes,
    required this.capabilities,
    required this.files,
  });

  int get downloadSizeBytes =>
      files.fold(0, (total, file) => total + file.sizeBytes);
}

/// Downloads and transactionally installs MNN language-model directories.
class LanguageModelService {
  LanguageModelService._();
  static final LanguageModelService instance = LanguageModelService._();

  static const miniCpm5Id = 'minicpm5-1b-mnn-int4';
  static const qwen35Id = 'qwen3.5-2b-mnn-int4';
  static const miniCpm5DownloadSizeBytes = 626439064;
  static const qwen35DownloadSizeBytes = 1386690287;
  static const supportedModelIds = [miniCpm5Id, qwen35Id];
  static const _manifestFileName = 'manifest.json';

  static const _specs = <_LanguageModelSpec>[
    _LanguageModelSpec(
      id: miniCpm5Id,
      displayName: 'MiniCPM5 1B INT4',
      storageFolder: 'minicpm5-1b-mnn-int4',
      repository: 'taobao-mnn/MiniCPM5-1B-MNN',
      revision: '7621114a378eace477bd3a83f96b5b4c38aaca37',
      nativeContextTokens: 131072,
      minimumMemoryBytes: 4 * 1024 * 1024 * 1024,
      capabilities: LocalLlmCapabilities(thinking: true, toolCalling: true),
      files: [
        _LanguageModelFile(
          'config.json',
          317,
          '236b584538be72c493daca7ab3abe24de5d3deedfedd47e87c44d5c24c5d846f',
        ),
        _LanguageModelFile(
          'embeddings_int4.bin',
          125337600,
          '71fe454d4901121805d99dd5f888c0b169f03263a6930dfb5c14b6866f41d81a',
        ),
        _LanguageModelFile(
          'llm.mnn',
          419768,
          '5d4ed23b414eeef767a3bfbd80b943a253a003ca9ee3b68cad78bc6b325cf4df',
        ),
        _LanguageModelFile(
          'llm.mnn.json',
          848443,
          '9eaee78129337385579a2f4718e46043757101f2dc384f8373ce9d6abae5e966',
        ),
        _LanguageModelFile(
          'llm.mnn.weight',
          495615626,
          'd87789339065661c6435b43e61fdf133929d46c768f0c67c5c9eeed44913aada',
        ),
        _LanguageModelFile(
          'llm_config.json',
          9824,
          '8043421e920ca16f638f930f04b17f52b61e9df36be0f8d404901ae6407c51b6',
        ),
        _LanguageModelFile(
          'tokenizer.mtok',
          3536385,
          '1d5777b5f38f3b72c7e2a54aa7eeca92b782a669050211e00ca84136e8cc2ef2',
        ),
        _LanguageModelFile(
          'tokenizer.txt',
          671101,
          '184864dbdd4a5ea71ef72c5e6cc414e743ae6a373e3876e1e41e387fae047e60',
        ),
      ],
    ),
    _LanguageModelSpec(
      id: qwen35Id,
      displayName: 'Qwen3.5 2B INT4',
      storageFolder: 'qwen3.5-2b-mnn-int4',
      repository: 'taobao-mnn/Qwen3.5-2B-MNN',
      revision: '35781816d7b6a9dcb273a6765ac9563401951c3c',
      nativeContextTokens: 262144,
      minimumMemoryBytes: 6 * 1024 * 1024 * 1024,
      capabilities: LocalLlmCapabilities(
        thinking: true,
        toolCalling: true,
        imageInput: true,
      ),
      files: [
        _LanguageModelFile(
          'config.json',
          652,
          '92853033efe602f95efca3e1c05cd8b108f973c8beed417843a9671f8147ed8d',
        ),
        _LanguageModelFile(
          'llm.mnn',
          2148136,
          '23df98f8b341b277365e0bbca025c1d192939e3d32d7f79776352c6f32e77960',
        ),
        _LanguageModelFile(
          'llm.mnn.json',
          5344018,
          '7131ff4f1a441add1039d371815ad94652ae6801f579591cb2f9ad90b5954025',
        ),
        _LanguageModelFile(
          'llm.mnn.weight',
          1176647702,
          'c93f71a2dbecf9328782bd38861656d8faa82e95e7f99607350074768a482054',
        ),
        _LanguageModelFile(
          'llm_config.json',
          8692,
          'a88234b36c2af0eff8e5c89667011badf71c15e30459eb0e21030a8f3f9ed240',
        ),
        _LanguageModelFile(
          'tokenizer.txt',
          6465727,
          '7e75de1f279a10b65bd9dc1a5207205cb8993823861c4c42bbbd74e48e1c23a4',
        ),
        _LanguageModelFile(
          'visual.mnn',
          488096,
          '88fc40a7b676e90eb2cb86d854db15cb90b9eb1f34087ab0f48c5e43572c8dac',
        ),
        _LanguageModelFile(
          'visual.mnn.weight',
          195587264,
          '8f90e106f5b9ae9a939faed240305cfdd5c6740ae91d3fc418a990bee0cce36b',
        ),
      ],
    ),
  ];

  final _storage = FileStorageService.instance;
  final Set<String> _busyModelIds = {};

  _LanguageModelSpec _spec(String id) =>
      _specs.firstWhere((spec) => spec.id == id);

  String _root(_LanguageModelSpec spec) =>
      p.join(_storage.baseDir, 'models', 'llm', spec.storageFolder);
  String _activeDir(_LanguageModelSpec spec) => p.join(_root(spec), 'active');
  String _downloadDir(_LanguageModelSpec spec) =>
      p.join(_root(spec), '.download');
  String _partialPath(_LanguageModelSpec spec, _LanguageModelFile file) =>
      p.join(_downloadDir(spec), '${file.name}.part');
  String get _selectionPath =>
      p.join(_storage.baseDir, 'models', 'llm', 'selection.json');

  int downloadSizeBytes(String id) => _spec(id).downloadSizeBytes;
  String displayName(String id) => _spec(id).displayName;
  LocalLlmCapabilities capabilities(String id) => _spec(id).capabilities;

  Future<String> selectedModelId() async {
    final file = File(_selectionPath);
    if (!await file.exists()) return qwen35Id;
    try {
      final json = jsonDecode(await file.readAsString());
      final id = json is Map ? json['modelId'] : null;
      return id is String && supportedModelIds.contains(id) ? id : qwen35Id;
    } on FormatException {
      return qwen35Id;
    } on FileSystemException {
      return qwen35Id;
    }
  }

  Future<void> selectModel(String id) async {
    final info = await inspect(id);
    if (!info.installed) throw StateError('${displayName(id)}尚未安装');
    final destination = File(_selectionPath);
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(jsonEncode({'modelId': id}), flush: true);
    await _replaceFile(temporary, destination);
  }

  Future<LanguageModelInfo> inspect(
    String id, {
    bool verifyIntegrity = false,
  }) async {
    final spec = _spec(id);
    LanguageModelInfo unavailable(String problem) =>
        LanguageModelInfo(modelId: id, installed: false, problem: problem);
    final active = Directory(_activeDir(spec));
    final manifest = File(p.join(active.path, _manifestFileName));
    if (!await manifest.exists()) return unavailable('语言模型尚未安装');
    try {
      final json = jsonDecode(await manifest.readAsString());
      if (json is! Map ||
          json['id'] != spec.id ||
          json['revision'] != spec.revision ||
          json['engine'] != 'mnn') {
        return unavailable('语言模型版本不匹配，请重新下载');
      }
    } on FormatException {
      return unavailable('语言模型清单损坏，请重新下载');
    } on FileSystemException {
      return unavailable('无法读取语言模型');
    }
    var size = await manifest.length();
    for (final definition in spec.files) {
      final file = File(p.join(active.path, definition.name));
      if (!await file.exists() || await file.length() != definition.sizeBytes) {
        return unavailable('${definition.name} 缺失或大小异常');
      }
      if (verifyIntegrity && !await _matchesDefinition(file, definition)) {
        return unavailable('${definition.name} 完整性校验失败');
      }
      size += definition.sizeBytes;
    }
    final license = File(p.join(active.path, 'LICENSE.txt'));
    if (await license.exists()) size += await license.length();
    return LanguageModelInfo(
      modelId: id,
      installed: true,
      configPath: p.join(active.path, 'config.json'),
      sizeBytes: size,
    );
  }

  Future<LocalLlmModelDescriptor> descriptor(String id) async {
    final spec = _spec(id);
    final info = await inspect(id);
    if (!info.installed) {
      throw StateError(info.problem ?? '${spec.displayName}尚未安装');
    }
    return LocalLlmModelDescriptor(
      id: spec.id,
      name: spec.displayName,
      configPath: info.configPath,
      nativeContextTokens: spec.nativeContextTokens,
      recommendedContextTokens: 4096,
      minimumMemoryBytes: spec.minimumMemoryBytes,
      capabilities: spec.capabilities,
    );
  }

  Future<int> partialDownloadBytes(String id) async {
    final spec = _spec(id);
    var total = 0;
    for (final definition in spec.files) {
      final partial = File(_partialPath(spec, definition));
      if (await partial.exists()) {
        total += (await partial.length()).clamp(0, definition.sizeBytes);
      }
    }
    return total;
  }

  Future<LanguageModelInfo> download(
    String id, {
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => _runExclusive(id, () async {
    final spec = _spec(id);
    await Directory(_downloadDir(spec)).create(recursive: true);
    final currentBytes = <String, int>{};
    for (final definition in spec.files) {
      final partial = File(_partialPath(spec, definition));
      final length = await partial.exists() ? await partial.length() : 0;
      currentBytes[definition.name] = length.clamp(0, definition.sizeBytes);
    }

    void report(String name, ModelDownloadEvent event) {
      currentBytes[name] = event.transferredBytes;
      onProgress?.call(
        SpeechModelImportProgress(
          currentBytes.values.fold(0, (sum, bytes) => sum + bytes),
          spec.downloadSizeBytes,
          connecting: event.connecting,
          sourceLabel: event.sourceLabel,
        ),
      );
    }

    for (final definition in spec.files) {
      final path = '${spec.revision}/${definition.name}?download=true';
      await ModelDownloadTransport.instance.download(
        sources: [
          ModelDownloadSource(
            uri: Uri.parse(
              'https://hf-mirror.com/${spec.repository}/resolve/$path',
            ),
            label: 'Hugging Face 国内镜像',
          ),
          ModelDownloadSource(
            uri: Uri.parse(
              'https://huggingface.co/${spec.repository}/resolve/$path',
            ),
            label: 'Hugging Face',
          ),
        ],
        partial: File(_partialPath(spec, definition)),
        expectedBytes: definition.sizeBytes,
        userAgent: 'fknotes/${spec.id}',
        onProgress: (event) => report(definition.name, event),
        shouldCancel: shouldCancel,
      );
    }
    if (shouldCancel?.call() == true) throw const ModelDownloadCanceled();
    return _install(
      spec,
      {
        for (final definition in spec.files)
          definition.name: File(_partialPath(spec, definition)),
      },
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
  });

  Future<LanguageModelInfo?> pickAndImport(
    String id, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    final spec = _spec(id);
    const group = XTypeGroup(
      label: 'MNN 语言模型文件',
      extensions: ['json', 'mnn', 'weight', 'bin', 'mtok', 'txt'],
    );
    final selected = await openFiles(acceptedTypeGroups: [group]);
    if (selected.isEmpty) return null;
    return _runExclusive(id, () async {
      final byName = {for (final file in selected) file.name: file};
      for (final definition in spec.files) {
        if (!byName.containsKey(definition.name)) {
          throw FormatException('缺少 ${definition.name}');
        }
      }
      final importing = Directory(p.join(_root(spec), '.importing'));
      if (await importing.exists()) await importing.delete(recursive: true);
      await importing.create(recursive: true);
      var copied = 0;
      try {
        final sources = <String, File>{};
        for (final definition in spec.files) {
          final source = byName[definition.name]!;
          if (await source.length() != definition.sizeBytes) {
            throw FormatException('${definition.name} 大小不匹配');
          }
          final destination = File(p.join(importing.path, definition.name));
          final output = await destination.open(mode: FileMode.write);
          try {
            await for (final chunk in source.openRead()) {
              await output.writeFrom(chunk);
              copied += chunk.length;
              onProgress?.call(
                SpeechModelImportProgress(copied, spec.downloadSizeBytes),
              );
            }
            await output.flush();
          } finally {
            await output.close();
          }
          sources[definition.name] = destination;
        }
        return await _install(spec, sources, onProgress: onProgress);
      } finally {
        if (await importing.exists()) await importing.delete(recursive: true);
      }
    });
  }

  Future<LanguageModelInfo> _install(
    _LanguageModelSpec spec,
    Map<String, File> sources, {
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => ModelInstallCoordinator.instance.run(
    () async {
      onProgress?.call(
        SpeechModelImportProgress(
          spec.downloadSizeBytes,
          spec.downloadSizeBytes,
          verifying: true,
        ),
      );
      for (final definition in spec.files) {
        final source = sources[definition.name];
        if (source == null || !await _matchesDefinition(source, definition)) {
          if (source != null && await source.exists()) await source.delete();
          throw FormatException('${definition.name} 文件不完整，请重新下载');
        }
      }
      final staging = Directory(p.join(_root(spec), '.installing'));
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      try {
        for (final definition in spec.files) {
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
          'Model license: Apache License 2.0\n'
          'Upstream: https://huggingface.co/${spec.repository}\n',
          flush: true,
        );
        await File(p.join(staging.path, _manifestFileName)).writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'id': spec.id,
            'name': spec.displayName,
            'engine': 'mnn',
            'repository': spec.repository,
            'revision': spec.revision,
            'license': 'Apache-2.0',
          }),
          flush: true,
        );
        await _activate(spec, staging);
        final download = Directory(_downloadDir(spec));
        if (await download.exists()) await download.delete(recursive: true);
        return inspect(spec.id);
      } finally {
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    },
    onWaiting: () => onProgress?.call(
      SpeechModelImportProgress(
        spec.downloadSizeBytes,
        spec.downloadSizeBytes,
        waitingForInstall: true,
      ),
    ),
    isCanceled: shouldCancel,
    cancellationError: () => const ModelDownloadCanceled(),
  );

  Future<void> _activate(_LanguageModelSpec spec, Directory staging) async {
    final active = Directory(_activeDir(spec));
    final previous = Directory('${active.path}.previous');
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

  Future<void> remove(String id) async {
    if (_busyModelIds.contains(id)) throw StateError('语言模型正在下载或导入');
    final root = Directory(_root(_spec(id)));
    if (await root.exists()) await root.delete(recursive: true);
    if (await selectedModelId() == id) {
      final selection = File(_selectionPath);
      if (await selection.exists()) await selection.delete();
    }
  }

  Future<bool> _matchesDefinition(
    File file,
    _LanguageModelFile definition,
  ) async {
    if (!await file.exists() || await file.length() != definition.sizeBytes) {
      return false;
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == definition.sha256;
  }

  Future<T> _runExclusive<T>(String id, Future<T> Function() operation) async {
    if (!_busyModelIds.add(id)) throw StateError('该语言模型已有任务正在进行');
    try {
      return await operation();
    } finally {
      _busyModelIds.remove(id);
    }
  }

  Future<void> _replaceFile(File source, File destination) async {
    try {
      await source.rename(destination.path);
    } on FileSystemException {
      if (await destination.exists()) await destination.delete();
      await source.rename(destination.path);
    }
  }
}
