import 'package:fknotes/services/note_assistant_prompt_builder.dart';
import 'package:fknotes/widgets/note_assistant_sheet.dart';
import 'package:fknotes/models/local_llm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manually stopped assistant output remains insertable', () {
    expect(
      canInsertNoteAssistantOutput(
        output: '已经生成的部分内容',
        finishReason: LocalLlmFinishReason.canceled,
      ),
      isTrue,
    );
    expect(
      canInsertNoteAssistantOutput(
        output: '已经生成的部分内容',
        finishReason: LocalLlmFinishReason.timeout,
      ),
      isFalse,
    );
    expect(
      canInsertNoteAssistantOutput(
        output: '   ',
        finishReason: LocalLlmFinishReason.canceled,
      ),
      isFalse,
    );
  });

  testWidgets('note assistant accepts a free-form instruction', (tester) async {
    NoteAssistantInvocation? selected;
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

    expect(selected?.action.isCustom, isTrue);
    expect(selected?.action.instruction, '请把这些想法写成一首短诗');
    expect(selected?.action.resultHeading, 'AI 生成内容');
    expect(selected?.scope, NoteAssistantScope.fullNote);
  });

  testWidgets('note assistant lets the user choose an available scope', (
    tester,
  ) async {
    NoteAssistantInvocation? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selected = await showNoteAssistantTaskSheet(
                  context,
                  availableScopes: const {
                    NoteAssistantScope.selection,
                    NoteAssistantScope.currentBlock,
                    NoteAssistantScope.fullNote,
                  },
                  initialScope: NoteAssistantScope.selection,
                );
              },
              child: const Text('打开范围选择'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开范围选择'));
    await tester.pumpAndSettle();
    expect(find.text('选中文字'), findsOneWidget);
    expect(find.text('当前段落'), findsOneWidget);
    expect(find.text('整篇笔记'), findsOneWidget);

    await tester.tap(find.text('当前段落'));
    await tester.pump();
    await tester.tap(find.text('总结笔记'));
    await tester.pumpAndSettle();

    expect(selected?.scope, NoteAssistantScope.currentBlock);
    expect(selected?.action.task, NoteAssistantTask.summarize);
  });
}
