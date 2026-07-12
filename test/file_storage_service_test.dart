import 'dart:io';

import 'package:fknotes/services/file_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fknotes_storage_test_');
    await FileStorageService.instance.init(baseDir: root.path);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('user data size excludes models, caches and temporary files', () async {
    Future<void> write(String relativePath, int bytes) async {
      final file = File(p.join(root.path, relativePath));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List.filled(bytes, 1));
    }

    await write('audio/recording.m4a', 11);
    await write('assistant/conversations.json', 13);
    await write('fknotes.db', 17);
    await write('models/llm/model/weights.bin', 101);
    await write('models/asr/model.onnx', 103);
    await write('mnn-cache/cache.bin', 107);
    await write('transcription_temp/audio.wav', 109);
    await write('settings/app-lock.json', 113);

    expect(await FileStorageService.instance.userDataSize(), 41);
    expect(await FileStorageService.instance.storageSize(), greaterThan(41));
  });
}
