import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../services/file_storage_service.dart';

enum AppLanguage { system, simplifiedChinese, english }

typedef PlatformLocaleReader = Future<String?> Function();
typedef PlatformLocaleWriter = Future<void> Function(String languageTag);

class AppLocaleController extends ChangeNotifier with WidgetsBindingObserver {
  AppLocaleController({
    String? settingsPath,
    PlatformLocaleReader? platformLocaleReader,
    PlatformLocaleWriter? platformLocaleWriter,
    bool observePlatform = true,
  }) : _settingsPathOverride = settingsPath,
       _platformLocaleReader =
           platformLocaleReader ?? AppLocalePlatform.readLanguageTag,
       _platformLocaleWriter =
           platformLocaleWriter ?? AppLocalePlatform.writeLanguageTag,
       _observing = observePlatform {
    if (_observing) WidgetsBinding.instance.addObserver(this);
  }

  static final instance = AppLocaleController();

  final String? _settingsPathOverride;
  final PlatformLocaleReader _platformLocaleReader;
  final PlatformLocaleWriter _platformLocaleWriter;
  final bool _observing;
  AppLanguage _language = AppLanguage.system;
  Future<void> _writeQueue = Future.value();

  AppLanguage get language => _language;
  Locale? get locale => switch (_language) {
    AppLanguage.system => null,
    AppLanguage.simplifiedChinese => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
    ),
    AppLanguage.english => const Locale('en'),
  };

  String get _settingsPath =>
      _settingsPathOverride ??
      p.join(
        FileStorageService.instance.baseDir,
        'settings',
        'app-locale.json',
      );

  Future<void> initialize() async {
    final stored = await _readStoredLanguage();
    final platformTag = await _platformLocaleReader();
    final resolved = platformTag == null
        ? stored
        : _languageFromTag(platformTag);
    if (_language != resolved) {
      _language = resolved;
      notifyListeners();
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    final previous = _language;
    _language = language;
    notifyListeners();
    try {
      await _platformLocaleWriter(_tagForLanguage(language));
      final operation = _writeQueue.then((_) => _write(language));
      _writeQueue = operation.catchError((_) {});
      await operation;
    } catch (_) {
      _language = previous;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    _synchronizePlatformSelection();
  }

  Future<void> _synchronizePlatformSelection() async {
    final tag = await _platformLocaleReader();
    if (tag == null) return;
    final resolved = _languageFromTag(tag);
    if (resolved == _language) return;
    _language = resolved;
    notifyListeners();
    final operation = _writeQueue.then((_) => _write(resolved));
    _writeQueue = operation.catchError((_) {});
    await operation;
  }

  Future<AppLanguage> _readStoredLanguage() async {
    final file = File(_settingsPath);
    if (!await file.exists()) return AppLanguage.system;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return AppLanguage.system;
      return AppLanguage.values.firstWhere(
        (language) => language.name == decoded['language'],
        orElse: () => AppLanguage.system,
      );
    } on FormatException {
      return AppLanguage.system;
    } on FileSystemException {
      return AppLanguage.system;
    }
  }

  Future<void> _write(AppLanguage language) async {
    final destination = File(_settingsPath);
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'language': language.name}),
      flush: true,
    );
    try {
      await temporary.rename(destination.path);
    } on FileSystemException {
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    }
  }

  static AppLanguage _languageFromTag(String tag) {
    final normalized = tag.toLowerCase();
    if (normalized.startsWith('zh')) return AppLanguage.simplifiedChinese;
    if (normalized.startsWith('en')) return AppLanguage.english;
    return AppLanguage.system;
  }

  static String _tagForLanguage(AppLanguage language) => switch (language) {
    AppLanguage.system => '',
    AppLanguage.simplifiedChinese => 'zh-Hans',
    AppLanguage.english => 'en',
  };

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class AppLocalePlatform {
  AppLocalePlatform._();

  static const _channel = MethodChannel('fknotes/app_locale');

  static Future<String?> readLanguageTag() async {
    try {
      return await _channel.invokeMethod<String>('getApplicationLocale');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<void> writeLanguageTag(String languageTag) async {
    try {
      await _channel.invokeMethod<void>('setApplicationLocale', languageTag);
    } on MissingPluginException {
      // Flutter-only platforms persist and apply the locale in Dart.
    } on PlatformException {
      // Android versions before per-app locales still use the Dart preference.
    }
  }
}
