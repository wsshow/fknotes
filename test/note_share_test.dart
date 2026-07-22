import 'dart:io';
import 'dart:typed_data';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note_share.dart';
import 'package:fknotes/pages/note_share_composer_page.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/note_share_image_service.dart';
import 'package:fknotes/services/note_share_layout_engine.dart';
import 'package:fknotes/widgets/note_block_editor.dart';
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
    final source = NoteBlockCodec.decode(
      content,
    ).map((block) => block.text).join();
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
    final source = NoteBlockCodec.decode(
      draft.content,
    ).map((block) => block.text).join();
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

NoteShareDraft _draft({
  String content = '有些念头不必立刻成为答案。先把它们写下来，等待未来的某一天重新打开。\n\n> 认真记录过的生活，不会真正消失。',
}) {
  final now = DateTime(2026, 7, 22, 10, 30);
  return NoteShareDraft(
    title: '把今天写成一封信',
    content: content,
    tags: const ['生活记录', '今日随想'],
    attachments: const [],
    createdAt: now,
    updatedAt: now,
  );
}

NoteShareDraft _poemDraft() {
  final now = DateTime(2026, 7, 22, 10, 30);
  return NoteShareDraft(
    title: '早春呈水部张十八员外',
    content: [
      '韩愈〔唐代〕',
      ...List.filled(5, '天街小雨润如酥，草色遥看近却无。\n最是一年春好处，绝胜烟柳满皇都。'),
    ].join('\n\n'),
    tags: const ['唐诗', '早春'],
    attachments: const [],
    createdAt: now,
    updatedAt: now,
  );
}
