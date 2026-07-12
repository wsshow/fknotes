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
    var session = store.createSession(systemPrompt: '你是一位旅行规划师');
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
    expect(restored.single.messages.last.content, '可以从西湖开始。');
    expect(restored.single.title, '帮我规划杭州的周末旅行');
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
}
