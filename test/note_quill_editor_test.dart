// The pinned Flutter Quill clipboard hooks are intentionally exercised here.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:fknotes/editor/note_assistant_editing.dart';
import 'package:fknotes/editor/note_editor_controller.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/note_audio_playback_service.dart';
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
      final delta = NoteAssistantMarkdownCodec.decode(
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
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _EditorTestApp(
          child: NoteQuillEditor(
            controller: controller,
            focusNode: focusNode,
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

      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      await tester.tapAt(tester.getTopLeft(imageFinder) + const Offset(8, 0.5));
      await tester.pump(const Duration(milliseconds: 350));
      expect(focusNode.hasFocus, isFalse);

      await tester.tap(
        find.byKey(ValueKey('remove-note-asset-${asset.id.value}')),
      );
      await tester.pump();

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

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    await tester.tap(find.byKey(ValueKey('play-note-audio-${asset.id.value}')));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
    expect(playback.activeAssetId, asset.id.value);
    expect(playback.lastPath, '/managed/recording.m4a');
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey('note-audio-actions-${asset.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改标题'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('audio-attachment-title')),
      '周会录音',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(controller.assets.single.displayTitle, '周会录音');
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
          child: NoteQuillToolbar(
            controller: controller,
            onOpenAssistant: () {},
            onInsertImage: () {},
            onRecordAudio: () {},
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
    storageKey: 'notes/images/3d2be3d5.png',
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
