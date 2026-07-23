import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_quill_editor_page.dart';
import 'package:fknotes/pages/note_share_composer_page.dart';
import 'package:fknotes/services/note_assistant_prompt_builder.dart';
import 'package:fknotes/services/note_read_aloud_service.dart';
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
              storageKey: 'images/managed.png',
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

    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
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
    expect(saved.assets.single.storageKey, startsWith('images/'));
    expect(saved.document.project().referencedAttachmentIds, [
      saved.assets.single.id,
    ]);
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
  });

  testWidgets('reads the current Delta text without media extraction noise', (
    tester,
  ) async {
    final imageId = NoteAttachmentId.generate();
    final now = DateTime.utc(2026, 7, 23, 18);
    final image = NoteAsset(
      id: imageId,
      kind: NoteAssetKind.image,
      storageKey: 'images/read-aloud.png',
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

  testWidgets('applies local assistant output as formatted Delta content', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 23, 19);
    final initial = Note(
      id: NoteId.generate(),
      title: '项目备忘',
      document: NoteDocument.fromPlainText('原始正文'),
      tags: const ['工作'],
      createdAt: now,
      updatedAt: now,
    );
    String? receivedContent;
    Set<NoteAssistantPlacement>? receivedPlacements;

    await tester.pumpWidget(
      _TestApp(
        child: NoteQuillEditorPage(
          initialNote: initial,
          writerLoader: () async => writer,
          autosaveDelay: const Duration(milliseconds: 50),
          assistantResultPresenter:
              (
                context, {
                required action,
                required scope,
                required title,
                required content,
                required languageCode,
                required placements,
              }) async {
                expect(scope, NoteAssistantScope.fullNote);
                expect(title, isEmpty);
                expect(languageCode, 'zh');
                receivedContent = content;
                receivedPlacements = placements;
                return const NoteAssistantResult(
                  text: '**核心结论**',
                  placement: NoteAssistantPlacement.append,
                );
              },
        ),
      ),
    );
    await _pumpFor(tester, const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('quill-local-assistant')));
    await _pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('note-assistant-scope-fullNote')));
    await tester.pump();
    final summarize = find.byKey(const Key('note-assistant-task-summarize'));
    await tester.ensureVisible(summarize);
    await tester.pump();
    await tester.tap(summarize);
    await _pumpFor(tester, const Duration(milliseconds: 500));

    expect(receivedContent, contains('标题:\n项目备忘'));
    expect(receivedContent, contains('标签:\n工作'));
    expect(receivedContent, contains('正文:\n原始正文'));
    expect(receivedPlacements, {
      NoteAssistantPlacement.replace,
      NoteAssistantPlacement.append,
    });
    final saved = writer.notes.single;
    expect(saved.contentProjection.plainText, '原始正文\n本地助手摘要\n核心结论');
    expect(saved.contentProjection.plainText, isNot(contains('**')));
    expect(
      saved.document.toDelta().operations.any(
        (operation) =>
            operation.data == '核心结论' && operation.attributes?['bold'] == true,
      ),
      isTrue,
    );
  });

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

  testWidgets('moves a persisted note to trash from the editor menu', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 23, 22);
    final persisted = Note(
      id: NoteId.generate(),
      title: '待删除笔记',
      document: NoteDocument.fromPlainText('仍可恢复'),
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
    await tester.tap(find.text('移到回收站'));
    await _pumpFor(tester, const Duration(milliseconds: 700));

    expect(find.byKey(const Key('open-quill-editor')), findsOneWidget);
    expect(writer.notes.single.status, NoteStatus.trashed);
    expect(writer.notes.single.trashedAt, isNotNull);
  });

  testWidgets('permanently deletes only from the trash with confirmation', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 23, 23);
    final trashed = Note(
      id: NoteId.generate(),
      title: '回收站笔记',
      document: NoteDocument.fromPlainText('即将永久删除'),
      status: NoteStatus.trashed,
      revision: 3,
      createdAt: now,
      updatedAt: now,
      trashedAt: now,
    );
    writer.notes.add(trashed);
    await tester.pumpWidget(
      _RouteTestApp(
        page: NoteQuillEditorPage(
          initialNote: trashed,
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
    expect(writer.deletedNotes.single.id, trashed.id);
  });
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
  var createCalls = 0;
  var updateCalls = 0;

  @override
  Future<Note> create(Note note) async {
    createCalls++;
    await createGate?.future;
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
            onPressed: () => Navigator.push<void>(
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
