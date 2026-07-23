// The pinned Flutter Quill clipboard hooks are intentionally exercised here.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:fknotes/editor/note_editor_controller.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/widgets/note_quill_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteEditorController', () {
    test(
      'keeps native newlines and Quill inline styles in the Delta snapshot',
      () {
        final controller = NoteEditorController(
          document: NoteDocument.fromPlainText('第一行'),
          assets: const [],
        );
        addTearDown(controller.dispose);

        controller.quillController.replaceText(
          3,
          0,
          '\n第二行',
          const TextSelection.collapsed(offset: 7),
        );
        controller.quillController.formatText(0, 3, quill.Attribute.bold);

        final snapshot = controller.snapshot();
        expect(snapshot.document.project().plainText, '第一行\n第二行');
        expect(snapshot.document.toDelta().toJson(), [
          {
            'insert': '第一行',
            'attributes': {'bold': true},
          },
          {'insert': '\n第二行\n'},
        ]);
      },
    );

    test(
      'inserts an image as an independent block in the current paragraph',
      () {
        final asset = _imageAsset();
        final controller = NoteEditorController(
          document: NoteDocument.fromPlainText('前文后文'),
          assets: const [],
        );
        addTearDown(controller.dispose);
        controller.quillController.updateSelection(
          const TextSelection.collapsed(offset: 2),
          quill.ChangeSource.local,
        );

        controller.insertAsset(asset);
        final snapshot = controller.snapshot();

        expect(snapshot.assets, [asset]);
        expect(snapshot.document.project().plainText, '前文\n\n后文');
        expect(snapshot.document.project().referencedAttachmentIds, [asset.id]);
      },
    );

    test(
      'system image paste imports bytes into a domain asset embed',
      () async {
        final asset = _imageAsset();
        var importedBytes = Uint8List(0);
        final controller = NoteEditorController(
          document: NoteDocument.empty(),
          assets: const [],
          readClipboardImage: () async => Uint8List.fromList([1, 2, 3]),
          importImage: (bytes) async {
            importedBytes = bytes;
            return asset;
          },
        );
        addTearDown(controller.dispose);

        expect(await controller.quillController.clipboardPaste(), isTrue);

        expect(importedBytes, [1, 2, 3]);
        expect(controller.snapshot().assets, [asset]);
      },
    );

    test('external rich paste strips path and URL image embeds', () async {
      final controller = NoteEditorController(
        document: NoteDocument.empty(),
        assets: const [],
      );
      addTearDown(controller.dispose);
      final sanitize =
          controller.quillController.config.clipboardConfig!.onRichTextPaste!;
      final pasted = Delta()
        ..insert('安全文本', {'italic': true})
        ..insert({'image': 'https://tracker.example/image.png'});

      final clean = await sanitize(pasted, true);

      expect(clean?.toJson(), [
        {
          'insert': '安全文本',
          'attributes': {'italic': true},
        },
      ]);
    });

    test('snapshot reconciles assets after an embed is deleted', () {
      final asset = _imageAsset();
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n'),
      );
      final controller = NoteEditorController(
        document: document,
        assets: [asset],
      );
      addTearDown(controller.dispose);

      controller.removeEmbedAt(0);

      expect(controller.snapshot().assets, isEmpty);
      expect(controller.snapshot().document.project().isVisuallyEmpty, isTrue);
    });

    test(
      'whole-document formatting crosses paragraphs and an image safely',
      () {
        final asset = _imageAsset();
        final document = NoteDocument.fromDelta(
          Delta()
            ..insert('第一段\n')
            ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
            ..insert('\n')
            ..insert('第二段\n'),
        );
        final controller = NoteEditorController(
          document: document,
          assets: [asset],
        );
        addTearDown(controller.dispose);

        controller.quillController.updateSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: controller.quillController.document.length - 1,
          ),
          quill.ChangeSource.local,
        );
        controller.quillController.formatSelection(quill.Attribute.bold);

        final snapshot = controller.snapshot();
        expect(snapshot.document.project().plainText, '第一段\n\n第二段');
        expect(snapshot.assets, [asset]);
        final embedOperation = snapshot.document
            .toDelta()
            .operations
            .singleWhere((operation) => operation.data is! String);
        expect(embedOperation.attributes, isNull);
      },
    );
  });

  testWidgets(
    'renders an inline image at editor width with its remove action',
    (tester) async {
      final asset = _imageAsset();
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert('图片之前\n')
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n')
          ..insert('图片之后\n'),
      );
      final controller = NoteEditorController(
        document: document,
        assets: [asset],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _EditorTestApp(
          child: NoteQuillEditor(
            controller: controller,
            resolveImage: (_) => MemoryImage(_onePixelPng),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final imageFinder = find.byKey(ValueKey('note-image-${asset.id.value}'));
      final editorFinder = find.byType(NoteQuillEditor);
      expect(imageFinder, findsOneWidget);
      expect(
        tester.getSize(imageFinder).width,
        closeTo(tester.getSize(editorFinder).width - 48, 1),
      );

      await tester.tap(
        find.byKey(ValueKey('remove-note-asset-${asset.id.value}')),
      );
      await tester.pump();

      expect(controller.snapshot().assets, isEmpty);
      expect(controller.snapshot().document.project().plainText, '图片之前\n图片之后');
    },
  );

  testWidgets('provides a single-row rich text toolbar', (tester) async {
    final controller = NoteEditorController(
      document: NoteDocument.empty(),
      assets: const [],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: NoteQuillToolbar(controller: controller, onInsertImage: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(quill.QuillSimpleToolbar), findsOneWidget);
    expect(find.byIcon(Icons.format_bold), findsOneWidget);
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
    expect(tester.getSize(find.byType(NoteQuillToolbar)).height, lessThan(90));
  });
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

NoteAsset _imageAsset() {
  final now = DateTime.utc(2026, 7, 23, 12);
  return NoteAsset(
    id: NoteAttachmentId.parse('3d2be3d5-00c8-4f5c-8e69-e90085dc2873'),
    kind: NoteAssetKind.image,
    storageKey: 'images/3d2be3d5.png',
    originalName: '原图.png',
    byteLength: _onePixelPng.length,
    mimeType: 'image/png',
    createdAt: now,
    updatedAt: now,
  );
}

final class _EditorTestApp extends StatelessWidget {
  const _EditorTestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      quill.FlutterQuillLocalizations.delegate,
    ],
    home: Scaffold(body: SizedBox.expand(child: child)),
  );
}
