import 'dart:convert';
import 'dart:io';

import 'package:fknotes/services/app_lock_preferences_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory storageDirectory;
  final service = AppLockPreferencesService.instance;

  setUpAll(() async {
    storageDirectory = await Directory.systemTemp.createTemp(
      'fknotes_app_lock_preferences_test_',
    );
    await FileStorageService.instance.init(baseDir: storageDirectory.path);
  });

  tearDownAll(() async {
    await storageDirectory.delete(recursive: true);
  });

  test('defaults to a disabled one-minute application lock', () async {
    final preferences = await service.load();

    expect(preferences.enabled, isFalse);
    expect(preferences.timeout, AppLockTimeout.oneMinute);
  });

  test('persists the enabled state and timeout atomically', () async {
    const preferences = AppLockPreferences(
      enabled: true,
      timeout: AppLockTimeout.fiveMinutes,
    );

    await service.save(preferences);
    final loaded = await service.load();

    expect(loaded.enabled, isTrue);
    expect(loaded.timeout, AppLockTimeout.fiveMinutes);
    final decoded =
        jsonDecode(
              await File(
                p.join(storageDirectory.path, 'settings', 'app-lock.json'),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(decoded['enabled'], isTrue);
    expect(decoded['timeoutSeconds'], 300);
  });
}
