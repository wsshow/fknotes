import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

class NoteShareImageService {
  static const _folderName = 'fknotes_share_exports';
  static const _retention = Duration(hours: 24);

  final Future<Directory> Function()? temporaryDirectoryProvider;

  const NoteShareImageService({this.temporaryDirectoryProvider});

  Future<Directory> createSession() async {
    await cleanupExpired();
    final root = await _rootDirectory();
    final session = Directory(p.join(root.path, const Uuid().v4()));
    await session.create(recursive: true);
    return session;
  }

  Future<File> writePage({
    required Directory session,
    required Uint8List bytes,
    required String title,
    required int pageIndex,
    required int pageCount,
  }) async {
    final base = safeFileName(title);
    final width = pageCount.toString().length.clamp(2, 4);
    final page = (pageIndex + 1).toString().padLeft(width, '0');
    final total = pageCount.toString().padLeft(width, '0');
    final file = File(p.join(session.path, '$base-$page-of-$total.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<ShareResult> shareFiles({
    required List<File> files,
    required String title,
    Rect? sharePositionOrigin,
  }) => SharePlus.instance.share(
    ShareParams(
      files: [
        for (final file in files)
          XFile(file.path, mimeType: 'image/png', name: p.basename(file.path)),
      ],
      title: title,
      subject: title,
      sharePositionOrigin: sharePositionOrigin,
    ),
  );

  Future<void> deleteSession(Directory session) async {
    try {
      if (await session.exists()) await session.delete(recursive: true);
    } on FileSystemException {
      // A receiving app may still have the temporary image open.
    }
  }

  Future<void> cleanupExpired() async {
    final root = await _rootDirectory();
    if (!await root.exists()) return;
    final cutoff = DateTime.now().subtract(_retention);
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      try {
        final modified = await entity.stat().then((value) => value.modified);
        if (modified.isBefore(cutoff)) await entity.delete(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup only.
      }
    }
  }

  Future<Directory> _rootDirectory() async {
    final temporary = temporaryDirectoryProvider == null
        ? await getTemporaryDirectory()
        : await temporaryDirectoryProvider!();
    final root = Directory(p.join(temporary.path, _folderName));
    await root.create(recursive: true);
    return root;
  }

  static String safeFileName(String title) {
    final normalized = title
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '-')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    if (normalized.isEmpty) return 'fknotes-note';
    final runes = normalized.runes.take(40).toList(growable: false);
    return 'fknotes-${String.fromCharCodes(runes)}';
  }
}
