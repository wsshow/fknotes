import 'package:fknotes/services/note_assistant_prompt_builder.dart';
import 'package:fknotes/widgets/note_assistant_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('note assistant accepts a free-form instruction', (tester) async {
    NoteAssistantAction? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  selected = await showNoteAssistantTaskSheet(context);
                },
                child: const Text('打开 AI'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开 AI'));
    await tester.pumpAndSettle();

    expect(find.text('快捷操作'), findsOneWidget);
    expect(find.text('总结笔记'), findsOneWidget);
    final instructionField = find.byKey(
      const Key('note-assistant-custom-instruction'),
    );
    expect(instructionField, findsOneWidget);

    await tester.enterText(instructionField, '请把这些想法写成一首短诗');
    await tester.pump();
    await tester.tap(find.byKey(const Key('note-assistant-submit-custom')));
    await tester.pumpAndSettle();

    expect(selected?.isCustom, isTrue);
    expect(selected?.instruction, '请把这些想法写成一首短诗');
    expect(selected?.resultHeading, 'AI 生成内容');
  });
}
