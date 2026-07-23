import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_library_page.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/widgets/note_delta_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _PageLibraryStore store;
  late NoteLibraryController controller;

  setUp(() {
    store = _PageLibraryStore([
      _note(
        '格式笔记',
        document: Delta()
          ..insert('加粗正文', {'bold': true})
          ..insert('\n'),
      ),
      _note('普通笔记', document: Delta()..insert('可搜索内容\n')),
    ]);
    controller = NoteLibraryController(storeLoader: () async => store);
    addTearDown(controller.dispose);
  });

  testWidgets('shows styled Delta cards without organizational scopes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    expect(find.text('格式笔记'), findsOneWidget);
    expect(find.text('普通笔记'), findsOneWidget);
    expect(find.byType(NoteDeltaPreview), findsNWidgets(2));
    expect(find.text('收藏'), findsNothing);
    expect(find.text('归档'), findsNothing);
    expect(find.text('回收站'), findsNothing);
  });

  testWidgets('debounces search and never exposes Markdown marker fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('delta-library-search')),
      '可搜索',
    );
    await tester.pump(const Duration(milliseconds: 279));
    expect(find.text('格式笔记'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2));
    await _pump(tester);

    expect(find.text('普通笔记'), findsOneWidget);
    expect(find.text('格式笔记'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('keeps creation on home and opens existing notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          controller: controller,
          editorBuilder: (editorContext, note) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('close-test-editor'),
                onPressed: () => Navigator.pop(editorContext),
                child: Text(note?.title ?? '新建编辑器'),
              ),
            ),
          ),
        ),
      ),
    );
    await _pump(tester);

    expect(find.byKey(const Key('delta-library-new-note')), findsNothing);

    await tester.tap(find.text('格式笔记'));
    await tester.pumpAndSettle();
    expect(find.text('格式笔记'), findsOneWidget);
  });

  testWidgets('card deletion requires confirmation and removes the note', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    final card = find.byKey(
      ValueKey('delta-note-${store.notes.first.id.value}'),
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byIcon(Icons.more_vert_rounded)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever_outlined), findsNothing);
    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();
    expect(find.text('永久删除？'), findsOneWidget);
    await tester.tap(find.text('永久删除').last);
    await _pump(tester);

    expect(find.text('格式笔记'), findsNothing);
    expect(store.notes, hasLength(1));
  });
}

Future<void> _pump(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final class _PageLibraryStore implements NoteLibraryStore {
  _PageLibraryStore(this.notes);

  final List<Note> notes;

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

Note _note(String title, {required Delta document}) {
  final now = DateTime.utc(2026, 7, 23, 12);
  return Note(
    id: NoteId.generate(),
    title: title,
    document: NoteDocument.fromDelta(document),
    revision: 1,
    createdAt: now,
    updatedAt: now,
  );
}

final class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}
