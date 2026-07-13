import 'local_llm.dart';

class LiteRtCatalogEntry {
  final String repository;
  final String collection;
  final DateTime? lastModified;
  final int downloads;

  const LiteRtCatalogEntry({
    required this.repository,
    required this.collection,
    this.lastModified,
    this.downloads = 0,
  });

  String get name => repository
      .split('/')
      .last
      .replaceFirst(RegExp(r'-litert-lm$', caseSensitive: false), '');

  Map<String, Object?> toJson() => {
    'repository': repository,
    'collection': collection,
    'lastModified': lastModified?.toUtc().toIso8601String(),
    'downloads': downloads,
  };

  factory LiteRtCatalogEntry.fromJson(Map<String, Object?> json) =>
      LiteRtCatalogEntry(
        repository: json['repository']! as String,
        collection: json['collection']! as String,
        lastModified: DateTime.tryParse(json['lastModified'] as String? ?? ''),
        downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      );
}

class LiteRtModelFile {
  final String name;
  final int sizeBytes;
  final String sha256;

  const LiteRtModelFile({
    required this.name,
    required this.sizeBytes,
    required this.sha256,
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
  };

  factory LiteRtModelFile.fromJson(Map<String, Object?> json) =>
      LiteRtModelFile(
        name: json['name']! as String,
        sizeBytes: (json['sizeBytes']! as num).toInt(),
        sha256: json['sha256']! as String,
      );
}

class LiteRtModelSpec {
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
  final LiteRtModelFile file;
  final DateTime inspectedAt;

  const LiteRtModelSpec({
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
    required this.file,
    required this.inspectedAt,
  });

  String get id => repository;
  int get downloadSizeBytes => file.sizeBytes;

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
      'imageInput': capabilities.imageInput,
      'audioInput': capabilities.audioInput,
    },
    'generationOptions': {
      'temperature': generationOptions.temperature,
      'topP': generationOptions.topP,
      'topK': generationOptions.topK,
    },
    'file': file.toJson(),
    'inspectedAt': inspectedAt.toUtc().toIso8601String(),
  };

  factory LiteRtModelSpec.fromJson(Map<String, Object?> json) {
    final capabilities = json['capabilities'] as Map? ?? const {};
    final generation = json['generationOptions'] as Map? ?? const {};
    return LiteRtModelSpec(
      repository: json['repository']! as String,
      revision: json['revision']! as String,
      name: json['name']! as String,
      collection: json['collection']! as String,
      license: json['license'] as String? ?? '',
      languages: (json['languages'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      nativeContextTokens:
          (json['nativeContextTokens'] as num?)?.toInt() ?? 32768,
      recommendedMemoryBytes:
          (json['recommendedMemoryBytes'] as num?)?.toInt() ?? 0,
      capabilities: LocalLlmCapabilities(
        imageInput: capabilities['imageInput'] == true,
        audioInput: capabilities['audioInput'] == true,
        backends: const {LocalLlmBackend.cpu, LocalLlmBackend.openCl},
      ),
      generationOptions: LocalLlmGenerationOptions(
        temperature: (generation['temperature'] as num?)?.toDouble() ?? .7,
        topP: (generation['topP'] as num?)?.toDouble() ?? .95,
        topK: (generation['topK'] as num?)?.toInt() ?? 40,
      ),
      file: LiteRtModelFile.fromJson(
        (json['file']! as Map).cast<String, Object?>(),
      ),
      inspectedAt:
          DateTime.tryParse(json['inspectedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
