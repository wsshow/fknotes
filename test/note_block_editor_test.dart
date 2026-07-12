import 'package:fknotes/app.dart';
import 'package:fknotes/widgets/note_block_editor.dart';
import 'package:fknotes/models/note_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('block codec preserves readable text and renumbers ordered lists', () {
    final blocks = NoteBlockCodec.decode(
      '想法\n\n---\n\n1. 第一项\n8. 第二项\n- [x] 已完成\n\n> 一段引用',
    );

    expect(blocks[1].type, NoteBlockType.divider);
    expect(blocks[2].type, NoteBlockType.ordered);
    expect(blocks[4].checked, isTrue);
    expect(
      NoteBlockCodec.encode(blocks),
      '想法\n\n---\n\n1. 第一项\n2. 第二项\n- [x] 已完成\n\n> 一段引用',
    );
  });

  test('GFM AST maps assistant Markdown into editable semantic blocks', () {
    const source = '''# 方案

**重点**、*说明*、~~旧稿~~、`code` 与 [链接](https://example.com)

- [x] 已完成

```dart
print('ok');
```

| 项目 | 状态 |
| --- | ---: |
| 基础 | 完成 |
''';

    final blocks = NoteBlockCodec.decode(source);

    expect(blocks.map((block) => block.type), [
      NoteBlockType.heading,
      NoteBlockType.paragraph,
      NoteBlockType.todo,
      NoteBlockType.code,
      NoteBlockType.rawMarkdown,
    ]);
    expect(blocks.first.headingLevel, 1);
    final paragraph = blocks[1];
    expect(paragraph.text, '重点、说明、旧稿、code 与 链接');
    NoteTextAttributes attributesAt(String value) {
      final offset = paragraph.text.indexOf(value);
      return paragraph.styles
          .firstWhere((range) => range.start <= offset && range.end > offset)
          .attributes;
    }

    expect(attributesAt('重点').bold, isTrue);
    expect(attributesAt('说明').italic, isTrue);
    expect(attributesAt('旧稿').strikethrough, isTrue);
    expect(attributesAt('code').inlineCode, isTrue);
    expect(attributesAt('链接').link, 'https://example.com');
    expect(blocks[2].checked, isTrue);
    expect(blocks[3].codeLanguage, 'dart');
    expect(blocks[3].text, "print('ok');");
    expect(blocks[4].text, contains('| 项目 | 状态 |'));

    final encoded = NoteBlockCodec.encode(blocks);
    expect(NoteBlockCodec.structurallyMatches(blocks, encoded), isTrue);
  });

  test('Markdown table data preserves cells, escaping and alignment', () {
    final table = MarkdownTableData.tryParse(
      '| 名称 | 说明 |\n| :--- | ---: |\n| FKNotes | 本地 \\| 私密 |',
    )!;

    expect(table.headers, ['名称', '说明']);
    expect(table.rows.single, ['FKNotes', '本地 | 私密']);
    expect(table.alignments, [
      MarkdownTableAlignment.left,
      MarkdownTableAlignment.right,
    ]);
    expect(
      table.encode(),
      '| 名称 | 说明 |\n| :--- | ---: |\n| FKNotes | 本地 \\| 私密 |',
    );
  });

  test('standard GFM markers reopen as semantic block types', () {
    final blocks = NoteBlockCodec.decode('- 条目\n\n1. 顺序\n\n- [ ] 待办\n\n> 引用');

    expect(blocks.map((block) => block.type), [
      NoteBlockType.bullet,
      NoteBlockType.ordered,
      NoteBlockType.todo,
      NoteBlockType.quote,
    ]);
    expect(NoteBlockCodec.visibleCharacterCount('- 条目\n\n---\n\n2. 下一项'), 5);
  });

  test('rich document codec preserves inline styles and block indentation', () {
    final encoded = NoteRichDocumentCodec.encode(const [
      NoteBlockData(
        NoteBlockType.paragraph,
        '重要内容',
        indent: 2,
        styles: [
          NoteTextStyleRange(
            0,
            2,
            NoteTextAttributes(bold: true, underline: true, fontSize: 24),
          ),
        ],
      ),
    ]);

    final decoded = NoteRichDocumentCodec.tryDecode(encoded)!;
    expect(decoded.single.text, '重要内容');
    expect(decoded.single.indent, 2);
    expect(decoded.single.styles.single.start, 0);
    expect(decoded.single.styles.single.end, 2);
    expect(decoded.single.styles.single.attributes.bold, isTrue);
    expect(decoded.single.styles.single.attributes.underline, isTrue);
    expect(decoded.single.styles.single.attributes.fontSize, 24);
    expect(NoteBlockCodec.encode(decoded), '**重要**内容');
  });

  testWidgets(
    'selected formatting emits Markdown and lossless editor metadata',
    (tester) async {
      final controller = TextEditingController(text: '重要内容');
      final editorKey = GlobalKey<NoteBlockEditorState>();
      String? richContent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBlockEditor(
              key: editorKey,
              controller: controller,
              hintText: '开始记录',
              onRichContentChanged: (value) => richContent = value,
            ),
          ),
        ),
      );

      final field = find.byType(TextField).first;
      await tester.tap(field);
      final fieldController = tester.widget<TextField>(field).controller!;
      final start = fieldController.text.indexOf('重');
      fieldController.selection = TextSelection(
        baseOffset: start,
        extentOffset: start + 2,
      );
      editorKey.currentState!.toggleBold();
      editorKey.currentState!.toggleUnderline();
      editorKey.currentState!.setFontSize(24);
      editorKey.currentState!.changeIndent(1);
      await tester.pump();

      final block = NoteRichDocumentCodec.tryDecode(richContent)!.single;
      expect(controller.text, '**重要**内容');
      expect(block.indent, 1);
      expect(block.styles.single.start, 0);
      expect(block.styles.single.end, 2);
      expect(block.styles.single.attributes.bold, isTrue);
      expect(block.styles.single.attributes.underline, isTrue);
      expect(block.styles.single.attributes.fontSize, 24);
      expect(fieldController.selection.baseOffset, start);
      expect(fieldController.selection.extentOffset, start + 2);
      expect(fieldController.selection.isValid, isTrue);
    },
  );

  testWidgets('collapsed formatting applies to text typed next', (
    tester,
  ) async {
    final controller = TextEditingController();
    final editorKey = GlobalKey<NoteBlockEditorState>();
    String? richContent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            key: editorKey,
            controller: controller,
            hintText: '开始记录',
            onRichContentChanged: (value) => richContent = value,
          ),
        ),
      ),
    );

    final field = find.byType(TextField).first;
    await tester.tap(field);
    editorKey.currentState!.toggleBold();
    editorKey.currentState!.toggleUnderline();
    editorKey.currentState!.setFontSize(20);
    await tester.enterText(field, '新文字');
    await tester.pump();

    final block = NoteRichDocumentCodec.tryDecode(richContent)!.single;
    expect(controller.text, '**新文字**');
    expect(block.styles.single.start, 0);
    expect(block.styles.single.end, 3);
    expect(block.styles.single.attributes.bold, isTrue);
    expect(block.styles.single.attributes.underline, isTrue);
    expect(block.styles.single.attributes.fontSize, 20);
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
  });

  testWidgets('Markdown formatting actions preserve links and heading levels', (
    tester,
  ) async {
    final controller = TextEditingController(text: '重要内容');
    final editorKey = GlobalKey<NoteBlockEditorState>();
    String? richContent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            key: editorKey,
            controller: controller,
            hintText: '开始记录',
            onRichContentChanged: (value) => richContent = value,
          ),
        ),
      ),
    );
    final field = find.byType(TextField).first;
    await tester.tap(field);
    final fieldController = tester.widget<TextField>(field).controller!;
    fieldController.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 5,
    );

    editorKey.currentState!.toggleItalic();
    editorKey.currentState!.toggleStrikethrough();
    editorKey.currentState!.setLink('https://example.com');
    await tester.pump();

    var block = NoteRichDocumentCodec.tryDecode(richContent)!.single;
    expect(block.styles.single.attributes.italic, isTrue);
    expect(block.styles.single.attributes.strikethrough, isTrue);
    expect(block.styles.single.attributes.link, 'https://example.com');
    expect(controller.text, '[*~~重要内容~~*](https://example.com)');

    editorKey.currentState!.setHeadingLevel(3);
    await tester.pump();
    block = NoteRichDocumentCodec.tryDecode(richContent)!.single;
    expect(block.type, NoteBlockType.heading);
    expect(block.headingLevel, 3);
    expect(controller.text, '### [*~~重要内容~~*](https://example.com)');
  });

  testWidgets('inline code formatting emits standard Markdown', (tester) async {
    final controller = TextEditingController(text: 'final value');
    final editorKey = GlobalKey<NoteBlockEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            key: editorKey,
            controller: controller,
            hintText: '开始记录',
          ),
        ),
      ),
    );
    final field = find.byType(TextField).first;
    await tester.tap(field);
    tester.widget<TextField>(field).controller!.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 12,
    );

    editorKey.currentState!.toggleInlineCode();
    await tester.pump();

    expect(controller.text, '`final value`');
  });

  testWidgets('underlined words leave whitespace undecorated', (tester) async {
    final controller = TextEditingController(text: '甲 乙');
    final richContent = NoteRichDocumentCodec.encode(const [
      NoteBlockData(
        NoteBlockType.paragraph,
        '甲 乙',
        styles: [NoteTextStyleRange(0, 3, NoteTextAttributes(underline: true))],
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            controller: controller,
            initialRichContent: richContent,
            hintText: '开始记录',
          ),
        ),
      ),
    );

    final field = find.byType(TextField).first;
    final widget = tester.widget<TextField>(field);
    final span = widget.controller!.buildTextSpan(
      context: tester.element(field),
      style: widget.style,
      withComposing: false,
    );
    final visibleSpans = span.children!.whereType<TextSpan>().skip(1).toList();

    expect(visibleSpans.map((child) => child.text), ['甲', ' ', '乙']);
    expect(visibleSpans[0].style?.decoration, TextDecoration.underline);
    expect(visibleSpans[1].style?.decoration, isNull);
    expect(visibleSpans[2].style?.decoration, TextDecoration.underline);
  });

  testWidgets('collapsed font size survives focus restoration', (tester) async {
    final controller = TextEditingController();
    final editorKey = GlobalKey<NoteBlockEditorState>();
    String? richContent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            key: editorKey,
            controller: controller,
            hintText: '开始记录',
            onRichContentChanged: (value) => richContent = value,
          ),
        ),
      ),
    );

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.enterText(field, '正文');
    final focusNode = tester.widget<TextField>(field).focusNode!;
    focusNode.unfocus();
    await tester.pump();

    editorKey.currentState!.setFontSize(24);
    await tester.pump();
    expect(editorKey.currentState!.activeFormat.value.fontSize, 24);
    expect(focusNode.hasFocus, isTrue);

    await tester.enterText(field, '正文大');
    await tester.pump();
    final block = NoteRichDocumentCodec.tryDecode(richContent)!.single;
    expect(block.styles.single.start, 2);
    expect(block.styles.single.end, 3);
    expect(block.styles.single.attributes.fontSize, 24);
  });

  testWidgets('adjacent quote blocks share a continuous border', (
    tester,
  ) async {
    const blocks = [
      NoteBlockData(NoteBlockType.quote, '第一行'),
      NoteBlockData(NoteBlockType.quote, '第二行'),
      NoteBlockData(NoteBlockType.quote, '缩进引用', indent: 1),
      NoteBlockData(NoteBlockType.paragraph, '普通段落'),
    ];
    final controller = TextEditingController(
      text: NoteBlockCodec.encode(blocks),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            controller: controller,
            initialRichContent: NoteRichDocumentCodec.encode(blocks),
            hintText: '开始记录',
          ),
        ),
      ),
    );

    final quoteContainers = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) {
          final decoration = container.decoration;
          final border = decoration is BoxDecoration ? decoration.border : null;
          return border is Border &&
              border.left.width == 2 &&
              border.left.color == AppColors.coral;
        })
        .toList();
    expect(quoteContainers, hasLength(3));
    final [first, second, indented] = quoteContainers;

    expect(first.margin, const EdgeInsets.only(top: 1));
    expect(second.margin, const EdgeInsets.only(bottom: 1));
    expect(indented.margin, const EdgeInsets.only(left: 18, top: 1, bottom: 1));
  });

  testWidgets('undo and redo restore typed text', (tester) async {
    final controller = TextEditingController();
    final editorKey = GlobalKey<NoteBlockEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            key: editorKey,
            controller: controller,
            hintText: '开始记录',
          ),
        ),
      ),
    );

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.enterText(field, '一段');
    await tester.enterText(field, '一段连续输入');
    await tester.pump();

    expect(editorKey.currentState!.historyState.value.canUndo, isTrue);
    editorKey.currentState!.undo();
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(editorKey.currentState!.historyState.value.canRedo, isTrue);

    editorKey.currentState!.redo();
    await tester.pump();
    expect(controller.text, '一段连续输入');
  });

  testWidgets('reviewed assistant output appends safely and is undoable', (
    tester,
  ) async {
    final controller = TextEditingController(text: '原始内容');
    final editorKey = GlobalKey<NoteBlockEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            key: editorKey,
            controller: controller,
            hintText: '开始记录',
          ),
        ),
      ),
    );

    expect(
      editorKey.currentState!.appendAssistantText(
        heading: '本地助手待办',
        text: '- [ ] 提交报告\n\n[[附件:private/secret.txt]]',
      ),
      isTrue,
    );
    await tester.pump();

    expect(controller.text, contains('- [ ] 提交报告'));
    final blocks = NoteBlockCodec.decode(controller.text);
    expect(blocks[1].text, '本地助手待办');
    expect(blocks[2].type, NoteBlockType.todo);
    expect(blocks[3].type, NoteBlockType.paragraph);
    expect(blocks[3].text, '附件引用：private/secret.txt');

    editorKey.currentState!.undo();
    await tester.pump();
    expect(controller.text, '原始内容');
  });

  testWidgets(
    'document history includes formatting, indentation and block type',
    (tester) async {
      final controller = TextEditingController(text: '重要内容');
      final editorKey = GlobalKey<NoteBlockEditorState>();
      String? richContent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBlockEditor(
              key: editorKey,
              controller: controller,
              hintText: '开始记录',
              onRichContentChanged: (value) => richContent = value,
            ),
          ),
        ),
      );

      final field = find.byType(TextField).first;
      await tester.tap(field);
      final fieldController = tester.widget<TextField>(field).controller!;
      final start = fieldController.text.indexOf('重');
      fieldController.selection = TextSelection(
        baseOffset: start,
        extentOffset: start + 2,
      );
      editorKey.currentState!.toggleBold();
      editorKey.currentState!.changeIndent(1);
      editorKey.currentState!.toggleBlock(NoteBlockType.bullet);
      await tester.pump();
      expect(controller.text, '  - **重要**内容');

      editorKey.currentState!.undo();
      await tester.pump();
      var block = NoteRichDocumentCodec.tryDecode(richContent)!.single;
      expect(block.type, NoteBlockType.paragraph);
      expect(block.indent, 1);
      expect(block.styles.single.attributes.bold, isTrue);

      editorKey.currentState!.undo();
      await tester.pump();
      block = NoteRichDocumentCodec.tryDecode(richContent)!.single;
      expect(block.indent, 0);
      expect(block.styles.single.attributes.bold, isTrue);

      editorKey.currentState!.redo();
      await tester.pump();
      block = NoteRichDocumentCodec.tryDecode(richContent)!.single;
      expect(block.indent, 1);
      expect(editorKey.currentState!.historyState.value.canRedo, isTrue);
    },
  );

  test(
    'attachment references round trip without duplicating file metadata',
    () {
      const source = '说明\n[[附件:files/audio/local.m4a]]';
      final blocks = NoteBlockCodec.decode(source);

      expect(blocks.last.type, NoteBlockType.attachment);
      expect(blocks.last.attachmentPath, 'files/audio/local.m4a');
      expect(
        NoteBlockCodec.encode(blocks),
        '说明\n\n[[附件:files/audio/local.m4a]]',
      );
      expect(NoteBlockCodec.visibleCharacterCount(source), 2);
    },
  );

  testWidgets('attachment reference resolves live data and opens it', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: '[[附件:files/audio/local.m4a]]',
    );
    final attachment = NoteAttachment(
      type: NoteType.audio,
      filePath: 'files/audio/local.m4a',
      fileName: '访谈录音.m4a',
      fileSize: 2048,
      mimeType: 'audio/mp4',
      createdAt: DateTime(2026, 7, 10),
    );
    var opened = false;

    Widget app(List<NoteAttachment> attachments) => MaterialApp(
      home: Scaffold(
        body: NoteBlockEditor(
          controller: controller,
          hintText: '开始记录',
          attachments: attachments,
          onOpenAttachment: (_) => opened = true,
        ),
      ),
    );

    await tester.pumpWidget(app([attachment]));
    expect(find.text('访谈录音.m4a'), findsOneWidget);
    expect(find.textContaining('点击预览'), findsOneWidget);
    await tester.tap(find.text('访谈录音.m4a'));
    expect(opened, isTrue);

    await tester.pumpWidget(app(const []));
    await tester.pump();
    expect(find.text('附件已移除'), findsOneWidget);
  });

  testWidgets('table block offers structured row and cell editing', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: '| 项目 | 状态 |\n| :--- | ---: |\n| 基础 | 完成 |',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(controller: controller, hintText: '开始记录'),
        ),
      ),
    );

    expect(find.text('Markdown 表格'), findsOneWidget);
    await tester.tap(find.text('编辑表格'));
    await tester.pumpAndSettle();
    expect(find.text('表头、对齐和单元格会同步保存为标准 GFM 表格。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('markdown-table-add-row')));
    await tester.pump();
    final bodyFields = find.widgetWithText(TextField, '内容');
    expect(bodyFields, findsNWidgets(4));
    await tester.enterText(bodyFields.last, '新增');
    await tester.tap(find.byKey(const Key('markdown-table-save')));
    await tester.pumpAndSettle();

    expect(controller.text, contains('|  | 新增 |'));
    expect(controller.text, contains('| :--- | ---: |'));
  });

  testWidgets('standard divider syntax renders as a real divider', (
    tester,
  ) async {
    final controller = TextEditingController(text: '上方\n\n---\n\n下方');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(controller: controller, hintText: '开始记录'),
        ),
      ),
    );

    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('---'), findsNothing);
  });

  testWidgets('pressing enter continues a bullet list', (tester) async {
    final controller = TextEditingController(text: '- 第一项');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(controller: controller, hintText: '开始记录'),
        ),
      ),
    );

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, '第一项\n');
    await tester.pump();

    expect(controller.text, '- 第一项\n- ');
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('enter on an empty list item exits the list', (tester) async {
    final controller = TextEditingController(text: '- ');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(controller: controller, hintText: '开始记录'),
        ),
      ),
    );

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, '\n');
    await tester.pump();

    expect(controller.text, '');
  });

  for (final block in {
    'bullet': ('- 列表', '列表'),
    'ordered': ('1. 列表', '列表'),
    'todo': ('- [ ] 待办', '待办'),
    'quote': ('> 引用', '引用'),
  }.entries) {
    testWidgets('backspace removes ${block.key} formatting at block start', (
      tester,
    ) async {
      final controller = TextEditingController(text: block.value.$1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBlockEditor(controller: controller, hintText: '开始记录'),
          ),
        ),
      );

      final field = find.byType(TextField).first;
      await tester.tap(field);
      tester.widget<TextField>(field).controller!.selection =
          const TextSelection.collapsed(offset: 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.text, block.value.$2);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    });
  }

  testWidgets('backspace removes an empty paragraph', (tester) async {
    const blocks = [
      NoteBlockData(NoteBlockType.paragraph, '上一行'),
      NoteBlockData(NoteBlockType.paragraph, ''),
      NoteBlockData(NoteBlockType.paragraph, '下一行'),
    ];
    final controller = TextEditingController(
      text: NoteBlockCodec.encode(blocks),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            controller: controller,
            initialRichContent: NoteRichDocumentCodec.encode(blocks),
            hintText: '开始记录',
          ),
        ),
      ),
    );

    final emptyField = find.byType(TextField).at(1);
    await tester.tap(emptyField);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(controller.text, '上一行\n\n下一行');
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('software keyboard backspace removes an empty paragraph', (
    tester,
  ) async {
    const blocks = [
      NoteBlockData(NoteBlockType.paragraph, '上一行'),
      NoteBlockData(NoteBlockType.paragraph, ''),
      NoteBlockData(NoteBlockType.paragraph, '下一行'),
    ];
    final controller = TextEditingController(
      text: NoteBlockCodec.encode(blocks),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            controller: controller,
            initialRichContent: NoteRichDocumentCodec.encode(blocks),
            hintText: '开始记录',
          ),
        ),
      ),
    );

    final emptyField = find.byType(TextField).at(1);
    await tester.showKeyboard(emptyField);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    await tester.pump();

    expect(controller.text, '上一行\n\n下一行');
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('software keyboard backspace removes formatting at block start', (
    tester,
  ) async {
    final controller = TextEditingController(text: '> 引用');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(controller: controller, hintText: '开始记录'),
        ),
      ),
    );

    final field = find.byType(TextField).first;
    await tester.showKeyboard(field);
    final fieldController = tester.widget<TextField>(field).controller!;
    final rawText = fieldController.text;
    fieldController.selection = const TextSelection.collapsed(offset: 1);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: rawText.substring(1),
        selection: const TextSelection.collapsed(offset: 0),
      ),
    );
    await tester.pump();

    expect(controller.text, '引用');
  });

  testWidgets('custom context menu copies only visible editor text', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = TextEditingController(text: '复制测试');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(controller: controller, hintText: '开始记录'),
        ),
      ),
    );

    final field = find.byType(TextField).first;
    await tester.longPressAt(tester.getTopLeft(field) + const Offset(24, 18));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('复制'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
    expect(find.text('查询'), findsNothing);

    await tester.tap(find.text('复制'));
    await tester.pump();
    expect(copiedText, isNotEmpty);
    expect(copiedText, isNot(contains('\u200B')));
  });

  testWidgets('custom context menu pastes clipboard text', (tester) async {
    final controller = TextEditingController();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.hasStrings' => {'value': true},
        'Clipboard.getData' => {'text': '粘贴内容'},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(controller: controller, hintText: '开始记录'),
        ),
      ),
    );

    final field = find.byType(TextField).first;
    await tester.longPress(field);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('粘贴'), findsOneWidget);
    expect(find.byIcon(Icons.content_paste_rounded), findsOneWidget);
    await tester.tap(find.text('粘贴'));
    await tester.pump();

    expect(controller.text, '粘贴内容');
  });

  testWidgets('multi-block Markdown paste creates semantic blocks atomically', (
    tester,
  ) async {
    final controller = TextEditingController();
    final editorKey = GlobalKey<NoteBlockEditorState>();
    String? richContent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            key: editorKey,
            controller: controller,
            hintText: '开始记录',
            onRichContentChanged: (value) => richContent = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField).first);

    expect(
      editorKey.currentState!.pasteMarkdown('# 计划\n\n- [x] 完成基础\n\n**重点**说明'),
      isTrue,
    );
    await tester.pump();

    final blocks = NoteRichDocumentCodec.tryDecode(richContent)!;
    expect(blocks.map((block) => block.type), [
      NoteBlockType.heading,
      NoteBlockType.todo,
      NoteBlockType.paragraph,
    ]);
    expect(blocks[1].checked, isTrue);
    expect(blocks[2].text, '重点说明');
    expect(blocks[2].styles.single.attributes.bold, isTrue);
    expect(controller.text, '# 计划\n\n- [x] 完成基础\n\n**重点**说明');

    editorKey.currentState!.undo();
    await tester.pump();
    expect(controller.text, isEmpty);
  });

  testWidgets('inline Markdown paste keeps the surrounding block and caret', (
    tester,
  ) async {
    final controller = TextEditingController(text: '前后');
    final editorKey = GlobalKey<NoteBlockEditorState>();
    String? richContent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            key: editorKey,
            controller: controller,
            hintText: '开始记录',
            onRichContentChanged: (value) => richContent = value,
          ),
        ),
      ),
    );
    final field = find.byType(TextField).first;
    await tester.tap(field);
    final fieldController = tester.widget<TextField>(field).controller!;
    fieldController.selection = const TextSelection.collapsed(offset: 2);

    expect(editorKey.currentState!.pasteMarkdown('**重点**'), isTrue);
    await tester.pump();

    final block = NoteRichDocumentCodec.tryDecode(richContent)!.single;
    expect(block.text, '前重点后');
    expect(block.styles.single.start, 1);
    expect(block.styles.single.end, 3);
    expect(block.styles.single.attributes.bold, isTrue);
    expect(controller.text, '前**重点**后');
  });

  testWidgets('live dictation replaces partial text as one undoable change', (
    tester,
  ) async {
    final controller = TextEditingController(text: '原有内容');
    final editorKey = GlobalKey<NoteBlockEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            key: editorKey,
            controller: controller,
            hintText: '开始记录',
          ),
        ),
      ),
    );

    expect(editorKey.currentState!.beginDictation(), isTrue);
    editorKey.currentState!.updateDictation('你好');
    await tester.pump();
    expect(controller.text, '原有内容你好');

    editorKey.currentState!.updateDictation('你好世界');
    editorKey.currentState!.finishDictation(keepText: true);
    await tester.pump();
    expect(controller.text, '原有内容你好世界');

    editorKey.currentState!.undo();
    await tester.pump();
    expect(controller.text, '原有内容');
  });

  testWidgets(
    'finalized dictation ignores empty text and follows the current caret',
    (tester) async {
      final controller = TextEditingController(text: '已有');
      final editorKey = GlobalKey<NoteBlockEditorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBlockEditor(
              key: editorKey,
              controller: controller,
              hintText: '开始记录',
            ),
          ),
        ),
      );

      final field = find.byType(TextField).first;
      await tester.tap(field);
      await tester.pump();
      final blockController = tester.widget<TextField>(field).controller!;
      blockController.value = const TextEditingValue(
        text: '已有',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(blockController.selection.extentOffset, 2);
      expect(editorKey.currentState!.prepareDictationInsertion(), isTrue);

      expect(editorKey.currentState!.insertDictationTextAtCaret('   '), isTrue);
      expect(controller.text, '已有');

      expect(editorKey.currentState!.insertDictationTextAtCaret('语音'), isTrue);
      await tester.pump();
      expect(controller.text, '已语音有');

      blockController.value = const TextEditingValue(
        text: '已语音有手动',
        selection: TextSelection.collapsed(offset: 6),
      );
      await tester.pump();
      expect(editorKey.currentState!.insertDictationTextAtCaret('继续'), isTrue);
      await tester.pump();
      expect(controller.text, '已语音有手动继续');

      blockController.value = const TextEditingValue(
        text: '已语音有手动继续拼',
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 8, end: 9),
      );
      expect(editorKey.currentState!.insertDictationTextAtCaret('等待'), isFalse);
      expect(controller.text, '已语音有手动继续拼');
    },
  );

  testWidgets(
    'final offline pass replaces only untouched streaming dictation',
    (tester) async {
      final controller = TextEditingController(text: '已有：');
      final editorKey = GlobalKey<NoteBlockEditorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteBlockEditor(
              key: editorKey,
              controller: controller,
              hintText: '开始记录',
            ),
          ),
        ),
      );

      final field = find.byType(TextField).first;
      await tester.tap(field);
      await tester.pump();
      final blockController = tester.widget<TextField>(field).controller!;
      blockController.selection = TextSelection.collapsed(
        offset: blockController.text.length,
      );
      expect(
        editorKey.currentState!.insertDictationTextAtCaret('一二三这是语音测试'),
        isTrue,
      );
      expect(
        editorKey.currentState!.replaceDictationTextBeforeCaret(
          previous: '一二三这是语音测试',
          replacement: '123，这是语音测试。',
        ),
        isTrue,
      );
      await tester.pump();
      expect(controller.text, '已有：123，这是语音测试。');

      blockController.selection = const TextSelection.collapsed(offset: 2);
      expect(
        editorKey.currentState!.replaceDictationTextBeforeCaret(
          previous: '123，这是语音测试。',
          replacement: '不能覆盖用户编辑',
        ),
        isFalse,
      );
      expect(controller.text, '已有：123，这是语音测试。');
    },
  );

  testWidgets('canceling live dictation restores the previous document', (
    tester,
  ) async {
    final controller = TextEditingController(text: '不要丢失');
    final editorKey = GlobalKey<NoteBlockEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteBlockEditor(
            key: editorKey,
            controller: controller,
            hintText: '开始记录',
          ),
        ),
      ),
    );

    expect(editorKey.currentState!.beginDictation(), isTrue);
    editorKey.currentState!.updateDictation('临时识别');
    editorKey.currentState!.finishDictation(keepText: false);
    await tester.pump();

    expect(controller.text, '不要丢失');
  });

  testWidgets('large documents coalesce typing and flush without data loss', (
    tester,
  ) async {
    final blocks = List.generate(
      80,
      (index) => NoteBlockData(NoteBlockType.paragraph, '第 $index 段内容'),
    );
    final original = NoteBlockCodec.encode(blocks);
    final controller = TextEditingController(text: original);
    final editorKey = GlobalKey<NoteBlockEditorState>();
    var richUpdates = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NoteBlockEditor(
              key: editorKey,
              controller: controller,
              initialRichContent: NoteRichDocumentCodec.encode(blocks),
              hintText: '开始记录',
              onRichContentChanged: (_) => richUpdates++,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '已修改');
    expect(controller.text, original);
    expect(richUpdates, 0);

    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.text, startsWith('已修改'));
    expect(richUpdates, 1);

    await tester.enterText(find.byType(TextField).first, '再次修改');
    final rich = editorKey.currentState!.flushPendingChanges();
    expect(controller.text, startsWith('再次修改'));
    expect(NoteRichDocumentCodec.tryDecode(rich)!.first.text, '再次修改');
  });
}
