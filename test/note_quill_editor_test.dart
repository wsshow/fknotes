// The pinned Flutter Quill clipboard hooks are intentionally exercised here.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:fknotes/app.dart';
import 'package:fknotes/editor/note_assistant_editing.dart';
import 'package:fknotes/editor/note_editor_controller.dart';
import 'package:fknotes/editor/note_markdown_codec.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/note_audio_playback_service.dart';
import 'package:fknotes/widgets/note_quill_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
        expect(snapshot.document.toDelta().toJson(), [
          {'insert': '前文\n'},
          {'insert': NoteEmbed.attachment(asset.id).toDeltaData()},
          {'insert': '\n后文\n'},
        ]);
        expect(
          controller.quillController.selection,
          const TextSelection.collapsed(offset: 5),
        );
        expect(controller.isAttachmentEmbedAtOffset(3), isTrue);
        expect(controller.isAttachmentEmbedAtOffset(4), isTrue);
        expect(controller.isAttachmentEmbedAtOffset(5), isFalse);
      },
    );

    test(
      'inserts dropped images at the requested document offset in order',
      () {
        final first = _imageAsset();
        final second = _imageAsset('72b9ed8e-983d-4b35-9032-0bb05c456e45');
        final controller = NoteEditorController(
          document: NoteDocument.fromPlainText('前\n后'),
          assets: const [],
        );
        addTearDown(controller.dispose);

        controller.insertAssetAt(first, 2);
        controller.insertAssetAt(second, 4);

        final snapshot = controller.snapshot();
        expect(snapshot.assets, [first, second]);
        expect(snapshot.document.toDelta().toJson(), [
          {'insert': '前\n'},
          {'insert': NoteEmbed.attachment(first.id).toDeltaData()},
          {'insert': '\n'},
          {'insert': NoteEmbed.attachment(second.id).toDeltaData()},
          {'insert': '\n后\n'},
        ]);
      },
    );

    test('moves a media block atomically without changing its asset', () {
      final image = _imageAsset();
      final audio = _audioAsset();
      final original = Delta()
        ..insert(NoteEmbed.attachment(image.id).toDeltaData())
        ..insert('\n正文\n')
        ..insert(NoteEmbed.attachment(audio.id).toDeltaData())
        ..insert('\n');
      final controller = NoteEditorController(
        document: NoteDocument.fromDelta(original),
        assets: [image, audio],
      );
      addTearDown(controller.dispose);

      expect(
        controller.moveAssetEmbed(
          attachmentId: image.id,
          sourceOffset: 0,
          targetOffset: controller.quillController.document.length,
        ),
        isTrue,
      );
      expect(controller.snapshot().assets, [audio, image]);
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '正文\n'},
        {'insert': NoteEmbed.attachment(audio.id).toDeltaData()},
        {'insert': '\n'},
        {'insert': NoteEmbed.attachment(image.id).toDeltaData()},
        {'insert': '\n'},
      ]);

      controller.quillController.undo();
      expect(
        controller.snapshot().document.toDelta().toJson(),
        original.toJson(),
      );
    });

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

    test('plain-text Markdown paste becomes native Quill formatting', () async {
      final controller = NoteEditorController(
        document: NoteDocument.empty(),
        assets: const [],
        readClipboardText: () async => '''
# 标题

正文 **加粗** 和 *斜体*

- 项目

1. 步骤

> 引用

```dart
final value = 1;
```
''',
      );
      addTearDown(controller.dispose);

      expect(await controller.quillController.clipboardPaste(), isTrue);

      final snapshot = controller.snapshot();
      final delta = snapshot.document.toDelta();
      expect(
        snapshot.document.project().plainText,
        '标题\n正文 加粗 和 斜体\n项目\n步骤\n引用\nfinal value = 1;',
      );
      expect(snapshot.document.project().plainText, isNot(contains('**')));
      expect(
        delta.operations,
        contains(
          isA<Operation>()
              .having((operation) => operation.data, 'text', '加粗')
              .having(
                (operation) => operation.attributes?['bold'],
                'bold',
                isTrue,
              ),
        ),
      );
      expect(
        delta.operations
            .where((operation) => operation.data == '\n')
            .map((operation) => operation.attributes)
            .whereType<Map<String, dynamic>>(),
        containsAll([
          containsPair('header', 1),
          containsPair('list', 'bullet'),
          containsPair('list', 'ordered'),
          containsPair('blockquote', true),
          containsPair('code-block', true),
        ]),
      );
    });

    test('ordinary plain-text paste stays on Quill native path', () async {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('原文'),
        assets: const [],
        readClipboardText: () async => '普通文本，没有 Markdown 语义。',
      );
      addTearDown(controller.dispose);
      final paste =
          controller.quillController.config.clipboardConfig!.onClipboardPaste!;

      expect(await paste(), isFalse);
      expect(controller.snapshot().document.project().plainText, '原文');
    });

    test('inline Markdown paste keeps the surrounding paragraph', () async {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('前后'),
        assets: const [],
        readClipboardText: () async => '**重点**',
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection.collapsed(offset: 1),
        quill.ChangeSource.local,
      );

      expect(await controller.quillController.clipboardPaste(), isTrue);
      expect(controller.snapshot().document.project().plainText, '前重点后');
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '前'},
        {
          'insert': '重点',
          'attributes': {'bold': true},
        },
        {'insert': '后\n'},
      ]);
    });

    test('block Markdown paste starts on a clean line', () async {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('前后'),
        assets: const [],
        readClipboardText: () async => '# 标题',
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection.collapsed(offset: 1),
        quill.ChangeSource.local,
      );

      expect(await controller.quillController.clipboardPaste(), isTrue);
      expect(controller.snapshot().document.project().plainText, '前\n标题\n后');
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '前\n标题'},
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {'insert': '后\n'},
      ]);
    });

    test('discards imported files when an embed cannot be inserted', () async {
      final asset = _imageAsset();
      NoteAsset? discarded;
      final document = NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n'),
      );
      final controller = NoteEditorController(
        document: document,
        assets: [asset],
        importImage: (_) async => asset,
        discardImportedAsset: (value) async => discarded = value,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.importImageBytes(Uint8List.fromList([1])),
        throwsArgumentError,
      );

      expect(discarded, asset);
      expect(controller.snapshot().assets, [asset]);
    });

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

    test('AI Markdown becomes native Delta formatting and list blocks', () {
      final delta = NoteMarkdownCodec.decode(
        '## 摘要\n\n**重点**与 [链接](https://example.com)\n\n- 一\n- 二',
      );
      final document = NoteDocument.fromDelta(delta);

      expect(document.project().plainText, '摘要\n重点与 链接\n一\n二');
      expect(delta.toJson(), [
        {'insert': '摘要'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {
          'insert': '重点',
          'attributes': {'bold': true},
        },
        {'insert': '与 '},
        {
          'insert': '链接',
          'attributes': {'link': 'https://example.com'},
        },
        {'insert': '\n一'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
        {'insert': '二'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
      ]);
    });

    test('Markdown tables and rules become structured block embeds', () {
      final delta = NoteMarkdownCodec.decode('''
| 项目 | 状态 |
| :--- | ---: |
| Quill | 完成 |
| 分享图 | 待检查 |

---
''');
      final document = NoteDocument.fromDelta(delta);
      final embeds = delta.operations
          .where((operation) => operation.data is! String)
          .map((operation) => NoteEmbed.parse(operation.data))
          .toList(growable: false);

      expect(embeds.map((embed) => embed.kind), [
        NoteEmbedKind.table,
        NoteEmbedKind.divider,
      ]);
      expect(embeds.first.table!.rows, const [
        ['项目', '状态'],
        ['Quill', '完成'],
        ['分享图', '待检查'],
      ]);
      expect(embeds.first.table!.alignments, const [
        NoteTableAlignment.start,
        NoteTableAlignment.end,
      ]);
      expect(document.project().plainText, contains('Quill\t完成'));
      expect(document.project().plainText, isNot(contains('|')));
      expect(document.project().plainText, isNot(contains('---')));
    });

    test('AI selection replacement is one native document transaction', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('保留 需要润色 结尾'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection(baseOffset: 3, extentOffset: 7),
        quill.ChangeSource.local,
      );
      final anchor = controller.captureAssistantAnchor();

      final applied = controller.applyAssistantMarkdown(
        anchor: anchor,
        scope: NoteAssistantEditScope.selection,
        placement: NoteAssistantEditPlacement.replace,
        markdown: '**已润色**',
      );

      expect(applied, isTrue);
      expect(controller.snapshot().document.project().plainText, '保留 已润色 结尾');
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '保留 '},
        {
          'insert': '已润色',
          'attributes': {'bold': true},
        },
        {'insert': ' 结尾\n'},
      ]);
    });

    test('streamed AI insertion can be undone as one complete action', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('保留 需要改写 结尾'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection(baseOffset: 3, extentOffset: 7),
        quill.ChangeSource.local,
      );

      final session = controller.beginAssistantInsertion();
      expect(controller.updateAssistantInsertion(session, '**草稿**'), isTrue);
      expect(controller.updateAssistantInsertion(session, '**最终稿**'), isTrue);
      controller.finishAssistantInsertion(session);

      expect(controller.snapshot().document.project().plainText, '保留 最终稿 结尾');
      expect(controller.revertAssistantInsertion(session), isTrue);
      expect(controller.snapshot().document.project().plainText, '保留 需要改写 结尾');
      expect(
        controller.quillController.selection,
        const TextSelection(baseOffset: 3, extentOffset: 7),
      );
    });

    test('AI refuses stale anchors after the user keeps editing', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('原文'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      final anchor = controller.captureAssistantAnchor();
      controller.quillController.replaceText(
        0,
        0,
        '新',
        const TextSelection.collapsed(offset: 1),
      );

      expect(
        controller.applyAssistantMarkdown(
          anchor: anchor,
          scope: NoteAssistantEditScope.document,
          placement: NoteAssistantEditPlacement.replace,
          markdown: '生成结果',
        ),
        isFalse,
      );
      expect(controller.snapshot().document.project().plainText, '新原文');
    });

    test('AI appends below the current line without merging paragraphs', () {
      final controller = NoteEditorController(
        document: NoteDocument.fromPlainText('第一行\n第二行'),
        assets: const [],
      );
      addTearDown(controller.dispose);
      controller.quillController.updateSelection(
        const TextSelection.collapsed(offset: 2),
        quill.ChangeSource.local,
      );
      final anchor = controller.captureAssistantAnchor();

      expect(
        controller.applyAssistantMarkdown(
          anchor: anchor,
          scope: NoteAssistantEditScope.currentLine,
          placement: NoteAssistantEditPlacement.insertBelow,
          markdown: '插入行',
        ),
        isTrue,
      );
      expect(
        controller.snapshot().document.project().plainText,
        '第一行\n插入行\n第二行',
      );
    });
  });

  testWidgets('editor and card preview share the paper-themed code style', (
    tester,
  ) async {
    final document = NoteDocument.fromDelta(
      Delta()
        ..insert('final answer = 42;')
        ..insert('\n', {'code-block': true}),
    );
    final controller = NoteEditorController(
      document: document,
      assets: const [],
    );
    final now = DateTime.utc(2026, 7, 23, 12);
    final note = Note(
      id: NoteId.generate(),
      title: '代码笔记',
      document: document,
      assets: const [],
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: Column(
          children: [
            Expanded(child: NoteQuillEditor(controller: controller)),
            SizedBox(height: 180, child: NoteRichDocumentPreview(note: note)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editors = tester
        .widgetList<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .toList();
    expect(editors, hasLength(2));
    for (final editor in editors) {
      final styles = editor.config.customStyles!;
      final code = styles.code!;
      expect(code.style.color, AppColors.ink);
      expect(code.decoration!.color, AppColors.paperSecondary);
      expect(code.decoration!.border, Border.all(color: AppColors.line));
      expect(styles.inlineCode!.backgroundColor, AppColors.accentSoft);
      expect(styles.inlineCode!.style.color, AppColors.mechanicalBlue);
    }
  });

  testWidgets(
    'reveals copy edit details and delete actions only after tapping an image',
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
      final focusNode = FocusNode();
      var copyCalls = 0;
      var editCalls = 0;
      var viewOriginalCalls = 0;
      var detailsCalls = 0;
      final testImage = await _createTestImage(320, 320);
      final imageProvider = _SynchronousTestImageProvider(testImage);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(testImage.dispose);

      await tester.pumpWidget(
        _EditorTestApp(
          child: NoteQuillEditor(
            controller: controller,
            focusNode: focusNode,
            resolveImage: (_) => imageProvider,
            onCopyImage: (_) async => copyCalls++,
            onEditImage: (_) async => editCalls++,
            onViewImageOriginal: (_) async => viewOriginalCalls++,
            onShowImageDetails: (_) async => detailsCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final imageFinder = find.byKey(ValueKey('note-image-${asset.id.value}'));
      final editorFinder = find.byType(NoteQuillEditor);
      expect(imageFinder, findsOneWidget);
      expect(
        find.byKey(ValueKey('note-image-frame-${asset.id.value}')),
        findsNothing,
      );
      final imageSize = tester.getSize(imageFinder);
      expect(
        imageSize.width,
        closeTo(tester.getSize(editorFinder).width - 48, 1),
      );
      expect(imageSize.height, closeTo(imageSize.width, 1));
      expect(
        imageSize.height,
        greaterThan(260),
        reason: '图片高度应由原始比例决定，不再受旧的 260dp 上限约束',
      );
      expect(
        find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('remove-note-asset-${asset.id.value}')),
        findsNothing,
      );

      await tester.drag(imageFinder, const Offset(0, -80), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
        findsNothing,
      );

      await tester.ensureVisible(
        find.byKey(ValueKey('note-asset-${asset.id.value}')),
      );
      await tester.pumpAndSettle();
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      final visibleImageRect = tester.getRect(imageFinder);
      final visibleEditorRect = tester.getRect(editorFinder);
      await tester.tapAt(visibleImageRect.intersect(visibleEditorRect).center);
      await tester.pump(const Duration(milliseconds: 350));
      expect(focusNode.hasFocus, isFalse);
      expect(
        find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
        findsOneWidget,
      );
      final imageSelection = tester.widget<DecoratedBox>(
        find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
      );
      expect(
        (imageSelection.decoration as BoxDecoration).border,
        Border.all(color: AppColors.accent, width: 2),
      );

      final imageSelectionTarget = find.byKey(
        ValueKey('note-image-selection-target-${asset.id.value}'),
      );
      final imageTapArea = tester
          .getRect(imageSelectionTarget)
          .intersect(
            Rect.fromLTRB(
              visibleEditorRect.left,
              visibleEditorRect.top,
              visibleEditorRect.right,
              visibleEditorRect.bottom - 112,
            ),
          );
      await tester.tapAt(imageTapArea.center);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
        findsNothing,
      );

      final restoredImageTapArea = tester
          .getRect(imageSelectionTarget)
          .intersect(visibleEditorRect);
      await tester.tapAt(restoredImageTapArea.center);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(ValueKey('note-image-actions-${asset.id.value}')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(ValueKey('view-original-note-image-${asset.id.value}')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('copy-note-image-${asset.id.value}')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('edit-note-image-${asset.id.value}')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('details-note-image-${asset.id.value}')),
      );
      await tester.pump();
      expect(viewOriginalCalls, 1);
      expect(copyCalls, 1);
      expect(editCalls, 1);
      expect(detailsCalls, 1);

      await tester.tap(
        find.byKey(ValueKey('remove-note-asset-${asset.id.value}')),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(controller.snapshot().assets, isEmpty);
      expect(controller.snapshot().document.project().plainText, '图片之前\n图片之后');
    },
  );

  testWidgets('renders and controls an inline recording card', (tester) async {
    final asset = _audioAsset();
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
          ..insert('\n'),
      ),
      assets: [asset],
    );
    final playback = _FakeAudioPlaybackDriver();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(playback.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: NoteQuillEditor(
          controller: controller,
          focusNode: focusNode,
          audioPlayback: playback,
          resolveAssetPath: (_) => '/managed/recording.m4a',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('note-asset-${asset.id.value}')),
      findsOneWidget,
    );
    expect(find.text('产品讨论'), findsOneWidget);
    expect(find.text('01:32'), findsOneWidget);
    expect(
      find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
      findsNothing,
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    await tester.tap(find.byKey(ValueKey('play-note-audio-${asset.id.value}')));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
    expect(playback.activeAssetId, asset.id.value);
    expect(playback.lastPath, '/managed/recording.m4a');
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    final audioSelection = tester.widget<DecoratedBox>(
      find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
    );
    expect(
      (audioSelection.decoration as BoxDecoration).border,
      Border.all(color: AppColors.accent, width: 2),
    );

    final audioSelectionTarget = find.byKey(
      ValueKey('note-audio-selection-target-${asset.id.value}'),
    );
    var audioTargetRect = tester.getRect(audioSelectionTarget);
    await tester.tapAt(
      Offset(audioTargetRect.center.dx, audioTargetRect.top + 4),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
      findsNothing,
    );

    audioTargetRect = tester.getRect(audioSelectionTarget);
    await tester.tapAt(
      Offset(audioTargetRect.center.dx, audioTargetRect.top + 4),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(ValueKey('note-asset-selection-${asset.id.value}')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ValueKey('note-audio-actions-${asset.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改标题'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const Key('attachment-title-count')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('cancel-attachment-title'))).width,
      tester.getSize(find.byKey(const Key('save-attachment-title'))).width,
    );
    await tester.enterText(
      find.byKey(const Key('audio-attachment-title')),
      '周会录音',
    );
    await tester.tap(find.byKey(const Key('save-attachment-title')));
    await tester.pumpAndSettle();

    expect(controller.assets.single.displayTitle, '周会录音');

    await tester.tap(
      find.byKey(ValueKey('note-audio-actions-${asset.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改标题'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore-attachment-title')));
    await tester.pumpAndSettle();

    expect(controller.assets.single.displayTitle, 'recording.m4a');
  });

  testWidgets('long press drag reorders image and recording blocks', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final image = _imageAsset();
    final audio = _audioAsset();
    final controller = NoteEditorController(
      document: NoteDocument.fromDelta(
        Delta()
          ..insert(NoteEmbed.attachment(image.id).toDeltaData())
          ..insert('\n中间正文\n')
          ..insert(NoteEmbed.attachment(audio.id).toDeltaData())
          ..insert('\n'),
      ),
      assets: [image, audio],
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

    final imageHandle = find.byKey(
      ValueKey('move-note-asset-${image.id.value}'),
    );
    final audioCard = find.byKey(ValueKey('note-asset-${audio.id.value}'));
    final gesture = await tester.startGesture(tester.getCenter(imageHandle));
    await tester.pump(const Duration(milliseconds: 420));
    await gesture.moveTo(
      tester.getRect(audioCard).bottomCenter - const Offset(0, 2),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const Key('note-asset-drop-indicator')), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.snapshot().document.project().referencedAttachmentIds, [
      audio.id,
      image.id,
    ]);
    controller.quillController.undo();
    await tester.pumpAndSettle();
    expect(controller.snapshot().document.project().referencedAttachmentIds, [
      image.id,
      audio.id,
    ]);

    final audioHandle = find.byKey(
      ValueKey('move-note-asset-${audio.id.value}'),
    );
    final imageCard = find.byKey(ValueKey('note-asset-${image.id.value}'));
    final audioGesture = await tester.startGesture(
      tester.getCenter(audioHandle),
    );
    await tester.pump(const Duration(milliseconds: 420));
    await audioGesture.moveTo(
      tester.getRect(imageCard).topCenter + const Offset(0, 2),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await audioGesture.up();
    await tester.pumpAndSettle();

    expect(controller.snapshot().document.project().referencedAttachmentIds, [
      audio.id,
      image.id,
    ]);
  });

  testWidgets('accepts multiline text through the native input connection', (
    tester,
  ) async {
    final controller = NoteEditorController(
      document: NoteDocument.empty(),
      assets: const [],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(child: NoteQuillEditor(controller: controller)),
    );
    await tester.pump();
    await tester.tap(find.byType(quill.QuillRawEditor));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '第一行\n第二行\n',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.pump();

    expect(controller.snapshot().document.project().plainText, '第一行\n第二行');
  });

  testWidgets(
    'converts Android IME Markdown paste before raw text reaches the document',
    (tester) async {
      final controller = NoteEditorController(
        document: NoteDocument.empty(),
        assets: const [],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _EditorTestApp(child: NoteQuillEditor(controller: controller)),
      );
      await tester.pump();
      await tester.tap(find.byType(quill.QuillRawEditor));
      await tester.pump();
      const pasted = '# 系统粘贴\n\n正文 **重点**\n';
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: pasted,
          selection: TextSelection.collapsed(offset: pasted.length - 1),
        ),
      );
      await tester.pump();

      expect(controller.snapshot().document.project().plainText, '系统粘贴\n正文 重点');
      expect(controller.snapshot().document.toDelta().toJson(), [
        {'insert': '系统粘贴'},
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {'insert': '正文 '},
        {
          'insert': '重点',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]);

      controller.quillController.undo();
      expect(controller.snapshot().document.project().isVisuallyEmpty, isTrue);
    },
  );

  testWidgets(
    'renders pasted Markdown table and reveals block actions only after tap',
    (tester) async {
      final controller = NoteEditorController(
        document: NoteDocument.empty(),
        assets: const [],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _EditorTestApp(child: NoteQuillEditor(controller: controller)),
      );
      await tester.pump();
      await tester.tap(find.byType(quill.QuillRawEditor));
      await tester.pump();
      const pasted = '''
| 项目 | 状态 |
| :--- | ---: |
| Quill | 完成 |

---
''';
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: pasted,
          selection: TextSelection.collapsed(offset: pasted.length - 1),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('项目'), findsOneWidget);
      expect(find.text('状态'), findsOneWidget);
      expect(find.text('Quill'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.byKey(const ValueKey('remove-note-table')), findsNothing);
      expect(find.byKey(const ValueKey('remove-note-divider')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('note-table-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('remove-note-table')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('note-divider-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('remove-note-divider')), findsOneWidget);
      expect(find.byKey(const ValueKey('remove-note-table')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets('provides a single-row rich text toolbar', (tester) async {
    final controller = NoteEditorController(
      document: NoteDocument.empty(),
      assets: const [],
    );
    var doneCalls = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _EditorTestApp(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: NoteQuillToolbar(
            controller: controller,
            onOpenAssistant: () {},
            onInsertImage: () {},
            onRecordAudio: () {},
            onDone: () => doneCalls++,
            doneLabel: '完成',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final actions = tester.widget<Row>(
      find.byKey(const Key('quill-toolbar-actions')),
    );
    expect(actions.children.map((child) => child.key).toList(), const [
      Key('quill-open-inline-assistant'),
      Key('quill-insert-image'),
      Key('quill-record-audio'),
      Key('quill-toolbar-undo'),
      Key('quill-toolbar-redo'),
      Key('quill-toolbar-bold'),
      Key('quill-toolbar-checklist'),
      Key('quill-toolbar-bullets'),
      Key('quill-toolbar-numbered-list'),
      Key('quill-toolbar-quote'),
      Key('quill-toolbar-italic'),
      Key('quill-toolbar-underline'),
      Key('quill-toolbar-heading'),
      Key('quill-toolbar-link'),
      Key('quill-toolbar-divider'),
      Key('quill-toolbar-clear-format'),
    ]);
    expect(find.byType(quill.QuillSimpleToolbar), findsNothing);
    expect(find.byIcon(Icons.format_bold), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(find.byIcon(Icons.code), findsNothing);
    expect(find.byIcon(Icons.format_strikethrough), findsNothing);
    expect(find.byIcon(Icons.format_indent_increase), findsNothing);
    expect(find.byIcon(Icons.format_indent_decrease), findsNothing);

    final assistantButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('quill-open-inline-assistant')),
        matching: find.byType(IconButton),
      ),
    );
    final imageButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('quill-insert-image')),
        matching: find.byType(IconButton),
      ),
    );
    final recordingButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('quill-record-audio')),
        matching: find.byType(IconButton),
      ),
    );
    expect(assistantButton.style, isNull);
    expect(imageButton.style, isNull);
    expect(recordingButton.style, isNull);
    final doneButton = find.byKey(const Key('quill-toolbar-done'));
    final scrollView = find.byKey(const Key('quill-toolbar-scroll-view'));
    expect(doneButton, findsOneWidget);
    expect(find.descendant(of: scrollView, matching: doneButton), findsNothing);
    expect(
      find.descendant(of: doneButton, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(tester.getSize(doneButton).width, lessThan(60));
    final doneButtonRect = tester.getRect(doneButton);
    await tester.drag(scrollView, const Offset(-300, 0));
    await tester.pump();
    expect(tester.getRect(doneButton), doneButtonRect);
    await tester.tap(doneButton);
    expect(doneCalls, 1);
    expect(tester.getSize(find.byType(NoteQuillToolbar)).height, lessThan(90));
  });
}

Future<ui.Image> _createTestImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const Color(0xFF587086),
  );
  return recorder.endRecording().toImage(width, height);
}

final class _SynchronousTestImageProvider extends ImageProvider<int> {
  const _SynchronousTestImageProvider(this.image);

  final ui.Image image;

  @override
  Future<int> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<int>(identityHashCode(this));

  @override
  ImageStreamCompleter loadImage(int key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
      );
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

NoteAsset _imageAsset([String id = '3d2be3d5-00c8-4f5c-8e69-e90085dc2873']) {
  final now = DateTime.utc(2026, 7, 23, 12);
  return NoteAsset(
    id: NoteAttachmentId.parse(id),
    kind: NoteAssetKind.image,
    storageKey: 'notes/images/$id.png',
    originalName: '原图.png',
    byteLength: _onePixelPng.length,
    mimeType: 'image/png',
    createdAt: now,
    updatedAt: now,
  );
}

NoteAsset _audioAsset() {
  final now = DateTime.utc(2026, 7, 23, 12);
  return NoteAsset(
    id: NoteAttachmentId.parse('94ee8ed8-4637-40e1-8c91-ff6df6593605'),
    kind: NoteAssetKind.audio,
    storageKey: 'notes/audio/94ee8ed8.m4a',
    originalName: 'recording.m4a',
    displayName: '产品讨论',
    byteLength: 4096,
    mimeType: 'audio/mp4',
    durationMs: 92340,
    createdAt: now,
    updatedAt: now,
  );
}

final class _FakeAudioPlaybackDriver extends ChangeNotifier
    implements NoteAudioPlaybackDriver {
  String? lastPath;

  @override
  String? activeAssetId;

  @override
  Duration duration = Duration.zero;

  @override
  String? errorMessage;

  @override
  Duration position = Duration.zero;

  @override
  NoteAudioPlaybackStatus status = NoteAudioPlaybackStatus.idle;

  @override
  Future<void> seek({
    required String assetId,
    required Duration position,
  }) async {
    if (activeAssetId != assetId) return;
    this.position = position;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    activeAssetId = null;
    status = NoteAudioPlaybackStatus.idle;
    notifyListeners();
  }

  @override
  Future<void> toggle({
    required String assetId,
    required String filePath,
  }) async {
    activeAssetId = assetId;
    lastPath = filePath;
    duration = const Duration(milliseconds: 92340);
    status = status == NoteAudioPlaybackStatus.playing
        ? NoteAudioPlaybackStatus.paused
        : NoteAudioPlaybackStatus.playing;
    notifyListeners();
  }
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
