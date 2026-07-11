import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/services/speech_transcription_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speaker diarization remains a running transcription stage', () {
    final job = TranscriptionJob(
      key: 'speaker-job',
      noteId: 1,
      filePath: 'audio/interview.wav',
      status: TranscriptionStatus.diarizing,
      speakerCount: -1,
    );
    expect(job.isRunning, isTrue);
  });

  test('speaker count accepts automatic or 2 through 8 only', () async {
    final attachment = NoteAttachment(
      type: NoteType.audio,
      filePath: 'audio/interview.wav',
      fileName: 'interview.wav',
      fileSize: 1,
      mimeType: 'audio/wav',
      createdAt: DateTime(2026, 7, 11),
    );
    for (final invalid in [0, 1, 9]) {
      expect(
        () => SpeechTranscriptionService.instance.start(
          noteId: 1,
          attachment: attachment,
          speakerCount: invalid,
        ),
        throwsArgumentError,
      );
    }
  });
}
