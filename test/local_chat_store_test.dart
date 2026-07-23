import 'dart:io';

import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/local_chat_database_service.dart';
import 'package:fknotes/services/local_chat_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  final store = LocalChatStore.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalChatDatabaseService.instance.close();
    root = await Directory.systemTemp.createTemp('fknotes_chat_store_test_');
    await FileStorageService.instance.init(baseDir: root.path);
  });

  tearDown(() async {
    await LocalChatDatabaseService.instance.close();
    await root.delete(recursive: true);
  });

  test('persists conversations, roles and messages locally', () async {
    final persona = store.createPersona(
      name: '旅行规划师',
      description: '规划本地旅行',
      systemPrompt: '你是一位旅行规划师',
    );
    await store.savePersona(persona);
    var session = store.createSession(
      personaId: persona.id,
      systemPrompt: persona.systemPrompt,
    );
    session = session.copyWith(
      title: store.titleFrom('帮我规划杭州的周末旅行'),
      messages: [
        store.createMessage(role: LocalChatRole.user, content: '帮我规划杭州的周末旅行'),
        store.createMessage(role: LocalChatRole.assistant, content: '可以从西湖开始。'),
      ],
      updatedAt: DateTime.now(),
    );
    await store.saveSession(session);
    await LocalChatDatabaseService.instance.validate();
    expect(
      (await (await LocalChatDatabaseService.instance.database).rawQuery(
        'PRAGMA journal_mode',
      )).single.values.single,
      'wal',
    );

    final restored = await store.loadSessions();
    expect(restored, hasLength(1));
    expect(restored.single.systemPrompt, '你是一位旅行规划师');
    expect(restored.single.personaId, persona.id);
    expect(restored.single.messages.last.content, '可以从西湖开始。');
    expect(restored.single.title, '帮我规划杭州的周末旅行');
    expect(
      await File(
        '${root.path}/${LocalChatDatabaseService.databaseFileName}',
      ).exists(),
      isTrue,
    );
    expect(await File('${root.path}/fknotes.db').exists(), isFalse);

    // Chat UI owns and reorders this collection after every saved turn.
    // Loading must never expose a fixed-length outer list.
    expect(() => restored.add(store.createSession()), returnsNormally);
  });

  test('manages reusable personas and safely resets deleted roles', () async {
    final persona = store.createPersona(
      name: '代码审查员',
      description: '检查代码风险',
      systemPrompt: '你是一位严格的代码审查员。',
    );
    await store.savePersona(persona);
    await store.saveSession(
      store.createSession(
        personaId: persona.id,
        systemPrompt: persona.systemPrompt,
      ),
    );

    final personas = await store.loadPersonas();
    expect(personas.first.id, LocalChatPersona.defaultId);
    expect(personas.any((item) => item.id == persona.id), isTrue);

    await store.deletePersona(persona.id);
    final restored = (await store.loadSessions()).single;
    expect(restored.personaId, LocalChatPersona.defaultId);
    expect(restored.systemPrompt, LocalChatPersona.defaultSystemPrompt);
    expect(
      (await store.loadPersonas()).any((item) => item.id == persona.id),
      isFalse,
    );
  });

  test('persists consecutive turns after reloading a session', () async {
    var session = store.createSession().copyWith(
      messages: [
        store.createMessage(role: LocalChatRole.user, content: '第一问'),
        store.createMessage(role: LocalChatRole.assistant, content: '第一答'),
      ],
    );
    await store.saveSession(session);

    session = (await store.loadSessions()).single;
    session = session.copyWith(
      messages: [
        ...session.messages,
        store.createMessage(role: LocalChatRole.user, content: '第二问'),
        store.createMessage(role: LocalChatRole.assistant, content: '第二答'),
      ],
      updatedAt: DateTime.now(),
    );
    await store.saveSession(session);

    final restored = (await store.loadSessions()).single;
    expect(restored.messages.map((message) => message.content), [
      '第一问',
      '第一答',
      '第二问',
      '第二答',
    ]);
  });

  test('deletes only the selected conversation', () async {
    final created = store.createSession();
    final first = created.copyWith(
      messages: [
        store.createMessage(role: LocalChatRole.user, content: '即将删除'),
      ],
    );
    final second = store.createSession();
    await store.saveSession(first);
    await store.saveSession(second);

    await store.deleteSession(first.id);

    expect((await store.loadSessions()).map((item) => item.id), [second.id]);
    final orphaned = await (await LocalChatDatabaseService.instance.database)
        .query('chat_messages', where: 'session_id = ?', whereArgs: [first.id]);
    expect(orphaned, isEmpty);
  });

  test('persists image attachments and deletes their managed files', () async {
    const filePath = 'assistant/test-image.jpg';
    await File(
      FileStorageService.instance.absolutePath(filePath),
    ).writeAsBytes([1, 2, 3, 4]);
    final attachment = store.createImageAttachment(
      filePath: filePath,
      fileName: 'idea.jpg',
      mimeType: 'image/jpeg',
    );
    final session = store.createSession().copyWith(
      messages: [
        store.createMessage(
          role: LocalChatRole.user,
          content: '分析这张图',
          attachments: [attachment],
        ),
      ],
    );
    await store.saveSession(session);

    final restored = (await store.loadSessions()).single;
    expect(restored.messages.single.attachments.single.fileName, 'idea.jpg');
    expect(await FileStorageService.instance.fileExists(filePath), isTrue);

    await store.deleteSession(session.id);
    expect(await FileStorageService.instance.fileExists(filePath), isFalse);
  });

  test('persists note contexts used by a conversation', () async {
    final noteId = NoteId.parse('f1341a17-27a4-42f8-bd30-b589550f0f57');
    final noteContext = LocalChatNoteContext(
      noteId: noteId,
      title: '发布计划',
      scope: LocalChatNoteScope.currentBlock,
      content: '周五发布测试版本。',
      updatedAt: DateTime(2026, 7, 14),
    );
    final session = store.createSession().copyWith(
      messages: [
        store.createMessage(
          role: LocalChatRole.user,
          content: '什么时候发布？',
          noteContexts: [noteContext],
        ),
        store.createMessage(
          role: LocalChatRole.assistant,
          content: '计划在周五发布。[N1]',
          noteContexts: [noteContext],
        ),
      ],
    );

    await store.saveSession(session);
    final restored = (await store.loadSessions()).single;

    expect(restored.messages.last.noteContexts, hasLength(1));
    expect(restored.messages.last.noteContexts.single.noteId, noteId);
    expect(restored.messages.last.noteContexts.single.title, '发布计划');
    expect(
      restored.messages.last.noteContexts.single.scope,
      LocalChatNoteScope.currentBlock,
    );
  });

  test('persists controlled tool proposals and completion state', () async {
    final noteId = NoteId.parse('f1341a17-27a4-42f8-bd30-b589550f0f57');
    var session = store.createSession().copyWith(
      messages: [
        store.createMessage(
          role: LocalChatRole.assistant,
          content: '请确认是否追加到笔记。',
          toolCalls: [
            LocalChatToolCall(
              id: 'tool-1',
              name: LocalChatToolName.appendNote,
              noteId: noteId,
              content: '追加内容',
            ),
          ],
        ),
      ],
    );
    await store.saveSession(session);

    var restored = (await store.loadSessions()).single;
    expect(restored.messages.single.toolCalls.single.noteId, noteId);
    expect(
      restored.messages.single.toolCalls.single.status,
      LocalChatToolStatus.proposed,
    );

    session = restored.copyWith(
      messages: [
        restored.messages.single.copyWith(
          toolCalls: [
            restored.messages.single.toolCalls.single.copyWith(
              status: LocalChatToolStatus.completed,
            ),
          ],
        ),
      ],
    );
    await store.saveSession(session);
    restored = (await store.loadSessions()).single;
    expect(
      restored.messages.single.toolCalls.single.status,
      LocalChatToolStatus.completed,
    );
  });
}
