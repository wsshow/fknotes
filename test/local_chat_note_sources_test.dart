import 'dart:ui';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/pages/local_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalChatNoteContext source(int id, String title) => LocalChatNoteContext(
    noteId: id,
    title: title,
    scope: LocalChatNoteScope.fullNote,
    content: '$title 正文',
    updatedAt: DateTime(2026),
  );

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );

  testWidgets('single source uses a natural label and opens the note', (
    tester,
  ) async {
    LocalChatNoteContext? opened;
    final note = source(42, 'Tool Test');
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 320,
          child: LocalChatNoteSources(
            noteContexts: [note],
            onOpenNote: (value) async => opened = value,
          ),
        ),
      ),
    );

    expect(find.text('[N1]'), findsNothing);
    expect(find.text('Tool Test · 整篇笔记'), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('打开来源笔记：Tool Test'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('打开来源笔记：Tool Test'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('local-chat-note-source-42')));
    await tester.pump();
    expect(opened?.noteId, 42);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple sources use compact numeric badges', (tester) async {
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 320,
          child: LocalChatNoteSources(
            noteContexts: [source(1, '项目计划'), source(2, '风险清单')],
          ),
        ),
      ),
    );

    expect(find.text('[N1]'), findsNothing);
    expect(find.text('[N2]'), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
