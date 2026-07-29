import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:fknotes/debug/app_diagnostics.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_quill_editor_page.dart';
import 'package:fknotes/pages/note_share_composer_page.dart';
import 'package:fknotes/services/note_audio_playback_service.dart';
import 'package:fknotes/services/note_audio_recording_service.dart';
import 'package:fknotes/services/note_read_aloud_service.dart';
import 'package:fknotes/services/note_watermark_service.dart';
import 'package:fknotes/widgets/note_recording_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late _MemoryNoteWriter writer;

  setUp(() => writer = _MemoryNoteWriter());

  testWidgets('debounces a valid Delta snapshot into a new note', (
    tester,
  ) async {
    final initial = Note(
      id: NoteId.generate(),
      title: '',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('第一行', {'bold': true})
          ..insert('\n第二行\n'),
      ),
      createdAt: DateTime.utc(2026, 7, 23, 15),
      updatedAt: DateTime.utc(2026, 7, 23, 15),
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: initial,
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 100),
          now: () => DateTime.utc(2026, 7, 23, 15, 1),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));

    await tester.enterText(
      find.byKey(const Key('quill-note-title')),
      '原生 Delta 笔记',
    );
    await tester.pump(const Duration(milliseconds: 99));
    expect(writer.notes, isEmpty);

    await tester.pump(const Duration(milliseconds: 2));
    await _pumpFor(tester, const Duration(milliseconds: 300));

    final saved = writer.notes.single;
    expect(saved.title, '原生 Delta 笔记');
    expect(saved.contentProjection.plainText, '第一行\n第二行');
    expect(saved.document.toDelta().toJson(), [
      {
        'insert': '第一行',
        'attributes': {'bold': true},
      },
      {'insert': '\n第二行\n'},
    ]);
    expect(find.text('已自动保存到本机'), findsOneWidget);
  });

  testWidgets('back navigation flushes changes before the debounce window', (
    tester,
  ) async {
    await tester.pumpWidget(
      _RouteTestApp(
        page: NoteQuillEditorPage(
          writerLoader: () async => writer,
          autosaveDelay: const Duration(minutes: 1),
          now: () => DateTime.utc(2026, 7, 23, 16),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quill-editor')));
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('quill-note-title')), '退出前保存');
    await tester.tap(find.byKey(const Key('quill-editor-back')));
    await _pumpFor(tester, const Duration(milliseconds: 800));

    expect(find.byKey(const Key('open-quill-editor')), findsOneWidget);
    expect(writer.notes.single.title, '退出前保存');
  });

  testWidgets('done action saves immediately and returns to the opener', (
    tester,
  ) async {
    await tester.pumpWidget(
      _RouteTestApp(
        page: NoteQuillEditorPage(
          writerLoader: () async => writer,
          autosaveDelay: const Duration(minutes: 1),
          now: () => DateTime.utc(2026, 7, 23, 16),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quill-editor')));
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('quill-note-title')), '完成后定位');
    await tester.tap(find.byKey(const Key('quill-toolbar-done')));
    await _pumpFor(tester, const Duration(milliseconds: 800));

    expect(find.byKey(const Key('open-quill-editor')), findsOneWidget);
    expect(writer.notes.single.title, '完成后定位');
  });

  testWidgets('serializes a newer edit behind an in-flight create', (
    tester,
  ) async {
    writer.createGate = Completer<void>();
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 100));

    await tester.enterText(find.byKey(const Key('quill-note-title')), '第一版');
    await _pumpFor(tester, const Duration(milliseconds: 60));
    expect(writer.createCalls, 1);

    await tester.enterText(find.byKey(const Key('quill-note-title')), '第二版');
    await _pumpFor(tester, const Duration(milliseconds: 60));
    expect(writer.updateCalls, 0);

    writer.createGate!.complete();
    await _pumpFor(tester, const Duration(milliseconds: 300));

    expect(writer.createCalls, 1);
    expect(writer.updateCalls, 1);
    expect(writer.notes.single.title, '第二版');
    expect(writer.notes.single.revision, 2);
  });

  testWidgets('records the root cause when automatic saving fails', (
    tester,
  ) async {
    writer.createError = StateError('NOT NULL constraint failed: notes.status');
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 10),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('quill-note-title')), '迁移失败诊断');
    await _pumpFor(tester, const Duration(milliseconds: 200));

    final record = AppDiagnostics.instance
        .snapshot(categories: {AppLogCategory.editor})
        .lastWhere((item) => item.event == 'note_autosave_failed');
    expect(record.level, AppLogLevel.error);
    expect(record.error, contains('notes.status'));
    expect(record.data['revision'], 0);
  });

  testWidgets('does not persist an untouched empty draft', (tester) async {
    await tester.pumpWidget(
      _RouteTestApp(
        page: NoteQuillEditorPage(
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 10),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-quill-editor')));
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('quill-editor-back')));
    await _pumpFor(tester, const Duration(milliseconds: 600));

    expect(writer.notes, isEmpty);
  });

  testWidgets('imports a gallery image into the Delta before autosaving', (
    tester,
  ) async {
    final source = PickedNoteImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      originalName: '选择的图片.png',
    );
    final now = DateTime.utc(2026, 7, 23, 17);
    NoteAsset? importedAsset;
    var pickerCalls = 0;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          pickImage: (sourceType) async {
            pickerCalls++;
            expect(sourceType, ImageSource.gallery);
            return source;
          },
          importImage: (bytes, {required originalName}) async {
            expect(bytes, [1, 2, 3]);
            importedAsset = NoteAsset(
              id: NoteAttachmentId.generate(),
              kind: NoteAssetKind.image,
              storageKey: 'notes/images/managed.png',
              originalName: originalName,
              byteLength: bytes.length,
              mimeType: 'image/png',
              createdAt: now,
              updatedAt: now,
            );
            return importedAsset!;
          },
          resolveImage: (_) => MemoryImage(_onePixelPng),
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byIcon(Icons.image_outlined));
    await _pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('quill-pick-gallery-image')));
    await _pumpFor(tester, const Duration(milliseconds: 800));

    expect(pickerCalls, 1);
    expect(importedAsset, isNotNull);
    expect(
      find.byKey(ValueKey('note-image-${importedAsset!.id.value}')),
      findsOneWidget,
    );
    expect(writer.createCalls, 1);
    final saved = writer.notes.single;
    expect(saved.assets, hasLength(1));
    expect(saved.assets.single.displayTitle, '选择的图片.png');
    expect(saved.assets.single.storageKey, startsWith('notes/images/'));
    expect(saved.document.project().referencedAttachmentIds, [
      saved.assets.single.id,
    ]);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);

    final image = find.byKey(ValueKey('note-image-${importedAsset!.id.value}'));
    await tester.ensureVisible(image);
    await tester.tap(image);
    await _pumpFor(tester, const Duration(milliseconds: 350));
    await tester.tap(
      find.byKey(ValueKey('edit-note-image-${importedAsset!.id.value}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改标题'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('image-attachment-title')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('image-attachment-title')),
      '重命名图片',
    );
    await tester.tap(find.byKey(const Key('save-attachment-title')));
    await _pumpFor(tester, const Duration(milliseconds: 300));

    expect(writer.notes.single.assets.single.displayTitle, '重命名图片');
  });

  testWidgets('watermark camera locates and burns the photo before import', (
    tester,
  ) async {
    final capturedAt = DateTime(2026, 7, 29, 14, 30);
    final location = NoteWatermarkLocation(
      latitude: 31.230416,
      longitude: 121.473701,
      accuracy: 7,
      placeName: '上海市 · 黄浦区 · 人民广场',
      capturedAt: capturedAt,
    );
    var locationCalls = 0;
    var watermarkCalls = 0;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          locateForWatermark: () async {
            locationCalls++;
            return location;
          },
          pickImage: (source) async {
            expect(source, ImageSource.camera);
            return PickedNoteImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              originalName: 'camera.jpg',
            );
          },
          watermarkImage: (bytes, selectedLocation) async {
            watermarkCalls++;
            expect(bytes, [1, 2, 3]);
            expect(selectedLocation, same(location));
            return Uint8List.fromList([9, 8, 7, 6]);
          },
          importImage: (bytes, {required originalName}) async {
            expect(bytes, [9, 8, 7, 6]);
            expect(originalName, startsWith('watermark-'));
            return NoteAsset(
              id: NoteAttachmentId.generate(),
              kind: NoteAssetKind.image,
              storageKey: 'notes/images/watermark.jpg',
              originalName: originalName,
              byteLength: bytes.length,
              mimeType: 'image/jpeg',
              createdAt: capturedAt,
              updatedAt: capturedAt,
            );
          },
          resolveImage: (_) => MemoryImage(_onePixelPng),
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const Key('quill-insert-image')));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    final gallerySize = tester.getSize(
      find.byKey(const Key('quill-pick-gallery-image')),
    );
    expect(
      tester.getSize(find.byKey(const Key('quill-take-photo'))),
      gallerySize,
    );
    expect(
      tester.getSize(find.byKey(const Key('quill-take-watermarked-photo'))),
      gallerySize,
    );
    await tester.tap(find.byKey(const Key('quill-take-watermarked-photo')));
    await _pumpFor(tester, const Duration(milliseconds: 400));

    expect(locationCalls, 1);
    expect(find.text('上海市 · 黄浦区 · 人民广场'), findsOneWidget);
    expect(watermarkCalls, 0);

    await tester.tap(find.byKey(const Key('watermark-location-confirm')));
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(watermarkCalls, 1);
    expect(writer.notes.single.assets.single.kind, NoteAssetKind.image);
    expect(
      writer.notes.single.assets.single.originalName,
      startsWith('watermark-'),
    );
  });

  testWidgets('watermark camera accepts a manually entered location', (
    tester,
  ) async {
    final capturedAt = DateTime(2026, 7, 29, 15);
    NoteWatermarkLocation? selectedLocation;
    var locationCalls = 0;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          now: () => capturedAt,
          locateForWatermark: () async {
            locationCalls++;
            throw const NoteWatermarkLocationException(
              NoteWatermarkLocationFailure.serviceDisabled,
            );
          },
          pickImage: (_) async => PickedNoteImage(
            bytes: Uint8List.fromList([1, 2, 3]),
            originalName: 'camera.jpg',
          ),
          watermarkImage: (bytes, location) async {
            selectedLocation = location;
            return Uint8List.fromList([9, 8, 7]);
          },
          importImage: (bytes, {required originalName}) async => NoteAsset(
            id: NoteAttachmentId.generate(),
            kind: NoteAssetKind.image,
            storageKey: 'notes/images/manual-watermark.jpg',
            originalName: originalName,
            byteLength: bytes.length,
            mimeType: 'image/jpeg',
            createdAt: capturedAt,
            updatedAt: capturedAt,
          ),
          resolveImage: (_) => MemoryImage(_onePixelPng),
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const Key('quill-insert-image')));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('quill-take-watermarked-photo')));
    await _pumpFor(tester, const Duration(milliseconds: 300));

    expect(find.text('请先开启系统定位服务，再使用水印相机'), findsOneWidget);
    await tester.tap(find.byKey(const Key('watermark-use-manual-location')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('watermark-manual-location-field')),
      '  公司会议室  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('watermark-location-confirm')));
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(locationCalls, 1);
    expect(selectedLocation?.normalizedPlaceName, '公司会议室');
    expect(selectedLocation?.hasCoordinates, isFalse);
    expect(writer.notes.single.assets.single.kind, NoteAssetKind.image);
  });

  testWidgets('imports a selected video as a native note card', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'fknotes_video_widget_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}/现场记录.mp4')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final now = DateTime.utc(2026, 7, 29, 15);
    NoteAsset? imported;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          pickVideo: (sourceType) async {
            expect(sourceType, ImageSource.gallery);
            return PickedNoteVideo(
              file: source,
              originalName: '现场记录.mp4',
              durationMs: 125000,
            );
          },
          importVideo: (file, {required originalName, durationMs}) async {
            expect(file.path, source.path);
            expect(originalName, '现场记录.mp4');
            expect(durationMs, 125000);
            imported = NoteAsset(
              id: NoteAttachmentId.generate(),
              kind: NoteAssetKind.video,
              storageKey: 'notes/video/managed.mp4',
              originalName: originalName,
              byteLength: file.lengthSync(),
              mimeType: 'video/mp4',
              durationMs: durationMs,
              createdAt: now,
              updatedAt: now,
            );
            return imported!;
          },
          resolveAssetPath: (_) => source.path,
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const Key('quill-insert-video')));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('quill-pick-gallery-video')));
    await _pumpFor(tester, const Duration(milliseconds: 800));

    expect(imported, isNotNull);
    expect(
      find.byKey(ValueKey('note-asset-${imported!.id.value}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('play-note-video-${imported!.id.value}')),
      findsOneWidget,
    );
    expect(find.text('02:05 · 4 B'), findsOneWidget);
    expect(writer.notes.single.assets.single.kind, NoteAssetKind.video);
    expect(writer.notes.single.document.project().referencedAttachmentIds, [
      imported!.id,
    ]);
  });

  testWidgets('imports an externally dropped image at the visible drop point', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final now = DateTime.utc(2026, 7, 23, 17, 30);
    NoteAsset? importedAsset;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          importImage: (bytes, {required originalName}) async {
            expect(bytes, _onePixelPng);
            expect(originalName, '外部拖入.png');
            importedAsset = NoteAsset(
              id: NoteAttachmentId.generate(),
              kind: NoteAssetKind.image,
              storageKey: 'notes/images/dropped.png',
              originalName: originalName,
              byteLength: bytes.length,
              mimeType: 'image/png',
              createdAt: now,
              updatedAt: now,
            );
            return importedAsset!;
          },
          resolveImage: (_) => MemoryImage(_onePixelPng),
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));

    final region = find.byKey(const Key('note-external-image-drop-region'));
    final globalPosition = tester.getCenter(
      find.byKey(const Key('quill-note-body')),
    );
    final dropTarget = tester.widget<DropTarget>(region);
    dropTarget.onDragEntered!(
      DropEventDetails(
        localPosition: const Offset(40, 80),
        globalPosition: globalPosition,
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('note-external-image-drop-overlay')),
      findsOneWidget,
    );

    dropTarget.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile.fromData(
            _onePixelPng,
            name: '外部拖入.png',
            path: '外部拖入.png',
            mimeType: 'image/png',
          ),
          DropItemFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            name: '说明.txt',
            path: '说明.txt',
            mimeType: 'text/plain',
          ),
        ],
        localPosition: const Offset(40, 80),
        globalPosition: globalPosition,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await _pumpFor(tester, const Duration(milliseconds: 800));
    debugDefaultTargetPlatformOverride = null;

    expect(
      find.byKey(const Key('note-external-image-drop-overlay')),
      findsNothing,
    );
    expect(importedAsset, isNotNull);
    expect(
      find.byKey(ValueKey('note-image-${importedAsset!.id.value}')),
      findsOneWidget,
    );
    expect(writer.notes.single.assets.single.originalName, '外部拖入.png');
    expect(find.text('部分文件不是支持的图片或超过 20 MB'), findsOneWidget);
  });

  testWidgets('records, pauses and inserts a managed audio card', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync(
      'fknotes_recording_widget_',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final recordingPath = '${temp.path}/recording.m4a';
    final recorder = _FakeAudioRecordingDriver(recordingPath);
    final playback = _FakeAudioPlaybackDriver();
    final now = DateTime.utc(2026, 7, 23, 17, 30);
    NoteAsset? imported;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          writerLoader: () async => writer,
          audioRecordingDriver: recorder,
          audioPlaybackDriver: playback,
          resolveAssetPath: (_) => '/managed/recording.m4a',
          importAudio:
              (
                source, {
                required originalName,
                required displayName,
                required durationMs,
              }) async {
                expect(source.existsSync(), isTrue);
                expect(originalName, startsWith('recording-'));
                expect(displayName, startsWith('语音笔记 '));
                imported = NoteAsset(
                  id: NoteAttachmentId.generate(),
                  kind: NoteAssetKind.audio,
                  storageKey: 'notes/audio/managed.m4a',
                  originalName: originalName,
                  displayName: displayName,
                  byteLength: source.lengthSync(),
                  mimeType: 'audio/mp4',
                  durationMs: durationMs,
                  createdAt: now,
                  updatedAt: now,
                );
                return imported!;
              },
          now: () => now,
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const Key('quill-record-audio')));
    await _pumpFor(tester, const Duration(milliseconds: 100));
    expect(recorder.startCalls, 1);
    expect(find.byType(NoteRecordingBar), findsOneWidget);
    expect(find.byKey(const Key('note-recording-waveform')), findsOneWidget);
    expect(find.byKey(const Key('quill-record-audio')), findsNothing);

    recorder.emitAmplitude(.85);
    await tester.pump();
    await tester.tap(find.byKey(const Key('pause-resume-note-recording')));
    await tester.pump();
    expect(recorder.pauseCalls, 1);
    expect(find.text('已暂停'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pause-resume-note-recording')));
    await tester.pump();
    expect(recorder.resumeCalls, 1);

    await tester.tap(find.byKey(const Key('finish-note-recording')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(recorder.stopCalls, 1);
    expect(recorder.stopCompleted, isTrue);
    expect(imported, isNotNull);
    expect(
      find.byKey(ValueKey('note-asset-${imported!.id.value}')),
      findsOneWidget,
    );
    expect(find.text(imported!.displayTitle), findsOneWidget);
    expect(writer.notes.single.assets.single.kind, NoteAssetKind.audio);
    expect(writer.notes.single.document.project().referencedAttachmentIds, [
      imported!.id,
    ]);
    expect(File(recordingPath).existsSync(), isFalse);
  });

  testWidgets('reads the current Delta text without media extraction noise', (
    tester,
  ) async {
    final imageId = NoteAttachmentId.generate();
    final now = DateTime.utc(2026, 7, 23, 18);
    final image = NoteAsset(
      id: imageId,
      kind: NoteAssetKind.image,
      storageKey: 'notes/images/read-aloud.png',
      originalName: '检查单.png',
      byteLength: 12,
      mimeType: 'image/png',
      ocrText: '不应被朗读的 OCR 文字',
      createdAt: now,
      updatedAt: now,
    );
    final note = Note(
      id: NoteId.generate(),
      title: '未保存前的标题',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('第一段\n')
          ..insert(NoteEmbed.attachment(imageId).toDeltaData())
          ..insert('\n')
          ..insert(const NoteEmbed.divider().toDeltaData())
          ..insert('\n')
          ..insert('第二段\n'),
      ),
      assets: [image],
      createdAt: now,
      updatedAt: now,
    );
    final readAloud = _FakeReadAloudDriver();

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: note,
          writerLoader: () async => writer,
          readAloud: readAloud,
          readAloudAvailabilityChecker: () async => true,
          resolveImage: (_) => MemoryImage(_onePixelPng),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const Key('quill-note-title')),
      '当前 Delta 标题',
    );

    await tester.tap(find.byKey(const Key('quill-read-aloud')));
    await _pumpFor(tester, const Duration(milliseconds: 200));

    expect(readAloud.spoken, ['当前 Delta 标题\n\n第一段\n第二段']);
    expect(readAloud.spoken.single, isNot(contains('检查单')));
    expect(readAloud.spoken.single, isNot(contains('OCR')));
    expect(readAloud.spoken.single, isNot(contains('——')));
    expect(writer.notes, isEmpty);
  });

  testWidgets(
    'missing local model keeps the inline composer idle while checking',
    (tester) async {
      final availability = Completer<bool>();
      final driver = _FakeInlineAssistantDriver();
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            writerLoader: () async => writer,
            inlineAssistantDriver: driver,
            languageModelAvailabilityChecker: () => availability.future,
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 200));

      expect(find.byKey(const Key('quill-local-assistant')), findsNothing);
      expect(
        find.byKey(const Key('quill-open-inline-assistant')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('quill-open-inline-assistant')));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      await tester.enterText(
        find.byKey(const Key('quill-inline-assistant-input')),
        '写一段开场白',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit-inline-assistant')));
      await tester.pump();

      expect(find.text('正在准备本地模型…'), findsNothing);
      expect(
        find.byKey(const Key('quill-inline-assistant-input')),
        findsOneWidget,
      );
      expect(driver.loadCalls, 0);

      availability.complete(false);
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(find.text('正在准备本地模型…'), findsNothing);
      expect(driver.loadCalls, 0);
    },
  );

  testWidgets(
    'bottom AI composer streams into the caret and undoes atomically',
    (tester) async {
      final now = DateTime.utc(2026, 7, 23, 19, 30);
      final driver = _FakeInlineAssistantDriver();
      await tester.pumpWidget(
        _TestApp(
          child: NoteQuillEditorPage(
            initialNote: Note(
              id: NoteId.generate(),
              title: '行程',
              document: NoteDocument.fromPlainText('已有想法'),
              createdAt: now,
              updatedAt: now,
            ),
            writerLoader: () async => writer,
            inlineAssistantDriver: driver,
            autosaveDelay: const Duration(milliseconds: 50),
          ),
        ),
      );
      await _pumpFor(tester, const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('quill-open-inline-assistant')));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(find.byKey(const Key('quill-inline-assistant')), findsOneWidget);
      expect(find.text('续写当前内容'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('quill-inline-assistant-input')),
        '整理一份两项清单',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit-inline-assistant')));
      await _pumpFor(tester, const Duration(milliseconds: 700));

      expect(driver.requests, hasLength(1));
      expect(
        driver.requests.single.messages.last.content,
        contains('整理一份两项清单'),
      );
      expect(driver.requests.single.messages.last.content, contains('已有想法'));
      expect(find.text('内容已写入笔记'), findsOneWidget);
      expect(writer.notes.single.contentProjection.plainText, '第一项\n第二项\n已有想法');

      await tester.tap(find.text('撤销'));
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(writer.notes.single.contentProjection.plainText, '已有想法');
    },
  );

  testWidgets('shares the current rich Delta snapshot without Markdown', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 23, 20);
    final initial = Note(
      id: NoteId.generate(),
      title: '分享测试',
      document: NoteDocument.fromDelta(
        Delta()
          ..insert('加粗', {'bold': true})
          ..insert('与正文\n'),
      ),
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: initial,
          writerLoader: () async => writer,
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('quill-editor-more')));
    await _pumpFor(tester, const Duration(milliseconds: 150));
    await tester.tap(find.text('分享为图片'));
    await _pumpFor(tester, const Duration(milliseconds: 500));

    final composer = tester.widget<NoteShareComposerPage>(
      find.byType(NoteShareComposerPage),
    );
    expect(composer.draft.title, '分享测试');
    expect(composer.draft.blocks.single.text, '加粗与正文');
    expect(composer.draft.blocks.single.text, isNot(contains('**')));
    expect(composer.draft.blocks.single.styles.single.style.bold, isTrue);
  });

  testWidgets('edits tags as canonical note metadata', (tester) async {
    final now = DateTime.utc(2026, 7, 23, 21);
    final initial = Note(
      id: NoteId.generate(),
      title: '标签测试',
      document: NoteDocument.fromPlainText('正文'),
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: initial,
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const Key('quill-edit-tags')));
    await _pumpFor(tester, const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const Key('note-tags-field')),
      '工作, 灵感, 工作',
    );
    await tester.tap(find.byKey(const Key('save-note-tags')));
    await _pumpFor(tester, const Duration(milliseconds: 500));

    expect(writer.notes.single.tags, ['工作', '灵感']);
    expect(find.byKey(const ValueKey('quill-note-tag-工作')), findsOneWidget);
    expect(find.byKey(const ValueKey('quill-note-tag-灵感')), findsOneWidget);
  });

  testWidgets('permanently deletes a persisted note after confirmation', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 23, 22);
    final persisted = Note(
      id: NoteId.generate(),
      title: '待删除笔记',
      document: NoteDocument.fromPlainText('即将永久删除'),
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    writer.notes.add(persisted);
    await tester.pumpWidget(
      _RouteTestApp(
        page: NoteQuillEditorPage(
          initialNote: persisted,
          writerLoader: () async => writer,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-quill-editor')));
    await _pumpFor(tester, const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const Key('quill-editor-more')));
    await _pumpFor(tester, const Duration(milliseconds: 120));
    await tester.tap(find.text('永久删除'));
    await _pumpFor(tester, const Duration(milliseconds: 150));
    expect(find.text('永久删除？'), findsOneWidget);
    await tester.tap(find.text('永久删除').last);
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(find.byKey(const Key('open-quill-editor')), findsOneWidget);
    expect(writer.notes, isEmpty);
    expect(writer.deletedNotes.single.id, persisted.id);
  });
}

