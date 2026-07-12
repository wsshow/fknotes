import 'dart:io';

import 'package:fknotes/models/local_chat.dart';
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
            imageInputAvailable: false,
            pickingImages: false,
            dictating: false,
            dictationPreparing: false,
            onTakePhoto: () {},
            onPickImages: () {},
            onRemoveAttachment: (_) {},
            onToggleDictation: () {},
            onSend: () => sendCount++,
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('local-chat-take-photo')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-add-image')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-voice-input')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-input')), findsOneWidget);
    expect(find.byKey(const Key('send-local-chat')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('local-chat-input')),
      '帮我整理这段内容',
    );
    await tester.pump();

    expect(find.byKey(const Key('send-local-chat')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-voice-input')), findsNothing);
    expect(find.byKey(const Key('local-chat-add-image')), findsNothing);

    await tester.tap(find.byKey(const Key('send-local-chat')));
    expect(sendCount, 1);
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
              imageInputAvailable: true,
              pickingImages: false,
              dictating: false,
              dictationPreparing: false,
              onTakePhoto: () {},
              onPickImages: () {},
              onRemoveAttachment: (_) {},
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
