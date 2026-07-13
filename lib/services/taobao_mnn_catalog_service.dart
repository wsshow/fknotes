import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/local_llm.dart';
import '../models/taobao_mnn_model.dart';
import 'file_storage_service.dart';

typedef TaobaoMnnHttpGet = Future<Uint8List> Function(Uri uri);

class TaobaoMnnCatalogException implements Exception {
  final String message;
  const TaobaoMnnCatalogException(this.message);

  @override
  String toString() => message;
}

class TaobaoMnnCatalogService {
  TaobaoMnnCatalogService({String? cacheDirectory, TaobaoMnnHttpGet? httpGet})
    : _cacheDirectoryOverride = cacheDirectory,
      _httpGet = httpGet ?? _defaultHttpGet;

  static final instance = TaobaoMnnCatalogService();
  static const organization = 'taobao-mnn';
  static const _catalogVersion = 1;
  static const _allowedExtensions = {
    'json',
    'mnn',
    'weight',
    'bin',
    'mtok',
    'txt',
  };

  final String? _cacheDirectoryOverride;
  final TaobaoMnnHttpGet _httpGet;
  List<TaobaoMnnCatalogEntry> _entries = const [];
  final Map<String, TaobaoMnnModelSpec> _details = {};
  DateTime? _lastSyncedAt;
  bool _cacheLoaded = false;

  List<TaobaoMnnCatalogEntry> get entries => List.unmodifiable(_entries);
  List<TaobaoMnnModelSpec> get cachedDetails =>
      List.unmodifiable(_details.values);
  DateTime? get lastSyncedAt => _lastSyncedAt;

  String get _cacheDirectory =>
      _cacheDirectoryOverride ??
      p.join(FileStorageService.instance.baseDir, 'models', 'catalog');
  File get _catalogFile => File(p.join(_cacheDirectory, 'taobao-mnn.json'));
  File get _detailsFile =>
      File(p.join(_cacheDirectory, 'taobao-mnn-details.json'));

  Future<void> loadCache() async {
    if (_cacheLoaded) return;
    _entries = await _readCatalogCache();
    _details
      ..clear()
      ..addEntries(
        (await _readDetailsCache()).map(
          (detail) => MapEntry(detail.id, detail),
        ),
      );
    _cacheLoaded = true;
  }

