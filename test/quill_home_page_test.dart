import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_chat.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_library_page.dart';
import 'package:fknotes/pages/note_quill_editor_page.dart';
import 'package:fknotes/pages/quill_home_page.dart';
import 'package:fknotes/providers/app_lock_controller.dart';
import 'package:fknotes/providers/app_locale_controller.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/widgets/note_quill_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late _HomeStore store;
  late NoteLibraryController controller;

  setUp(() {
    final base = DateTime.utc(2026, 7, 23, 8);
    store = _HomeStore([
      _note('较早置顶', updatedAt: base, pinned: true),
      _note('最新笔记', updatedAt: base.add(const Duration(hours: 2))),
    ]);
    controller = NoteLibraryController(storeLoader: () async => store);
    addTearDown(controller.dispose);
  });

  testWidgets('single home exposes the complete searchable note library', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
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
    expect(find.byKey(const Key('delta-library-search-pull')), findsOneWidget);
    expect(find.byKey(const Key('quill-home-new-note')), findsOneWidget);
    expect(find.byKey(const Key('quill-home-assistant')), findsOneWidget);
    expect(find.byKey(const Key('delta-library-open-data')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('quill-home-new-note'))),
      const Size.square(56),
    );
    final toolDock = find.byKey(const Key('edge-tool-dock'));
    final brandSpine = find.byKey(const Key('brand-spine-paper-tab'));
    expect(tester.getSize(toolDock), const Size(38, 86.5));
    expect(tester.getSize(toolDock).width, tester.getSize(brandSpine).width);
    expect(tester.getRect(toolDock).right, 800);
    expect(
      tester.getSize(find.byKey(const Key('quill-home-assistant'))).height,
      42,
    );
    expect(
      tester.getRect(find.byKey(const Key('quill-home-assistant'))).top,
      lessThan(80),
    );
    expect(find.byKey(const Key('quill-floating-navigation')), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    expect(find.text('最新笔记'), findsOneWidget);
    expect(find.text('较早置顶'), findsOneWidget);
  });

  testWidgets('empty state and new-note action sit above the screen bottom', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final emptyController = NoteLibraryController(
      storeLoader: () async => _HomeStore(<Note>[]),
    );
    addTearDown(emptyController.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: emptyController,
          editorBuilder: _testEditor,
        ),
      ),
    );
    await _pump(tester);

    final screenHeight = tester.getSize(find.byType(QuillHomePage)).height;
    final emptyMessage = find.text('还没有笔记');
    final createAction = find.byKey(const Key('quill-home-new-note'));

    expect(emptyMessage, findsOneWidget);
    expect(tester.getCenter(emptyMessage).dy, lessThan(screenHeight * 0.5));
    expect(
      screenHeight - tester.getRect(createAction).bottom,
      greaterThanOrEqualTo(40),
    );
  });

  testWidgets(
    'data settings is a secondary route instead of primary navigation',
    (tester) async {
      await tester.pumpWidget(
        _TestApp(
          child: QuillHomePage(
            controller: controller,
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
      expect(
        find.byKey(const Key('delta-library-search-pull')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'all home entry points converge on the Delta library and editor',
    (tester) async {
      await tester.pumpWidget(
        _TestApp(
          child: QuillHomePage(
            controller: controller,
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
      expect(
        find.byKey(const Key('delta-library-search-pull')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('delta-library-open-data')));
      await _pump(tester);
      expect(find.text('本地数据'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.text('导出完整备份'), findsOneWidget);
      expect(find.text('从备份恢复'), findsOneWidget);
      expect(find.text('云同步'), findsOneWidget);
    },
  );

  testWidgets('returning from new note keeps the home keyboard closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          editorBuilder: _testEditor,
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('delta-library-search-pull')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delta-library-search')));
    await tester.pump();
    expect(_searchEditable(tester).focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byKey(const Key('quill-home-new-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-test-editor')));
    await tester.pumpAndSettle();

    expect(_searchEditable(tester).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('done returns home and reveals the saved note card', (
    tester,
  ) async {
    final created = _note('完成后定位', updatedAt: DateTime.utc(2026, 7, 23, 12));
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          editorBuilder: (context, note) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('finish-test-editor'),
                onPressed: () {
                  store.notes.add(created);
                  Navigator.pop(
                    context,
                    NoteEditorRouteResult(note: created, completed: true),
                  );
                },
                child: const Text('完成'),
              ),
            ),
          ),
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('quill-home-new-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-test-editor')));
    await _pump(tester);

    expect(find.byType(NoteLibraryPage), findsOneWidget);
    expect(find.text('完成后定位'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('index-ticks-current'))).data,
      '3',
    );
  });

  testWidgets('done exits an assistant source editor back to home', (
    tester,
  ) async {
    final sourceNote = store.notes.last;
    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          noteLoader: store.get,
          assistantBuilder: (context, onOpenNote) =>
              _testAssistant(context, onOpenNote, sourceNote),
          editorBuilder: (context, note) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('finish-assistant-source-editor'),
                onPressed: () => Navigator.pop(
                  context,
                  NoteEditorRouteResult(note: note, completed: true),
                ),
                child: const Text('完成'),
              ),
            ),
          ),
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('quill-home-assistant')));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('open-assistant-source')));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('finish-assistant-source-editor')));
    await tester.pumpAndSettle();

    expect(find.text('全新 Delta 本地助手'), findsNothing);
    expect(find.byType(NoteLibraryPage), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('index-ticks-current'))).data,
      '2',
    );
  });

  testWidgets('bulk selection reuses the tiled shelf and hides note creation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _TestApp(
        child: QuillHomePage(
          controller: controller,
          editorBuilder: _testEditor,
        ),
      ),
    );
    await _pump(tester);

    await tester.longPress(find.text('最新笔记'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delta-library-shelf-grid')), findsOneWidget);
    expect(find.byKey(const Key('delta-library-selection-grid')), findsNothing);
    expect(find.byType(NoteRichDocumentPreview), findsNothing);
    expect(find.byKey(const Key('quill-home-new-note')), findsNothing);
    final first = find.byKey(
      ValueKey('delta-shelf-note-${store.notes.first.id.value}'),
    );
    final second = find.byKey(
      ValueKey('delta-shelf-note-${store.notes.last.id.value}'),
    );
    expect(tester.getRect(first).top, tester.getRect(second).top);

    await tester.tap(find.byKey(const Key('delta-library-exit-selection')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quill-home-new-note')), findsOneWidget);
  });
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

EditableText _searchEditable(WidgetTester tester) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('delta-library-search')),
        matching: find.byType(EditableText),
      ),
    );

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
  Future<List<Note>> list() async => List.of(notes);

  @override
  Future<List<Note>> search(String query) async => notes
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