final class _FakeAudioRecordingDriver implements NoteAudioRecordingDriver {
  _FakeAudioRecordingDriver(this.outputPath);

  final String outputPath;
  final StreamController<double> _amplitudes =
      StreamController<double>.broadcast();
  var startCalls = 0;
  var pauseCalls = 0;
  var resumeCalls = 0;
  var stopCalls = 0;
  var stopCompleted = false;
  var cancelCalls = 0;

  @override
  Stream<double> get amplitudes => _amplitudes.stream;

  void emitAmplitude(double value) => _amplitudes.add(value);

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
  }

  @override
  Future<RecordedNoteAudio> stop() async {
    stopCalls++;
    final file = File(outputPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(2048, 5));
    stopCompleted = true;
    return RecordedNoteAudio(path: outputPath);
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    final file = File(outputPath);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<void> dispose() async {
    await _amplitudes.close();
  }
}

final class _FakeAudioPlaybackDriver extends ChangeNotifier
    implements NoteAudioPlaybackDriver {
  @override
  String? activeAssetId;

  @override
  Duration duration = Duration.zero;

  @override
  String? errorMessage;

  @override
  Duration position = Duration.zero;

  @override
  NoteAudioPlaybackStatus status = NoteAudioPlaybackStatus.idle;

  @override
  Future<void> seek({
    required String assetId,
    required Duration position,
  }) async {}

  @override
  Future<void> stop() async {
    activeAssetId = null;
    status = NoteAudioPlaybackStatus.idle;
    notifyListeners();
  }

  @override
  Future<void> toggle({
    required String assetId,
    required String filePath,
  }) async {
    activeAssetId = assetId;
    status = NoteAudioPlaybackStatus.playing;
    notifyListeners();
  }
}

