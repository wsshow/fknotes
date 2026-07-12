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
}
