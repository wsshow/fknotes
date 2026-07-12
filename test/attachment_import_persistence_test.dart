import 'dart:io';

import 'package:fknotes/models/note_entry.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/video_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final imports = AttachmentImportService.instance;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fknotes_import_jobs_');
    await FileStorageService.instance.init(baseDir: root.path);
    await imports.resetForTesting(deletePersistence: true);
    await imports.restoreJobs();
  });

  tearDown(() async {
    await imports.resetForTesting(deletePersistence: true);
    await root.delete(recursive: true);
  });

  test('job JSON preserves note ownership and recovery metadata', () {
    final now = DateTime.utc(2026, 7, 12, 12);
    final job = AttachmentImportJob(
      id: 'job-json',
      type: NoteType.document,
      fileName: '方案.pdf',
      mimeType: 'application/pdf',
      totalBytes: 4096,
      copiedBytes: 2048,
      noteId: 18,
      ownsNoteDraft: true,
      createdAt: now,
      updatedAt: now,
    );

    final restored = AttachmentImportJob.fromJson(job.toJson());

    expect(restored.id, job.id);
    expect(restored.type, NoteType.document);
    expect(restored.noteId, 18);
    expect(restored.ownsNoteDraft, isTrue);
    expect(restored.copiedBytes, 2048);
    expect(restored.createdAt, now);
  });

  test('restores a completed native file after process interruption', () async {
    const jobId = 'native-recovery';
    imports.addJobForTesting(
      const AttachmentImportJob(
        id: jobId,
        type: NoteType.document,
        fileName: '资料.pdf',
        mimeType: 'application/pdf',
        totalBytes: 4,
      ),
    );
    imports.assignToNote(jobId, 33, ownsNoteDraft: true);
    await imports.flushPersistenceForTesting();
    final completedFile = File(p.join(root.path, 'documents', '$jobId.pdf'));
    await completedFile.writeAsBytes([1, 2, 3, 4]);

    await imports.resetForTesting();
    await imports.restoreJobs();

    final restored = imports.jobById(jobId);
    expect(restored?.status, AttachmentImportStatus.completed);
    expect(restored?.filePath, 'documents/$jobId.pdf');
    expect(restored?.fileSize, 4);
    expect(restored?.ownsNoteDraft, isTrue);
  });

  test(
    'marks an interrupted copy as retryable when no file survived',
    () async {
      const jobId = 'missing-recovery';
      imports.addJobForTesting(
        const AttachmentImportJob(
          id: jobId,
          type: NoteType.video,
          fileName: '现场.mp4',
          mimeType: 'video/mp4',
          totalBytes: 1024,
        ),
      );
      imports.assignToNote(jobId, 44);
      await imports.flushPersistenceForTesting();

      await imports.resetForTesting();
      await imports.restoreJobs();

      final restored = imports.jobById(jobId);
      expect(restored?.status, AttachmentImportStatus.failed);
      expect(restored?.errorMessage, contains('应用退出'));
    },
  );
}
