import 'package:fknotes/pages/local_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
            onPickImages: () {},
            onRemoveAttachment: (_) {},
            onToggleDictation: () {},
            onSend: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('local-chat-add-image')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-voice-input')), findsOneWidget);
    expect(find.byKey(const Key('local-chat-input')), findsOneWidget);
    expect(find.byKey(const Key('send-local-chat')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
