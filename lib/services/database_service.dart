import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../debug/app_diagnostics.dart';
import '../utils/markdown_text.dart';
import 'file_storage_service.dart';
import '../models/local_chat.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _database;

  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    final path = p.join(FileStorageService.instance.baseDir, 'fknotes.db');
    final stopwatch = Stopwatch()..start();
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.database,
        'database_open_started',
        data: {'schemaVersion': 13},
      );
    }
    try {
      final database = await openDatabase(
        path,
        version: 13,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      if (kDebugMode) {
        AppDiagnostics.info(
          AppLogCategory.database,
          'database_open_completed',
          data: {'durationMs': stopwatch.elapsedMilliseconds},
        );
      }
      return database;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        AppDiagnostics.error(
          AppLogCategory.database,
          'database_open_failed',
          data: {'durationMs': stopwatch.elapsedMilliseconds},
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.database,
        'database_schema_create_started',
        data: {'version': version},
      );
    }
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL DEFAULT 'text',
        title TEXT NOT NULL DEFAULT '',
        content TEXT,
        rich_content TEXT,
        search_text TEXT NOT NULL DEFAULT '',
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
        cover_mode TEXT NOT NULL DEFAULT 'automatic',
        cover_attachment_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await _createAttachmentsTable(db);
    await _createChatTables(db);
    await _createIndexes(db);
    await _createSearchIndex(db);
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.database,
        'database_schema_create_completed',
        data: {'version': version},
      );
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.database,
        'database_migration_started',
        data: {'fromVersion': oldVersion, 'toVersion': newVersion},
      );
    }
    if (oldVersion < 13) {
      final columns = (await db.rawQuery(
        'PRAGMA table_info(entries)',
      )).map((column) => column['name'] as String).toSet();
      if (!columns.contains('search_text')) {
        await db.execute(
          "ALTER TABLE entries ADD COLUMN search_text TEXT NOT NULL DEFAULT ''",
        );
      }
    }
    if (oldVersion < 11) {
      await _createAttachmentsTable(db);
      final columns = (await db.rawQuery(
        'PRAGMA table_info(attachments)',
      )).map((column) => column['name'] as String).toSet();
      if (!columns.contains('display_name')) {
        await db.execute(
          'ALTER TABLE attachments ADD COLUMN display_name TEXT',
        );
      }
    }
    if (oldVersion < 12) {
      final columns = (await db.rawQuery(
        'PRAGMA table_info(entries)',
      )).map((column) => column['name'] as String).toSet();
      if (!columns.contains('cover_mode')) {
        await db.execute(
          "ALTER TABLE entries ADD COLUMN cover_mode TEXT NOT NULL DEFAULT 'automatic'",
        );
      }
      if (!columns.contains('cover_attachment_path')) {
        await db.execute(
          'ALTER TABLE entries ADD COLUMN cover_attachment_path TEXT',
        );
      }
    }
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
    if (oldVersion < 4) {
      await _createAttachmentsTable(db);
      final columns = (await db.rawQuery(
        'PRAGMA table_info(attachments)',
      )).map((column) => column['name'] as String).toSet();
      if (!columns.contains('transcript')) {
        await db.execute('ALTER TABLE attachments ADD COLUMN transcript TEXT');
      }
      if (!columns.contains('transcription_model')) {
        await db.execute(
          'ALTER TABLE attachments ADD COLUMN transcription_model TEXT',
        );
      }
      if (!columns.contains('transcribed_at')) {
        await db.execute(
          'ALTER TABLE attachments ADD COLUMN transcribed_at TEXT',
        );
      }
    }
    if (oldVersion < 5) {
      await _createChatTables(db);
    }
    if (oldVersion < 6) {
      await _createSearchIndex(db);
    }
    if (oldVersion < 7) {
      await _createChatPersonasTable(db);
      final columns = (await db.rawQuery(
        'PRAGMA table_info(chat_sessions)',
      )).map((column) => column['name'] as String).toSet();
      if (!columns.contains('persona_id')) {
        await db.execute(
          "ALTER TABLE chat_sessions ADD COLUMN persona_id TEXT NOT NULL DEFAULT '${LocalChatPersona.defaultId}'",
        );
      }
    }
    if (oldVersion < 8) {
      final columns = (await db.rawQuery(
        'PRAGMA table_info(chat_messages)',
      )).map((column) => column['name'] as String).toSet();
      if (!columns.contains('attachments_json')) {
        await db.execute(
          "ALTER TABLE chat_messages ADD COLUMN attachments_json TEXT NOT NULL DEFAULT '[]'",
        );
      }
    }
    if (oldVersion < 9) {
      final columns = (await db.rawQuery(
        'PRAGMA table_info(chat_messages)',
      )).map((column) => column['name'] as String).toSet();
      if (!columns.contains('note_contexts_json')) {
        await db.execute(
          "ALTER TABLE chat_messages ADD COLUMN note_contexts_json TEXT NOT NULL DEFAULT '[]'",
        );
      }
    }
    if (oldVersion < 10) {
      final columns = (await db.rawQuery(
        'PRAGMA table_info(chat_messages)',
      )).map((column) => column['name'] as String).toSet();
      if (!columns.contains('tool_calls_json')) {
        await db.execute(
          "ALTER TABLE chat_messages ADD COLUMN tool_calls_json TEXT NOT NULL DEFAULT '[]'",
        );
      }
    }
    if (oldVersion < 11) {
      await _createSearchIndex(db);
    }
    if (oldVersion < 13) {
      await _backfillSearchText(db);
      await _createSearchIndex(db);
    }
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.database,
        'database_migration_completed',
        data: {'fromVersion': oldVersion, 'toVersion': newVersion},
      );
    }
  }

  Future<void> _createAttachmentsTable(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS attachments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      file_path TEXT NOT NULL,
      file_name TEXT NOT NULL DEFAULT '',
      display_name TEXT,
      file_size INTEGER NOT NULL DEFAULT 0,
      mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
      thumbnail_path TEXT,
      duration_ms INTEGER,
      ocr_text TEXT,
      transcript TEXT,
      transcription_model TEXT,
      transcribed_at TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      FOREIGN KEY(note_id) REFERENCES entries(id) ON DELETE CASCADE
    )
  ''');

  Future<void> _createChatTables(Database db) async {
    await _createChatPersonasTable(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        persona_id TEXT NOT NULL DEFAULT '${LocalChatPersona.defaultId}',
        system_prompt TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(persona_id) REFERENCES chat_personas(id) ON DELETE SET DEFAULT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        attachments_json TEXT NOT NULL DEFAULT '[]',
        note_contexts_json TEXT NOT NULL DEFAULT '[]',
        tool_calls_json TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'complete',
        created_at TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_sessions_updated '
      'ON chat_sessions(updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_session '
      'ON chat_messages(session_id, sort_order)',
    );
  }

  Future<void> _createChatPersonasTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_personas (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        system_prompt TEXT NOT NULL,
        built_in INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    final now = DateTime.now().toIso8601String();
    await db.insert('chat_personas', {
      'id': LocalChatPersona.defaultId,
      'name': '通用助手',
      'description': '准确、清晰地处理日常问题',
      'system_prompt': LocalChatPersona.defaultSystemPrompt,
      'built_in': 1,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

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

  Future<void> _backfillSearchText(Database db) async {
    final attachmentLabels = <int, Map<String, String>>{};
    for (final row in await db.query(
      'attachments',
      columns: ['note_id', 'file_path', 'file_name', 'display_name'],
    )) {
      final noteId = row['note_id'] as int?;
      final path = row['file_path'] as String? ?? '';
      if (noteId == null || path.isEmpty) continue;
      final displayName = row['display_name'] as String? ?? '';
      final fileName = row['file_name'] as String? ?? '';
      attachmentLabels.putIfAbsent(noteId, () => {})[path] =
          displayName.trim().isEmpty ? fileName : displayName;
    }
    for (final row in await db.query(
      'entries',
      columns: ['id', 'content', 'rich_content'],
    )) {
      final id = row['id'] as int;
      final text = MarkdownText.toPlainTextDocument(
        row['content'] as String? ?? '',
        richContent: row['rich_content'] as String?,
        attachmentLabelsByPath: attachmentLabels[id] ?? const {},
      );
      await db.update(
        'entries',
        {'search_text': text},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _createSearchIndex(Database db) async {
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
          kind UNINDEXED,
          source_id UNINDEXED,
          parent_id UNINDEXED,
          title,
          body,
          metadata,
          tokenize = 'trigram case_sensitive 0'
        )
      ''');
    } on DatabaseException {
      try {
        await db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
            kind UNINDEXED,
            source_id UNINDEXED,
            parent_id UNINDEXED,
            title,
            body,
            metadata,
            tokenize = 'unicode61 remove_diacritics 2'
          )
        ''');
      } on DatabaseException {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS search_fts (
            kind TEXT NOT NULL,
            source_id TEXT NOT NULL,
            parent_id TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            body TEXT NOT NULL DEFAULT '',
            metadata TEXT NOT NULL DEFAULT ''
          )
        ''');
      }
    }
    for (final trigger in [
      'entries_search_ai',
      'entries_search_au',
      'entries_search_ad',
      'attachments_search_ai',
      'attachments_search_au',
      'attachments_search_ad',
      'chat_sessions_search_ai',
      'chat_sessions_search_au',
      'chat_sessions_search_ad',
      'chat_messages_search_ai',
      'chat_messages_search_au',
      'chat_messages_search_ad',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }
    await db.execute('''
      CREATE TRIGGER entries_search_ai AFTER INSERT ON entries BEGIN
        INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
        VALUES('note', NEW.id, '', NEW.title, COALESCE(NEW.search_text, ''),
          COALESCE(NEW.tags, '') || ' ' || COALESCE(NEW.ocr_text, '') || ' ' ||
          COALESCE(NEW.file_name, ''));
      END
    ''');
    await db.execute('''
      CREATE TRIGGER entries_search_au AFTER UPDATE ON entries BEGIN
        DELETE FROM search_fts WHERE kind = 'note' AND source_id = OLD.id;
        INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
        VALUES('note', NEW.id, '', NEW.title, COALESCE(NEW.search_text, ''),
          COALESCE(NEW.tags, '') || ' ' || COALESCE(NEW.ocr_text, '') || ' ' ||
          COALESCE(NEW.file_name, ''));
      END
    ''');
    await db.execute('''
      CREATE TRIGGER entries_search_ad AFTER DELETE ON entries BEGIN
        DELETE FROM search_fts WHERE kind = 'note' AND source_id = OLD.id;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER attachments_search_ai AFTER INSERT ON attachments BEGIN
        INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
        VALUES('attachment', NEW.id, NEW.note_id,
          COALESCE(NULLIF(NEW.display_name, ''), NEW.file_name),
          COALESCE(NEW.ocr_text, '') || ' ' || COALESCE(NEW.transcript, ''),
          NEW.type || ' ' || NEW.mime_type || ' ' || NEW.file_name);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER attachments_search_au AFTER UPDATE ON attachments BEGIN
        DELETE FROM search_fts WHERE kind = 'attachment' AND source_id = OLD.id;
        INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
        VALUES('attachment', NEW.id, NEW.note_id,
          COALESCE(NULLIF(NEW.display_name, ''), NEW.file_name),
          COALESCE(NEW.ocr_text, '') || ' ' || COALESCE(NEW.transcript, ''),
          NEW.type || ' ' || NEW.mime_type || ' ' || NEW.file_name);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER attachments_search_ad AFTER DELETE ON attachments BEGIN
        DELETE FROM search_fts WHERE kind = 'attachment' AND source_id = OLD.id;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER chat_sessions_search_ai AFTER INSERT ON chat_sessions BEGIN
        INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
        VALUES('chat_session', NEW.id, '', NEW.title, NEW.system_prompt, '');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER chat_sessions_search_au AFTER UPDATE ON chat_sessions BEGIN
        DELETE FROM search_fts WHERE kind = 'chat_session' AND source_id = OLD.id;
        INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
        VALUES('chat_session', NEW.id, '', NEW.title, NEW.system_prompt, '');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER chat_sessions_search_ad AFTER DELETE ON chat_sessions BEGIN
        DELETE FROM search_fts WHERE kind = 'chat_session' AND source_id = OLD.id;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER chat_messages_search_ai AFTER INSERT ON chat_messages BEGIN
        INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
        VALUES('chat_message', NEW.id, NEW.session_id, '', NEW.content, NEW.role);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER chat_messages_search_au AFTER UPDATE ON chat_messages BEGIN
        DELETE FROM search_fts WHERE kind = 'chat_message' AND source_id = OLD.id;
        INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
        VALUES('chat_message', NEW.id, NEW.session_id, '', NEW.content, NEW.role);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER chat_messages_search_ad AFTER DELETE ON chat_messages BEGIN
        DELETE FROM search_fts WHERE kind = 'chat_message' AND source_id = OLD.id;
      END
    ''');
    await db.delete('search_fts');
    await db.execute('''
      INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
      SELECT 'note', id, '', title, COALESCE(search_text, ''),
        COALESCE(tags, '') || ' ' || COALESCE(ocr_text, '') || ' ' ||
        COALESCE(file_name, '')
      FROM entries
    ''');
    await db.execute('''
      INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
      SELECT 'attachment', id, note_id,
        COALESCE(NULLIF(display_name, ''), file_name),
        COALESCE(ocr_text, '') || ' ' || COALESCE(transcript, ''),
        type || ' ' || mime_type || ' ' || file_name
      FROM attachments
    ''');
    await db.execute('''
      INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
      SELECT 'chat_session', id, '', title, system_prompt, ''
      FROM chat_sessions
    ''');
    await db.execute('''
      INSERT INTO search_fts(kind, source_id, parent_id, title, body, metadata)
      SELECT 'chat_message', id, session_id, '', content, role
      FROM chat_messages
    ''');
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    if (kDebugMode) {
      AppDiagnostics.info(AppLogCategory.database, 'database_closed');
    }
  }

  Future<void> validateUserData() async {
    final stopwatch = Stopwatch()..start();
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.database,
        'database_validation_started',
      );
    }
    final db = await database;
    final quickCheck = await db.rawQuery('PRAGMA quick_check');
    if (quickCheck.isEmpty ||
        quickCheck.first.values.firstOrNull?.toString().toLowerCase() != 'ok') {
      throw const FormatException('备份数据库完整性检查失败');
    }
    if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const FormatException('备份数据库关联关系损坏');
    }
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((row) => row['name']).whereType<String>().toSet();
    const requiredTables = {
      'entries',
      'attachments',
      'chat_sessions',
      'chat_messages',
      'chat_personas',
    };
    if (!tables.containsAll(requiredTables)) {
      throw const FormatException('备份数据库结构不完整');
    }

    final attachments = await db.query(
      'attachments',
      columns: ['file_path', 'thumbnail_path'],
    );
    for (final attachment in attachments) {
      final filePath = attachment['file_path'] as String? ?? '';
      final absoluteFile = File(
        FileStorageService.instance.absolutePath(filePath),
      );
      if (!await absoluteFile.exists()) {
        throw FormatException('备份缺少附件：$filePath');
      }
      final thumbnailPath = attachment['thumbnail_path'] as String?;
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        FileStorageService.instance.absolutePath(thumbnailPath);
      }
    }
    if (kDebugMode) {
      AppDiagnostics.info(
        AppLogCategory.database,
        'database_validation_completed',
        data: {
          'durationMs': stopwatch.elapsedMilliseconds,
          'attachmentCount': attachments.length,
        },
      );
    }
  }
}
