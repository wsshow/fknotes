import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/services/note_repository.dart';
import 'package:fknotes/services/speech_transcription_service.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late NoteRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    repository = NoteRepository(database);
    await repository.initialize();
  });

  tearDown(() => database.close());

  test('speaker diarization remains a running transcription stage', () {
    final job = TranscriptionJob(
      key: 'speaker-job',
      noteId: _noteId,
      assetId: _assetId,
      filePath: 'notes/audio/interview.wav',
      status: TranscriptionStatus.diarizing,
      speakerCount: -1,
    );
    expect(job.isRunning, isTrue);
  });

  test('speaker count accepts automatic or 2 through 8 only', () async {
    final attachment = _audioAsset();
    for (final invalid in [0, 1, 9]) {
      await expectLater(
        SpeechTranscriptionService.instance.start(
          noteId: _noteId,
          attachment: attachment,
          speakerCount: invalid,
        ),
        throwsArgumentError,
      );
    }
  });

  test(
    'writes transcript to the current Delta note and search index',
    () async {
      final created = await repository.create(_note());
      final transcribedAt = DateTime.utc(2026, 7, 23, 11);
      final writer = NoteTranscriptWriter(
        repositoryLoader: () async => repository,
      );

      final updated = await writer.write(
        noteId: created.id,
        assetId: _assetId,
        storageKey: 'notes/audio/interview.wav',
        transcript: '  会议决定下周发布  ',
        engine: 'sense-voice-small',
        now: transcribedAt,
      );

      expect(updated.revision, created.revision + 1);
      expect(
        updated.document.toDelta().toJson(),
        created.document.toDelta().toJson(),
      );
      expect(updated.assets.single.transcript, '会议决定下周发布');
      expect(updated.assets.single.transcriptionEngine, 'sense-voice-small');
      expect(updated.assets.single.transcribedAt, transcribedAt);
      expect(updated.assets.single.updatedAt, transcribedAt);
      expect((await repository.search('下周发布')).single.id, created.id);
    },
  );

  test(
    'rejects a result when its exact audio asset no longer exists',
    () async {
      final created = await repository.create(_note());
      final writer = NoteTranscriptWriter(
        repositoryLoader: () async => repository,
      );

      await expectLater(
        writer.write(
          noteId: created.id,
          assetId: NoteAttachmentId.parse(
            '8b79d346-0d47-4057-9060-ababc553c64f',
          ),
          storageKey: 'notes/audio/interview.wav',
          transcript: '不应写入',
          engine: 'sense-voice-small',
        ),
        throwsStateError,
      );
      expect(
        (await repository.get(created.id))?.assets.single.transcript,
        isNull,
      );
    },
  );
}

final _noteId = NoteId.parse('f134fcaa-f02c-4edb-a587-9f74aaad0f98');
final _assetId = NoteAttachmentId.parse('3d2be3d5-00c8-4f5c-8e69-e90085dc2873');

NoteAsset _audioAsset() {
  final now = DateTime.utc(2026, 7, 23, 10);
  return NoteAsset(
    id: _assetId,
    kind: NoteAssetKind.audio,
    storageKey: 'notes/audio/interview.wav',
    originalName: 'interview.wav',
    byteLength: 1,
    mimeType: 'audio/wav',
    durationMs: 1000,
    createdAt: now,
    updatedAt: now,
  );
}

Note _note() {
  final now = DateTime.utc(2026, 7, 23, 10);
  return Note(
    id: _noteId,
    title: '访谈记录',
    document: NoteDocument.fromDelta(
      Delta()
        ..insert(NoteEmbed.attachment(_assetId).toDeltaData())
        ..insert('\n'),
    ),
    assets: [_audioAsset()],
    createdAt: now,
    updatedAt: now,
  );
}
