import 'dart:convert';
import 'dart:io';

import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/realtime_dictation_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory storageDirectory;
  final service = RealtimeDictationPreferencesService.instance;

  setUpAll(() async {
    storageDirectory = await Directory.systemTemp.createTemp(
      'fknotes_dictation_preferences_test_',
    );
    await FileStorageService.instance.init(baseDir: storageDirectory.path);
  });

  tearDownAll(() async {
    await storageDirectory.delete(recursive: true);
  });

  test('normalizes blank lines and case-insensitive duplicates', () {
    expect(
      RealtimeDictationPreferencesService.normalizeHotwords(
        '  FKNotes  \n\n非空笔记\nfknotes\nSherpa ONNX',
      ),
      ['FKNotes', '非空笔记', 'Sherpa ONNX'],
    );
  });

  test('rejects oversized hotword collections', () {
    final value = List.generate(101, (index) => '术语$index').join('\n');
    expect(
      () => RealtimeDictationPreferencesService.normalizeHotwords(value),
      throwsFormatException,
    );
  });

  test('keeps unstable second-pass recognition disabled by default', () async {
    final preferences = await service.load();

    expect(preferences.twoPassEnabled, isFalse);
  });

  test('persists JSON and sherpa runtime text consistently', () async {
    final saved = await service.save(
      hotwordsText: 'FKNotes\n非空笔记\nFKNotes',
      hotwordsScore: 2.5,
      twoPassEnabled: false,
      noiseSuppressionEnabled: true,
    );
    expect(saved.hotwords, ['FKNotes', '非空笔记']);
    expect(saved.hotwordsScore, 2.5);

    final loaded = await service.load();
    expect(loaded.hotwords, saved.hotwords);
    expect(loaded.hotwordsScore, 2.5);
    expect(loaded.twoPassEnabled, isFalse);
    expect(loaded.noiseSuppressionEnabled, isTrue);
    expect(
      await File(service.hotwordsFilePath).readAsString(),
      'FKNotes\n非空笔记\n',
    );

    final settings =
        jsonDecode(
              await File(
                p.join(
                  storageDirectory.path,
                  'settings',
                  'realtime-dictation.json',
                ),
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(settings['hotwords'], ['FKNotes', '非空笔记']);
    expect(settings['twoPassEnabled'], isFalse);
    expect(settings['noiseSuppressionEnabled'], isTrue);

    await service.save(
      hotwordsText: '',
      hotwordsScore: 2.0,
      twoPassEnabled: true,
      noiseSuppressionEnabled: false,
    );
    expect(await File(service.hotwordsFilePath).exists(), isFalse);
  });
}
