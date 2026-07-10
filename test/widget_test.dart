import 'package:flutter_test/flutter_test.dart';
import 'package:fknotes/models/note_entry.dart';

void main() {
  test('NoteEntry exposes OCR text as preview when content is empty', () {
    final now = DateTime(2026, 6, 22);
    final entry = NoteEntry(
      type: NoteType.image,
      title: 'receipt',
      ocrText: 'total 128',
      createdAt: now,
      updatedAt: now,
    );

    expect(entry.previewText, 'total 128');
    expect(entry.hasMedia, isFalse);
  });

  test('NoteType round trips database values', () {
    for (final type in NoteType.values) {
      expect(NoteType.fromDb(type.dbValue), type);
    }
  });

  test('NoteEntry preserves organization metadata in local map', () {
    final now = DateTime(2026, 7, 10, 10, 30);
    final entry = NoteEntry(
      id: 7,
      type: NoteType.document,
      title: 'Research',
      tags: const ['work', 'offline'],
      isFavorite: true,
      isPinned: true,
      createdAt: now,
      updatedAt: now,
    );

    final restored = NoteEntry.fromMap(entry.toMap());
    expect(restored.tags, ['work', 'offline']);
    expect(restored.isFavorite, isTrue);
    expect(restored.isPinned, isTrue);
    expect(restored.isDeleted, isFalse);
  });

  test('A note can contain ordered attachments of multiple types', () {
    final now = DateTime(2026, 7, 10, 11, 30);
    final entry = NoteEntry(
      type: NoteType.image,
      title: 'Field notes',
      content: '现场记录',
      attachments: [
        NoteAttachment(
          type: NoteType.image,
          filePath: 'files/images/a.jpg',
          fileName: 'a.jpg',
          fileSize: 120,
          mimeType: 'image/jpeg',
          ocrText: '路牌文字',
          createdAt: now,
        ),
        NoteAttachment(
          type: NoteType.image,
          filePath: 'files/images/b.jpg',
          fileName: 'b.jpg',
          fileSize: 130,
          mimeType: 'image/jpeg',
          createdAt: now,
        ),
        NoteAttachment(
          type: NoteType.audio,
          filePath: 'files/audio/a.m4a',
          fileName: 'a.m4a',
          fileSize: 240,
          mimeType: 'audio/mp4',
          durationMs: 3000,
          createdAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    expect(entry.hasMedia, isTrue);
    expect(entry.containsType(NoteType.text), isTrue);
    expect(entry.containsType(NoteType.image), isTrue);
    expect(entry.containsType(NoteType.audio), isTrue);
    expect(entry.attachmentCountFor(NoteType.image), 2);
    expect(entry.totalAttachmentSize, 490);
    expect(entry.aggregateOcr, '路牌文字');
    expect(entry.attachmentSummary, '混合 · 3 项');
    expect(entry.toPortableMap()['attachments'], hasLength(3));
  });

  test('Multiple images produce a dynamic image count', () {
    final now = DateTime(2026, 7, 10);
    NoteAttachment image(String name) => NoteAttachment(
      type: NoteType.image,
      filePath: 'files/images/$name',
      fileName: name,
      fileSize: 1,
      mimeType: 'image/jpeg',
      createdAt: now,
    );

    final entry = NoteEntry(
      type: NoteType.image,
      title: 'Album',
      attachments: [image('1.jpg'), image('2.jpg'), image('3.jpg')],
      createdAt: now,
      updatedAt: now,
    );

    expect(entry.attachmentSummary, '图片 · 3 张');
  });

  test('attachment tokens become readable content outside the editor', () {
    final now = DateTime(2026, 7, 10);
    final entry = NoteEntry(
      type: NoteType.audio,
      content: '会议记录\n[[附件:files/audio/meeting.m4a]]',
      attachments: [
        NoteAttachment(
          type: NoteType.audio,
          filePath: 'files/audio/meeting.m4a',
          fileName: '会议录音.m4a',
          fileSize: 1,
          mimeType: 'audio/mp4',
          createdAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    expect(entry.readableContent, '会议记录\n【附件：会议录音.m4a】');
    expect(entry.previewText, isNot(contains('[[附件:')));
  });

  test(
    'Removing the final migrated attachment does not restore legacy media',
    () {
      final now = DateTime(2026, 7, 10);
      final migrated = NoteEntry(
        type: NoteType.image,
        title: 'Legacy image',
        filePath: 'files/images/legacy.jpg',
        fileName: 'legacy.jpg',
        createdAt: now,
        updatedAt: now,
      );

      expect(migrated.allAttachments, hasLength(1));
      final removed = migrated.copyWith(attachments: const []);
      expect(removed.allAttachments, isEmpty);
      expect(removed.hasMedia, isFalse);
    },
  );
}
