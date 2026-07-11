import 'dart:io';

import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/streaming_speech_model_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory storageDirectory;

  setUpAll(() async {
    storageDirectory = await Directory.systemTemp.createTemp(
      'fknotes_streaming_model_test_',
    );
    await FileStorageService.instance.init(baseDir: storageDirectory.path);
  });

  tearDownAll(() async {
    await storageDirectory.delete(recursive: true);
  });

  test(
    'reuses a legacy bilingual installation for the bpe vocab upgrade',
    () async {
      final active = Directory(
        p.join(
          storageDirectory.path,
          'models',
          'asr',
          'streaming-zipformer-bilingual-zh-en-2023-02-20',
          'active',
        ),
      );
      await active.create(recursive: true);
      const legacyFiles = {
        'encoder.int8.onnx': 181895032,
        'decoder.onnx': 13091040,
        'joiner.int8.onnx': 3228404,
        'tokens.txt': 56317,
      };
      for (final entry in legacyFiles.entries) {
        final output = await File(
          p.join(active.path, entry.key),
        ).open(mode: FileMode.write);
        await output.truncate(entry.value);
        await output.close();
      }

      final reusable = await StreamingSpeechModelService.instance
          .partialDownloadBytes(StreamingSpeechModelService.bilingualModelId);
      expect(reusable, 198270793);
      expect(
        StreamingSpeechModelService.bilingualDownloadSizeBytes - reusable,
        12564,
      );
    },
  );
}
