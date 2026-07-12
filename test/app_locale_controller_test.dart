import 'dart:io';

import 'package:fknotes/providers/app_locale_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late String settingsPath;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'fknotes_app_locale_',
    );
    settingsPath = p.join(temporaryDirectory.path, 'locale.json');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('persists an explicit language and synchronizes the platform', () async {
    var platformTag = '';
    final controller = AppLocaleController(
      settingsPath: settingsPath,
      platformLocaleReader: () async => null,
      platformLocaleWriter: (tag) async => platformTag = tag,
      observePlatform: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.setLanguage(AppLanguage.english);

    expect(controller.locale, const Locale('en'));
    expect(platformTag, 'en');

    final restored = AppLocaleController(
      settingsPath: settingsPath,
      platformLocaleReader: () async => null,
      platformLocaleWriter: (_) async {},
      observePlatform: false,
    );
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.language, AppLanguage.english);
  });

  test('Android per-app language selection takes precedence', () async {
    final controller = AppLocaleController(
      settingsPath: settingsPath,
      platformLocaleReader: () async => 'zh-Hans',
      platformLocaleWriter: (_) async {},
      observePlatform: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.language, AppLanguage.simplifiedChinese);
    expect(controller.locale?.scriptCode, 'Hans');
  });
}
