import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_storage_service.dart';

enum AppLockTimeout {
  immediately(0, '立即'),
  oneMinute(60, '1 分钟后'),
  fiveMinutes(5 * 60, '5 分钟后'),
  fifteenMinutes(15 * 60, '15 分钟后');

  final int seconds;
  final String label;

  const AppLockTimeout(this.seconds, this.label);

  static AppLockTimeout fromSeconds(Object? value) {
    if (value is int) {
      for (final timeout in values) {
        if (timeout.seconds == value) return timeout;
      }
    }
    return oneMinute;
  }
}

class AppLockPreferences {
  final bool enabled;
  final AppLockTimeout timeout;

  const AppLockPreferences({
    this.enabled = false,
    this.timeout = AppLockTimeout.oneMinute,
  });

  AppLockPreferences copyWith({bool? enabled, AppLockTimeout? timeout}) =>
      AppLockPreferences(
        enabled: enabled ?? this.enabled,
        timeout: timeout ?? this.timeout,
      );
}

abstract interface class AppLockPreferencesStore {
  Future<AppLockPreferences> load();

  Future<void> save(AppLockPreferences preferences);
}

class AppLockPreferencesService implements AppLockPreferencesStore {
  AppLockPreferencesService._();

  static final AppLockPreferencesService instance =
      AppLockPreferencesService._();

  String get _settingsDirectory =>
      p.join(FileStorageService.instance.baseDir, 'settings');
  String get _preferencesPath => p.join(_settingsDirectory, 'app-lock.json');

  @override
  Future<AppLockPreferences> load() async {
    final file = File(_preferencesPath);
    if (!await file.exists()) return const AppLockPreferences();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const AppLockPreferences();
      return AppLockPreferences(
        enabled: decoded['enabled'] == true,
        timeout: AppLockTimeout.fromSeconds(decoded['timeoutSeconds']),
      );
    } on FormatException {
      return const AppLockPreferences();
    } on FileSystemException {
      return const AppLockPreferences();
    }
  }

  @override
  Future<void> save(AppLockPreferences preferences) async {
    await Directory(_settingsDirectory).create(recursive: true);
    final destination = File(_preferencesPath);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'enabled': preferences.enabled,
        'timeoutSeconds': preferences.timeout.seconds,
      }),
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
