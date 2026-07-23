import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/note.dart';
import '../models/note_document.dart';
import 'file_storage_service.dart';

final class NoteAssetImportService {
  NoteAssetImportService({
    FileStorageService? storage,
    DateTime Function()? now,
  }) : _storage = storage ?? FileStorageService.instance,
       _now = now ?? DateTime.now;

  static final NoteAssetImportService instance = NoteAssetImportService();

  final FileStorageService _storage;
  final DateTime Function() _now;

  Future<NoteAsset> importImageBytes(
    Uint8List bytes, {
    String originalName = '粘贴的图片',
  }) async {
    final stored = await _storage.importNoteImageBytes(bytes);
    String? previewStorageKey;
    try {
      final generated = await _storage.generateNoteThumbnailInBackground(
        stored.storageKey,
      );
      previewStorageKey = generated.isEmpty ? null : generated;
      final timestamp = _now().toUtc();
      final safeName = p.basename(originalName.trim());
      return NoteAsset(
        id: NoteAttachmentId.generate(),
        kind: NoteAssetKind.image,
        storageKey: stored.storageKey,
        originalName: safeName.isEmpty ? '图片' : safeName,
        byteLength: stored.byteLength,
        mimeType: stored.mimeType,
        previewStorageKey: previewStorageKey,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
    } catch (_) {
      await _storage.deleteFile(stored.storageKey);
      await _storage.deleteFile(previewStorageKey);
      rethrow;
    }
  }

  Future<NoteAsset> importAudioFile(
    File source, {
    required String originalName,
    required String displayName,
    required int durationMs,
  }) async {
    final stored = await _storage.importNoteAudioFile(source);
    try {
      final timestamp = _now().toUtc();
      final safeOriginalName = p.basename(originalName.trim());
      final safeDisplayName = displayName.trim();
      return NoteAsset(
        id: NoteAttachmentId.generate(),
        kind: NoteAssetKind.audio,
        storageKey: stored.storageKey,
        originalName: safeOriginalName.isEmpty
            ? 'recording.m4a'
            : safeOriginalName,
        displayName: safeDisplayName.isEmpty ? null : safeDisplayName,
        byteLength: stored.byteLength,
        mimeType: stored.mimeType,
        durationMs: durationMs,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
    } catch (_) {
      await _storage.deleteFile(stored.storageKey);
      rethrow;
    }
  }
}
