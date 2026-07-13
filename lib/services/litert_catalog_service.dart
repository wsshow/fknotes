import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/litert_model.dart';
import '../models/local_llm.dart';
import 'file_storage_service.dart';
import 'model_catalog_http_client.dart';

typedef LiteRtCatalogHttpGet = Future<Uint8List> Function(Uri uri);

class LiteRtCatalogException implements Exception {
  final String message;
  const LiteRtCatalogException(this.message);

  @override
  String toString() => message;
}

class LiteRtCatalogService {
  LiteRtCatalogService({String? cacheDirectory, LiteRtCatalogHttpGet? httpGet})
    : _cacheDirectoryOverride = cacheDirectory,
      _httpGet = httpGet ?? ModelCatalogHttpClient.instance.get;

  static final instance = LiteRtCatalogService();
  static const organization = 'litert-community';
  static const _cacheVersion = 1;
  static const _supportedCollections = {
    'android models',
    'gemma family',
    'qwen family',
    'multi-modality models',
  };
  static const _allowedOrganizations = {'litert-community', 'google'};

  final String? _cacheDirectoryOverride;
  final LiteRtCatalogHttpGet _httpGet;
  List<LiteRtCatalogEntry> _entries = const [];
  final Map<String, LiteRtModelSpec> _details = {};
  final Set<String> _addedRepositories = {};
  DateTime? _lastSyncedAt;
  bool _cacheLoaded = false;

  List<LiteRtCatalogEntry> get entries => List.unmodifiable(_entries);
  List<LiteRtModelSpec> get cachedDetails => List.unmodifiable(_details.values);
  List<LiteRtModelSpec> get managedDetails => List.unmodifiable(
    _details.values.where(
      (detail) => _addedRepositories.contains(detail.repository),
    ),
  );
  DateTime? get lastSyncedAt => _lastSyncedAt;

  String get _cacheDirectory =>
      _cacheDirectoryOverride ??
      p.join(FileStorageService.instance.baseDir, 'models', 'catalog');
  File get _catalogFile =>
      File(p.join(_cacheDirectory, 'litert-community.json'));
  File get _detailsFile =>
      File(p.join(_cacheDirectory, 'litert-community-details.json'));
  File get _addedFile =>
      File(p.join(_cacheDirectory, 'litert-community-added.json'));

  Future<void> loadCache() async {
    if (_cacheLoaded) return;
    final cachedEntries = await _readCatalogCache();
    final cachedDetails = await _readDetailsCache();
    final addedRepositories = await _readAddedRepositories();
    _entries = cachedEntries.isEmpty ? _bundledEntries : cachedEntries;
    _details
      ..clear()
      ..addEntries(
        (cachedDetails.isEmpty ? _bundledDetails : cachedDetails).map(
          (detail) => MapEntry(detail.repository, detail),
        ),
      );
    _addedRepositories
      ..clear()
      ..addAll(addedRepositories);
    _cacheLoaded = true;
  }

