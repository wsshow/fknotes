import 'dart:collection';

enum LocalLlmRole { system, user, assistant, tool }

enum LocalLlmBackend { cpu, openCl, vulkan, metal }

enum LocalLlmEngineState {
  unavailable,
  idle,
  loading,
  ready,
  generating,
  canceling,
  unloading,
  failed,
}

enum LocalLlmFinishReason { completed, maxTokens, canceled, timeout }

class LocalLlmMessage {
  final LocalLlmRole role;
  final String content;
  final List<LocalLlmAttachment> attachments;

  const LocalLlmMessage({
    required this.role,
    required this.content,
    this.attachments = const [],
  });
}

class LocalLlmAttachment {
  final String path;
  final String mimeType;

  const LocalLlmAttachment({required this.path, required this.mimeType});
}

class LocalLlmCapabilities {
  final bool textGeneration;
  final bool thinking;
  final bool toolCalling;
  final bool imageInput;
  final bool audioInput;
  final Set<LocalLlmBackend> backends;

  const LocalLlmCapabilities({
    this.textGeneration = true,
    this.thinking = false,
    this.toolCalling = false,
    this.imageInput = false,
    this.audioInput = false,
    this.backends = const {LocalLlmBackend.cpu},
  });
}

class LocalLlmEngineAvailability {
  final bool supported;
  final String engine;
  final String version;
  final String? unavailableReason;
  final LocalLlmCapabilities capabilities;

  const LocalLlmEngineAvailability({
    required this.supported,
    required this.engine,
    this.version = '',
    this.unavailableReason,
    this.capabilities = const LocalLlmCapabilities(),
  });
}

class LocalLlmModelDescriptor {
  final String id;
  final String name;
  final String configPath;
  final int nativeContextTokens;
  final int recommendedContextTokens;
  final int minimumMemoryBytes;
  final LocalLlmCapabilities capabilities;

  const LocalLlmModelDescriptor({
    required this.id,
    required this.name,
    required this.configPath,
    required this.nativeContextTokens,
    this.recommendedContextTokens = 4096,
    this.minimumMemoryBytes = 0,
    this.capabilities = const LocalLlmCapabilities(),
  }) : assert(nativeContextTokens > 0),
       assert(recommendedContextTokens > 0),
       assert(recommendedContextTokens <= nativeContextTokens);
}

class LocalLlmLoadOptions {
  final LocalLlmBackend backend;
  final int threads;
  final int contextTokens;
  final bool enableThinking;
  final bool enablePromptCache;

  const LocalLlmLoadOptions({
    this.backend = LocalLlmBackend.cpu,
    this.threads = 4,
    this.contextTokens = 4096,
    this.enableThinking = false,
    this.enablePromptCache = true,
  }) : assert(threads > 0),
       assert(contextTokens > 0);
}

class LocalLlmGenerationOptions {
  final int maxNewTokens;
  final double temperature;
  final double topP;
  final int topK;
  final Duration timeout;

  const LocalLlmGenerationOptions({
    this.maxNewTokens = 512,
    this.temperature = 0.7,
    this.topP = 0.95,
    this.topK = 40,
    this.timeout = const Duration(minutes: 2),
  }) : assert(maxNewTokens > 0),
       assert(temperature >= 0),
       assert(topP > 0 && topP <= 1),
       assert(topK > 0);
}

class LocalLlmGenerationRequest {
  final List<LocalLlmMessage> messages;
  final LocalLlmGenerationOptions options;

  LocalLlmGenerationRequest({
    required List<LocalLlmMessage> messages,
    this.options = const LocalLlmGenerationOptions(),
  }) : messages = UnmodifiableListView(messages) {
    if (messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', '消息不能为空');
    }
    if (!messages.any((message) => message.role == LocalLlmRole.user)) {
      throw ArgumentError.value(messages, 'messages', '至少需要一条用户消息');
    }
  }
}

sealed class LocalLlmGenerationEvent {
  const LocalLlmGenerationEvent();
}

class LocalLlmTextDelta extends LocalLlmGenerationEvent {
  final String text;
  final bool reasoning;

  const LocalLlmTextDelta(this.text, {this.reasoning = false});
}

class LocalLlmGenerationMetrics {
  final int promptTokens;
  final int generatedTokens;
  final Duration loadTime;
  final Duration prefillTime;
  final Duration decodeTime;

  const LocalLlmGenerationMetrics({
    this.promptTokens = 0,
    this.generatedTokens = 0,
    this.loadTime = Duration.zero,
    this.prefillTime = Duration.zero,
    this.decodeTime = Duration.zero,
  });

  double get prefillTokensPerSecond => _rate(promptTokens, prefillTime);
  double get decodeTokensPerSecond => _rate(generatedTokens, decodeTime);

  static double _rate(int tokens, Duration duration) {
    if (tokens <= 0 || duration.inMicroseconds <= 0) return 0;
    return tokens * Duration.microsecondsPerSecond / duration.inMicroseconds;
  }
}

class LocalLlmGenerationCompleted extends LocalLlmGenerationEvent {
  final LocalLlmFinishReason reason;
  final LocalLlmGenerationMetrics metrics;

  const LocalLlmGenerationCompleted({
    required this.reason,
    this.metrics = const LocalLlmGenerationMetrics(),
  });
}

class LocalLlmRuntimeSnapshot {
  final LocalLlmEngineState state;
  final LocalLlmModelDescriptor? model;
  final Object? error;

  const LocalLlmRuntimeSnapshot({required this.state, this.model, this.error});
}

class LocalLlmException implements Exception {
  final String message;
  final Object? cause;

  const LocalLlmException(this.message, {this.cause});

  @override
  String toString() => message;
}
