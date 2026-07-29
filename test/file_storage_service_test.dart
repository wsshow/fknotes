import 'dart:io';
import 'dart:typed_data';

import 'package:fknotes/services/file_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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

    await write('notes/audio/recording.m4a', 11);
    await write('assistant/conversation.jpg', 13);
    await write('backups/manual.fknotes.zip', 19);
    await write('fknotes.db', 17);
    await write('fknotes-chat.db', 23);
    await write('models/llm/model/weights.bin', 101);
    await write('models/asr/model.onnx', 103);
    await write('mnn-cache/cache.bin', 107);
    await write('transcription_temp/audio.wav', 109);
    await write('settings/app-lock.json', 113);

    expect(await FileStorageService.instance.userDataSize(), 83);
    expect(await FileStorageService.instance.storageSize(), greaterThan(83));
  });

  test('managed paths cannot escape application storage', () {
    expect(
      () => FileStorageService.instance.absolutePath('../outside.txt'),
      throwsFormatException,
    );
    expect(
      () => FileStorageService.instance.absolutePath('/tmp/outside.txt'),
      throwsFormatException,
    );
    expect(
      FileStorageService.instance.absolutePath('notes/images/safe.jpg'),
      p.join(root.path, 'notes', 'images', 'safe.jpg'),
    );
  });

  test('normalizes assistant images to bounded JPEG files', () async {
    final source = File(p.join(root.path, 'source.png'));
    final image = img.Image(width: 2200, height: 100, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(220, 80, 40, 128));
    await source.writeAsBytes(img.encodePng(image));

    final relativePath = await FileStorageService.instance.importAssistantImage(
      source,
    );
    final output = File(FileStorageService.instance.absolutePath(relativePath));
    final decoded = img.decodeJpg(await output.readAsBytes());

    expect(relativePath, startsWith('assistant/'));
    expect(relativePath, endsWith('.jpg'));
    expect(decoded, isNotNull);
    expect(decoded!.width, 2048);
    expect(decoded.height, lessThanOrEqualTo(100));
  });

  test('generates a full-image thumbnail in the note asset tree', () async {
    final source = File(p.join(root.path, 'notes', 'images', 'wide.png'));
    final image = img.Image(width: 800, height: 100);
    img.fill(image, color: img.ColorRgb8(210, 70, 45));
    await source.writeAsBytes(img.encodePng(image));

    final relativePath = await FileStorageService.instance
        .generateNoteThumbnailInBackground('notes/images/wide.png');
    final output = File(FileStorageService.instance.absolutePath(relativePath));
    final decoded = img.decodeJpg(await output.readAsBytes());

    expect(relativePath, startsWith('notes/thumbnails/'));
    expect(relativePath, endsWith('_thumb_v3.jpg'));
    expect(decoded, isNotNull);
    expect(decoded!.width, 640);
    expect(decoded.height, 80);
    final corner = decoded.getPixel(0, 0);
    final center = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(corner.r, greaterThan(corner.g * 2));
    expect(center.r, greaterThan(center.g * 2));
  });

  test('rejects oversized assistant image files before decoding', () async {
    final source = File(p.join(root.path, 'too-large.jpg'));
    final handle = source.openSync(mode: FileMode.write);
    handle.truncateSync(20 * 1024 * 1024 + 1);
    handle.closeSync();

    await expectLater(
      FileStorageService.instance.importAssistantImage(source),
      throwsFormatException,
    );
  });

  test(
    'normalizes note image and thumbnail together from one import',
    () async {
      final source = img.Image(width: 120, height: 80, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(230, 80, 40, 180));

      final stored = await FileStorageService.instance.importNoteImageBytes(
        Uint8List.fromList(img.encodePng(source)),
      );
      final thumbnail = File(
        FileStorageService.instance.absolutePath(stored.previewStorageKey),
      );
      final decodedThumbnail = img.decodeJpg(await thumbnail.readAsBytes());

      expect(stored.storageKey, startsWith('notes/images/'));
      expect(stored.mimeType, 'image/png');
      expect(stored.byteLength, greaterThan(0));
      expect(stored.previewStorageKey, startsWith('notes/thumbnails/'));
      expect(stored.previewStorageKey, endsWith('_thumb_v3.jpg'));
      expect(
        await FileStorageService.instance.fileExists(stored.storageKey),
        isTrue,
      );
      expect(await thumbnail.exists(), isTrue);
      expect(decodedThumbnail, isNotNull);
      expect(decodedThumbnail!.width, 120);
      expect(decodedThumbnail.height, 80);
    },
  );

  test('rejects undecodable note clipboard image bytes', () async {
    await expectLater(
      FileStorageService.instance.importNoteImageBytes(
        Uint8List.fromList([1, 2, 3, 4]),
      ),
      throwsFormatException,
    );
  });

  test('atomically imports a completed recording into note storage', () async {
    final source = File(p.join(root.path, 'temporary-recording.m4a'));
    await source.writeAsBytes(List<int>.generate(4096, (index) => index % 251));

    final stored = await FileStorageService.instance.importNoteAudioFile(
      source,
    );
    final managed = File(
      FileStorageService.instance.absolutePath(stored.storageKey),
    );

    expect(stored.storageKey, startsWith('notes/audio/'));
    expect(stored.storageKey, endsWith('.m4a'));
    expect(stored.mimeType, 'audio/mp4');
    expect(stored.byteLength, 4096);
    expect(await managed.readAsBytes(), await source.readAsBytes());
    expect(
      await managed.parent
          .list()
          .where((entity) => entity.path.endsWith('.part'))
          .isEmpty,
      isTrue,
    );
  });

  test(
    'initialization creates only canonical note folders and clears parts',
    () async {
      final partial = File(
        p.join(root.path, 'notes', 'video', 'active.mp4.part'),
      );
      await partial.writeAsBytes([1, 2, 3]);

      await FileStorageService.instance.init(baseDir: root.path);

      expect(await partial.exists(), isFalse);
      for (final folder in [
        'images',
        'audio',
        'video',
        'documents',
        'thumbnails',
      ]) {
        expect(await Directory(p.join(root.path, folder)).exists(), isFalse);
      }
      for (final folder in [
        'notes/images',
        'notes/audio',
        'notes/video',
        'notes/files',
        'notes/thumbnails',
      ]) {
        expect(await Directory(p.join(root.path, folder)).exists(), isTrue);
      }
    },
  );
}
