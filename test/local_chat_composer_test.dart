import 'dart:io';

import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/pages/local_chat_page.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('chat composer exposes text, image and voice inputs on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var sendCount = 0;
    var notePickerCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LocalChatComposer(
            controller: controller,
            focusNode: focusNode,
            generating: false,
            pendingAttachments: const [],
            pendingNoteContexts: const [],
            imageInputAvailable: false,
            pickingImages: false,
            dictating: false,
            dictationPreparing: false,
            onTakePhoto: () {},
            onPickImages: () {},
            onRemoveAttachment: (_) {},
            onPickNoteContexts: () => notePickerCount++,
            onRemoveNoteContext: (_) {},
            onToggleDictation: () {},
            onSend: () => sendCount++,
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('local-chat-take-photo')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-add-note-context')), findsNothing);
    expect(find.byKey(const Key('local-chat-more-actions')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-voice-input')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-input')), findsOneWidget);
    expect(find.byKey(const Key('send-local-chat')), findsNothing);

    await tester.tap(find.byKey(const Key('local-chat-more-actions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-chat-add-menu-image')), findsOneWidget);
    expect(
      find.byKey(const Key('local-chat-add-menu-note-context')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('local-chat-add-menu-note-context')));
    await tester.pumpAndSettle();
    expect(notePickerCount, 1);

    await tester.enterText(
      find.byKey(const Key('local-chat-input')),
      '帮我整理这段内容',
    );
    await tester.pump();

    expect(find.byKey(const Key('send-local-chat')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-voice-input')), findsNothing);
    expect(find.byKey(const Key('local-chat-more-actions')), findsNothing);

    await tester.tap(find.byKey(const Key('send-local-chat')));
    expect(sendCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat composer renders English actions without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var imagePickerCount = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          bottomNavigationBar: LocalChatComposer(
            controller: controller,
            focusNode: focusNode,
            generating: false,
            pendingAttachments: const [],
            pendingNoteContexts: const [],
            imageInputAvailable: true,
            pickingImages: false,
            dictating: false,
            dictationPreparing: false,
            onTakePhoto: () {},
            onPickImages: () => imagePickerCount++,
            onRemoveAttachment: (_) {},
            onPickNoteContexts: () {},
            onRemoveNoteContext: (_) {},
            onToggleDictation: () {},
            onSend: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Take photo'), findsOneWidget);
    expect(find.byTooltip('Voice input'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsOneWidget);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Reference library notes'), findsOneWidget);
    expect(find.text('Add image'), findsOneWidget);
    await tester.tap(find.byKey(const Key('local-chat-add-menu-image')));
    await tester.pumpAndSettle();
    expect(imagePickerCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat composer previews and removes pending note sources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var removed = false;
    final note = LocalChatNoteContext(
      noteId: 12,
      title: '产品路线图',
      scope: LocalChatNoteScope.fullNote,
      content: '路线图正文',
      updatedAt: DateTime(2026),
    );
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LocalChatComposer(
            controller: controller,
            focusNode: focusNode,
            generating: false,
            pendingAttachments: const [],
            pendingNoteContexts: [note],
            imageInputAvailable: true,
            pickingImages: false,
            dictating: false,
            dictationPreparing: false,
            onTakePhoto: () {},
            onPickImages: () {},
            onRemoveAttachment: (_) {},
            onPickNoteContexts: () {},
            onRemoveNoteContext: (_) => removed = true,
            onToggleDictation: () {},
            onSend: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.text('下一条消息将引用'), findsOneWidget);
    expect(find.text('产品路线图'), findsOneWidget);
    await tester.tap(find.byTooltip('移除笔记引用'));
    expect(removed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending images scroll horizontally and open a zoomable preview',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late final Directory root;
      late final List<LocalChatAttachment> attachments;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('fknotes-chat-images');
        await FileStorageService.instance.init(baseDir: root.path);
        final imageBytes = img.encodePng(img.Image(width: 2, height: 2));
        attachments = <LocalChatAttachment>[];
        for (var index = 0; index < 3; index++) {
          final relativePath = 'assistant/$index.png';
          await File(
            FileStorageService.instance.absolutePath(relativePath),
          ).writeAsBytes(imageBytes);
          attachments.add(
            LocalChatAttachment(
              id: 'image-$index',
              type: LocalChatAttachmentType.image,
              filePath: relativePath,
              fileName: '$index.png',
              mimeType: 'image/png',
              createdAt: DateTime(2026),
            ),
          );
        }
      });
      addTearDown(() async => root.delete(recursive: true));
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: LocalChatComposer(
              controller: controller,
              focusNode: focusNode,
              generating: false,
              pendingAttachments: attachments,
              pendingNoteContexts: const [],
              imageInputAvailable: true,
              pickingImages: false,
              dictating: false,
              dictationPreparing: false,
              onTakePhoto: () {},
              onPickImages: () {},
              onRemoveAttachment: (_) {},
              onPickNoteContexts: () {},
              onRemoveNoteContext: (_) {},
              onToggleDictation: () {},
              onSend: () {},
              onStop: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final strip = tester.widget<ListView>(
        find.byKey(const Key('local-chat-image-strip')),
      );
      expect(strip.scrollDirection, Axis.horizontal);
      expect(
        find.byKey(const Key('local-chat-image-strip-add')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('send-local-chat')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pending-chat-image-image-0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('local-chat-image-preview')), findsOneWidget);
      expect(
        find.byKey(const Key('local-chat-image-preview-pages')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('local-chat-image-zoom-image-0')),
        findsOneWidget,
      );
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('local-chat-image-preview-pages')),
        const Offset(-280, 0),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('2 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
