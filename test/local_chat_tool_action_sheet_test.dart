import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/widgets/local_chat_tool_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('write proposal requires preview and explicit confirmation', (
    tester,
  ) async {
    final noteId = NoteId.parse('f1341a17-27a4-42f8-bd30-b589550f0f57');
    final call = LocalChatToolCall(
      id: 'append-1',
      name: LocalChatToolName.appendNote,
      noteId: noteId,
      content: '拟追加的内容',
    );
    final target = Note(
      id: noteId,
      title: '项目记录',
      document: NoteDocument.fromPlainText('当前正文'),
      revision: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    bool? confirmed;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: LocalChatToolActionCard(
              call: call,
              targetLabel: target.title,
              onReview: () async {
                confirmed = await showLocalChatToolActionSheet(
                  context,
                  call: call,
                  target: target,
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('追加到笔记'), findsOneWidget);
    expect(confirmed, isNull);
    await tester.tap(find.byKey(const Key('local-chat-review-tool-append-1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('确认前不会写入'), findsOneWidget);
    expect(find.text('当前正文'), findsOneWidget);
    expect(find.text('拟追加的内容'), findsOneWidget);
    expect(confirmed, isNull);

    await tester.tap(find.byKey(const Key('local-chat-confirm-tool-action')));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
