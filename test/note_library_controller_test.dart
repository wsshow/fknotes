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
      _note('收藏笔记', favorite: true, revision: 2),
      _note('归档笔记', status: NoteStatus.archived, revision: 1),
      _note('已删除笔记', status: NoteStatus.trashed, revision: 3),
    ]);
    controller = NoteLibraryController(
      storeLoader: () async => store,
      now: () => DateTime.utc(2026, 7, 23, 18),
    );
    addTearDown(controller.dispose);
  });

  test(
    'loads independent active, favorite, archive and trash scopes',
    () async {
      await controller.initialize();
      expect(controller.notes.map((note) => note.title), ['普通笔记', '收藏笔记']);

      await controller.setScope(NoteLibraryScope.favorites);
      expect(controller.notes.map((note) => note.title), ['收藏笔记']);

      await controller.setScope(NoteLibraryScope.archived);
      expect(controller.notes.map((note) => note.title), ['归档笔记']);

      await controller.setScope(NoteLibraryScope.trash);
      expect(controller.notes.map((note) => note.title), ['已删除笔记']);
    },
  );

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

  test('mutations preserve revisions and refresh the visible scope', () async {
    await controller.initialize();
    final original = controller.notes.first;

    await controller.togglePinned(original);
    final pinned = controller.notes.singleWhere(
      (note) => note.id == original.id,
    );
    expect(pinned.isPinned, isTrue);
    expect(pinned.revision, 2);
    expect(pinned.updatedAt, DateTime.utc(2026, 7, 23, 18));

    await controller.archive(pinned);
    expect(controller.notes.any((note) => note.id == original.id), isFalse);
    expect(store.note(original.id).status, NoteStatus.archived);
    expect(store.note(original.id).revision, 3);
  });

  test(
    'trash search is local because repository search excludes trash',
    () async {
      await controller.setScope(NoteLibraryScope.trash);
      await controller.search('已删除');

      expect(controller.notes.map((note) => note.title), ['已删除笔记']);
      expect(store.searchCalls, 0);
    },
  );

  test(
    'write conflicts reload fresh state and remain visible as errors',
    () async {
      await controller.initialize();
      final original = controller.notes.first;
      store.updateError = NoteWriteConflict(original.id);

      await expectLater(
        controller.toggleFavorite(original),
        throwsA(isA<NoteWriteConflict>()),
      );

      expect(controller.error, isA<NoteWriteConflict>());
      expect(controller.isBusy(original.id), isFalse);
      expect(controller.notes.first.isFavorite, isFalse);
    },
  );

  test(
    'permanent deletion removes the complete note graph from the scope',
    () async {
      await controller.setScope(NoteLibraryScope.trash);
      final deleted = controller.notes.single;

      await controller.deletePermanently(deleted);

      expect(controller.notes, isEmpty);
      expect(store.deletedNotes, [deleted]);
      expect(store.notes.any((note) => note.id == deleted.id), isFalse);
    },
  );
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
  Future<List<Note>> list({required NoteStatus status}) async =>
      notes.where((note) => note.status == status).toList(growable: false);

  @override
  Future<List<Note>> search(String query) {
    searchCalls++;
    final overridden = searchOverrides[query];
    if (overridden != null) return overridden;
    final normalized = query.toLowerCase();
    return Future.value(
      notes
          .where(
            (note) =>
                note.status != NoteStatus.trashed &&
                note.searchText.toLowerCase().contains(normalized),
          )
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

Note _note(
  String title, {
  String body = '',
  NoteStatus status = NoteStatus.active,
  bool favorite = false,
  int revision = 0,
}) {
  final now = DateTime.utc(2026, 7, 23, 12);
  return Note(
    id: NoteId.generate(),
    title: title,
    document: NoteDocument.fromPlainText(body),
    status: status,
    isFavorite: favorite,
    revision: revision,
    createdAt: now,
    updatedAt: now,
    trashedAt: status == NoteStatus.trashed ? now : null,
  );
}
