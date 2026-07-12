import 'package:fknotes/app.dart';
import 'package:fknotes/widgets/editor_context_menu.dart';
import 'package:fknotes/widgets/fk_markdown_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editable text uses the branded Chinese action menu', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'FKNotes 选择菜单');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            contextMenuBuilder: buildAppEditableTextContextMenu,
            controller: controller,
            decoration: const InputDecoration(hintText: '输入内容'),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('复制'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Ask Claude'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.elevation == 5 &&
            widget.color == AppColors.surface &&
            widget.shape is RoundedRectangleBorder,
      ),
      findsOneWidget,
    );
  });

  testWidgets('Markdown selection uses the same app menu', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FkMarkdownView(data: 'FKNotes 本地助手支持选择 Markdown 内容。'),
        ),
      ),
    );

    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    expect(selectable.contextMenuBuilder, buildAppEditableTextContextMenu);

    await tester.longPress(find.byType(SelectableText).first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Ask Claude'), findsNothing);
  });
}
