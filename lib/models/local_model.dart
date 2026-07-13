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
