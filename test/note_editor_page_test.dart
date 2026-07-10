import 'dart:io';

import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/pages/home_page.dart';
import 'package:fknotes/pages/media_detail_page.dart';
import 'package:fknotes/pages/note_editor_page.dart';
import 'package:fknotes/providers/note_provider.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/video_import_service.dart';
import 'package:fknotes/widgets/note_block_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory storageDirectory;

  setUpAll(() async {
    storageDirectory = await Directory.systemTemp.createTemp(
      'fknotes_widget_test_',
    );
    await FileStorageService.instance.init(baseDir: storageDirectory.path);
  });

  tearDownAll(() async {
    await storageDirectory.delete(recursive: true);
  });

  testWidgets('capture sheet keeps camera and OCR as separate actions', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
        child: const MaterialApp(home: HomePage()),
      ),
    );

    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();

    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('拍照 OCR'), findsNothing);
    expect(find.text('图片'), findsWidgets);
  });

  testWidgets('tapping below the body editor focuses the final text block', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
        child: const MaterialApp(home: NoteEditorPage()),
      ),
    );

    final surface = find.byKey(const Key('note-editor-scroll-surface'));
    final editor = find.byType(NoteBlockEditor);
    final surfaceRect = tester.getRect(surface);
    final editorRect = tester.getRect(editor);
    final blankPoint = Offset(surfaceRect.center.dx, surfaceRect.bottom - 8);
    expect(blankPoint.dy, greaterThan(editorRect.bottom));

    await tester.tapAt(blankPoint);
    await tester.pump();

    final bodyField = find.descendant(
      of: editor,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(bodyField).focusNode?.hasFocus, isTrue);
  });

  testWidgets('single-line toolbar exposes formatting and history actions', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
        child: const MaterialApp(home: NoteEditorPage()),
      ),
    );

    expect(find.textContaining('已保存在本机 · 0 字'), findsOneWidget);
    expect(find.byTooltip('撤销'), findsOneWidget);
    expect(find.byTooltip('重做'), findsOneWidget);
    expect(find.byTooltip('加粗'), findsOneWidget);
    expect(find.byTooltip('下划线'), findsOneWidget);
    expect(find.byTooltip('字号'), findsOneWidget);
    expect(find.byTooltip('增加缩进'), findsOneWidget);

    await tester.tap(find.byTooltip('字号'));
    await tester.pumpAndSettle();

    expect(find.text('14'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
  });

  testWidgets('editor image imports do not present OCR as a capture mode', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
        child: const MaterialApp(home: NoteEditorPage()),
      ),
    );

    await tester.tap(find.byTooltip('添加图片、录音或文件'));
    await tester.pumpAndSettle();

    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('拍照 OCR'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('image detail offers OCR only as an explicit follow-up action', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final now = DateTime(2026, 7, 10);
    final attachment = NoteAttachment(
      type: NoteType.image,
      filePath: 'files/images/photo.jpg',
      fileName: 'photo.jpg',
      fileSize: 1,
      mimeType: 'image/jpeg',
      createdAt: now,
    );
    final entry = NoteEntry(
      type: NoteType.image,
      title: '照片',
      attachments: [attachment],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
        child: MaterialApp(
          home: MediaDetailPage(entry: entry, attachment: attachment),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(Tab, '识别文字'));
    await tester.pumpAndSettle();

    expect(find.text('暂无识别文字'), findsOneWidget);
    expect(find.text('需要时可对这张图片进行本地文字识别'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '识别文字'), findsOneWidget);
    expect(find.text('重新识别'), findsNothing);
  });

  testWidgets('video import card reports progress without blocking editing', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final now = DateTime(2026, 7, 10);
    final entry = NoteEntry(
      id: 42,
      type: NoteType.video,
      title: '现场记录',
      createdAt: now,
      updatedAt: now,
      attachments: const [],
    );
    const jobId = 'video-import-test';
    VideoImportService.instance.addJobForTesting(
      const VideoImportJob(
        id: jobId,
        fileName: '现场视频.mp4',
        mimeType: 'video/mp4',
        totalBytes: 14 * 1024 * 1024,
        copiedBytes: 7 * 1024 * 1024,
        noteId: 42,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
        child: MaterialApp(home: NoteEditorPage(existingEntry: entry)),
      ),
    );
    await tester.pump();

    expect(find.text('现场视频.mp4'), findsOneWidget);
    expect(find.textContaining('正在导入 50%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final bodyField = find.byType(TextField).at(1);
    await tester.tap(bodyField);
    await tester.enterText(bodyField, '导入视频时仍然可以继续记录');
    expect(
      tester.widget<TextField>(bodyField).controller?.text,
      contains('导入视频时仍然可以继续记录'),
    );
    expect(find.textContaining('正在导入 50%'), findsOneWidget);

    VideoImportService.instance.dismiss(jobId);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'image import card appears before thumbnail processing completes',
    (tester) async {
      _usePhoneViewport(tester);
      final now = DateTime(2026, 7, 10);
      final entry = NoteEntry(
        id: 43,
        type: NoteType.image,
        title: '现场照片',
        createdAt: now,
        updatedAt: now,
        attachments: const [],
      );
      const jobId = 'image-import-test';
      AttachmentImportService.instance.addJobForTesting(
        const AttachmentImportJob(
          id: jobId,
          type: NoteType.image,
          fileName: '现场照片.jpg',
          mimeType: 'image/jpeg',
          totalBytes: 800 * 1024,
          copiedBytes: 800 * 1024,
          noteId: 43,
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => NoteProvider(),
          child: MaterialApp(home: NoteEditorPage(existingEntry: entry)),
        ),
      );
      await tester.pump();

      expect(find.text('现场照片.jpg'), findsOneWidget);
      expect(find.text('正在生成缩略图…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      AttachmentImportService.instance.dismiss(jobId);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('quote formatting keeps the keyboard, focus and caret', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
        child: const MaterialApp(home: NoteEditorPage()),
      ),
    );
    await tester.pump();

    final bodyField = find.byType(TextField).at(1);
    await tester.tap(bodyField);
    await tester.enterText(bodyField, '测试引用');

    final field = tester.widget<TextField>(bodyField);
    final controller = field.controller!;
    final focusNode = field.focusNode!;
    controller.selection = const TextSelection.collapsed(offset: 2);

    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byTooltip('引用'));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(controller.selection, const TextSelection.collapsed(offset: 2));

    // Dispose the page before its autosave debounce reaches the database.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(1080, 2400);
  addTearDown(tester.view.reset);
}
