import 'dart:io';

import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/services/database_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/local_chat_store.dart';
import 'package:fknotes/services/note_service.dart';
import 'package:fknotes/services/search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  final notes = NoteService.instance;
  final chats = LocalChatStore.instance;
  final search = SearchService.instance;
  late int richNoteId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = await Directory.systemTemp.createTemp('fknotes_search_');
    await FileStorageService.instance.init(baseDir: root.path);
    final now = DateTime(2026, 7, 12, 14);
    await notes.insertEntry(
      NoteEntry(
        type: NoteType.audio,
        title: '项目周会记录',
        content: '讨论 Flutter 发布安排',
        tags: const ['工作'],
        attachments: [
          NoteAttachment(
            type: NoteType.audio,
            filePath: 'audio/meeting.m4a',
            fileName: '产品会议录音.m4a',
            fileSize: 1024,
            mimeType: 'audio/mp4',
            transcript: '下一步完成离线搜索和发布检查',
            createdAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    richNoteId = await notes.insertEntry(
      NoteEntry(
        type: NoteType.text,
        title: '富文本搜索契约',
        content: '**探&#32034;**方案',
        richContent:
            '{"version":2,"blocks":[{"type":"paragraph","text":"探索方案","styles":[{"start":0,"end":2,"bold":true}]}]}',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await chats.saveSession(
      LocalChatSession(
        id: 'chat-search-test',
        title: '旅行规划',
        systemPrompt: '你是严谨的旅行助手',
        messages: [
          LocalChatMessage(
            id: 'chat-message-search-test',
            role: LocalChatRole.assistant,
            content: '建议预订靠近西湖的住宿，并准备雨具。',
            createdAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDownAll(() async {
    await DatabaseService.instance.close();
    await root.delete(recursive: true);
  });

  test(
    'trigram index finds Chinese text inside an attachment transcript',
    () async {
      final results = await search.search('离线搜索');
      final note = results.singleWhere((result) => result.note != null);

      expect(note.title, '项目周会记录');
      expect(note.matchedAttachment, isTrue);
      expect(note.snippet, contains('离线搜索'));
      expect(note.matches(LocalSearchFilter.attachments), isTrue);
    },
  );

  test(
    'search includes local conversation messages and role prompts',
    () async {
      final messageResults = await search.search('西湖的住宿');
      final promptResults = await search.search('旅行助手');

      expect(messageResults.single.chatSessionId, 'chat-search-test');
      expect(messageResults.single.snippet, contains('西湖'));
      expect(promptResults.single.chatSessionId, 'chat-search-test');
      expect(
        promptResults.single.matches(LocalSearchFilter.conversations),
        isTrue,
      );
    },
  );

  test('two-character queries use the correctness fallback', () async {
    final results = await search.search('周会');

    expect(results.any((result) => result.title == '项目周会记录'), isTrue);
  });

  test(
    'search indexes visible rich text and returns a clean snippet',
    () async {
      final results = await search.search('探索');
      final result = results.singleWhere((item) => item.note?.id == richNoteId);

      expect(result.snippet, contains('探索方案'));
      expect(result.snippet, isNot(contains('**')));
      expect(result.snippet, isNot(contains('&#')));
    },
  );
}