final class _FakeReadAloudDriver extends ChangeNotifier
    implements NoteReadAloudDriver {
  final List<String> spoken = [];

  @override
  ReadAloudStatus status = ReadAloudStatus.idle;

  @override
  String? errorMessage;

  @override
  bool get isActive => status != ReadAloudStatus.idle;

  @override
  Future<void> speak(String rawText) async {
    spoken.add(rawText);
    status = ReadAloudStatus.playing;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    status = ReadAloudStatus.idle;
    notifyListeners();
  }
}

final class _MemoryNoteWriter implements NoteEditorWriter {
  final List<Note> notes = [];
  final List<Note> deletedNotes = [];
  Completer<void>? createGate;
  Object? createError;
  var createCalls = 0;
  var updateCalls = 0;

  @override
  Future<Note> create(Note note) async {
    createCalls++;
    await createGate?.future;
    final error = createError;
    if (error != null) throw error;
    final persisted = note.copyWith(revision: 1);
    notes.add(persisted);
    return persisted;
  }

  @override
  Future<Note> update(Note note) async {
    updateCalls++;
    final persisted = note.copyWith(revision: note.revision + 1);
    final index = notes.indexWhere((candidate) => candidate.id == note.id);
    if (index < 0) throw StateError('Note was not created.');
    notes[index] = persisted;
    return persisted;
  }

