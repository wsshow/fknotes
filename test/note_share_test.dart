import 'dart:io';
import 'dart:typed_data';

import 'package:fknotes/app.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/models/note_share.dart';
import 'package:fknotes/pages/note_share_composer_page.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/note_share_image_service.dart';
import 'package:fknotes/services/note_share_layout_engine.dart';
import 'package:fknotes/widgets/note_share_page_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storageRoot;
  late Directory temporaryRoot;

  setUpAll(() async {
    await initializeDateFormatting('zh');
    storageRoot = await Directory.systemTemp.createTemp('fknotes_share_store_');
    temporaryRoot = await Directory.systemTemp.createTemp(
      'fknotes_share_temp_',
    );
    await FileStorageService.instance.init(baseDir: storageRoot.path);
  });

  tearDownAll(() async {
    await storageRoot.delete(recursive: true);
    await temporaryRoot.delete(recursive: true);
  });

  test('canvas presets and custom limits produce deterministic dimensions', () {
    expect(
      const NoteShareCanvasSpec().pixelSize,
      const NoteSharePixelSize(1080, 1440),
    );
    expect(
      const NoteShareCanvasSpec(
        preset: NoteShareCanvasPreset.storyNineSixteen,
      ).pixelSize,
      const NoteSharePixelSize(1080, 1920),
    );
    expect(
      const NoteShareCanvasSpec(
        preset: NoteShareCanvasPreset.landscapeSixteenNine,
        orientation: NoteShareOrientation.landscape,
      ).pixelSize,
      const NoteSharePixelSize(1920, 1080),
    );
    final bounded = const NoteShareCanvasSpec(
      preset: NoteShareCanvasPreset.custom,
      customWidth: 4096,
      customHeight: 12000,
    ).pixelSize;
    expect(bounded.pixels, lessThanOrEqualTo(NoteShareCanvasSpec.maxPixels));
    expect(
      bounded.width,
      greaterThanOrEqualTo(NoteShareCanvasSpec.minCustomSide),
    );
  });

  test('share options round trip through the local preference payload', () {
    const options = NoteShareOptions(
      template: NoteShareTemplateId.night,
      canvas: NoteShareCanvasSpec(
        preset: NoteShareCanvasPreset.custom,
        orientation: NoteShareOrientation.landscape,
        customWidth: 1600,
        customHeight: 900,
      ),
      density: NoteShareDensity.compact,
      includeDate: false,
      includeImages: false,
    );
    final restored = NoteShareOptions.fromJson(options.toJson());
    expect(restored.template, options.template);
    expect(restored.canvas.pixelSize, options.canvas.pixelSize);
    expect(restored.density, options.density);
    expect(restored.includeDate, isFalse);
    expect(restored.includeImages, isFalse);
  });

  test('share draft keeps repeated embeds but deduplicates asset loading', () {
    final now = DateTime.utc(2026, 7, 23);
    final asset = NoteAsset(
      id: NoteAttachmentId.generate(),
      kind: NoteAssetKind.image,
      storageKey: 'notes/images/repeated.png',
      originalName: 'repeated.png',
      byteLength: 12,
      mimeType: 'image/png',
      createdAt: now,
      updatedAt: now,
    );
    final blocks = [
      NoteShareBlock(type: NoteShareBlockType.attachment, asset: asset),
      NoteShareBlock(type: NoteShareBlockType.paragraph, text: '图片说明'),
      NoteShareBlock(type: NoteShareBlockType.attachment, asset: asset),
    ];
    final draft = NoteShareDraft(
      title: '重复图片',
      blocks: blocks,
      tags: const [],
      createdAt: now,
      updatedAt: now,
    );

    expect(
      draft.blocks.where(
        (block) => block.type == NoteShareBlockType.attachment,
      ),
      hasLength(2),
    );
    expect(draft.attachments, [same(asset)]);
  });

  test('share layout preserves tall image geometry without cropping', () {
    final asset = _imageAsset('notes/images/tall-layout.png');
    final draft = _draft(
      blocks: [
        NoteShareBlock(type: NoteShareBlockType.attachment, asset: asset),
      ],
    );
    final layout = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: const NoteShareOptions(
        canvas: NoteShareCanvasSpec(preset: NoteShareCanvasPreset.long),
      ),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
      imageAspectRatios: {asset.id: .25},
    );
    final sharedImage = layout.pages.single.blocks.single;

    expect(sharedImage.imageHeight, greaterThan(1000));
    expect(
      layout.pages.single.bodyHeight,
      closeTo(
        sharedImage.imageHeight! + NoteShareLayoutEngine.attachmentBottomGap,
        .01,
      ),
    );
  });

  test('fixed share cards scale an oversized image into the page body', () {
    final asset = _imageAsset('notes/images/tall-card.png');
    final draft = _draft(
      blocks: [
        NoteShareBlock(type: NoteShareBlockType.attachment, asset: asset),
      ],
    );
    final layout = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: const NoteShareOptions(
        canvas: NoteShareCanvasSpec(preset: NoteShareCanvasPreset.square),
      ),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
      imageAspectRatios: {asset.id: .1},
    );
    final page = layout.pages.single;
    final sharedImage = page.blocks.single;

    expect(sharedImage.imageHeight, isNotNull);
    expect(
      sharedImage.imageHeight! + NoteShareLayoutEngine.attachmentBottomGap,
      lessThanOrEqualTo(page.bodyHeight),
    );
  });

  testWidgets('share canvas contains the full image at its measured ratio', (
    tester,
  ) async {
    const storageKey = 'notes/images/tall-share.png';
    await tester.runAsync(
      () => File('assets/brand/fknotes_icon.png').copy(
        FileStorageService.instance.absolutePath(storageKey),
      ),
    );
    final asset = _imageAsset(storageKey);
    final draft = _draft(
      blocks: [
        NoteShareBlock(type: NoteShareBlockType.attachment, asset: asset),
      ],
    );
    const options = NoteShareOptions(
      canvas: NoteShareCanvasSpec(preset: NoteShareCanvasPreset.long),
    );
    final layout = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: options,
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
      imageAspectRatios: {asset.id: .25},
    );
    tester.view.physicalSize = Size(500, layout.logicalHeight + 100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: NoteSharePageCanvas(
            draft: draft,
            options: options,
            layout: layout,
            pageIndex: 0,
            untitledTitle: '一则笔记',
            sourceLabel: '来自「非空笔记」',
            locale: const Locale('zh'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final image = tester.widget<Image>(
      find.byKey(ValueKey('note-share-image-${asset.id.value}')),
    );
    expect(image.fit, BoxFit.contain);
    expect(
      tester
          .getSize(
            find.byKey(ValueKey('note-share-image-frame-${asset.id.value}')),
          )
          .height,
      closeTo(
        layout.pages.single.blocks.single.imageHeight! +
            NoteShareLayoutEngine.attachmentBottomGap,
        .01,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('layout paginates long content without dropping text', () {
    final content = List.generate(
      24,
      (index) => '第${index + 1}段：认真记录每一个普通时刻，让文字替我们保存当时的想法。',
    ).join('\n\n');
    final draft = _draft(content: content);
    final layout = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: const NoteShareOptions(),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );
    expect(layout.pages.length, greaterThan(1));
    final output = layout.pages
        .expand((page) => page.blocks)
        .map((item) => item.block.text)
        .join();
    final source = draft.blocks.map((block) => block.text).join();
    expect(output, source);

    final story = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: const NoteShareOptions(
        canvas: NoteShareCanvasSpec(
          preset: NoteShareCanvasPreset.storyNineSixteen,
        ),
      ),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );
    expect(story.pages.length, lessThan(layout.pages.length));

    final longImage = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: const NoteShareOptions(
        canvas: NoteShareCanvasSpec(preset: NoteShareCanvasPreset.long),
      ),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );
    expect(longImage.pages, hasLength(1));
    expect(longImage.outputPixelSize.height, greaterThan(1920));
    expect(
      longImage.outputPixelSize.height,
      lessThanOrEqualTo(NoteShareCanvasSpec.maxCustomHeight),
    );
    final longOutput = longImage.pages.single.blocks
        .map((item) => item.block.text)
        .join();
    expect(longOutput, source);
  });

  test('long image dimensions stay stable while switching templates', () {
    final draft = _draft(
      content: List.generate(
        18,
        (index) => '第${index + 1}段：同一篇笔记切换视觉样式时，长图画布尺寸不应发生变化。',
      ).join('\n\n'),
    );
    final sizes = <NoteSharePixelSize>{
      for (final template in NoteShareTemplateId.values)
        const NoteShareLayoutEngine()
            .paginate(
              draft: draft,
              options: NoteShareOptions(
                template: template,
                canvas: const NoteShareCanvasSpec(
                  preset: NoteShareCanvasPreset.long,
                ),
              ),
              textDirection: TextDirection.ltr,
              untitledTitle: '一则笔记',
            )
            .outputPixelSize,
    };
    expect(sizes, hasLength(1));
  });

  test('share layout paginates tables by row and repeats the header', () {
    final table = NoteTable(
      rows: [
        const ['序号', '项目', '状态'],
        for (var index = 1; index <= 28; index++)
          ['$index', '检查项 $index', index.isEven ? '完成' : '待处理'],
      ],
      alignments: const [
        NoteTableAlignment.end,
        NoteTableAlignment.start,
        NoteTableAlignment.center,
      ],
    );
    final draft = _draft(
      blocks: [NoteShareBlock(type: NoteShareBlockType.table, table: table)],
    );

    final layout = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: const NoteShareOptions(),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );
    final tableBlocks = layout.pages
        .expand((page) => page.blocks)
        .map((item) => item.block)
        .where((block) => block.type == NoteShareBlockType.table)
        .toList(growable: false);
    final restoredRows = [
      tableBlocks.first.table!.rows.first,
      for (final block in tableBlocks) ...block.table!.rows.skip(1),
    ];

    expect(tableBlocks.length, greaterThan(1));
    expect(
      tableBlocks.every(
        (block) =>
            block.table!.rows.first.join('|') == table.rows.first.join('|'),
      ),
      isTrue,
    );
    expect(restoredRows, table.rows);
  });

  testWidgets('share canvas renders table cells as a bordered grid', (
    tester,
  ) async {
    final table = NoteTable(
      rows: const [
        ['项目', '状态'],
        ['Quill', '完成'],
      ],
    );
    final draft = _draft(
      blocks: [NoteShareBlock(type: NoteShareBlockType.table, table: table)],
    );
    const options = NoteShareOptions();
    final layout = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: options,
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteSharePageCanvas(
            draft: draft,
            options: options,
            layout: layout,
            pageIndex: 0,
            untitledTitle: '一则笔记',
            sourceLabel: '来自「非空笔记」',
            locale: const Locale('zh'),
          ),
        ),
      ),
    );

    expect(find.byType(Table), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('share layout preserves lossless inline formatting from the editor', () {
    final blocks = [
      NoteShareBlock(
        type: NoteShareBlockType.paragraph,
        text: 'qq，，，aaa 与斜体',
        styles: [
          NoteShareTextRange(0, 5, NoteShareTextStyle(bold: true)),
          NoteShareTextRange(10, 12, NoteShareTextStyle(italic: true)),
        ],
      ),
    ];
    final draft = _draft(blocks: blocks);

    final layout = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: const NoteShareOptions(),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );
    final shared = layout.pages.single.blocks.single.block;

    expect(shared.text, blocks.single.text);
    expect(shared.styles, hasLength(2));
    expect(shared.styles.first.style.bold, isTrue);
    expect(shared.styles.last.style.italic, isTrue);
  });

  testWidgets('share canvas renders bold and italic spans instead of markers', (
    tester,
  ) async {
    final blocks = [
      NoteShareBlock(
        type: NoteShareBlockType.paragraph,
        text: 'qq，，，aaa 与斜体',
        styles: [
          NoteShareTextRange(0, 5, NoteShareTextStyle(bold: true)),
          NoteShareTextRange(10, 12, NoteShareTextStyle(italic: true)),
        ],
      ),
    ];
    final draft = _draft(blocks: blocks);
    const options = NoteShareOptions();
    final layout = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: options,
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteSharePageCanvas(
            draft: draft,
            options: options,
            layout: layout,
            pageIndex: 0,
            untitledTitle: '一则笔记',
            sourceLabel: '来自「非空笔记」',
            locale: const Locale('zh'),
          ),
        ),
      ),
    );

    final body = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere(
          (widget) => widget.text.toPlainText() == blocks.single.text,
        );
    final spans = _textSpans(body.text as TextSpan).toList();
    expect(
      spans.any(
        (span) =>
            span.text == 'qq，，，' && span.style?.fontWeight == FontWeight.w700,
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) =>
            span.text == '斜体' && span.style?.fontStyle == FontStyle.italic,
      ),
      isTrue,
    );
    expect(body.text.toPlainText(), isNot(contains('**')));
  });

  test('fixed cards use remaining page space before continuing', () {
    final longParagraph = List.filled(90, '把文字自然排满当前信纸，再把余下内容延续到下一页。').join();
    final draft = _draft(content: '短引子。\n\n$longParagraph');
    final layout = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: const NoteShareOptions(),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );

    expect(layout.pages.length, greaterThan(1));
    expect(layout.pages.first.blocks, hasLength(greaterThan(1)));
    final output = layout.pages
        .expand((page) => page.blocks)
        .map((item) => item.block.text)
        .join();
    final source = draft.blocks.map((block) => block.text).join();
    expect(output, source);
  });

  test('tags share the footer row instead of reserving body height', () {
    final draft = _draft();
    final withTags = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: const NoteShareOptions(),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );
    final withoutTags = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: const NoteShareOptions(includeTags: false),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );

    expect(withTags.pages.first.bodyHeight, withoutTags.pages.first.bodyHeight);
  });

  test('image service writes ordered, safe PNG file names', () async {
    final service = NoteShareImageService(
      temporaryDirectoryProvider: () async => temporaryRoot,
    );
    final session = await service.createSession();
    final first = await service.writePage(
      session: session,
      bytes: Uint8List.fromList([1, 2, 3]),
      title: '旅行/随笔:夏天',
      pageIndex: 0,
      pageCount: 2,
    );
    final second = await service.writePage(
      session: session,
      bytes: Uint8List.fromList([4, 5]),
      title: '旅行/随笔:夏天',
      pageIndex: 1,
      pageCount: 2,
    );
    expect(first.path, endsWith('fknotes-旅行-随笔-夏天-01-of-02.png'));
    expect(second.path, endsWith('fknotes-旅行-随笔-夏天-02-of-02.png'));
    expect(await first.readAsBytes(), [1, 2, 3]);
    await service.deleteSession(session);
    expect(await session.exists(), isFalse);
  });

  testWidgets('composer switches templates and ratios while keeping source', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: NoteShareComposerPage(draft: _draft()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('制作分享图'), findsOneWidget);
    expect(find.text('来自「非空笔记」'), findsWidgets);
    expect(
      find.byKey(const ValueKey('note-share-source-mark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('note-share-paper-texture')),
      findsOneWidget,
    );
    final letterSheet = tester.widget<Container>(
      find.byKey(const ValueKey('note-share-paper-sheet-letter')),
    );
    final letterDecoration = letterSheet.decoration! as BoxDecoration;
    expect(letterDecoration.color, AppColors.paperPrimary);
    expect(letterDecoration.border, Border.all(color: AppColors.line));
    expect(
      letterDecoration.borderRadius,
      BorderRadius.circular(AppRadius.small),
    );
    expect(letterDecoration.boxShadow, isNotEmpty);
    expect(
      tester.widget<Text>(find.text('把今天写成一封信')).style?.color,
      AppColors.ink,
    );
    final styleChips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(styleChips, hasLength(NoteShareTemplateId.values.length));
    expect(NoteShareTemplateId.values.length, greaterThanOrEqualTo(13));
    expect(styleChips.every((chip) => chip.avatar == null), isTrue);

    final letterChip = find.widgetWithText(ChoiceChip, '一封非空来信');
    expect(tester.widget<ChoiceChip>(letterChip).showCheckmark, isFalse);

    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    final nightChip = find.widgetWithText(ChoiceChip, '夜读');
    await tester.tap(nightChip);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(nightChip).selected, isTrue);
    expect(
      find.byKey(const ValueKey('note-share-night-backdrop')),
      findsOneWidget,
    );

    final ratioField = find.byType(
      DropdownButtonFormField<NoteShareCanvasPreset>,
    );
    await tester.ensureVisible(ratioField);
    await tester.tap(ratioField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1:1 · 方形卡片').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('1080 × 1080'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all card styles keep a footer safe area without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const canvases = [
      NoteShareCanvasSpec(preset: NoteShareCanvasPreset.square),
      NoteShareCanvasSpec(preset: NoteShareCanvasPreset.noteThreeFour),
      NoteShareCanvasSpec(preset: NoteShareCanvasPreset.storyNineSixteen),
      NoteShareCanvasSpec(
        preset: NoteShareCanvasPreset.landscapeSixteenNine,
        orientation: NoteShareOrientation.landscape,
      ),
      NoteShareCanvasSpec(preset: NoteShareCanvasPreset.long),
    ];
    final draft = _poemDraft();

    for (final template in NoteShareTemplateId.values) {
      for (final canvas in canvases) {
        final options = NoteShareOptions(
          template: template,
          canvas: canvas,
          density: NoteShareDensity.comfortable,
        );
        final layout = const NoteShareLayoutEngine().paginate(
          draft: draft,
          options: options,
          textDirection: TextDirection.ltr,
          untitledTitle: '一则笔记',
        );
        for (var pageIndex = 0; pageIndex < layout.pages.length; pageIndex++) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: NoteSharePageCanvas(
                    draft: draft,
                    options: options,
                    layout: layout,
                    pageIndex: pageIndex,
                    untitledTitle: '一则笔记',
                    sourceLabel: '来自「非空笔记」',
                    locale: const Locale('zh'),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            tester
                .widget<Align>(
                  find.byKey(
                    ValueKey('note-share-paper-alignment-${template.name}'),
                  ),
                )
                .alignment,
            Alignment.center,
          );
          if (template == NoteShareTemplateId.neon) {
            final sheet = tester.widget<Container>(
              find.byKey(const ValueKey('note-share-paper-sheet-neon')),
            );
            final decoration = sheet.decoration! as BoxDecoration;
            expect(decoration.gradient, isA<LinearGradient>());
            expect((decoration.gradient! as LinearGradient).colors, const [
              Color(0xFFEF4CFF),
              Color(0xFF8B5CF6),
              Color(0xFF43F2D2),
            ]);
            expect(
              find.byKey(const ValueKey('note-share-neon-paper-interior')),
              findsOneWidget,
            );
          }
          expect(
            tester.takeException(),
            isNull,
            reason:
                '${template.name}/${canvas.preset.name}/page $pageIndex overflowed',
          );
          final landscape = layout.logicalHeight < layout.logicalWidth;
          expect(
            tester
                .getSize(find.byKey(const ValueKey('note-share-footer-gap')))
                .height,
            NoteShareLayoutEngine.footerGapFor(landscape),
          );
        }
      }
    }
  });

  testWidgets('long image body height includes compact decorated blocks', (
    tester,
  ) async {
    final blocks = <NoteShareBlock>[
      for (var index = 0; index < 18; index++)
        NoteShareBlock(
          type: NoteShareBlockType.code,
          text:
              'final section$index = "这一段需要完整显示";\n'
              'print(section$index);',
        ),
      NoteShareBlock(
        type: NoteShareBlockType.paragraph,
        text: '这是长图最末尾的正文，不能被底部署名区域截断。',
      ),
    ];
    final draft = _draft(blocks: blocks);
    const options = NoteShareOptions(
      canvas: NoteShareCanvasSpec(preset: NoteShareCanvasPreset.long),
      density: NoteShareDensity.compact,
    );
    final layout = const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: options,
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );
    tester.view.physicalSize = Size(500, layout.logicalHeight + 100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: NoteSharePageCanvas(
            draft: draft,
            options: options,
            layout: layout,
            pageIndex: 0,
            untitledTitle: '一则笔记',
            sourceLabel: '来自「非空笔记」',
            locale: const Locale('zh'),
          ),
        ),
      ),
    );
    await tester.pump();

    final viewportHeight = tester
        .getSize(find.byKey(const ValueKey('note-share-body-viewport')))
        .height;
    final contentHeight = tester
        .getSize(find.byKey(const ValueKey('note-share-body-content')))
        .height;
    expect(
      viewportHeight,
      greaterThanOrEqualTo(contentHeight),
      reason: '长图正文的实际排版高度必须完整落在署名上方',
    );
  });

  testWidgets('composer renders PNG files before invoking system sharing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sharedBytes = <List<int>>[];
    final service = NoteShareImageService(
      temporaryDirectoryProvider: () async => temporaryRoot,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: NoteShareComposerPage(
          draft: _draft(content: '短笔记正文。'),
          imageService: service,
          shareFilesOverride: (files) async {
            for (final file in files) {
              sharedBytes.add(await file.readAsBytes());
            }
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('生成并分享'));
    await tester.pump();
    for (var index = 0; index < 30 && sharedBytes.isEmpty; index++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }

    expect(sharedBytes, isNotEmpty);
    expect(sharedBytes.first.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    for (
      var index = 0;
      index < 20 && find.text('正在生成第 1/1 张图片').evaluate().isNotEmpty;
      index++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(find.text('正在生成第 1/1 张图片'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-image preset exports all content as one tall PNG', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final content = List.generate(
      24,
      (index) => '第${index + 1}段：把这一刻认真写下来，让完整正文进入同一张长图。',
    ).join('\n\n');
    final sharedBytes = <List<int>>[];
    final service = NoteShareImageService(
      temporaryDirectoryProvider: () async => temporaryRoot,
    );
    final expectedLayout = const NoteShareLayoutEngine().paginate(
      draft: _draft(content: content),
      options: const NoteShareOptions(
        canvas: NoteShareCanvasSpec(preset: NoteShareCanvasPreset.long),
      ),
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );
    expect(expectedLayout.outputPixelSize.height, greaterThan(1920));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: NoteShareComposerPage(
          draft: _draft(content: content),
          imageService: service,
          shareFilesOverride: (files) async {
            expect(files, hasLength(1));
            sharedBytes.add(await files.single.readAsBytes());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -620));
    await tester.pumpAndSettle();
    final ratioField = find.byType(
      DropdownButtonFormField<NoteShareCanvasPreset>,
    );
    await tester.ensureVisible(ratioField);
    await tester.tap(ratioField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('长图 · 单张自适应').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(find.text('画布高度随内容延展，全部内容合成一张图片'), findsOneWidget);
    expect(
      find.text('1080 × ${expectedLayout.outputPixelSize.height}'),
      findsOneWidget,
    );
    final canvasSize = tester.getSize(find.byType(NoteSharePageCanvas));
    expect(canvasSize.width, expectedLayout.logicalWidth);
    expect(canvasSize.height, closeTo(expectedLayout.logicalHeight, .01));

    await tester.tap(find.text('生成并分享'));
    await tester.pump();
    for (var index = 0; index < 80 && sharedBytes.isEmpty; index++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }

    expect(sharedBytes, hasLength(1));
    final bytes = sharedBytes.single;
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(_pngDimension(bytes, 16), 1080);
    expect(_pngDimension(bytes, 20), greaterThan(1920));
    expect(tester.takeException(), isNull);
  });
}

int _pngDimension(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

Iterable<TextSpan> _textSpans(TextSpan root) sync* {
  yield root;
  for (final child in root.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) yield* _textSpans(child);
  }
}

NoteShareDraft _draft({
  String content = '有些念头不必立刻成为答案。先把它们写下来，等待未来的某一天重新打开。\n\n> 认真记录过的生活，不会真正消失。',
  List<NoteShareBlock>? blocks,
}) {
  final now = DateTime(2026, 7, 22, 10, 30);
  return NoteShareDraft(
    title: '把今天写成一封信',
    blocks:
        blocks ??
        [
          for (final paragraph in content.split('\n\n'))
            NoteShareBlock(
              type: paragraph.startsWith('> ')
                  ? NoteShareBlockType.quote
                  : NoteShareBlockType.paragraph,
              text: paragraph.startsWith('> ')
                  ? paragraph.substring(2)
                  : paragraph,
            ),
        ],
    tags: const ['生活记录', '今日随想'],
    createdAt: now,
    updatedAt: now,
  );
}

NoteShareDraft _poemDraft() {
  final now = DateTime(2026, 7, 22, 10, 30);
  return NoteShareDraft(
    title: '早春呈水部张十八员外',
    blocks: [
      NoteShareBlock(type: NoteShareBlockType.paragraph, text: '韩愈〔唐代〕'),
      for (var index = 0; index < 5; index++)
        NoteShareBlock(
          type: NoteShareBlockType.paragraph,
          text: '天街小雨润如酥，草色遥看近却无。\n最是一年春好处，绝胜烟柳满皇都。',
        ),
    ],
    tags: const ['唐诗', '早春'],
    createdAt: now,
    updatedAt: now,
  );
}

NoteAsset _imageAsset(String storageKey) {
  final now = DateTime.utc(2026, 7, 29);
  return NoteAsset(
    id: NoteAttachmentId.generate(),
    kind: NoteAssetKind.image,
    storageKey: storageKey,
    originalName: storageKey.split('/').last,
    byteLength: 12,
    mimeType: 'image/png',
    createdAt: now,
    updatedAt: now,
  );
}
