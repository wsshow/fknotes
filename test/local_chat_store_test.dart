import 'dart:io';

import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/local_chat_store.dart';
import 'package:fknotes/services/database_service.dart';
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
    await DatabaseService.instance.close();
    root = await Directory.systemTemp.createTemp('fknotes_chat_store_test_');
    await FileStorageService.instance.init(baseDir: root.path);
  });

  tearDown(() async {
    await DatabaseService.instance.close();
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

    final restored = await store.loadSessions();
    expect(restored, hasLength(1));
    expect(restored.single.systemPrompt, '你是一位旅行规划师');
    expect(restored.single.personaId, persona.id);
    expect(restored.single.messages.last.content, '可以从西湖开始。');
    expect(restored.single.title, '帮我规划杭州的周末旅行');
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
    final orphaned = await (await DatabaseService.instance.database).query(
      'chat_messages',
      where: 'session_id = ?',
      whereArgs: [first.id],
    );
    expect(orphaned, isEmpty);
  });

  test('persists image attachments and deletes their managed files', () async {
    final source = File('${root.path}/source.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);
    final filePath = await FileStorageService.instance.copyFile(
      source,
      'assistant',
    );
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
}
