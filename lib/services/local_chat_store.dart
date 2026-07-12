import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/local_chat.dart';
import 'database_service.dart';

class LocalChatStore {
  LocalChatStore._();
  static final LocalChatStore instance = LocalChatStore._();

  static const defaultSystemPrompt = LocalChatPersona.defaultSystemPrompt;

  final _uuid = const Uuid();
  Future<void> _writeQueue = Future.value();

  LocalChatSession createSession({
    String personaId = LocalChatPersona.defaultId,
    String? systemPrompt,
  }) {
    final now = DateTime.now();
    return LocalChatSession(
      id: _uuid.v4(),
      title: '新对话',
      personaId: personaId,
      systemPrompt: systemPrompt ?? defaultSystemPrompt,
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  LocalChatMessage createMessage({
    required LocalChatRole role,
    required String content,
    LocalChatMessageStatus status = LocalChatMessageStatus.complete,
  }) => LocalChatMessage(
    id: _uuid.v4(),
    role: role,
    content: content,
    createdAt: DateTime.now(),
    status: status,
  );

  String titleFrom(String content) {
    final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return '新对话';
    final runes = normalized.runes.toList(growable: false);
    if (runes.length <= 24) return normalized;
    return '${String.fromCharCodes(runes.take(24))}…';
  }

  LocalChatPersona createPersona({
    required String name,
    required String description,
    required String systemPrompt,
  }) {
    final now = DateTime.now();
    return LocalChatPersona(
      id: _uuid.v4(),
      name: name.trim(),
      description: description.trim(),
      systemPrompt: systemPrompt.trim(),
      builtIn: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<List<LocalChatPersona>> loadPersonas() async {
    final database = await DatabaseService.instance.database;
    final rows = await database.query(
      'chat_personas',
      orderBy: 'built_in DESC, updated_at DESC',
    );
    return rows
        .map(
          (row) => LocalChatPersona(
            id: row['id'] as String,
            name: row['name'] as String,
            description: row['description'] as String,
            systemPrompt: row['system_prompt'] as String,
            builtIn: row['built_in'] == 1,
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<void> savePersona(LocalChatPersona persona) async {
    if (persona.name.trim().isEmpty || persona.systemPrompt.trim().isEmpty) {
      throw const FormatException('角色名称和系统提示词不能为空');
    }
    final database = await DatabaseService.instance.database;
    await database.insert('chat_personas', {
      'id': persona.id,
      'name': persona.name.trim(),
      'description': persona.description.trim(),
      'system_prompt': persona.systemPrompt.trim(),
      'built_in': persona.builtIn ? 1 : 0,
      'created_at': persona.createdAt.toIso8601String(),
      'updated_at': persona.updatedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePersona(String id) async {
    if (id == LocalChatPersona.defaultId) {
      throw const FormatException('内置角色不能删除');
    }
    final database = await DatabaseService.instance.database;
    await database.transaction((transaction) async {
      await transaction.update(
        'chat_sessions',
        {
          'persona_id': LocalChatPersona.defaultId,
          'system_prompt': defaultSystemPrompt,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'persona_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'chat_personas',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<LocalChatSession>> loadSessions() async {
    final database = await DatabaseService.instance.database;
    final sessionRows = await database.query(
      'chat_sessions',
      orderBy: 'updated_at DESC',
    );
    if (sessionRows.isEmpty) return [];
    final messageRows = await database.query(
      'chat_messages',
      orderBy: 'session_id, sort_order',
    );
    final messagesBySession = <String, List<LocalChatMessage>>{};
    for (final row in messageRows) {
      final sessionId = row['session_id'] as String;
      messagesBySession
          .putIfAbsent(sessionId, () => [])
          .add(
            LocalChatMessage(
              id: row['id'] as String,
              role: row['role'] == 'assistant'
                  ? LocalChatRole.assistant
                  : LocalChatRole.user,
              content: row['content'] as String,
              createdAt: DateTime.parse(row['created_at'] as String),
              status: row['status'] == 'stopped'
                  ? LocalChatMessageStatus.stopped
                  : LocalChatMessageStatus.complete,
            ),
          );
    }
    return sessionRows
        .map(
          (row) => LocalChatSession(
            id: row['id'] as String,
            title: row['title'] as String,
            personaId:
                row['persona_id'] as String? ?? LocalChatPersona.defaultId,
            systemPrompt: row['system_prompt'] as String,
            messages: List.unmodifiable(messagesBySession[row['id']] ?? []),
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
          ),
        )
        .toList(growable: false);
  }

  Future<void> saveSession(LocalChatSession session) {
    final result = _writeQueue.then((_) async {
      final database = await DatabaseService.instance.database;
      await database.transaction((transaction) async {
        await transaction.insert('chat_sessions', {
          'id': session.id,
          'title': session.title,
          'persona_id': session.personaId,
          'system_prompt': session.systemPrompt,
          'created_at': session.createdAt.toIso8601String(),
          'updated_at': session.updatedAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await transaction.delete(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: [session.id],
        );
        final batch = transaction.batch();
        for (var index = 0; index < session.messages.length; index++) {
          final message = session.messages[index];
          batch.insert('chat_messages', {
            'id': message.id,
            'session_id': session.id,
            'role': message.role.name,
            'content': message.content,
            'status': message.status.name,
            'created_at': message.createdAt.toIso8601String(),
            'sort_order': index,
          });
        }
        await batch.commit(noResult: true);
      });
    });
    _writeQueue = result.catchError((_) {});
    return result;
  }

  Future<void> deleteSession(String id) {
    final result = _writeQueue.then((_) async {
      final database = await DatabaseService.instance.database;
      await database.delete('chat_sessions', where: 'id = ?', whereArgs: [id]);
    });
    _writeQueue = result.catchError((_) {});
    return result;
  }
}
