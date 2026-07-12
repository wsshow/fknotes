import '../models/local_model.dart';
import '../services/local_model_manager.dart';
import 'generated/app_localizations.dart';

bool _usesChinese(AppLocalizations l10n) =>
    l10n.localeName.toLowerCase().startsWith('zh');

String localizedModelName(AppLocalizations l10n, LocalModelDefinition model) {
  if (_usesChinese(l10n)) return model.name;
  return switch (model.id) {
    LocalModelManager.streamingChineseId => 'Streaming Zipformer Chinese',
    LocalModelManager.streamingBilingualId =>
      'Streaming Zipformer Chinese–English',
    LocalModelManager.speechDenoiserId => 'DPDFNet Live Denoiser',
    LocalModelManager.kokoroTtsId => 'Kokoro Chinese–English INT8',
    LocalModelManager.mlKitChineseOcrId => 'ML Kit Chinese Text Recognition',
    _ => model.name,
  };
}

String localizedModelSummary(
  AppLocalizations l10n,
  LocalModelDefinition model,
) {
  if (_usesChinese(l10n)) return model.summary;
  return switch (model.id) {
    LocalModelManager.miniCpm5Id => 'Lightweight, fast local note assistant',
    LocalModelManager.qwen35Id =>
      'Lightweight text-and-image assistant (experimental vision)',
    LocalModelManager.qwen3Vl4BId =>
      'Balanced multilingual vision-language model',
    LocalModelManager.qwen3Vl8BId =>
      'More capable multilingual vision-language model',
    LocalModelManager.miniCpmV4Id =>
      'Mobile-optimized vision model for Chinese content',
    LocalModelManager.gemma4E2BId =>
      'On-device reasoning with image and audio support',
    LocalModelManager.gemma4E4BId =>
      'Stronger image, audio, and reasoning capabilities',
    LocalModelManager.senseVoiceId =>
      'Audio transcription and optional dictation refinement',
    LocalModelManager.streamingChineseId =>
      'Real-time speech input with live text',
    LocalModelManager.streamingBilingualId =>
      'Mixed Chinese–English real-time speech input',
    LocalModelManager.voiceActivityId =>
      'Detects speech and skips silence in long recordings',
    LocalModelManager.speechDenoiserId =>
      'Reduces background noise before live dictation',
    LocalModelManager.speakerDiarizationId =>
      'Separates speakers in recording transcripts',
    LocalModelManager.kokoroTtsId => 'Reads Chinese and English notes offline',
    LocalModelManager.mlKitChineseOcrId =>
      'OCR for Chinese and Latin text in images',
    _ => model.summary,
  };
}

String localizedModelDescription(
  AppLocalizations l10n,
  LocalModelDefinition model,
) {
  if (_usesChinese(l10n)) return model.description;
  return switch (model.id) {
    LocalModelManager.miniCpm5Id =>
      'Designed for summaries, titles, tags, rewriting, and task extraction. Supports Chinese and English, reasoning, and tool use.',
    LocalModelManager.qwen35Id =>
      'Good for writing, complex summaries, bilingual organization, and note Q&A. Image input is supported, but specialized vision models are better for detailed visual work.',
    LocalModelManager.qwen3Vl4BId =>
      'Suitable for image Q&A, Chinese OCR, documents, charts, higher-quality writing, and knowledge organization.',
    LocalModelManager.qwen3Vl8BId =>
      'Handles complex images, long documents, charts, OCR, and higher-quality generation. Intended for flagship devices with ample memory.',
    LocalModelManager.miniCpmV4Id =>
      'Optimized for Chinese OCR, screenshots, documents, and high-resolution images while balancing model size and visual quality.',
    LocalModelManager.gemma4E2BId =>
      'Supports reasoning, image understanding, and WAV audio understanding, plus multilingual writing and code on newer high-end devices.',
    LocalModelManager.gemma4E4BId =>
      'For more complex reasoning, code, multilingual image understanding, and audio tasks. Best on devices with at least 12 GB of memory.',
    LocalModelManager.senseVoiceId =>
      'Works with Mandarin, Cantonese, English, and mixed recordings. It can also run as an optional second pass after live dictation.',
    LocalModelManager.streamingChineseId =>
      'Provides on-device live dictation in the note editor without uploading microphone audio.',
    LocalModelManager.streamingBilingualId =>
      'Designed for natural Chinese–English code-switching within a sentence. Recognition stays entirely on device.',
    LocalModelManager.voiceActivityId =>
      'Locates speech segments on device before transcription, reducing work and errors caused by long silences.',
    LocalModelManager.speechDenoiserId =>
      'A low-resource causal streaming denoiser for 16 kHz mono speech, designed as mobile ASR preprocessing.',
    LocalModelManager.speakerDiarizationId =>
      'Uses Pyannote INT8 for speech segments and a Chinese 3D-Speaker embedding model for clustering. Speaker count can be automatic or set from 2 to 8.',
    LocalModelManager.kokoroTtsId =>
      'Supports mixed Chinese and English, 103 voices, and 24 kHz audio. The current default is a Chinese female voice.',
    LocalModelManager.mlKitChineseOcrId =>
      'Installed with FKNotes and runs entirely on device. This component cannot be removed separately.',
    _ => model.description,
  };
}

String localizedModelLanguages(
  AppLocalizations l10n,
  LocalModelDefinition model,
) {
  if (_usesChinese(l10n)) return model.languages.join('、');
  const translations = {
    '中文': 'Chinese',
    '英文': 'English',
    '英语': 'English',
    '多语言': 'Multilingual',
    '图片': 'Images',
    '音频': 'Audio',
    '普通话': 'Mandarin',
    '粤语': 'Cantonese',
    '日语': 'Japanese',
    '韩语': 'Korean',
    '与语言无关': 'Language independent',
    '中文优化': 'Optimized for Chinese',
  };
  return model.languages.map((item) => translations[item] ?? item).join(', ');
}

String localizedModelSource(AppLocalizations l10n, LocalModelDefinition model) {
  if (_usesChinese(l10n)) return model.source;
  return switch (model.id) {
    LocalModelManager.miniCpm5Id || LocalModelManager.miniCpmV4Id =>
      'OpenBMB / taobao-mnn · Hugging Face multi-source downloads',
    LocalModelManager.qwen35Id ||
    LocalModelManager.qwen3Vl4BId ||
    LocalModelManager.qwen3Vl8BId =>
      'Qwen / taobao-mnn · Hugging Face multi-source downloads',
    LocalModelManager.gemma4E2BId || LocalModelManager.gemma4E4BId =>
      'Google / taobao-mnn · Hugging Face multi-source downloads',
    LocalModelManager.streamingChineseId ||
    LocalModelManager.streamingBilingualId =>
      'Hugging Face repository · official and regional endpoints',
    LocalModelManager.voiceActivityId => 'Official k2-fsa model · GitHub',
    LocalModelManager.speechDenoiserId =>
      'Official k2-fsa model · regional mirror with GitHub fallback',
    LocalModelManager.speakerDiarizationId =>
      'Official k2-fsa models · regional mirror and GitHub',
    LocalModelManager.kokoroTtsId => 'Official k2-fsa model · GitHub',
    LocalModelManager.mlKitChineseOcrId => 'Bundled with FKNotes',
    _ => model.source,
  };
}

String localizedModelVersion(
  AppLocalizations l10n,
  LocalModelDefinition model,
) {
  if (_usesChinese(l10n)) return model.version;
  if (model.id == LocalModelManager.mlKitChineseOcrId) {
    return 'Built-in component';
  }
  return model.version;
}