  @override
  Future<void> deletePermanently(Note note) async {
    deletedNotes.add(note);
    notes.removeWhere((candidate) => candidate.id == note.id);
  }
}

final class _FakeInlineAssistantDriver implements NoteInlineAssistantDriver {
  final List<LocalLlmGenerationRequest> requests = [];
  var loadCalls = 0;
  var cancelCalls = 0;

  @override
  Future<void> load() async {
    loadCalls++;
  }

  @override
  Stream<LocalLlmGenerationEvent> generate(
    LocalLlmGenerationRequest request,
  ) async* {
    requests.add(request);
    yield const LocalLlmTextDelta('- 第一项');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    yield const LocalLlmTextDelta('\n- 第二项');
    yield const LocalLlmGenerationCompleted(
      reason: LocalLlmFinishReason.completed,
    );
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 50);
  final frames = (duration.inMilliseconds / frame.inMilliseconds).ceil();
  for (var index = 0; index < frames; index++) {
    await tester.pump(frame);
  }
}

final class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      quill.FlutterQuillLocalizations.delegate,
    ],
    home: child,
  );
}

final class _RouteTestApp extends StatelessWidget {
  const _RouteTestApp({required this.page});

  final Widget page;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      quill.FlutterQuillLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('open-quill-editor'),
            onPressed: () => Navigator.push<Object?>(
              context,
              MaterialPageRoute(builder: (_) => page),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
}
