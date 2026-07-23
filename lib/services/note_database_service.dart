import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/note_document.dart';
import 'file_storage_service.dart';
import 'note_repository.dart';

/// Owns the clean-slate Delta note database.
///
/// This database starts from a clean installation. A file with this name from
/// a pre-Delta release is intentionally neither detected nor migrated.
final class NoteDatabaseService {
  NoteDatabaseService({this.databasePath});

  static final NoteDatabaseService instance = NoteDatabaseService();
  static const String databaseFileName = 'fknotes.db';
  static const int schemaVersion = 1;

  final String? databasePath;
  Database? _database;
  NoteRepository? _repository;

  Future<Database> get database async => _database ??= await _open();

  Future<NoteRepository> get repository async {
    final existing = _repository;
    if (existing != null) return existing;
    final created = NoteRepository(await database);
    await created.initialize();
    return _repository = created;
  }

  Future<Database> _open() async {
    final path =
        databasePath ??
        p.join(FileStorageService.instance.baseDir, databaseFileName);
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await database.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: (database, _) => NoteRepository(database).initialize(),
    );
  }

  Future<void> validate({String? assetRoot}) async {
    final db = await database;
    final quickCheck = await db.rawQuery('PRAGMA quick_check');
    if (quickCheck.singleOrNull?.values.singleOrNull != 'ok') {
      throw const FormatException('笔记数据库完整性检查失败');
    }
    if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const FormatException('笔记数据库附件关联损坏');
    }

    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')",
    )).map((row) => row['name']).whereType<String>().toSet();
    if (!tables.containsAll(const {'notes', 'note_assets', 'note_tags'})) {
      throw const FormatException('笔记数据库结构不完整');
    }

    for (final row in await db.query('notes', columns: ['document_json'])) {
      NoteDocument.fromJsonString(row['document_json']! as String);
    }
    for (final row in await db.query(
      'note_assets',
      columns: ['kind', 'storage_key', 'preview_storage_key', 'byte_length'],
    )) {
      final kind = row['kind']! as String;
      final storageKey = row['storage_key']! as String;
      for (final entry in [
        (key: storageKey, isPreview: false),
        (key: row['preview_storage_key'] as String?, isPreview: true),
      ]) {
        final key = entry.key;
        if (key == null) continue;
        final relative = key;
        if (!_isCanonicalAssetKey(
          relative,
          kind: kind,
          isPreview: entry.isPreview,
        )) {
          throw FormatException('笔记附件路径不属于新数据空间：$relative');
        }
        final path = assetRoot == null
            ? FileStorageService.instance.absolutePath(relative)
            : _resolveInside(assetRoot, relative);
        final file = File(path);
        if (!await file.exists()) {
          throw FormatException('笔记附件缺失：$relative');
        }
        if (!entry.isPreview &&
            await file.length() != row['byte_length']! as int) {
          throw FormatException('笔记附件大小不匹配：$relative');
        }
      }
    }
  }

  static bool _isCanonicalAssetKey(
    String value, {
    required String kind,
    required bool isPreview,
  }) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    final root = isPreview
        ? 'notes/thumbnails'
        : switch (kind) {
            'image' => 'notes/images',
            'audio' => 'notes/audio',
            'video' => 'notes/video',
            'file' => 'notes/files',
            _ => '',
          };
    return normalized == value &&
        root.isNotEmpty &&
        normalized.startsWith('$root/') &&
        normalized.length > root.length + 1;
  }

  static String _resolveInside(String root, String relative) {
    final resolved = p.normalize(p.joinAll([root, ...p.posix.split(relative)]));
    if (!p.isWithin(root, resolved)) {
      throw const FormatException('笔记附件路径不安全');
    }
    return resolved;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _repository = null;
  }
}
