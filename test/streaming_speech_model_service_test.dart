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
    'counts only resumable bytes from the transactional download area',
    () async {
      final root = p.join(
        storageDirectory.path,
        'models',
        'asr',
        'streaming-zipformer-bilingual-zh-en-2023-02-20',
      );
      final partial = File(p.join(root, '.download', 'encoder.int8.onnx.part'));
      await partial.parent.create(recursive: true);
      await partial.writeAsBytes(List.filled(137, 1));
      final incompleteActive = File(p.join(root, 'active', 'tokens.txt'));
      await incompleteActive.parent.create(recursive: true);
      await incompleteActive.writeAsBytes(List.filled(89, 1));

      final bytes = await StreamingSpeechModelService.instance
          .partialDownloadBytes(StreamingSpeechModelService.bilingualModelId);

      expect(bytes, 137);
      final info = await StreamingSpeechModelService.instance.inspect(
        modelId: StreamingSpeechModelService.bilingualModelId,
      );
      expect(info.installed, isFalse);
      expect(info.problem, '实时语音模型尚未安装');
    },
  );
}
