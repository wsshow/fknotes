import 'package:fknotes/pages/transcript_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('full-screen transcript editor returns trimmed text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) =>
                        const TranscriptEditorPage(initialText: '原始转写'),
                  ),
                );
              },
              child: const Text('编辑'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.byType(TranscriptEditorPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('仅修改本地转写文字，原始录音不会改变'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('transcript-editor-field'))).height,
      greaterThan(300),
    );

    await tester.enterText(
      find.byKey(const Key('transcript-editor-field')),
      '  修改后的转写  ',
    );
    await tester.pump();
    expect(find.text('10 字'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save-transcript-edit')));
    await tester.pumpAndSettle();

    expect(find.byType(TranscriptEditorPage), findsNothing);
    expect(result, '修改后的转写');
  });
}
