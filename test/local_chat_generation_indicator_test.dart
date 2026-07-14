import 'package:fknotes/pages/local_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'generation indicator explains the active stage without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const label = 'Composing an answer from your notes…';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 250,
                child: LocalChatGenerationIndicator(label: label),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('local-chat-generation-status')),
        findsOneWidget,
      );
      expect(find.text(label), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
