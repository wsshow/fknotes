import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'file_storage_service.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _database;

  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    final path = p.join(FileStorageService.instance.baseDir, 'fknotes.db');
    return openDatabase(
      path,
      version: 3,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL DEFAULT 'text',
        title TEXT NOT NULL DEFAULT '',
        content TEXT,
        rich_content TEXT,
        file_path TEXT,
        file_name TEXT,
        file_size INTEGER,
        mime_type TEXT,
        thumbnail_path TEXT,
        duration_ms INTEGER,
        ocr_text TEXT,
        tags TEXT NOT NULL DEFAULT '',
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await _createAttachmentsTable(db);
    await _createIndexes(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createAttachmentsTable(db);
      await db.execute('''
        INSERT INTO attachments (
          note_id, type, file_path, file_name, file_size, mime_type,
          thumbnail_path, duration_ms, ocr_text, sort_order, created_at
        )
        SELECT
          id, type, file_path, COALESCE(file_name, ''), COALESCE(file_size, 0),
          COALESCE(mime_type, 'application/octet-stream'), thumbnail_path,
          duration_ms, ocr_text, 0, created_at
        FROM entries
        WHERE file_path IS NOT NULL AND file_path != ''
      ''');
      await _createIndexes(db);
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE entries ADD COLUMN rich_content TEXT');
    }
  }

  Future<void> _createAttachmentsTable(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS attachments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      file_path TEXT NOT NULL,
      file_name TEXT NOT NULL DEFAULT '',
      file_size INTEGER NOT NULL DEFAULT 0,
      mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
      thumbnail_path TEXT,
      duration_ms INTEGER,
      ocr_text TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      FOREIGN KEY(note_id) REFERENCES entries(id) ON DELETE CASCADE
    )
  ''');

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_updated ON entries(updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_state ON entries(is_deleted, is_archived)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_type ON entries(type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attachments_note ON attachments(note_id, sort_order)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attachments_type ON attachments(type)',
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
