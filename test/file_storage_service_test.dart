import 'dart:io';

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
      FileStorageService.instance.absolutePath('images/safe.jpg'),
      p.join(root.path, 'images', 'safe.jpg'),
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

  test('generates a full-image thumbnail on a fixed portrait canvas', () async {
    final source = File(p.join(root.path, 'images', 'wide.png'));
    final image = img.Image(width: 800, height: 100);
    img.fill(image, color: img.ColorRgb8(210, 70, 45));
    await source.writeAsBytes(img.encodePng(image));

    final relativePath = await FileStorageService.instance
        .generateThumbnailInBackground('images/wide.png');
    final output = File(FileStorageService.instance.absolutePath(relativePath));
    final decoded = img.decodeJpg(await output.readAsBytes());

    expect(relativePath, endsWith('_thumb_v2.jpg'));
    expect(decoded, isNotNull);
    expect(decoded!.width, 300);
    expect(decoded.height, 360);
    final corner = decoded.getPixel(0, 0);
    final center = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(corner.r, greaterThan(240));
    expect(corner.g, greaterThan(235));
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
    'orphan cleanup preserves referenced, protected and recent files',
    () async {
      Future<File> write(String relativePath, {bool old = true}) async {
        final file = File(p.join(root.path, relativePath));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(List.filled(7, 1));
        if (old) {
          await file.setLastModified(
            DateTime.now().subtract(const Duration(days: 2)),
          );
        }
        return file;
      }

      final referenced = await write('images/referenced.jpg');
      final protected = await write('audio/importing.m4a');
      final recent = await write('documents/recent.pdf', old: false);
      final orphan = await write('video/orphan.mp4');
      final orphanThumbnail = await write('thumbnails/orphan_thumb.jpg');
      final partial = await write('video/active.mp4.part');

      final result = await FileStorageService.instance
          .cleanupOrphanedAttachments(
            referencedPaths: {'images/referenced.jpg'},
            protectedPaths: {'audio/importing.m4a'},
            minimumAge: const Duration(hours: 24),
          );

      expect(await referenced.exists(), isTrue);
      expect(await protected.exists(), isTrue);
      expect(await recent.exists(), isTrue);
      expect(await partial.exists(), isTrue);
      expect(await orphan.exists(), isFalse);
      expect(await orphanThumbnail.exists(), isFalse);
      expect(result.deletedFiles, 2);
      expect(result.reclaimedBytes, 14);
    },
  );
}
