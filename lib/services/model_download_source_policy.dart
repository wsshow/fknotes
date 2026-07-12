import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'file_storage_service.dart';
import 'model_download_transport.dart';

enum ModelDownloadSourcePreference { automatic, officialFirst, mainlandFirst }

/// Owns the user's download-source preference and the session's adaptive
/// source ordering. Locale region is only a weak initial hint; actual transfer
/// success wins for the rest of the session and every list keeps a fallback.
class ModelDownloadSourcePolicy extends ChangeNotifier {
  ModelDownloadSourcePolicy({
    String? settingsPath,
    String? Function()? countryCodeProvider,
  }) : _settingsPathOverride = settingsPath,
       _countryCodeProvider =
           countryCodeProvider ??
           (() => PlatformDispatcher.instance.locale.countryCode);

  static final instance = ModelDownloadSourcePolicy();

  final String? _settingsPathOverride;
  final String? Function() _countryCodeProvider;
  ModelDownloadSourcePreference _preference =
      ModelDownloadSourcePreference.automatic;
  ModelDownloadSourceKind? _sessionHealthyKind;
  String? _lastUsedSourceLabel;
  Future<void> _writeQueue = Future.value();

  ModelDownloadSourcePreference get preference => _preference;
  String? get lastUsedSourceLabel => _lastUsedSourceLabel;

  String get _settingsPath =>
      _settingsPathOverride ??
      p.join(
        FileStorageService.instance.baseDir,
        'settings',
        'model-download.json',
      );

  bool get regionPrefersMainland =>
      _countryCodeProvider()?.toUpperCase() == 'CN';

  ModelDownloadSourceKind get effectivePreferredKind => switch (_preference) {
    ModelDownloadSourcePreference.officialFirst =>
      ModelDownloadSourceKind.official,
    ModelDownloadSourcePreference.mainlandFirst =>
      ModelDownloadSourceKind.mainlandMirror,
    ModelDownloadSourcePreference.automatic =>
      _sessionHealthyKind ??
          (regionPrefersMainland
              ? ModelDownloadSourceKind.mainlandMirror
              : ModelDownloadSourceKind.official),
  };

  Future<void> load() async {
    final file = File(_settingsPath);
    if (!await file.exists()) return;
    final previous = _preference;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final name = decoded['preference'];
      _preference = ModelDownloadSourcePreference.values.firstWhere(
        (value) => value.name == name,
        orElse: () => ModelDownloadSourcePreference.automatic,
      );
    } on FormatException {
      _preference = ModelDownloadSourcePreference.automatic;
    } on FileSystemException {
      _preference = ModelDownloadSourcePreference.automatic;
    }
    if (_preference != previous) notifyListeners();
  }

  Future<void> setPreference(ModelDownloadSourcePreference preference) async {
    if (_preference == preference) return;
    _preference = preference;
    _sessionHealthyKind = null;
    notifyListeners();
    final operation = _writeQueue.then((_) => _write());
    _writeQueue = operation.catchError((_) {});
    await operation;
  }

  List<ModelDownloadSource> order(List<ModelDownloadSource> sources) {
    if (sources.length < 2) return List.unmodifiable(sources);
    final preferred = effectivePreferredKind;
    final indexed = sources.indexed.toList();
    indexed.sort((left, right) {
      final rank = _rank(
        left.$2.kind,
        preferred,
      ).compareTo(_rank(right.$2.kind, preferred));
      return rank != 0 ? rank : left.$1.compareTo(right.$1);
    });
    return List.unmodifiable(indexed.map((item) => item.$2));
  }

  void reportSuccessfulSource(ModelDownloadSource source) {
    final adaptive =
        source.kind == ModelDownloadSourceKind.official ||
        source.kind == ModelDownloadSourceKind.mainlandMirror;
    final sessionWillChange =
        adaptive &&
        _preference == ModelDownloadSourcePreference.automatic &&
        _sessionHealthyKind != source.kind;
    final changed = _lastUsedSourceLabel != source.label || sessionWillChange;
    _lastUsedSourceLabel = source.label;
    if (adaptive && _preference == ModelDownloadSourcePreference.automatic) {
      _sessionHealthyKind = source.kind;
    }
    if (changed) notifyListeners();
  }

  static int _rank(
    ModelDownloadSourceKind kind,
    ModelDownloadSourceKind preferred,
  ) {
    if (kind == preferred) return 0;
    if (kind == ModelDownloadSourceKind.official ||
        kind == ModelDownloadSourceKind.mainlandMirror) {
      return 1;
    }
    return 2;
  }

  Future<void> _write() async {
    final destination = File(_settingsPath);
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'preference': _preference.name}),
      flush: true,
    );
    try {
      await temporary.rename(destination.path);
    } on FileSystemException {
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    }
  }
}
