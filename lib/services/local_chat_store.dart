import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/local_chat.dart';
import 'database_service.dart';

class LocalChatStore {
  LocalChatStore._();
  static final LocalChatStore instance = LocalChatStore._();

  static const defaultSystemPrompt =
      '你是 FKNotes 的本地助手。请准确、清晰地回答用户问题；不确定时应明确说明，不要编造事实。';

  final _uuid = const Uuid();
  Future<void> _writeQueue = Future.value();

  LocalChatSession createSession({String? systemPrompt}) {
    final now = DateTime.now();
    return LocalChatSession(
      id: _uuid.v4(),
      title: '新对话',
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
