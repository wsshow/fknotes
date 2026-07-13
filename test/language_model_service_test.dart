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
    const expected = {
      LanguageModelService.miniCpm5Id:
          LanguageModelService.miniCpm5DownloadSizeBytes,
      LanguageModelService.qwen35Id:
          LanguageModelService.qwen35DownloadSizeBytes,
      LanguageModelService.qwen3Vl4BId:
          LanguageModelService.qwen3Vl4BDownloadSizeBytes,
      LanguageModelService.qwen3Vl8BId:
          LanguageModelService.qwen3Vl8BDownloadSizeBytes,
      LanguageModelService.miniCpmV4Id:
          LanguageModelService.miniCpmV4DownloadSizeBytes,
    };

    expect(LanguageModelService.supportedModelIds, expected.keys);
    for (final entry in expected.entries) {
      expect(service.downloadSizeBytes(entry.key), entry.value);
    }
  });

  test('declares each pinned model multimodal capability', () {
    expect(
      service.capabilities(LanguageModelService.qwen35Id).imageInput,
      isTrue,
    );
    expect(
      service.capabilities(LanguageModelService.miniCpm5Id).imageInput,
      isFalse,
    );
    for (final id in const [
      LanguageModelService.qwen3Vl4BId,
      LanguageModelService.qwen3Vl8BId,
      LanguageModelService.miniCpmV4Id,
    ]) {
      expect(service.capabilities(id).imageInput, isTrue, reason: id);
    }
  });

  test('retires legacy MNN Gemma 4 assets and selection', () async {
    final modelRoot = Directory(
      p.join(storage.path, 'models', 'llm', 'gemma-4-e2b-it-mnn-int4'),
    );
    await modelRoot.create(recursive: true);
    await File(p.join(modelRoot.path, 'legacy.bin')).writeAsString('legacy');
    final selection = File(
      p.join(storage.path, 'models', 'llm', 'selection.json'),
    );
    await selection.parent.create(recursive: true);
    await selection.writeAsString('{"modelId":"gemma-4-e2b-it-mnn-int4"}');

    await service.retireMnnGemmaModels();

    expect(await modelRoot.exists(), isFalse);
    expect(await selection.exists(), isFalse);
    expect(await service.selectedModelId(), LanguageModelService.qwen35Id);
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
