import 'dart:io';
import 'dart:typed_data';

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
    expect(asset.storageKey, startsWith('images/'));
    expect(asset.previewStorageKey, startsWith('thumbnails/'));
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
}
