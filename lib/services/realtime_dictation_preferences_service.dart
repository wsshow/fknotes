import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_storage_service.dart';

class RealtimeDictationPreferences {
  static const defaultHotwordsScore = 2.0;

  final List<String> hotwords;
  final double hotwordsScore;
  final bool twoPassEnabled;
  final bool noiseSuppressionEnabled;

  const RealtimeDictationPreferences({
    this.hotwords = const [],
    this.hotwordsScore = defaultHotwordsScore,
    this.twoPassEnabled = true,
    this.noiseSuppressionEnabled = false,
  });

  bool get hotwordsEnabled => hotwords.isNotEmpty;
}

/// Persists user-owned contextual vocabulary for live dictation.
///
/// The JSON file remains the source of truth. A plain-text companion file is
/// regenerated from it for sherpa-onnx, which expects one hotword per line.
class RealtimeDictationPreferencesService {
  RealtimeDictationPreferencesService._();
  static final RealtimeDictationPreferencesService instance =
      RealtimeDictationPreferencesService._();

  static const maxHotwords = 100;
  static const maxHotwordLength = 80;
  static const minHotwordsScore = 1.0;
  static const maxHotwordsScore = 5.0;

  final _storage = FileStorageService.instance;

  String get _settingsDir => p.join(_storage.baseDir, 'settings');
  String get _preferencesPath =>
      p.join(_settingsDir, 'realtime-dictation.json');
  String get hotwordsFilePath =>
      p.join(_settingsDir, 'realtime-dictation-hotwords.txt');

  Future<RealtimeDictationPreferences> load() async {
    final file = File(_preferencesPath);
    if (!await file.exists()) return const RealtimeDictationPreferences();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const RealtimeDictationPreferences();
      final rawHotwords = decoded['hotwords'];
      final hotwords = normalizeHotwords(
        rawHotwords is List ? rawHotwords.whereType<String>().join('\n') : '',
      );
      final rawScore = decoded['hotwordsScore'];
      final score = rawScore is num
          ? rawScore.toDouble().clamp(minHotwordsScore, maxHotwordsScore)
          : RealtimeDictationPreferences.defaultHotwordsScore;
      final preferences = RealtimeDictationPreferences(
        hotwords: hotwords,
        hotwordsScore: score,
        twoPassEnabled: decoded['twoPassEnabled'] as bool? ?? true,
        noiseSuppressionEnabled:
            decoded['noiseSuppressionEnabled'] as bool? ?? false,
      );
      await _writeRuntimeHotwords(preferences.hotwords);
      return preferences;
    } on FormatException {
      return const RealtimeDictationPreferences();
    } on FileSystemException {
      return const RealtimeDictationPreferences();
    }
  }

  Future<RealtimeDictationPreferences> save({
    required String hotwordsText,
    required double hotwordsScore,
    required bool twoPassEnabled,
    required bool noiseSuppressionEnabled,
  }) async {
    if (hotwordsScore < minHotwordsScore || hotwordsScore > maxHotwordsScore) {
      throw const FormatException('热词增强强度必须在 1.0 到 5.0 之间');
    }
    final hotwords = normalizeHotwords(hotwordsText);
    final preferences = RealtimeDictationPreferences(
      hotwords: hotwords,
      hotwordsScore: hotwordsScore,
      twoPassEnabled: twoPassEnabled,
      noiseSuppressionEnabled: noiseSuppressionEnabled,
    );
    await Directory(_settingsDir).create(recursive: true);
    await _writeRuntimeHotwords(hotwords);
    await _atomicWrite(
      File(_preferencesPath),
      const JsonEncoder.withIndent('  ').convert({
        'hotwords': hotwords,
        'hotwordsScore': hotwordsScore,
        'twoPassEnabled': twoPassEnabled,
        'noiseSuppressionEnabled': noiseSuppressionEnabled,
      }),
    );
    return preferences;
  }

  static List<String> normalizeHotwords(String value) {
    final result = <String>[];
    final seen = <String>{};
    for (final rawLine in value.split(RegExp(r'\r?\n'))) {
      final hotword = rawLine.trim();
      if (hotword.isEmpty) continue;
      if (hotword.length > maxHotwordLength) {
        throw FormatException('热词“${hotword.substring(0, 12)}…”超过 80 个字符');
      }
      if (hotword.contains(RegExp(r'[\u0000-\u001f]'))) {
        throw const FormatException('热词不能包含控制字符');
      }
      final identity = hotword.toLowerCase();
      if (seen.add(identity)) result.add(hotword);
      if (result.length > maxHotwords) {
        throw const FormatException('最多可设置 100 个热词');
      }
    }
    return result;
  }

  Future<void> _writeRuntimeHotwords(List<String> hotwords) async {
    final file = File(hotwordsFilePath);
    if (hotwords.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await Directory(_settingsDir).create(recursive: true);
    await _atomicWrite(file, '${hotwords.join('\n')}\n');
  }

  Future<void> _atomicWrite(File destination, String contents) async {
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    try {
      await temporary.rename(destination.path);
    } on FileSystemException {
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    }
  }
}
