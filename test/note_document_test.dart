import 'dart:convert';

import 'package:fknotes/models/note_document.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteDocument', () {
    test('stores a versioned canonical Delta envelope', () {
      final document = NoteDocument.empty();

      expect(jsonDecode(document.toJsonString()), {
        'schemaVersion': 1,
        'delta': [
          {'insert': '\n'},
        ],
      });
      expect(document.toQuillDocument().toPlainText(), '\n');
    });

    test('round trips Quill styles without exposing markup as plain text', () {
      final delta = Delta()
        ..insert('加粗', {'bold': true})
        ..insert('与普通文本\n');
      final document = NoteDocument.fromDelta(delta);
      final restored = NoteDocument.fromJsonString(document.toJsonString());

      expect(restored, document);
      expect(restored.toDelta().toJson(), delta.toJson());
      expect(restored.project().plainText, '加粗与普通文本');
      expect(restored.project().searchText, '加粗与普通文本');
    });

    test('projects stable attachment embeds through the consumer resolver', () {
      final firstId = NoteAttachmentId.parse(
        '3d2be3d5-00c8-4f5c-8e69-e90085dc2873',
      );
      final secondId = NoteAttachmentId.parse(
        'dca51acb-2e50-4ef1-9ad8-c4ce1e150f48',
      );
      final delta = Delta()
        ..insert('正文\n')
        ..insert(NoteEmbed.attachment(firstId).toDeltaData())
        ..insert('\n')
        ..insert(NoteEmbed.attachment(secondId).toDeltaData())
        ..insert('\n')
        ..insert(NoteEmbed.attachment(firstId).toDeltaData())
        ..insert('\n');
      final document = NoteDocument.fromDelta(delta);

      final projection = document.project(
        resolveEmbedText: (embed) => switch (embed.kind) {
          NoteEmbedKind.attachment => '【${embed.attachmentId}】',
          NoteEmbedKind.divider => '——',
        },
      );

      expect(projection.plainText, '正文\n【$firstId】\n【$secondId】\n【$firstId】');
      expect(projection.referencedAttachmentIds, [firstId, secondId]);
      expect(projection.hasEmbeds, isTrue);
      expect(projection.isVisuallyEmpty, isFalse);
    });

    test('an embed-only document is not visually empty', () {
      final id = NoteAttachmentId.parse('3d2be3d5-00c8-4f5c-8e69-e90085dc2873');
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(id).toDeltaData())
          ..insert('\n'),
      );

      expect(document.project().plainText, '');
      expect(document.project().isVisuallyEmpty, isFalse);
    });

    test('removes incidental inline styles from block embeds', () {
      final id = NoteAttachmentId.parse('3d2be3d5-00c8-4f5c-8e69-e90085dc2873');
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(id).toDeltaData(), {'bold': true})
          ..insert('\n'),
      );

      expect(document.toDelta().toJson(), [
        {'insert': NoteEmbed.attachment(id).toDeltaData()},
        {'insert': '\n'},
      ]);
    });

    test('rejects file paths and non-canonical attachment IDs', () {
      final delta = Delta()
        ..insert({
          NoteEmbed.attachmentType: {'id': '/data/user/0/note/image.png'},
        })
        ..insert('\n');

      expect(() => NoteDocument.fromDelta(delta), throwsFormatException);
    });

    test('rejects built-in image embeds that can persist local paths', () {
      final delta = Delta()
        ..insert({'image': '/data/user/0/note/image.png'})
        ..insert('\n');

      expect(() => NoteDocument.fromDelta(delta), throwsFormatException);
    });

    test('rejects block embeds mixed into a text line', () {
      final id = NoteAttachmentId.parse('3d2be3d5-00c8-4f5c-8e69-e90085dc2873');
      final delta = Delta()
        ..insert('前文')
        ..insert(NoteEmbed.attachment(id).toDeltaData())
        ..insert('\n');

      expect(() => NoteDocument.fromDelta(delta), throwsFormatException);
    });

    test('rejects change deltas and missing terminal newline', () {
      expect(
        () => NoteDocument.fromDelta(Delta()..retain(1)),
        throwsFormatException,
      );
      expect(
        () => NoteDocument.fromDelta(Delta()..insert('正文')),
        throwsFormatException,
      );
    });

    test('rejects unversioned and unknown document envelopes', () {
      expect(
        () => NoteDocument.fromJsonString('[{"insert":"正文\\n"}]'),
        throwsFormatException,
      );
      expect(
        () => NoteDocument.fromJsonString(
          '{"schemaVersion":2,"delta":[{"insert":"\\n"}]}',
        ),
        throwsFormatException,
      );
    });
  });

  group('NoteAttachmentId', () {
    test('generates canonical stable IDs', () {
      final id = NoteAttachmentId.generate();

      expect(NoteAttachmentId.parse(id.value), id);
    });
  });
}