  Future<List<LiteRtCatalogEntry>> sync() async {
    final uri = Uri.https('huggingface.co', '/api/collections', {
      'owner': organization,
      'limit': '100',
    });
    final decoded = jsonDecode(utf8.decode(await _httpGet(uri)));
    if (decoded is! List) {
      throw const LiteRtCatalogException('Invalid Collections response');
    }
    final byRepository = <String, LiteRtCatalogEntry>{};
    for (final rawCollection in decoded.whereType<Map>()) {
      final collection = rawCollection['title'] as String? ?? '';
      if (!_supportedCollections.contains(collection.toLowerCase())) continue;
      final items = rawCollection['items'];
      if (items is! List) continue;
      for (final rawItem in items.whereType<Map>()) {
        final repository = rawItem['id'] as String? ?? '';
        final parts = repository.split('/');
        final owner = parts.length == 2 ? parts.first : '';
        final pipeline = rawItem['pipeline_tag'] as String?;
        if (rawItem['type'] != 'model' ||
            !_allowedOrganizations.contains(owner) ||
            rawItem['private'] == true ||
            (rawItem['gated'] != null && rawItem['gated'] != false) ||
            (pipeline != null && pipeline != 'text-generation') ||
            !_supportsRepositoryName(repository)) {
          continue;
        }
        final candidate = LiteRtCatalogEntry(
          repository: repository,
          collection: collection,
          lastModified: DateTime.tryParse(
            rawItem['lastModified'] as String? ?? '',
          ),
          downloads: (rawItem['downloads'] as num?)?.toInt() ?? 0,
        );
        final previous = byRepository[repository];
        if (previous == null || candidate.downloads > previous.downloads) {
          byRepository[repository] = candidate;
        }
      }
    }
    final entries = byRepository.values.toList()
      ..sort((left, right) {
        final collection = left.collection.compareTo(right.collection);
        return collection != 0
            ? collection
            : right.downloads.compareTo(left.downloads);
      });
    if (entries.isEmpty) {
      throw const LiteRtCatalogException(
        'No compatible LiteRT-LM models were returned',
      );
    }
    _entries = entries;
    _lastSyncedAt = DateTime.now();
    _cacheLoaded = true;
    await _writeJson(_catalogFile, {
      'version': _cacheVersion,
      'syncedAt': _lastSyncedAt!.toUtc().toIso8601String(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
    });
    return this.entries;
  }

  Future<LiteRtModelSpec> inspect(
    LiteRtCatalogEntry entry, {
    bool force = false,
  }) async {
    final cached = _details[entry.repository];
    if (!force && cached != null) return cached;
    final uri = Uri.https('huggingface.co', '/api/models/${entry.repository}', {
      'blobs': 'true',
    });
    final decoded = jsonDecode(utf8.decode(await _httpGet(uri)));
    if (decoded is! Map) {
      throw const LiteRtCatalogException('Invalid model metadata');
    }
    final metadata = decoded.cast<String, Object?>();
    final author = metadata['author'] as String? ?? '';
    final gated = metadata['gated'];
    final tags = (metadata['tags'] as List? ?? const [])
        .whereType<String>()
        .map((tag) => tag.toLowerCase())
        .toSet();
    if (!_allowedOrganizations.contains(author) ||
        metadata['private'] == true ||
        metadata['disabled'] == true ||
        (gated != null && gated != false) ||
        (metadata['library_name'] != 'litert-lm' &&
            !tags.contains('litert-lm'))) {
      throw const LiteRtCatalogException(
        'Model is not a public LiteRT-LM model',
      );
    }
    final revision = metadata['sha'] as String? ?? '';
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(revision)) {
      throw const LiteRtCatalogException('Model revision is invalid');
    }
    final siblings = metadata['siblings'];
    if (siblings is! List) {
      throw const LiteRtCatalogException('Model file list is missing');
    }
    final candidates = <LiteRtModelFile>[];
    for (final raw in siblings.whereType<Map>()) {
      final name = raw['rfilename'] as String? ?? '';
      final lower = name.toLowerCase();
      final size = (raw['size'] as num?)?.toInt() ?? -1;
      final lfs = raw['lfs'];
      final checksum = lfs is Map ? lfs['sha256'] as String? ?? '' : '';
      if (name != p.basename(name) ||
          !lower.endsWith('.litertlm') ||
          _isWebOrDeviceSpecific(lower) ||
          size <= 0 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
        continue;
      }
      candidates.add(
        LiteRtModelFile(name: name, sizeBytes: size, sha256: checksum),
      );
    }
    if (candidates.isEmpty) {
      throw const LiteRtCatalogException(
        'No generic Android LiteRT-LM file was found',
      );
    }
    candidates.sort((left, right) {
      final rank = _filePreference(
        left.name,
      ).compareTo(_filePreference(right.name));
      return rank != 0 ? rank : left.sizeBytes.compareTo(right.sizeBytes);
    });
    final file = candidates.first;
    final card = metadata['cardData'];
    final cardData = card is Map ? card : const <Object?, Object?>{};
    final lowerName = entry.name.toLowerCase();
    final isGemma4 = lowerName.contains('gemma-4');
    final isGemma3n = lowerName.contains('gemma-3n');
    final spec = LiteRtModelSpec(
      repository: entry.repository,
      revision: revision,
      name: entry.name,
      collection: entry.collection,
      license: cardData['license'] as String? ?? '',
      languages: (cardData['language'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      nativeContextTokens: 32768,
      recommendedMemoryBytes: _recommendedMemory(file.sizeBytes),
      capabilities: LocalLlmCapabilities(
        imageInput: isGemma4 || isGemma3n,
        audioInput: isGemma4 || isGemma3n,
        backends: const {LocalLlmBackend.cpu, LocalLlmBackend.openCl},
      ),
      generationOptions: _generationOptions(lowerName),
      file: file,
      inspectedAt: DateTime.now(),
    );
    _details[entry.repository] = spec;
    await _writeJson(_detailsFile, {
      'version': _cacheVersion,
      'details': _details.values.map((detail) => detail.toJson()).toList(),
    });
    return spec;
  }

  LiteRtModelSpec? cachedSpec(String repository) => _details[repository];

  Future<void> markAdded(String repository) async {
    await loadCache();
    if (!_details.containsKey(repository)) {
      throw const LiteRtCatalogException(
        'Model details must be inspected before adding the model',
      );
    }
    if (!_addedRepositories.add(repository)) return;
    await _writeJson(_addedFile, {
      'version': _cacheVersion,
      'repositories': _addedRepositories.toList()..sort(),
    });
  }

  Future<List<LiteRtCatalogEntry>> _readCatalogCache() async {
    try {
      if (!await _catalogFile.exists()) return const [];
      final decoded = jsonDecode(await _catalogFile.readAsString());
      if (decoded is! Map || decoded['version'] != _cacheVersion) {
        return const [];
      }
      _lastSyncedAt = DateTime.tryParse(decoded['syncedAt'] as String? ?? '');
      return (decoded['entries'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (entry) =>
                LiteRtCatalogEntry.fromJson(entry.cast<String, Object?>()),
          )
          .where((entry) => _supportsRepositoryName(entry.repository))
          .toList();
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<List<LiteRtModelSpec>> _readDetailsCache() async {
    try {
      if (!await _detailsFile.exists()) return const [];
      final decoded = jsonDecode(await _detailsFile.readAsString());
      if (decoded is! Map || decoded['version'] != _cacheVersion) {
        return const [];
      }
      return (decoded['details'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (detail) =>
                LiteRtModelSpec.fromJson(detail.cast<String, Object?>()),
          )
          .where((detail) => _supportsRepositoryName(detail.repository))
          .toList();
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<Set<String>> _readAddedRepositories() async {
    try {
      if (!await _addedFile.exists()) return const {};
      final decoded = jsonDecode(await _addedFile.readAsString());
      if (decoded is! Map || decoded['version'] != _cacheVersion) {
        return const {};
      }
      return (decoded['repositories'] as List? ?? const [])
          .whereType<String>()
          .where(_supportsRepositoryName)
          .toSet();
    } on FormatException {
      return const {};
    } on FileSystemException {
      return const {};
    }
  }

  Future<void> _writeJson(File destination, Object value) async {
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    try {
      await temporary.rename(destination.path);
    } on FileSystemException {
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    }
  }

  static bool _supportsRepositoryName(String repository) {
    final lower = repository.toLowerCase();
    return !lower.contains('embedding') &&
        !lower.contains('asr') &&
        !lower.contains('whisper') &&
        !lower.contains('parakeet') &&
        !lower.contains('moonshine');
  }

  static bool _isWebOrDeviceSpecific(String name) =>
      name.contains('-web.') ||
      name.contains('_web.') ||
      name.contains('.mediatek.') ||
      name.contains('.qualcomm.') ||
      name.contains('_qualcomm_') ||
      name.contains('_intel_') ||
      name.contains('_google_tensor_');

  static int _filePreference(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('mixed_int4') || lower.contains('-int4.')) return 0;
    if (lower.contains('_q8_') || lower.contains('-q8.')) return 1;
    if (lower.contains('f32') || lower.contains('float32')) return 3;
    return 2;
  }

  static int _recommendedMemory(int bytes) {
    const gib = 1024 * 1024 * 1024;
    if (bytes <= 1 * gib) return 4 * gib;
    if (bytes <= 2 * gib) return 6 * gib;
    if (bytes <= 3 * gib) return 8 * gib;
    if (bytes <= 5 * gib) return 12 * gib;
    return 16 * gib;
  }

  static LocalLlmGenerationOptions _generationOptions(String name) {
    if (name.contains('qwen3')) {
      return const LocalLlmGenerationOptions(
        temperature: .6,
        topP: .95,
        topK: 20,
      );
    }
    if (name.contains('qwen2.5')) {
      return const LocalLlmGenerationOptions(
        temperature: .7,
        topP: .8,
        topK: 20,
      );
    }
    return const LocalLlmGenerationOptions();
  }

  static const _bundledEntries = <LiteRtCatalogEntry>[
    LiteRtCatalogEntry(
      repository: 'litert-community/Qwen2.5-1.5B-Instruct',
      collection: 'Qwen Family',
    ),
    LiteRtCatalogEntry(
      repository: 'litert-community/Qwen3-0.6B',
      collection: 'Qwen Family',
    ),
    LiteRtCatalogEntry(
      repository: 'litert-community/Qwen3-4B',
      collection: 'Qwen Family',
    ),
    LiteRtCatalogEntry(
      repository: 'litert-community/gemma-4-12B-it-litert-lm',
      collection: 'Gemma Family',
    ),
  ];

  static final _bundledDetails = <LiteRtModelSpec>[
    _bundled(
      repository: 'litert-community/Qwen2.5-1.5B-Instruct',
      revision: '19edb84c69a0212f29a6ef17ba0d6f278b6a1614',
      name: 'Qwen2.5-1.5B-Instruct',
      fileName: 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      bytes: 1597931520,
      checksum:
          'faa60663b333290c1496c499828b21d3e3254a788cacd8cce917ce0f761a2dc9',
      memory: 6 * 1024 * 1024 * 1024,
    ),
    _bundled(
      repository: 'litert-community/Qwen3-0.6B',
      revision: '3adacb36657dbe0119addf143782ed973c680716',
      name: 'Qwen3-0.6B',
      fileName: 'qwen3_0_6b_mixed_int4.litertlm',
      bytes: 497664000,
      checksum:
          'b1baab462f6be49d70eada79d715c2c52cd9ece0cad00bddf6a2c097d23498e9',
      memory: 4 * 1024 * 1024 * 1024,
    ),
    _bundled(
      repository: 'litert-community/Qwen3-4B',
      revision: '84cc5a35c9c65cd18fcd65bb1f3a7d77a4acfe6e',
      name: 'Qwen3-4B',
      fileName: 'qwen3_4b_mixed_int4.litertlm',
      bytes: 2659057664,
      checksum:
          'f0794bc77efeaaf4f7af815f04c483b19b8f2ae4a102cef1b7b760a25848a18e',
      memory: 8 * 1024 * 1024 * 1024,
    ),
    _bundled(
      repository: 'litert-community/gemma-4-12B-it-litert-lm',
      revision: '44cf85a326f79b814fa86a60af414c042755b43a',
      name: 'gemma-4-12B-it',
      fileName: 'gemma-4-12B-it.litertlm',
      bytes: 6547589312,
      checksum:
          '74fc29a10c20eb5b3ced6c389471a7994a0ffd657255b2a1c764262fb9054aef',
      memory: 16 * 1024 * 1024 * 1024,
      imageInput: true,
      audioInput: true,
    ),
  ];

  static LiteRtModelSpec _bundled({
    required String repository,
    required String revision,
    required String name,
    required String fileName,
    required int bytes,
    required String checksum,
    required int memory,
    bool imageInput = false,
    bool audioInput = false,
  }) => LiteRtModelSpec(
    repository: repository,
    revision: revision,
    name: name,
    collection: name.toLowerCase().contains('qwen')
        ? 'Qwen Family'
        : 'Gemma Family',
    license: 'apache-2.0',
    languages: const ['多语言'],
    nativeContextTokens: 32768,
    recommendedMemoryBytes: memory,
    capabilities: LocalLlmCapabilities(
      imageInput: imageInput,
      audioInput: audioInput,
      backends: const {LocalLlmBackend.cpu, LocalLlmBackend.openCl},
    ),
    generationOptions: _generationOptions(name.toLowerCase()),
    file: LiteRtModelFile(name: fileName, sizeBytes: bytes, sha256: checksum),
    inspectedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}
