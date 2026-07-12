import 'dart:io';

import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/language_model_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory storage;
  final service = LanguageModelService.instance;

  setUpAll(() async {
    storage = await Directory.systemTemp.createTemp('fknotes-language-model');
    await FileStorageService.instance.init(baseDir: storage.path);
  });

  tearDownAll(() async {
    if (await storage.exists()) await storage.delete(recursive: true);
  });

  test('pinned download sizes match the model catalog', () {
    expect(
      service.downloadSizeBytes(LanguageModelService.miniCpm5Id),
      LanguageModelService.miniCpm5DownloadSizeBytes,
    );
    expect(
      service.downloadSizeBytes(LanguageModelService.qwen35Id),
      LanguageModelService.qwen35DownloadSizeBytes,
    );
  });

  test('declares multimodal capability only for the visual model', () {
    expect(
      service.capabilities(LanguageModelService.qwen35Id).imageInput,
      isTrue,
    );
    expect(
      service.capabilities(LanguageModelService.miniCpm5Id).imageInput,
      isFalse,
    );
  });

  test('partial bytes include independently resumable files', () async {
    final download = Directory(
      p.join(
        storage.path,
        'models',
        'llm',
        'minicpm5-1b-mnn-int4',
        '.download',
      ),
    );
    await download.create(recursive: true);
    await File(
      p.join(download.path, 'config.json.part'),
    ).writeAsBytes(List<int>.filled(100, 1));
    await File(
      p.join(download.path, 'llm.mnn.weight.part'),
    ).writeAsBytes(List<int>.filled(2048, 2));

    expect(
      await service.partialDownloadBytes(LanguageModelService.miniCpm5Id),
      2148,
    );
  });

  test('missing installation does not produce a runtime descriptor', () async {
    final info = await service.inspect(LanguageModelService.qwen35Id);
    expect(info.installed, isFalse);

    await expectLater(
      service.descriptor(LanguageModelService.qwen35Id),
      throwsStateError,
    );
  });
}
