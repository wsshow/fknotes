import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/note_share.dart';
import 'file_storage_service.dart';

class NoteSharePreferencesService {
  NoteSharePreferencesService._();
  static final NoteSharePreferencesService instance =
      NoteSharePreferencesService._();

  File get _file => File(
    p.join(FileStorageService.instance.baseDir, 'note_share_preferences.json'),
  );

  Future<NoteShareOptions> load() async {
    try {
      if (!await _file.exists()) return const NoteShareOptions();
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map) return const NoteShareOptions();
      return NoteShareOptions.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return const NoteShareOptions();
    }
  }

  Future<void> save(NoteShareOptions options) async {
    final file = _file;
    final temporary = File('${file.path}.tmp');
    await file.parent.create(recursive: true);
    await temporary.writeAsString(jsonEncode(options.toJson()), flush: true);
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      await temporary.copy(file.path);
      await temporary.delete();
    }
  }
}
