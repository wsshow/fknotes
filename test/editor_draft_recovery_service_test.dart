import 'dart:convert';
import 'dart:io';

import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/services/editor_draft_recovery_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  final service = EditorDraftRecoveryService.instance;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fknotes_draft_recovery_');
    await FileStorageService.instance.init(baseDir: root.path);
    await service.clearAll();
  });

  tearDown(() async {
    await service.clearAll();
    await root.delete(recursive: true);
  });

  test('atomically saves and loads all recoverable editor state', () async {
    final now = DateTime.utc(2026, 7, 12, 10, 30);
    final attachment = NoteAttachment(
      id: 7,
      noteId: 42,
      type: NoteType.document,
      filePath: 'documents/plan.md',
      fileName: 'plan.md',
      fileSize: 128,
      mimeType: 'text/markdown',
      createdAt: now,
    );
    final draft = EditorRecoveryDraft(
      noteId: 42,
      baseUpdatedAt: now.subtract(const Duration(minutes: 1)),
      savedAt: now,
      title: '恢复标题',
      content: '# 恢复正文',
      richContent: '{"blocks":[]}',
      tags: const ['工作', '离线'],
      isFavorite: true,
      isPinned: true,
      attachments: [attachment],
      removedAttachments: const [],
    );

    await service.save(draft);
    final restored = await service.load(42);

    expect(restored, isNotNull);
    expect(restored!.title, '恢复标题');
    expect(restored.content, '# 恢复正文');
    expect(restored.tags, ['工作', '离线']);
    expect(restored.isFavorite, isTrue);
    expect(restored.attachments.single.filePath, 'documents/plan.md');
    expect(
      File('${root.path}/recovery/editor-drafts/note-42.json.tmp').existsSync(),
      isFalse,
    );
  });

  test('serializes rapid save and clear operations in call order', () async {
    final draft = EditorRecoveryDraft(
      noteId: null,
      baseUpdatedAt: null,
      savedAt: DateTime.utc(2026, 7, 12),
      title: '临时内容',
      content: '',
      richContent: null,
      tags: const [],
      isFavorite: false,
      isPinned: false,
      attachments: const [],
      removedAttachments: const [],
    );

    final save = service.save(draft);
    final clear = service.clear(null);
    await Future.wait([save, clear]);

    expect(await service.load(null), isNull);
  });

  test(
    'drops malformed recovery files instead of blocking the editor',
    () async {
      final directory = Directory('${root.path}/recovery/editor-drafts');
      await directory.create(recursive: true);
      final file = File('${directory.path}/new-note.json');
      await file.writeAsString('{broken');

      expect(await service.load(null), isNull);
      expect(await file.exists(), isFalse);
    },
  );

  test(
    'recovers a newer flushed temporary file after an interrupted rename',
    () async {
      final directory = Directory('${root.path}/recovery/editor-drafts');
      await directory.create(recursive: true);
      final oldDraft = EditorRecoveryDraft(
        noteId: 9,
        baseUpdatedAt: null,
        savedAt: DateTime.utc(2026, 7, 12, 10),
        title: '旧内容',
        content: '',
        richContent: null,
        tags: const [],
        isFavorite: false,
        isPinned: false,
        attachments: const [],
        removedAttachments: const [],
      );
      final newDraft = EditorRecoveryDraft(
        noteId: 9,
        baseUpdatedAt: null,
        savedAt: DateTime.utc(2026, 7, 12, 10, 1),
        title: '最新内容',
        content: '',
        richContent: null,
        tags: const [],
        isFavorite: false,
        isPinned: false,
        attachments: const [],
        removedAttachments: const [],
      );
      final file = File('${directory.path}/note-9.json');
      await file.writeAsString(jsonEncode(oldDraft.toJson()));
      await File(
        '${file.path}.tmp',
      ).writeAsString(jsonEncode(newDraft.toJson()));

      final restored = await service.load(9);

      expect(restored?.title, '最新内容');
      expect(await File('${file.path}.tmp').exists(), isFalse);
      expect((await service.load(9))?.title, '最新内容');
    },
  );
}
