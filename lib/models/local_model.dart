enum LocalModelCategory { language, speech, vision }

enum LocalModelAvailability { downloadable, builtIn, planned }

enum LocalModelTask {
  audioTranscription,
  liveDictation,
  voiceActivityDetection,
  speechEnhancement,
  speakerDiarization,
  textToSpeech,
  textGeneration,
  textRecognition,
  imageUnderstanding,
}

/// A stable product-facing slot that explains why a model is active.
///
/// Installation and usage are deliberately separate: downloaded models can
/// remain available without appearing in the "in use" dashboard.
enum LocalModelUsage {
  assistant,
  liveDictation,
  audioTranscription,
  voiceActivityDetection,
  speechEnhancement,
  textRecognition,
}

class LocalModelDefinition {
  final String id;
  final String name;
  final String summary;
  final String description;
  final LocalModelCategory category;
  final LocalModelAvailability availability;
  final LocalModelTask task;
  final int downloadSizeBytes;
  final List<String> languages;
  final String engine;
  final String version;
  final String source;
  final String license;
  final bool recommended;
  final int recommendedMemoryBytes;
  final bool remote;
  final String repository;
  final String revision;

  const LocalModelDefinition({
    required this.id,
    required this.name,
    required this.summary,
    required this.description,
    required this.category,
    required this.availability,
    required this.task,
    this.downloadSizeBytes = 0,
    this.languages = const [],
    required this.engine,
    this.version = '',
    this.source = '',
    this.license = '',
    this.recommended = false,
    this.recommendedMemoryBytes = 0,
    this.remote = false,
    this.repository = '',
    this.revision = '',
  });
}

class LocalModelInstallation {
  final bool installed;
  final int installedSizeBytes;
  final int partialSizeBytes;

  const LocalModelInstallation({
    this.installed = false,
    this.installedSizeBytes = 0,
    this.partialSizeBytes = 0,
  });
}

class ActiveLocalModel {
  final LocalModelDefinition definition;
  final LocalModelInstallation installation;
  final Set<LocalModelUsage> usages;

  const ActiveLocalModel({
    required this.definition,
    required this.installation,
    required this.usages,
  });
}
