import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_library_page.dart';
import 'package:fknotes/pages/quill_home_page.dart';
import 'package:fknotes/providers/app_lock_controller.dart';
import 'package:fknotes/providers/app_locale_controller.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late _HomeStore store;
  late NoteLibraryController recentController;
  late NoteLibraryController libraryController;

  setUp(() {
    final base = DateTime.utc(2026, 7, 23, 8);
    store = _HomeStore([
      _note('较早置顶', updatedAt: base, pinned: true),
      _note('最新笔记', updatedAt: base.add(const Duration(hours: 2))),
    ]);
    recentController = NoteLibraryController(storeLoader: () async => store);
    libraryController = NoteLibraryController(storeLoader: () async => store);
    addTearDown(recentController.dispose);
    addTearDown(libraryController.dispose);
  });

  testWidgets('single home exposes the complete searchable note library', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          recentController: recentController,
          libraryController: libraryController,
          dataSizeLoader: () async => 2048,
          editorBuilder: _testEditor,
          noteLoader: store.get,
          assistantBuilder: (context, onOpenNote) =>
              _testAssistant(context, onOpenNote, store.notes.last),
        ),
      ),
    );
    await _pump(tester);

    expect(find.byType(QuillHomePage), findsOneWidget);
    expect(find.byType(NoteLibraryPage), findsOneWidget);
    expect(find.byKey(const Key('delta-library-search')), findsOneWidget);
    expect(find.byKey(const Key('quill-home-new-note')), findsOneWidget);
    expect(find.byKey(const Key('quill-home-assistant')), findsOneWidget);
    expect(find.byKey(const Key('delta-library-open-data')), findsOneWidget);
    expect(find.byKey(const Key('quill-floating-navigation')), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    expect(find.text('最新笔记'), findsOneWidget);
    expect(find.text('较早置顶'), findsOneWidget);
  });

  testWidgets(
    'data settings is a secondary route instead of primary navigation',
    (tester) async {
      await tester.pumpWidget(
        _TestApp(
          child: QuillHomePage(
            recentController: recentController,
            libraryController: libraryController,
            dataSizeLoader: () async => 2048,
            editorBuilder: _testEditor,
            noteLoader: store.get,
          ),
        ),
      );
      await _pump(tester);

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const Key('quill-floating-navigation')), findsNothing);
      await tester.tap(find.byKey(const Key('delta-library-open-data')));
      await _pump(tester);
      expect(find.text('本地数据'), findsOneWidget);
      expect(find.byKey(const Key('quill-data-back')), findsOneWidget);

      await tester.tap(find.byKey(const Key('quill-data-back')));
      await _pump(tester);
      expect(find.byKey(const Key('delta-library-search')), findsOneWidget);
    },
  );

  testWidgets(
    'all home entry points converge on the Delta library and editor',
    (tester) async {
      await tester.pumpWidget(
        _TestApp(
          child: QuillHomePage(
            recentController: recentController,
            libraryController: libraryController,
            dataSizeLoader: () async => 2048,
            editorBuilder: _testEditor,
            noteLoader: store.get,
            assistantBuilder: (context, onOpenNote) =>
                _testAssistant(context, onOpenNote, store.notes.last),
          ),
        ),
      );
      await _pump(tester);

      await tester.tap(find.byKey(const Key('quill-home-assistant')));
      await _pump(tester);
      expect(find.text('全新 Delta 本地助手'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-assistant-source')));
      await _pump(tester);
      expect(find.text('最新笔记'), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-test-editor')));
      await _pump(tester);
      await tester.binding.handlePopRoute();
      await _pump(tester);

      await tester.tap(find.byKey(const Key('quill-home-new-note')));
      await tester.pumpAndSettle();
      expect(find.text('新的 Delta 笔记'), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-test-editor')));
      await _pump(tester);

      expect(find.byType(NoteLibraryPage), findsOneWidget);
      expect(find.byKey(const Key('delta-library-search')), findsOneWidget);

      await tester.tap(find.byKey(const Key('delta-library-open-data')));
      await _pump(tester);
      expect(find.text('本地数据'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.text('导出完整备份'), findsOneWidget);
      expect(find.text('从备份恢复'), findsOneWidget);
      expect(find.text('云同步'), findsOneWidget);
    },
  );
}

Widget _testEditor(BuildContext context, Note? note) => Scaffold(
  body: Center(
    child: TextButton(
      key: const Key('close-test-editor'),
      onPressed: () => Navigator.pop(context),
      child: Text(note?.title ?? '新的 Delta 笔记'),
    ),
  ),
);

Widget _testAssistant(
  BuildContext context,
  Future<void> Function(LocalChatNoteContext source) onOpenNote,
  Note sourceNote,
) => Scaffold(
  body: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('全新 Delta 本地助手'),
        TextButton(
          key: const Key('open-assistant-source'),
          onPressed: () => onOpenNote(
            LocalChatNoteContext(
              noteId: sourceNote.id,
              title: sourceNote.title,
              scope: LocalChatNoteScope.fullNote,
              content: 'Delta 正文',
              updatedAt: DateTime.utc(2026, 7, 23),
            ),
          ),
          child: const Text('打开来源'),
        ),
      ],
    ),
  ),
);

Future<void> _pump(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final class _HomeStore implements NoteLibraryStore {
  _HomeStore(this.notes);

  final List<Note> notes;

  Future<Note?> get(NoteId id) async {
    for (final note in notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  @override
  Future<List<Note>> list({required NoteStatus status}) async =>
      notes.where((note) => note.status == status).toList(growable: false);

  @override
  Future<List<Note>> search(String query) async => notes
      .where((note) => note.status != NoteStatus.trashed)
      .where((note) => note.searchText.contains(query))
      .toList(growable: false);

  @override
  Future<Note> update(Note note) async {
    final persisted = note.copyWith(revision: note.revision + 1);
    final index = notes.indexWhere((candidate) => candidate.id == note.id);
    notes[index] = persisted;
    return persisted;
  }

  @override
  Future<void> deletePermanently(Note note) async {
    notes.removeWhere((candidate) => candidate.id == note.id);
  }
}

Note _note(String title, {required DateTime updatedAt, bool pinned = false}) =>
    Note(
      id: NoteId.generate(),
      title: title,
      document: NoteDocument.fromPlainText('Delta 正文'),
      isPinned: pinned,
      revision: 1,
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );

final class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => AppLocaleController(observePlatform: false),
      ),
      ChangeNotifierProvider(
        create: (_) => AppLockController(observeLifecycle: false),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    ),
  );
}
