import 'local_llm.dart';

class TaobaoMnnCatalogEntry {
  final String repository;
  final String collection;
  final DateTime? lastModified;
  final int downloads;
  final String? pipelineTag;

  const TaobaoMnnCatalogEntry({
    required this.repository,
    required this.collection,
    this.lastModified,
    this.downloads = 0,
    this.pipelineTag,
  });

  String get name => repository
      .split('/')
      .last
      .replaceFirst(RegExp(r'-MNN$', caseSensitive: false), '');

  Map<String, Object?> toJson() => {
    'repository': repository,
    'collection': collection,
    'lastModified': lastModified?.toUtc().toIso8601String(),
    'downloads': downloads,
    'pipelineTag': pipelineTag,
  };

  factory TaobaoMnnCatalogEntry.fromJson(Map<String, Object?> json) =>
      TaobaoMnnCatalogEntry(
        repository: json['repository']! as String,
        collection: json['collection']! as String,
        lastModified: DateTime.tryParse(json['lastModified'] as String? ?? ''),
        downloads: (json['downloads'] as num?)?.toInt() ?? 0,
        pipelineTag: json['pipelineTag'] as String?,
      );
}

class TaobaoMnnModelFile {
  final String name;
  final int sizeBytes;
  final String? sha256;
  final String? gitBlobId;

  const TaobaoMnnModelFile({
    required this.name,
    required this.sizeBytes,
    this.sha256,
    this.gitBlobId,
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'gitBlobId': gitBlobId,
  };

  factory TaobaoMnnModelFile.fromJson(Map<String, Object?> json) =>
      TaobaoMnnModelFile(
        name: json['name']! as String,
        sizeBytes: (json['sizeBytes']! as num).toInt(),
        sha256: json['sha256'] as String?,
        gitBlobId: json['gitBlobId'] as String?,
      );
}

class TaobaoMnnModelSpec {
  final String repository;
  final String revision;
  final String name;
  final String collection;
  final String license;
  final List<String> languages;
  final int nativeContextTokens;
  final int recommendedMemoryBytes;
  final LocalLlmCapabilities capabilities;
  final LocalLlmGenerationOptions generationOptions;
  final List<TaobaoMnnModelFile> files;
  final DateTime inspectedAt;

  const TaobaoMnnModelSpec({
    required this.repository,
    required this.revision,
    required this.name,
    required this.collection,
    required this.license,
    required this.languages,
    required this.nativeContextTokens,
    required this.recommendedMemoryBytes,
    required this.capabilities,
    required this.generationOptions,
    required this.files,
    required this.inspectedAt,
  });

  String get id => repository;
  int get downloadSizeBytes =>
      files.fold(0, (total, file) => total + file.sizeBytes);

  Map<String, Object?> toJson() => {
    'repository': repository,
    'revision': revision,
    'name': name,
    'collection': collection,
    'license': license,
    'languages': languages,
    'nativeContextTokens': nativeContextTokens,
    'recommendedMemoryBytes': recommendedMemoryBytes,
    'capabilities': {
      'thinking': capabilities.thinking,
      'toolCalling': capabilities.toolCalling,
      'imageInput': capabilities.imageInput,
      'audioInput': capabilities.audioInput,
    },
    'generationOptions': {
      'temperature': generationOptions.temperature,
      'topP': generationOptions.topP,
      'topK': generationOptions.topK,
    },
    'files': files.map((file) => file.toJson()).toList(),
    'inspectedAt': inspectedAt.toUtc().toIso8601String(),
  };

  factory TaobaoMnnModelSpec.fromJson(Map<String, Object?> json) {
    final capabilities = json['capabilities']! as Map;
    final generation = json['generationOptions']! as Map;
    return TaobaoMnnModelSpec(
      repository: json['repository']! as String,
      revision: json['revision']! as String,
      name: json['name']! as String,
      collection: json['collection']! as String,
      license: json['license'] as String? ?? '',
      languages: (json['languages'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      nativeContextTokens: (json['nativeContextTokens'] as num).toInt(),
      recommendedMemoryBytes: (json['recommendedMemoryBytes'] as num).toInt(),
      capabilities: LocalLlmCapabilities(
        thinking: capabilities['thinking'] == true,
        toolCalling: capabilities['toolCalling'] == true,
        imageInput: capabilities['imageInput'] == true,
        audioInput: capabilities['audioInput'] == true,
      ),
      generationOptions: LocalLlmGenerationOptions(
        temperature: (generation['temperature'] as num?)?.toDouble() ?? .7,
        topP: (generation['topP'] as num?)?.toDouble() ?? .95,
        topK: (generation['topK'] as num?)?.toInt() ?? 40,
      ),
      files: (json['files']! as List)
          .whereType<Map>()
          .map(
            (file) => TaobaoMnnModelFile.fromJson(file.cast<String, Object?>()),
          )
          .toList(),
      inspectedAt:
          DateTime.tryParse(json['inspectedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
