import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/local_chat.dart';
import '../models/note.dart';

class LocalChatToolProtocol {
  static const _openTag = '<fknotes_tool>';
  static final _completeCall = RegExp(
    r'<fknotes_tool>\s*([\s\S]*?)\s*</fknotes_tool>',
  );
  static const _uuid = Uuid();

  static bool containsToolMarkup(String raw) {
    if (raw.contains(_openTag)) return true;
    final lastAngle = raw.lastIndexOf('<');
    if (lastAngle < 0) return false;
    return _openTag.startsWith(raw.substring(lastAngle));
  }

  static String visibleText(String raw) {
    var visible = raw.replaceAll(_completeCall, '');
    final openIndex = visible.lastIndexOf(_openTag);
    if (openIndex >= 0) visible = visible.substring(0, openIndex);
    final lastAngle = visible.lastIndexOf('<');
    if (lastAngle >= 0) {
      final fragment = visible.substring(lastAngle);
      if (_openTag.startsWith(fragment)) {
        visible = visible.substring(0, lastAngle);
      }
    }
    return visible.trimRight();
  }

  static List<LocalChatToolCall> parseCalls(String raw) {
    final calls = <LocalChatToolCall>[];
    for (final match in _completeCall.allMatches(raw).take(3)) {
      try {
        final decoded = jsonDecode(match.group(1)!);
        if (decoded is! Map) continue;
        final call = _validatedCall(Map<String, Object?>.from(decoded));
        if (call != null) calls.add(call);
      } catch (_) {
        continue;
      }
    }
    return calls;
  }

  static LocalChatToolCall? _validatedCall(Map<String, Object?> json) {
    final rawName = json['name'];
    if (rawName is! String) return null;
    final query = _boundedString(json['query'], 120);
    final title = _boundedString(json['title'], 120);
    final content = _boundedString(json['content'], 6000);
    NoteId? noteId;
    if (json['noteId'] case final String value) {
      try {
        noteId = NoteId.parse(value);
      } on FormatException {
        noteId = null;
      }
    }
    final name = switch (rawName) {
      'search_notes' => LocalChatToolName.searchNotes,
      'create_note' => LocalChatToolName.createNote,
      'append_note' => LocalChatToolName.appendNote,
      'replace_note' => LocalChatToolName.replaceNote,
      _ => null,
    };
    if (name == null) return null;
    final valid = switch (name) {
      LocalChatToolName.searchNotes => query?.isNotEmpty == true,
      LocalChatToolName.createNote => content?.isNotEmpty == true,
      LocalChatToolName.appendNote || LocalChatToolName.replaceNote =>
        noteId != null && content?.isNotEmpty == true,
    };
    if (!valid) return null;
    return LocalChatToolCall(
      id: _uuid.v4(),
      name: name,
      query: query,
      noteId: noteId,
      title: title,
      content: content,
    );
  }

  static String? _boundedString(Object? value, int limit) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= limit ? trimmed : trimmed.substring(0, limit);
  }
}
