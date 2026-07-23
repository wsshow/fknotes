import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart' show Document;
import 'package:flutter_quill/quill_delta.dart';
import 'package:uuid/uuid.dart';

/// The stable identity of a file owned by a note.
///
/// Documents store this ID instead of a path. The attachment repository is
/// responsible for resolving the ID to metadata and managed local storage.
final class NoteAttachmentId {
  NoteAttachmentId._(this.value);

  factory NoteAttachmentId.generate() => NoteAttachmentId._(const Uuid().v4());

  factory NoteAttachmentId.parse(String value) {
    if (!_uuidPattern.hasMatch(value)) {
      throw FormatException('Invalid canonical attachment ID: $value');
    }
    return NoteAttachmentId._(value);
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteAttachmentId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

enum NoteEmbedKind { attachment, divider }

/// A domain-owned Quill embed.
///
/// Keeping the payload deliberately small prevents presentation details and
/// local file paths from leaking into the canonical document.
final class NoteEmbed {
  const NoteEmbed._({required this.kind, this.attachmentId});

  factory NoteEmbed.attachment(NoteAttachmentId id) =>
      NoteEmbed._(kind: NoteEmbedKind.attachment, attachmentId: id);

  const NoteEmbed.divider() : kind = NoteEmbedKind.divider, attachmentId = null;

  static const String attachmentType = 'fknotes.attachment';
  static const String dividerType = 'fknotes.divider';

  final NoteEmbedKind kind;
  final NoteAttachmentId? attachmentId;

  Map<String, Object> toDeltaData() => switch (kind) {
    NoteEmbedKind.attachment => <String, Object>{
      attachmentType: <String, Object>{'id': attachmentId!.value},
    },
    NoteEmbedKind.divider => const <String, Object>{dividerType: true},
  };

  static NoteEmbed parse(Object? data) {
    if (data is! Map || data.length != 1) {
      throw const FormatException('A note embed must contain one type.');
    }
    final type = data.keys.single;
    final payload = data.values.single;
    if (type == attachmentType) {
      if (payload is! Map || payload.length != 1 || payload['id'] is! String) {
        throw const FormatException('Invalid attachment embed payload.');
      }
      return NoteEmbed.attachment(
        NoteAttachmentId.parse(payload['id'] as String),
      );
    }
    if (type == dividerType && payload == true) {
      return const NoteEmbed.divider();
    }
    throw FormatException('Unsupported note embed type: $type');
  }
}

typedef NoteEmbedTextResolver = String Function(NoteEmbed embed);

/// A presentation-neutral view of a note document.
final class NoteDocumentProjection {
  const NoteDocumentProjection({
    required this.plainText,
    required this.searchText,
    required this.referencedAttachmentIds,
    required this.hasEmbeds,
  });

  final String plainText;
  final String searchText;
  final List<NoteAttachmentId> referencedAttachmentIds;
  final bool hasEmbeds;

  bool get isVisuallyEmpty => plainText.trim().isEmpty && !hasEmbeds;
}

/// The sole canonical body model for a note.
///
/// Storage uses a small versioned envelope around Quill Delta JSON. Only
/// insert-only document deltas are accepted; change deltas must be applied by
/// Quill before persistence.
final class NoteDocument {
  NoteDocument._(this._delta, this._encoded);

  factory NoteDocument.empty() {
    final delta = Delta()..insert('\n');
    return NoteDocument.fromDelta(delta);
  }

  factory NoteDocument.fromPlainText(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final delta = Delta()..insert(normalized);
    if (!normalized.endsWith('\n')) {
      delta.insert('\n');
    }
    return NoteDocument.fromDelta(delta);
  }

  factory NoteDocument.fromDelta(Delta source) {
    final delta = _canonicalize(source);
    _validateDocumentDelta(delta);
    final envelope = <String, Object>{
      'schemaVersion': schemaVersion,
      'delta': delta.toJson(),
    };
    return NoteDocument._(delta, jsonEncode(envelope));
  }

  factory NoteDocument.fromJsonString(String encoded) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException catch (error) {
      throw FormatException('Invalid note document JSON: ${error.message}');
    }
    if (decoded is! Map ||
        decoded.length != 2 ||
        decoded['schemaVersion'] != schemaVersion ||
        decoded['delta'] is! List) {
      throw const FormatException('Unsupported note document envelope.');
    }
    final delta = Delta.fromJson(decoded['delta'] as List);
    return NoteDocument.fromDelta(delta);
  }

  static const int schemaVersion = 1;
  static const String objectReplacementCharacter = '\uFFFC';

  final Delta _delta;
  final String _encoded;

  String toJsonString() => _encoded;

  Delta toDelta() => Delta.from(_delta);

  Document toQuillDocument() => Document.fromJson(_delta.toJson());

  NoteDocumentProjection project({NoteEmbedTextResolver? resolveEmbedText}) {
    final text = StringBuffer();
    final attachmentIds = <NoteAttachmentId>[];
    final seenAttachmentIds = <NoteAttachmentId>{};
    var hasEmbeds = false;

    for (final operation in _delta.operations) {
      final data = operation.data;
      if (data is String) {
        text.write(data);
        continue;
      }
      final embed = NoteEmbed.parse(data);
      hasEmbeds = true;
      final attachmentId = embed.attachmentId;
      if (attachmentId != null && seenAttachmentIds.add(attachmentId)) {
        attachmentIds.add(attachmentId);
      }
      text.write(resolveEmbedText?.call(embed) ?? '');
    }

    final plainText = _withoutTerminalNewline(text.toString());
    return NoteDocumentProjection(
      plainText: plainText,
      searchText: plainText.replaceAll(RegExp(r'\s+'), ' ').trim(),
      referencedAttachmentIds: List.unmodifiable(attachmentIds),
      hasEmbeds: hasEmbeds,
    );
  }

  static String _withoutTerminalNewline(String value) =>
      value.endsWith('\n') ? value.substring(0, value.length - 1) : value;

  static Delta _canonicalize(Delta source) {
    final canonical = Delta();
    for (final operation in source.operations) {
      if (operation.isInsert && operation.data is! String) {
        // Quill can apply a selected inline style to an embed while formatting
        // across the whole document. It has no visual meaning for our block
        // nodes, so do not persist that incidental editor state.
        canonical.insert(operation.data);
      } else {
        canonical.push(operation);
      }
    }
    return canonical;
  }

  static void _validateDocumentDelta(Delta delta) {
    if (delta.isEmpty) {
      throw const FormatException('A note document cannot be empty.');
    }

    var lineHasText = false;
    var expectsNewlineAfterEmbed = false;
    var endsWithNewline = false;

    for (final operation in delta.operations) {
      if (!operation.isInsert) {
        throw const FormatException(
          'A persisted note must be an insert-only document delta.',
        );
      }
      final data = operation.data;
      if (data is String) {
        if (data.contains('\r')) {
          throw const FormatException('Note documents use LF line endings.');
        }
        if (data.contains(objectReplacementCharacter)) {
          throw const FormatException(
            'Object replacement characters must be represented as embeds.',
          );
        }
        for (final codeUnit in data.codeUnits) {
          final isNewline = codeUnit == 10;
          if (expectsNewlineAfterEmbed) {
            if (!isNewline) {
              throw const FormatException(
                'A block embed must occupy its own line.',
              );
            }
            expectsNewlineAfterEmbed = false;
            lineHasText = false;
            endsWithNewline = true;
            continue;
          }
          if (isNewline) {
            lineHasText = false;
            endsWithNewline = true;
          } else {
            lineHasText = true;
            endsWithNewline = false;
          }
        }
        continue;
      }

      if (lineHasText || expectsNewlineAfterEmbed) {
        throw const FormatException('A block embed must occupy its own line.');
      }
      NoteEmbed.parse(data);
      expectsNewlineAfterEmbed = true;
      endsWithNewline = false;
    }

    if (expectsNewlineAfterEmbed || !endsWithNewline) {
      throw const FormatException(
        'A Quill note document must end with a newline.',
      );
    }

    try {
      jsonEncode(delta.toJson());
    } on JsonUnsupportedObjectError {
      throw const FormatException(
        'The note document is not JSON serializable.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteDocument && other._encoded == _encoded;

  @override
  int get hashCode => _encoded.hashCode;
}
