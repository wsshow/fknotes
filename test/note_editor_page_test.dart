import 'dart:io';

import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/pages/home_page.dart';
import 'package:fknotes/pages/media_detail_page.dart';
import 'package:fknotes/pages/note_editor_page.dart';
import 'package:fknotes/providers/note_provider.dart';
import 'package:fknotes/services/file_storage_service.dart';
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
