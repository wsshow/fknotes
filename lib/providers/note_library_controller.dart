import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../services/file_storage_service.dart';
import '../services/note_database_service.dart';
import '../services/note_repository.dart';

enum NoteLibraryScope { active, favorites, archived, trash }

abstract interface class NoteLibraryStore {
  Future<List<Note>> list({required NoteStatus status});

  Future<List<Note>> search(String query);

  Future<Note> update(Note note);

  Future<void> deletePermanently(Note note);
}

final class RepositoryNoteLibraryStore implements NoteLibraryStore {
  RepositoryNoteLibraryStore(this.repository, {FileStorageService? storage})
    : storage = storage ?? FileStorageService.instance;

  final NoteRepository repository;
  final FileStorageService storage;

  @override
  Future<List<Note>> list({required NoteStatus status}) =>
      repository.list(status: status);

  @override
  Future<List<Note>> search(String query) => repository.search(query);

  @override
  Future<Note> update(Note note) => repository.update(note);

  @override
  Future<void> deletePermanently(Note note) async {
    await repository.deletePermanently(note.id);
    for (final asset in note.assets) {
      for (final key in [asset.storageKey, asset.previewStorageKey]) {
        try {
          await storage.deleteFile(key);
        } on FileSystemException {
          // Database deletion is authoritative. A later orphan sweep can
          // retry cleanup if the OS still has a file handle open.
        }
      }
    }
  }
}

typedef NoteLibraryStoreLoader = Future<NoteLibraryStore> Function();

/// State for the clean Delta note library.
///
/// Every async request carries a generation so a slow search can never replace
/// a newer query. Note mutations use repository revisions and refresh on a
/// conflict instead of silently overwriting another editor session.
final class NoteLibraryController extends ChangeNotifier {
  NoteLibraryController({
    NoteLibraryStoreLoader? storeLoader,
    DateTime Function()? now,
  }) : _storeLoader =
           storeLoader ??
           (() async => RepositoryNoteLibraryStore(
             await NoteDatabaseService.instance.repository,
           )),
       _now = now ?? DateTime.now;

  final NoteLibraryStoreLoader _storeLoader;
  final DateTime Function() _now;
  final Set<NoteId> _busyNoteIds = {};
  List<Note> _notes = const [];
  NoteLibraryScope _scope = NoteLibraryScope.active;
  String _query = '';
  Object? _error;
  var _loading = false;
  var _requestGeneration = 0;

  List<Note> get notes => _notes;
  NoteLibraryScope get scope => _scope;
  String get query => _query;
  Object? get error => _error;
  bool get isLoading => _loading;
  bool get hasError => _error != null;
  bool isBusy(NoteId id) => _busyNoteIds.contains(id);

  Future<void> initialize() => refresh();

  Future<void> setScope(NoteLibraryScope value) async {
    if (_scope == value) return;
    _scope = value;
    _query = '';
    notifyListeners();
    await refresh();
  }

  Future<void> search(String value) async {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_query == normalized && !_loading) return;
    _query = normalized;
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    final generation = ++_requestGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final store = await _storeLoader();
      final loaded = await _loadForCurrentFilter(store);
      if (generation != _requestGeneration) return;
      _notes = List.unmodifiable(loaded);
    } catch (error) {
      if (generation != _requestGeneration) return;
      _error = error;
    } finally {
      if (generation == _requestGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<List<Note>> _loadForCurrentFilter(NoteLibraryStore store) async {
    final status = switch (_scope) {
      NoteLibraryScope.active ||
      NoteLibraryScope.favorites => NoteStatus.active,
      NoteLibraryScope.archived => NoteStatus.archived,
      NoteLibraryScope.trash => NoteStatus.trashed,
    };
    List<Note> loaded;
    if (_query.isEmpty) {
      loaded = await store.list(status: status);
    } else if (status == NoteStatus.trashed) {
      final candidates = await store.list(status: status);
      final lowerQuery = _query.toLowerCase();
      loaded = candidates
          .where((note) => note.searchText.toLowerCase().contains(lowerQuery))
          .toList(growable: false);
    } else {
      loaded = (await store.search(
        _query,
      )).where((note) => note.status == status).toList(growable: false);
    }
    if (_scope == NoteLibraryScope.favorites) {
      loaded = loaded.where((note) => note.isFavorite).toList(growable: false);
    }
    return loaded;
  }

  Future<void> togglePinned(Note note) =>
      _mutate(note, (value) => value.copyWith(isPinned: !value.isPinned));

  Future<void> toggleFavorite(Note note) =>
      _mutate(note, (value) => value.copyWith(isFavorite: !value.isFavorite));

  Future<void> archive(Note note) => _mutate(
    note,
    (value) => value.copyWith(status: NoteStatus.archived, trashedAt: null),
  );

  Future<void> restore(Note note) => _mutate(
    note,
    (value) => value.copyWith(status: NoteStatus.active, trashedAt: null),
  );

  Future<void> moveToTrash(Note note) => _mutate(
    note,
    (value) =>
        value.copyWith(status: NoteStatus.trashed, trashedAt: _now().toUtc()),
  );

  Future<void> _mutate(Note note, Note Function(Note value) change) async {
    if (!_busyNoteIds.add(note.id)) return;
    _error = null;
    notifyListeners();
    try {
      final timestamp = _now().toUtc();
      final store = await _storeLoader();
      await store.update(change(note).copyWith(updatedAt: timestamp));
      await refresh();
    } catch (error) {
      await refresh();
      _error = error;
      notifyListeners();
      rethrow;
    } finally {
      _busyNoteIds.remove(note.id);
      notifyListeners();
    }
  }

  Future<void> deletePermanently(Note note) async {
    if (!_busyNoteIds.add(note.id)) return;
    _error = null;
    notifyListeners();
    try {
      final store = await _storeLoader();
      await store.deletePermanently(note);
      _notes = List.unmodifiable(
        _notes.where((candidate) => candidate.id != note.id),
      );
    } catch (error) {
      _error = error;
      rethrow;
    } finally {
      _busyNoteIds.remove(note.id);
      notifyListeners();
    }
  }
}

typedef NoteMutation = Note Function(Note value);
