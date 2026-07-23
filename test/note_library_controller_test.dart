import 'dart:async';

import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryLibraryStore store;
  late NoteLibraryController controller;

  setUp(() {
    store = _MemoryLibraryStore([
      _note('普通笔记', body: '正文', revision: 1),
      _note('另一篇笔记', revision: 2),
    ]);
    controller = NoteLibraryController(
      storeLoader: () async => store,
      now: () => DateTime.utc(2026, 7, 23, 18),
    );
    addTearDown(controller.dispose);
  });

  test('loads one unified note collection', () async {
    await controller.initialize();
    expect(controller.notes.map((note) => note.title), ['普通笔记', '另一篇笔记']);
  });

  test('a late search response cannot replace a newer query', () async {
    final oldResponse = Completer<List<Note>>();
    final newResponse = Completer<List<Note>>();
    store.searchOverrides['旧'] = oldResponse.future;
    store.searchOverrides['新'] = newResponse.future;

    final oldSearch = controller.search('旧');
    final newSearch = controller.search('新');
    newResponse.complete([_note('新结果', revision: 1)]);
    await newSearch;
    oldResponse.complete([_note('旧结果', revision: 1)]);
    await oldSearch;

    expect(controller.query, '新');
    expect(controller.notes.map((note) => note.title), ['新结果']);
  });

  test('pinning preserves revisions and refreshes the collection', () async {
    await controller.initialize();
    final original = controller.notes.first;

    await controller.togglePinned(original);
    final pinned = controller.notes.singleWhere(
      (note) => note.id == original.id,
    );
    expect(pinned.isPinned, isTrue);
    expect(pinned.revision, 2);
    expect(pinned.updatedAt, DateTime.utc(2026, 7, 23, 18));
  });

  test(
    'write conflicts reload fresh state and remain visible as errors',
    () async {
      await controller.initialize();
      final original = controller.notes.first;
      store.updateError = NoteWriteConflict(original.id);

      await expectLater(
        controller.togglePinned(original),
        throwsA(isA<NoteWriteConflict>()),
      );

      expect(controller.error, isA<NoteWriteConflict>());
      expect(controller.isBusy(original.id), isFalse);
      expect(controller.notes.first.isPinned, isFalse);
    },
  );

  test('permanent deletion removes only the selected note', () async {
    await controller.initialize();
    final deleted = controller.notes.first;

    await controller.deletePermanently(deleted);

    expect(controller.notes, hasLength(1));
    expect(controller.notes.any((note) => note.id == deleted.id), isFalse);
    expect(store.deletedNotes, [deleted]);
    expect(store.notes.any((note) => note.id == deleted.id), isFalse);
  });
}

final class _MemoryLibraryStore implements NoteLibraryStore {
  _MemoryLibraryStore(this.notes);

  final List<Note> notes;
  final Map<String, Future<List<Note>>> searchOverrides = {};
  final List<Note> deletedNotes = [];
  Object? updateError;
  var searchCalls = 0;

  Note note(NoteId id) => notes.singleWhere((candidate) => candidate.id == id);

  @override
  Future<List<Note>> list() async => List.of(notes);

  @override
  Future<List<Note>> search(String query) {
    searchCalls++;
    final overridden = searchOverrides[query];
    if (overridden != null) return overridden;
    final normalized = query.toLowerCase();
    return Future.value(
      notes
          .where((note) => note.searchText.toLowerCase().contains(normalized))
          .toList(growable: false),
    );
  }

  @override
  Future<Note> update(Note note) async {
    final error = updateError;
    if (error != null) throw error;
    final persisted = note.copyWith(revision: note.revision + 1);
    final index = notes.indexWhere((candidate) => candidate.id == note.id);
    notes[index] = persisted;
    return persisted;
  }

  @override
  Future<void> deletePermanently(Note note) async {
    deletedNotes.add(note);
    notes.removeWhere((candidate) => candidate.id == note.id);
  }
}

Note _note(String title, {String body = '', int revision = 0}) {
  final now = DateTime.utc(2026, 7, 23, 12);
  return Note(
    id: NoteId.generate(),
    title: title,
    document: NoteDocument.fromPlainText(body),
    revision: revision,
    createdAt: now,
    updatedAt: now,
  );
}
