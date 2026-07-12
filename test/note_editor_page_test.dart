import 'dart:io';

import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/pages/home_page.dart';
import 'package:fknotes/pages/local_chat_page.dart';
import 'package:fknotes/pages/media_detail_page.dart';
import 'package:fknotes/pages/note_editor_page.dart';
import 'package:fknotes/pages/transcript_editor_page.dart';
import 'package:fknotes/providers/app_lock_controller.dart';
import 'package:fknotes/providers/note_provider.dart';
import 'package:fknotes/services/app_lock_preferences_service.dart';
import 'package:fknotes/services/device_authentication_service.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/video_import_service.dart';
import 'package:fknotes/widgets/note_block_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
    await _pumpHomePage(tester);

    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();

    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('拍照 OCR'), findsNothing);
    expect(find.text('图片'), findsWidgets);
  });

  testWidgets('home opens the standalone local chat', (tester) async {
    _usePhoneViewport(tester);
    await _pumpHomePage(tester);

    expect(find.byTooltip('本地助手'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-local-chat')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LocalChatPage), findsOneWidget);
    expect(find.text('本地助手'), findsOneWidget);
    expect(find.byTooltip('角色设定'), findsOneWidget);

    await tester.tap(find.byTooltip('角色设定'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'opening role sheet');
    final promptField = find.byKey(const Key('local-chat-system-prompt'));
    expect(promptField, findsOneWidget);
    expect(
      tester.widget<TextField>(promptField).textAlignVertical,
      TextAlignVertical.top,
    );
    await tester.enterText(promptField, '你是一位测试助手');
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'editing role prompt');
    await tester.tap(find.text('保存设定'));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'starting sheet dismissal');
    await tester.pumpAndSettle();
    expect(promptField, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('data tab shows the installed version and build metadata', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    PackageInfo.setMockInitialValues(
      appName: '非空笔记',
      packageName: 'com.fknotes.app',
      version: '2.3.4',
      buildNumber: '57',
      buildSignature: '',
    );

    await _pumpHomePage(tester);
    await tester.tap(find.text('数据'));
    await tester.pumpAndSettle();
    expect(find.text('本地数据'), findsOneWidget);
    expect(find.text('应用锁'), findsOneWidget);
    expect(find.text('资料占用'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.text('关于'), findsOneWidget);
    expect(find.textContaining('版本号 2.3.4 (57)'), findsOneWidget);
    expect(find.textContaining('构建时间 未记录'), findsOneWidget);
    expect(find.text('重建数据索引'), findsNothing);
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
    expect(find.byTooltip('本地助手'), findsOneWidget);
    expect(find.byTooltip('加粗'), findsOneWidget);
    expect(find.byTooltip('斜体'), findsOneWidget);
    expect(find.byTooltip('段落样式'), findsOneWidget);
    expect(find.byTooltip('下划线'), findsOneWidget);
    expect(find.byTooltip('字号'), findsOneWidget);
    expect(find.byTooltip('列表与缩进'), findsOneWidget);
    expect(find.byTooltip('更多格式'), findsOneWidget);
    expect(find.byTooltip('实时语音输入'), findsOneWidget);
    expect(find.byTooltip('朗读笔记'), findsOneWidget);
    expect(find.byTooltip('预览排版'), findsNothing);

    await tester.ensureVisible(find.byTooltip('更多格式'));
    await tester.tap(find.byTooltip('更多格式'));
    await tester.pumpAndSettle();
    expect(find.text('删除线'), findsOneWidget);
    expect(find.byIcon(Icons.strikethrough_s_rounded), findsOneWidget);
    expect(find.text('行内代码'), findsOneWidget);
    expect(find.text('添加链接'), findsOneWidget);
    await tester.tap(find.text('删除线'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('朗读笔记'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('需要离线朗读模型'), findsOneWidget);
    expect(find.textContaining('140.2 MB'), findsOneWidget);
    expect(find.text('管理模型'), findsOneWidget);

    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('实时语音输入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('实时语音输入'));
    await tester.pumpAndSettle();

    expect(find.text('需要实时语音模型'), findsOneWidget);
    expect(find.textContaining('159.6 MB'), findsOneWidget);
    expect(find.text('管理模型'), findsOneWidget);

    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('字号'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('字号'));
    await tester.pumpAndSettle();

    expect(find.text('14'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);

    await tester.tap(find.text('24'));
    await tester.pumpAndSettle();

    expect(find.text('24'), findsOneWidget);
  });

  testWidgets('Markdown content stays in the live structured editor', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final entry = NoteEntry(
      type: NoteType.text,
      title: '预览测试',
      content: '# 标题\n\n**重点**\n\n| 项目 | 状态 |\n| --- | --- |\n| 基础 | 完成 |',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
        child: MaterialApp(home: NoteEditorPage(existingEntry: entry)),
      ),
    );

    expect(find.byType(NoteBlockEditor), findsOneWidget);
    expect(find.byKey(const Key('note-markdown-preview-body')), findsNothing);
    expect(find.byTooltip('预览排版'), findsNothing);
    expect(find.text('**重点**'), findsNothing);
    final editorFields = tester.widgetList<TextField>(
      find.descendant(
        of: find.byType(NoteBlockEditor),
        matching: find.byType(TextField),
      ),
    );
    final visibleText = editorFields
        .map((field) => field.controller?.text ?? '')
        .join('\n');
    expect(visibleText, contains('标题'));
    expect(visibleText, contains('重点'));
    expect(visibleText, contains('项目'));
    expect(visibleText, contains('状态'));
  });

  testWidgets('editor exposes the local assistant action', (tester) async {
    _usePhoneViewport(tester);
    final entry = NoteEntry(
      type: NoteType.text,
      title: '助手测试',
      content: '需要总结的笔记',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
        child: MaterialApp(home: NoteEditorPage(existingEntry: entry)),
      ),
    );

    expect(find.byTooltip('本地助手'), findsOneWidget);
    final assistantButton = find.descendant(
      of: find.byKey(const Key('note-editor-assistant')),
      matching: find.byType(IconButton),
    );
    final onAssistant = tester.widget<IconButton>(assistantButton).onPressed;
    expect(onAssistant, isNotNull);

    await tester.tap(find.byTooltip('更多笔记操作'));
    await tester.pumpAndSettle();
    final assistantItem = find.byWidgetPredicate(
      (widget) =>
          widget is PopupMenuItem<String> && widget.value == 'assistant',
    );
    expect(assistantItem, findsNothing);
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
  });

  testWidgets('tag editor uses a bottom sheet and saves unique tags', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
        child: const MaterialApp(home: NoteEditorPage()),
      ),
    );

    await tester.tap(find.text('添加标签'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('使用逗号分隔多个标签，重复标签会自动合并。'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('note-tags-field')),
      '工作，灵感, 工作',
    );
    await tester.pump();
    expect(find.text('2/8'), findsOneWidget);
    expect(find.text('#工作'), findsOneWidget);
    expect(find.text('#灵感'), findsOneWidget);

    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-note-tags')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('#工作'), findsOneWidget);
    expect(find.text('#灵感'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
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

  testWidgets('audio detail offers optional local transcription', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final now = DateTime(2026, 7, 10);
    final attachment = NoteAttachment(
      type: NoteType.audio,
      filePath: 'audio/voice.m4a',
      fileName: 'voice.m4a',
      fileSize: 1024,
      mimeType: 'audio/mp4',
      createdAt: now,
    );
    final entry = NoteEntry(
      id: 99,
      type: NoteType.audio,
      title: '语音想法',
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
    await tester.pump();

    await tester.tap(find.widgetWithText(Tab, '转写文字'));
    await tester.pumpAndSettle();

    expect(find.text('需要离线识别模型'), findsOneWidget);
    expect(find.text('在线下载约 228 MB'), findsOneWidget);
    expect(find.text('从文件导入'), findsOneWidget);
    expect(find.text('查看全部模型'), findsOneWidget);
    expect(find.textContaining('音频不会离开设备'), findsOneWidget);
  });

  testWidgets('audio transcript opens a full-screen editor', (tester) async {
    _usePhoneViewport(tester);
    final now = DateTime(2026, 7, 10);
    final attachment = NoteAttachment(
      type: NoteType.audio,
      filePath: 'audio/transcribed.m4a',
      fileName: 'transcribed.m4a',
      fileSize: 1024,
      mimeType: 'audio/mp4',
      transcript: '已有转写文字',
      createdAt: now,
    );
    final entry = NoteEntry(
      type: NoteType.audio,
      title: '语音笔记',
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
    await tester.pump();

    await tester.tap(find.widgetWithText(Tab, '转写文字'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑文字'));
    await tester.pumpAndSettle();

    expect(find.byType(TranscriptEditorPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byKey(const Key('cancel-transcript-edit')));
    await tester.pumpAndSettle();
    expect(find.byType(TranscriptEditorPage), findsNothing);
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

    await tester.ensureVisible(find.byTooltip('段落样式'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('段落样式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('引用'));
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

Future<void> _pumpHomePage(WidgetTester tester) async {
  final appLock = AppLockController(
    preferencesStore: _DisabledAppLockPreferencesStore(),
    authenticator: _UnusedDeviceAuthenticator(),
    observeLifecycle: false,
  );
  await appLock.initialize();
  addTearDown(appLock.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appLock),
        ChangeNotifierProvider(create: (_) => NoteProvider()),
      ],
      child: const MaterialApp(home: HomePage()),
    ),
  );
}

class _DisabledAppLockPreferencesStore implements AppLockPreferencesStore {
  @override
  Future<AppLockPreferences> load() async => const AppLockPreferences();

  @override
  Future<void> save(AppLockPreferences preferences) async {}
}

class _UnusedDeviceAuthenticator implements DeviceAuthenticator {
  @override
  Future<DeviceAuthenticationResult> authenticate({
    required String reason,
  }) async => throw StateError('Authentication should not be requested');

  @override
  Future<bool> isSupported() async => false;
}
