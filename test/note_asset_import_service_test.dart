import 'dart:io';
import 'dart:typed_data';

import 'package:fknotes/models/note.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/note_asset_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory directory;
  late NoteAssetImportService importer;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fknotes_asset_import_');
    await FileStorageService.instance.init(baseDir: directory.path);
    importer = NoteAssetImportService(now: () => DateTime.utc(2026, 7, 23, 14));
  });

  tearDown(() => directory.delete(recursive: true));

  test('creates a stable image asset from clipboard bytes', () async {
    final image = img.Image(width: 64, height: 48);
    img.fill(image, color: img.ColorRgb8(245, 240, 230));

    final asset = await importer.importImageBytes(
      Uint8List.fromList(img.encodeJpg(image)),
      originalName: '../截屏.jpg',
    );

    expect(asset.displayTitle, '截屏.jpg');
    expect(asset.storageKey, startsWith('notes/images/'));
    expect(asset.previewStorageKey, startsWith('notes/thumbnails/'));
    expect(asset.mimeType, 'image/jpeg');
    expect(asset.createdAt, DateTime.utc(2026, 7, 23, 14));
    expect(
      await FileStorageService.instance.fileExists(asset.storageKey),
      isTrue,
    );
    expect(
      await FileStorageService.instance.fileExists(asset.previewStorageKey),
      isTrue,
    );
  });

  test(
    'creates a managed audio asset with duration and display name',
    () async {
      final source = File('${directory.path}/capture.m4a');
      await source.writeAsBytes(List<int>.filled(2048, 7));

      final asset = await importer.importAudioFile(
        source,
        originalName: '../recording-1.m4a',
        displayName: '产品讨论',
        durationMs: 92340,
      );

      expect(asset.kind, NoteAssetKind.audio);
      expect(asset.originalName, 'recording-1.m4a');
      expect(asset.displayTitle, '产品讨论');
      expect(asset.storageKey, startsWith('notes/audio/'));
      expect(asset.mimeType, 'audio/mp4');
      expect(asset.durationMs, 92340);
      expect(
        await FileStorageService.instance.fileExists(asset.storageKey),
        isTrue,
      );
    },
  );
}
