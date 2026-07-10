import 'dart:io';

import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/services/database_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/note_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory storageDirectory;
  final notes = NoteService.instance;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    storageDirectory = await Directory.systemTemp.createTemp(
      'fknotes_note_service_test_',
    );
    await FileStorageService.instance.init(baseDir: storageDirectory.path);
  });

  tearDownAll(() async {
    await DatabaseService.instance.close();
    await storageDirectory.delete(recursive: true);
  });

  test(
    'attachment updates preserve rows and background imports append one row',
    () async {
      final now = DateTime(2026, 7, 10);
      NoteAttachment attachment(String path, int order) => NoteAttachment(
        type: NoteType.image,
        filePath: path,
        fileName: path,
        fileSize: 10,
        mimeType: 'image/jpeg',
        sortOrder: order,
        createdAt: now,
      );

      final id = await notes.insertEntry(
        NoteEntry(
          type: NoteType.image,
          title: '图片笔记',
          createdAt: now,
          updatedAt: now,
          attachments: [
            attachment('images/a.jpg', 0),
            attachment('images/b.jpg', 1),
          ],
        ),
      );
      final original = await notes.getEntry(id);
      final originalIds = {
        for (final item in original!.allAttachments) item.filePath: item.id,
      };

      await notes.updateEntry(original.copyWith(title: '只修改标题'));
      final afterMetadataUpdate = await notes.getEntry(id);
      expect({
        for (final item in afterMetadataUpdate!.allAttachments)
          item.filePath: item.id,
      }, originalIds);

      final appended = await notes.insertAttachment(
        id,
        attachment('images/c.jpg', 2),
      );
      expect(appended.id, isNotNull);
      final afterAppend = await notes.getEntry(id);
      expect(afterAppend!.allAttachments, hasLength(3));
      expect(
        afterAppend.allAttachments
            .where((item) => item.filePath == 'images/a.jpg')
            .single
            .id,
        originalIds['images/a.jpg'],
      );

      await notes.updateEntry(
        afterAppend.copyWith(
          attachments: afterAppend.allAttachments
              .where((item) => item.filePath != 'images/b.jpg')
              .toList(),
        ),
      );
      final afterRemove = await notes.getEntry(id);
      expect(afterRemove!.allAttachments.map((item) => item.filePath), [
        'images/a.jpg',
        'images/c.jpg',
      ]);
    },
  );

  test(
    'rich content persists while search continues to use plain text',
    () async {
      final now = DateTime(2026, 7, 10, 15);
      const richContent =
          '{"version":1,"blocks":[{"type":"paragraph","text":"重要内容","styles":[{"start":0,"end":2,"bold":true}]}]}';
      final id = await notes.insertEntry(
        NoteEntry(
          type: NoteType.text,
          title: '富文本测试',
          content: '重要内容',
          richContent: richContent,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final restored = await notes.getEntry(id);
      expect(restored?.content, '重要内容');
      expect(restored?.richContent, richContent);
      expect(
        (await notes.searchLike('重要')).map((entry) => entry.id),
        contains(id),
      );
    },
  );

  test('audio transcript persists and participates in search', () async {
    final now = DateTime(2026, 7, 10, 16);
    final id = await notes.insertEntry(
      NoteEntry(
        type: NoteType.audio,
        title: '会议录音',
        createdAt: now,
        updatedAt: now,
        attachments: [
          NoteAttachment(
            type: NoteType.audio,
            filePath: 'audio/meeting.m4a',
            fileName: 'meeting.m4a',
            fileSize: 1024,
            mimeType: 'audio/mp4',
            createdAt: now,
          ),
        ],
      ),
    );

    final transcribedAt = now.add(const Duration(minutes: 2));
    await notes.updateAttachmentTranscript(
      noteId: id,
      filePath: 'audio/meeting.m4a',
      transcript: '下一步需要完成离线搜索',
      model: 'sensevoice-test',
      transcribedAt: transcribedAt,
    );

    final restored = await notes.getEntry(id);
    final attachment = restored!.allAttachments.single;
    expect(attachment.transcript, '下一步需要完成离线搜索');
    expect(attachment.transcriptionModel, 'sensevoice-test');
    expect(attachment.transcribedAt, transcribedAt);
    expect(restored.previewText, '下一步需要完成离线搜索');
    expect(
      (await notes.searchLike('离线搜索')).map((entry) => entry.id),
      contains(id),
    );
  });
}