  Future<List<TaobaoMnnCatalogEntry>> sync() async {
    final uri = Uri.https('huggingface.co', '/api/collections', {
      'owner': organization,
      'limit': '100',
    });
    final decoded = jsonDecode(utf8.decode(await _httpGet(uri)));
    if (decoded is! List) {
      throw const TaobaoMnnCatalogException('Invalid Collections response');
    }
    final byRepository = <String, TaobaoMnnCatalogEntry>{};
    for (final rawCollection in decoded.whereType<Map>()) {
      final collection = rawCollection['title'] as String? ?? '';
      final unsupportedCollection = _isUnsupportedCollection(collection);
      final items = rawCollection['items'];
      if (unsupportedCollection || items is! List) continue;
      for (final rawItem in items.whereType<Map>()) {
        final repository = rawItem['id'] as String? ?? '';
        final author = rawItem['author'] as String? ?? '';
        final pipelineTag = rawItem['pipeline_tag'] as String?;
        if (rawItem['type'] != 'model' ||
            author != organization ||
            rawItem['private'] == true ||
            rawItem['gated'] == true ||
            !repository.startsWith('$organization/') ||
            !repository.toLowerCase().endsWith('-mnn') ||
            _isUnsupportedRepository(repository) ||
            (pipelineTag != null && pipelineTag != 'text-generation')) {
          continue;
        }
        final candidate = TaobaoMnnCatalogEntry(
          repository: repository,
          collection: collection,
          lastModified: DateTime.tryParse(
            rawItem['lastModified'] as String? ?? '',
          ),
          downloads: (rawItem['downloads'] as num?)?.toInt() ?? 0,
          pipelineTag: pipelineTag,
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
      throw const TaobaoMnnCatalogException(
        'No compatible taobao-mnn models were returned',
      );
    }
    _entries = entries;
    _cacheLoaded = true;
    _lastSyncedAt = DateTime.now();
    await _writeJson(_catalogFile, {
      'version': _catalogVersion,
      'syncedAt': _lastSyncedAt!.toUtc().toIso8601String(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
    });
    return this.entries;
  }

  Future<TaobaoMnnModelSpec> inspect(
    TaobaoMnnCatalogEntry entry, {
    bool force = false,
  }) async {
    final cached = _details[entry.repository];
    if (!force && cached != null) return cached;
    final metadataUri = Uri.https(
      'huggingface.co',
      '/api/models/${entry.repository}',
      {'blobs': 'true'},
    );
    final decoded = jsonDecode(utf8.decode(await _httpGet(metadataUri)));
    if (decoded is! Map) {
      throw const TaobaoMnnCatalogException('Invalid model metadata');
    }
    final metadata = decoded.cast<String, Object?>();
    if (metadata['author'] != organization ||
        metadata['private'] == true ||
        metadata['gated'] == true ||
        metadata['disabled'] == true) {
      throw const TaobaoMnnCatalogException('Model is not publicly available');
    }
    final revision = metadata['sha'] as String? ?? '';
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(revision)) {
      throw const TaobaoMnnCatalogException('Model revision is invalid');
    }
    final siblings = metadata['siblings'];
    if (siblings is! List) {
      throw const TaobaoMnnCatalogException('Model file list is missing');
    }
    final files = <TaobaoMnnModelFile>[];
    for (final raw in siblings.whereType<Map>()) {
      final name = raw['rfilename'] as String? ?? '';
      final size = (raw['size'] as num?)?.toInt() ?? -1;
      final extension = name.split('.').last.toLowerCase();
      if (name.isEmpty ||
          name != p.basename(name) ||
          !_allowedExtensions.contains(extension)) {
        continue;
      }
      if (size < 0) {
        throw TaobaoMnnCatalogException('Missing file size: $name');
      }
      final lfs = raw['lfs'];
      final sha256 = lfs is Map ? lfs['sha256'] as String? : null;
      final gitBlobId = raw['blobId'] as String?;
      final validSha256 =
          sha256 != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256);
      final validGitBlob =
          gitBlobId != null && RegExp(r'^[a-f0-9]{40}$').hasMatch(gitBlobId);
      if (!validSha256 && !validGitBlob) {
        throw TaobaoMnnCatalogException('Missing verification metadata: $name');
      }
      files.add(
        TaobaoMnnModelFile(
          name: name,
          sizeBytes: size,
          sha256: validSha256 ? sha256 : null,
          gitBlobId: validGitBlob ? gitBlobId : null,
        ),
      );
    }
    _validateRequiredFiles(files);
    final config = await _readPinnedJson(
      entry.repository,
      revision,
      'config.json',
    );
    final runtimeConfig = await _readPinnedJson(
      entry.repository,
      revision,
      'llm_config.json',
    );
    _validateConfigReferences(config, runtimeConfig, files);
    final names = files.map((file) => file.name).toSet();
    final isVisual =
        runtimeConfig['is_visual'] == true ||
        names.contains('visual.mnn') ||
        names.contains('visual.mnn.weight');
    final isAudio =
        runtimeConfig['is_audio'] == true ||
        names.contains('audio.mnn') ||
        names.contains('audio.mnn.weight');
    final totalBytes = files.fold(0, (total, file) => total + file.sizeBytes);
    final card = metadata['cardData'];
    final cardData = card is Map ? card : const <Object?, Object?>{};
    final languages = (cardData['language'] as List? ?? const [])
        .whereType<String>()
        .toList();
    final lowerName = entry.name.toLowerCase();
    final spec = TaobaoMnnModelSpec(
      repository: entry.repository,
      revision: revision,
      name: entry.name,
      collection: entry.collection,
      license: cardData['license'] as String? ?? '',
      languages: languages,
      nativeContextTokens:
          (runtimeConfig['max_position_embeddings'] as num?)?.toInt() ?? 32768,
      recommendedMemoryBytes: _recommendedMemory(totalBytes),
      capabilities: LocalLlmCapabilities(
        thinking:
            lowerName.contains('thinking') ||
            lowerName.contains('reasoning') ||
            lowerName.startsWith('qwq'),
        toolCalling:
            runtimeConfig.toString().contains('tool_call') ||
            (cardData['tags'] as List? ?? const []).contains('chat'),
        imageInput: isVisual,
        audioInput: isAudio,
      ),
      generationOptions: LocalLlmGenerationOptions(
        temperature: _doubleValue(config, ['temperature'], .7),
        topP: _doubleValue(config, ['topP', 'top_p'], .95),
        topK: _intValue(config, ['topK', 'top_k'], 40),
      ),
      files: files,
      inspectedAt: DateTime.now(),
    );
    _details[spec.id] = spec;
    await _writeJson(_detailsFile, {
      'version': _catalogVersion,
      'details': _details.values.map((detail) => detail.toJson()).toList(),
    });
    return spec;
  }

  TaobaoMnnModelSpec? cachedSpec(String repository) => _details[repository];

  Future<Map<String, Object?>> _readPinnedJson(
    String repository,
    String revision,
    String fileName,
  ) async {
    final uri = Uri.https(
      'huggingface.co',
      '/$repository/resolve/$revision/$fileName',
    );
    final bytes = await _httpGet(uri);
    if (bytes.length > 2 * 1024 * 1024) {
      throw TaobaoMnnCatalogException('$fileName is unexpectedly large');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw TaobaoMnnCatalogException('$fileName is invalid');
    }
    return decoded.cast<String, Object?>();
  }

  static void _validateRequiredFiles(List<TaobaoMnnModelFile> files) {
    final names = files.map((file) => file.name).toSet();
    const required = {
      'config.json',
      'llm_config.json',
      'llm.mnn',
      'llm.mnn.weight',
    };
    final missing = required.difference(names);
    if (missing.isNotEmpty ||
        (!names.contains('tokenizer.txt') &&
            !names.contains('tokenizer.mtok'))) {
      throw TaobaoMnnCatalogException(
        'Incomplete MNN model files: ${missing.join(', ')}',
      );
    }
  }

  static void _validateConfigReferences(
    Map<String, Object?> config,
    Map<String, Object?> runtimeConfig,
    List<TaobaoMnnModelFile> files,
  ) {
    final names = files.map((file) => file.name).toSet();
    for (final key in ['llm_model', 'llm_weight', 'tokenizer_file']) {
      final value = config[key];
      if (value is String &&
          (value != p.basename(value) || !names.contains(value))) {
        throw TaobaoMnnCatalogException('Invalid model reference: $key');
      }
    }
    final embedding = config['embedding_file'];
    final pleEmbedding = runtimeConfig['ple_embed_file'];
    final hasEmbedding = embedding is String && names.contains(embedding);
    final hasPleEmbedding =
        pleEmbedding is String &&
        pleEmbedding == p.basename(pleEmbedding) &&
        names.contains(pleEmbedding);
    if (embedding is String && !hasEmbedding && !hasPleEmbedding) {
      throw const TaobaoMnnCatalogException(
        'Invalid model reference: embedding_file',
      );
    }
    if (config['llm_model'] != 'llm.mnn' ||
        config['llm_weight'] != 'llm.mnn.weight') {
      throw const TaobaoMnnCatalogException(
        'Unsupported MNN runtime configuration',
      );
    }
    for (final capability in const [
      ('is_visual', 'visual.mnn', 'visual.mnn.weight'),
      ('is_audio', 'audio.mnn', 'audio.mnn.weight'),
    ]) {
      if (runtimeConfig[capability.$1] == true &&
          (!names.contains(capability.$2) || !names.contains(capability.$3))) {
        throw TaobaoMnnCatalogException(
          'Incomplete ${capability.$1} model files',
        );
      }
    }
  }

  Future<List<TaobaoMnnCatalogEntry>> _readCatalogCache() async {
    try {
      if (!await _catalogFile.exists()) return const [];
      final decoded = jsonDecode(await _catalogFile.readAsString());
      if (decoded is! Map || decoded['version'] != _catalogVersion) {
        return const [];
      }
      _lastSyncedAt = DateTime.tryParse(decoded['syncedAt'] as String? ?? '');
      return (decoded['entries'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (entry) =>
                TaobaoMnnCatalogEntry.fromJson(entry.cast<String, Object?>()),
          )
          .toList();
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<List<TaobaoMnnModelSpec>> _readDetailsCache() async {
    try {
      if (!await _detailsFile.exists()) return const [];
      final decoded = jsonDecode(await _detailsFile.readAsString());
      if (decoded is! Map || decoded['version'] != _catalogVersion) {
        return const [];
      }
      return (decoded['details'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (detail) =>
                TaobaoMnnModelSpec.fromJson(detail.cast<String, Object?>()),
          )
          .toList();
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
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

  static bool _isUnsupportedCollection(String title) {
    final value = title.toLowerCase();
    return value == 'asr' ||
        value == 'eagle3' ||
        value.contains('diffusion') ||
        value.contains('embedding') ||
        value.contains('reranker');
  }

  static bool _isUnsupportedRepository(String repository) {
    final value = repository.toLowerCase();
    return value.contains('embedding') ||
        value.contains('reranker') ||
        value.contains('stable-diffusion');
  }

  static int _recommendedMemory(int downloadBytes) {
    const gib = 1024 * 1024 * 1024;
    if (downloadBytes <= 1 * gib) return 4 * gib;
    if (downloadBytes <= 3 * gib) return 6 * gib;
    if (downloadBytes <= 5 * gib) return 8 * gib;
    if (downloadBytes <= 8 * gib) return 12 * gib;
    return 16 * gib;
  }

  static double _doubleValue(
    Map<String, Object?> values,
    List<String> keys,
    double fallback,
  ) {
    for (final key in keys) {
      final value = values[key];
      if (value is num) return value.toDouble();
    }
    return fallback;
  }

  static int _intValue(
    Map<String, Object?> values,
    List<String> keys,
    int fallback,
  ) {
    for (final key in keys) {
      final value = values[key];
      if (value is num) return value.toInt();
    }
    return fallback;
  }

  static Future<Uint8List> _defaultHttpGet(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'fknotes/model-catalog');
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Hugging Face returned ${response.statusCode}',
          uri: uri,
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }
}
