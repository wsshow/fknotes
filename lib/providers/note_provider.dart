import 'package:flutter/material.dart';

import '../models/note_entry.dart';
import '../services/file_storage_service.dart';
import '../services/note_service.dart';

class NoteProvider extends ChangeNotifier {
  final NoteService _notes = NoteService.instance;
  final FileStorageService _storage = FileStorageService.instance;

  List<NoteEntry> _entries = [];
  NoteType? _typeFilter;
  NoteScope _scope = NoteScope.active;
  NoteSort _sort = NoteSort.updated;
  bool _isLoading = false;

  List<NoteEntry> get allEntries => List.unmodifiable(_entries);
  List<NoteEntry> get activeEntries => _entries
      .where((entry) => !entry.isDeleted && !entry.isArchived)
      .toList(growable: false);
  List<NoteEntry> get entries {
    Iterable<NoteEntry> result = switch (_scope) {
      NoteScope.active => _entries.where((e) => !e.isDeleted && !e.isArchived),
      NoteScope.favorites => _entries.where(
        (e) => !e.isDeleted && !e.isArchived && e.isFavorite,
      ),
      NoteScope.archived => _entries.where((e) => !e.isDeleted && e.isArchived),
      NoteScope.trash => _entries.where((e) => e.isDeleted),
    };
    if (_typeFilter != null) {
      result = result.where((e) => e.containsType(_typeFilter!));
    }
    final list = result.toList();
    list.sort((a, b) {
      if (_scope != NoteScope.trash && a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return switch (_sort) {
        NoteSort.updated => b.updatedAt.compareTo(a.updatedAt),
        NoteSort.created => b.createdAt.compareTo(a.createdAt),
        NoteSort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        NoteSort.size => b.totalAttachmentSize.compareTo(a.totalAttachmentSize),
      };
    });
    return list;
  }

  NoteType? get typeFilter => _typeFilter;
  NoteScope get scope => _scope;
  NoteSort get sort => _sort;
  bool get isLoading => _isLoading;
  int get favoriteCount => activeEntries.where((e) => e.isFavorite).length;
  int get archiveCount =>
      _entries.where((e) => e.isArchived && !e.isDeleted).length;
  int get trashCount => _entries.where((e) => e.isDeleted).length;
  int get attachmentCount =>
      activeEntries.fold(0, (sum, entry) => sum + entry.allAttachments.length);
  int get totalFileSize =>
      _entries.fold(0, (sum, entry) => sum + entry.totalAttachmentSize);

  int countForType(NoteType type) =>
      activeEntries.where((entry) => entry.containsType(type)).length;

  Future<void> loadEntries() async {
    _isLoading = true;
    notifyListeners();
    try {
      _entries = await _notes.getAllEntries();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setTypeFilter(NoteType? type) {
    _typeFilter = type;
    notifyListeners();
  }

  void setScope(NoteScope scope) {
    _scope = scope;
    _typeFilter = null;
    notifyListeners();
  }

  void setSort(NoteSort sort) {
    _sort = sort;
    notifyListeners();
  }

  NoteEntry? getEntryById(int id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<int> addEntry(NoteEntry entry) async {
    final id = await _notes.insertEntry(entry);
    await loadEntries();
    return id;
  }

  Future<void> updateEntry(NoteEntry entry) async {
    await _notes.updateEntry(entry);
    await loadEntries();
  }

  Future<void> toggleFavorite(NoteEntry entry) => updateEntry(
    entry.copyWith(isFavorite: !entry.isFavorite, updatedAt: DateTime.now()),
  );

  Future<void> togglePinned(NoteEntry entry) => updateEntry(
    entry.copyWith(isPinned: !entry.isPinned, updatedAt: DateTime.now()),
  );

  Future<void> toggleArchived(NoteEntry entry) => updateEntry(
    entry.copyWith(
      isArchived: !entry.isArchived,
      isPinned: false,
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> moveToTrash(NoteEntry entry) => updateEntry(
    entry.copyWith(
      isDeleted: true,
      isPinned: false,
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> restore(NoteEntry entry) => updateEntry(
    entry.copyWith(
      isDeleted: false,
      isArchived: false,
      clearDeletedAt: true,
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> deletePermanently(NoteEntry entry) async {
    if (entry.id == null) return;
    await _deleteAttachmentFiles(entry);
    await _notes.deleteEntry(entry.id!);
    await loadEntries();
  }

  Future<void> emptyTrash() async {
    final trashed = _entries.where((e) => e.isDeleted).toList();
    for (final entry in trashed) {
      await _deleteAttachmentFiles(entry);
      if (entry.id != null) await _notes.deleteEntry(entry.id!);
    }
    await loadEntries();
  }

  Future<void> _deleteAttachmentFiles(NoteEntry entry) async {
    for (final attachment in entry.allAttachments) {
      await _storage.deleteFile(attachment.filePath);
      await _storage.deleteFile(attachment.thumbnailPath);
    }
  }
}
