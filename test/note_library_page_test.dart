import 'dart:convert';
import 'dart:typed_data';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/pages/note_library_page.dart';
import 'package:fknotes/providers/note_library_controller.dart';
import 'package:fknotes/widgets/note_delta_preview.dart';
import 'package:fknotes/widgets/note_quill_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _PageLibraryStore store;
  late NoteLibraryController controller;

  setUp(() {
    store = _PageLibraryStore([
      _note(
        '格式笔记',
        document: Delta()
          ..insert('加粗正文', {'bold': true})
          ..insert('\n'),
      ),
      _note('普通笔记', document: Delta()..insert('可搜索内容\n')),
    ]);
    controller = NoteLibraryController(storeLoader: () async => store);
    addTearDown(controller.dispose);
  });

  testWidgets('shows styled Delta cards without organizational scopes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    expect(find.text('格式笔记'), findsOneWidget);
    expect(find.text('普通笔记'), findsOneWidget);
    expect(find.byType(NoteRichDocumentPreview), findsOneWidget);
    expect(find.byType(NoteDeltaPreview), findsOneWidget);
    expect(
      find.byKey(ValueKey('folded-note-preview-${store.notes.last.id.value}')),
      findsOneWidget,
    );
    expect(find.text('可搜索内容', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('note-document-preview-fade')), findsNothing);
    expect(find.text('收藏'), findsNothing);
    expect(find.text('归档'), findsNothing);
    expect(find.text('回收站'), findsNothing);
    expect(find.text('搜索笔记'), findsOneWidget);
    expect(find.byKey(const Key('delta-library-search-pull')), findsOneWidget);
    expect(find.byKey(const Key('delta-library-search')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('search-pull-tab-surface'))),
      const Size(100, 28),
    );

    final paperTab = find.byKey(const Key('brand-spine-paper-tab'));
    final noteSheet = find.byKey(
      ValueKey('delta-note-${store.notes.first.id.value}'),
    );
    expect(tester.getSize(paperTab), const Size(38, 208));
    expect(tester.getTopLeft(paperTab), const Offset(0, 24));
    expect(tester.getSize(noteSheet).width, 640);
    final noteSheetRect = tester.getRect(noteSheet);
    final viewportWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(noteSheetRect.left, viewportWidth - noteSheetRect.right);
    expect(find.byKey(const Key('brand-spine-item-count')), findsNothing);
  });

  testWidgets('debounces search and never exposes Markdown marker fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('delta-library-search-pull')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('delta-library-search')),
      '可搜索',
    );
    await tester.pump(const Duration(milliseconds: 279));
    expect(find.text('格式笔记'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2));
    await _pump(tester);

    expect(find.text('普通笔记'), findsOneWidget);
    expect(find.text('格式笔记'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('pull gesture expands search and collapse restores the deck', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    await tester.drag(
      find.byKey(const Key('delta-library-search-pull')),
      const Offset(0, 28),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delta-library-search')), findsOneWidget);
    expect(find.byType(SearchBar), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('search-pull-handle-surface'))),
      const Size(320, 48),
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('delta-library-search')))
          .decoration
          ?.filled,
      isFalse,
    );
    expect(_searchEditable(tester).focusNode.hasFocus, isFalse);

    await tester.enterText(
      find.byKey(const Key('delta-library-search')),
      '可搜索',
    );
    await tester.pump(const Duration(milliseconds: 281));
    await _pump(tester);
    expect(find.text('格式笔记'), findsNothing);

    await tester.tap(find.byKey(const Key('delta-library-collapse-search')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delta-library-search-pull')), findsOneWidget);
    expect(find.text('格式笔记'), findsOneWidget);
    expect(find.text('普通笔记'), findsOneWidget);
    expect(controller.query, isEmpty);
  });

  testWidgets(
    'pulling down the first card opens a tiled shelf without refresh UI',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _TestApp(child: NoteLibraryPage(controller: controller)),
      );
      await _pump(tester);

      expect(find.byType(RefreshIndicator), findsNothing);
      expect(find.byKey(const Key('delta-library-shelf-page')), findsNothing);

      final rolodex = find.byKey(const Key('delta-library-rolodex'));
      final initialTop = tester.getTopLeft(rolodex).dy;
      final partialPull = await tester.startGesture(tester.getCenter(rolodex));
      await partialPull.moveBy(const Offset(0, 70));
      await tester.pump();

      expect(find.byKey(const Key('delta-library-shelf-page')), findsNothing);
      expect(
        find.byKey(const Key('delta-library-shelf-pull-indicator')),
        findsOneWidget,
      );
      final partialProgress = tester
          .widget<CircularProgressIndicator>(
            find.byKey(const Key('delta-library-shelf-pull-progress')),
          )
          .value!;
      expect(partialProgress, inInclusiveRange(.5, .6));
      expect(tester.getTopLeft(rolodex).dy, greaterThan(initialTop));

      await partialPull.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delta-library-shelf-page')), findsNothing);
      expect(
        find.byKey(const Key('delta-library-shelf-pull-indicator')),
        findsNothing,
      );
      expect(tester.getTopLeft(rolodex).dy, closeTo(initialTop, .1));

      final fullPull = await tester.startGesture(tester.getCenter(rolodex));
      await fullPull.moveBy(const Offset(0, 140));
      await tester.pump();
      expect(find.byKey(const Key('delta-library-shelf-page')), findsNothing);
      expect(find.text('松开进入平铺视图'), findsOneWidget);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byKey(const Key('delta-library-shelf-pull-progress')),
            )
            .value,
        1,
      );

      await fullPull.up();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delta-library-shelf-page')), findsOneWidget);
      expect(find.byKey(const Key('delta-library-shelf-grid')), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsNothing);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(find.text('所有笔记'), findsOneWidget);
      expect(find.text('2 条笔记'), findsOneWidget);
      expect(
        find.byKey(ValueKey('delta-shelf-note-${store.notes.first.id.value}')),
        findsOneWidget,
      );
      final grid = tester.widget<GridView>(
        find.byKey(const Key('delta-library-shelf-grid')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        3,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const Key('delta-library-shelf-filter-image')),
      );
      await tester.pumpAndSettle();
      expect(find.text('没有找到匹配的笔记'), findsOneWidget);
      await tester.tap(find.byKey(const Key('delta-library-shelf-filter-all')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delta-library-enter-selection')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('delta-library-selection-header')),
        findsOneWidget,
      );
      expect(find.text('选择笔记'), findsOneWidget);
      expect(find.text('已选择 0 篇'), findsOneWidget);
      expect(
        find.byKey(const Key('delta-library-selection-actions')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('delta-library-selection-header')),
          matching: find.byKey(const Key('delta-library-pin-selected')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('delta-library-selection-actions')),
          matching: find.byKey(const Key('delta-library-pin-selected')),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('delta-library-selection-grid')),
        findsNothing,
      );
      expect(find.byKey(const Key('delta-library-shelf-grid')), findsOneWidget);

      await tester.tap(find.byKey(const Key('delta-library-select-all')));
      await tester.pump();
      expect(find.text('已选择 2 篇'), findsOneWidget);
      expect(find.text('取消全选'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delta-library-select-all')));
      await tester.pump();
      expect(find.text('已选择 0 篇'), findsOneWidget);
      expect(
        find.byKey(const Key('delta-library-selection-header')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(ValueKey('delta-shelf-note-${store.notes.first.id.value}')),
      );
      await tester.pump();
      expect(find.text('已选择 1 篇'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delta-library-exit-selection')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delta-library-shelf-page')), findsOneWidget);

      await tester.tap(find.byKey(const Key('delta-library-collapse-shelf')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delta-library-rolodex')), findsOneWidget);
    },
  );

  testWidgets('tapping a blank home area collapses expanded search', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('delta-library-search-pull')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delta-library-search')));
    await tester.enterText(
      find.byKey(const Key('delta-library-search')),
      '可搜索',
    );
    await tester.pump(const Duration(milliseconds: 281));
    await _pump(tester);

    expect(find.byKey(const Key('delta-library-search')), findsOneWidget);
    expect(_searchEditable(tester).focusNode.hasFocus, isTrue);
    expect(controller.query, '可搜索');

    await tester.tapAt(const Offset(56, 400));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delta-library-search')), findsNothing);
    expect(find.byKey(const Key('delta-library-search-pull')), findsOneWidget);
    expect(controller.query, isEmpty);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('keeps creation on home and opens existing notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          controller: controller,
          editorBuilder: (editorContext, note) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('close-test-editor'),
                onPressed: () => Navigator.pop(editorContext),
                child: Text(note?.title ?? '新建编辑器'),
              ),
            ),
          ),
        ),
      ),
    );
    await _pump(tester);

    expect(find.byKey(const Key('delta-library-new-note')), findsNothing);

    await tester.tap(find.text('格式笔记'));
    await tester.pumpAndSettle();
    expect(find.text('格式笔记'), findsOneWidget);
  });

  testWidgets('card switching keeps intermediate animation frames in bounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    await tester.tap(find.text('普通笔记'));
    for (final duration in const [
      Duration(milliseconds: 40),
      Duration(milliseconds: 40),
      Duration(milliseconds: 40),
      Duration(milliseconds: 100),
    ]) {
      await tester.pump(duration);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('index dial moves beneath a stationary reading capsule', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    final pointer = find.byKey(const Key('index-ticks-reading'));
    final dial = find.byKey(const Key('index-ticks-dial'));
    expect(pointer, findsOneWidget);
    expect(find.byKey(const Key('index-ticks-pointer')), findsNothing);
    expect(dial, findsOneWidget);
    final pointerBefore = tester.getRect(pointer);
    expect(pointerBefore.right, 800);
    expect(
      tester.widget<Text>(find.byKey(const Key('index-ticks-current'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('index-ticks-total'))).data,
      '2',
    );

    await tester.tap(find.text('普通笔记'));
    await tester.pumpAndSettle();

    expect(tester.getRect(pointer), pointerBefore);
    expect(
      tester.widget<Text>(find.byKey(const Key('index-ticks-current'))).data,
      '2',
    );
  });

  testWidgets('returning from a note does not restore search focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: NoteLibraryPage(
          controller: controller,
          editorBuilder: (editorContext, note) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('close-test-editor'),
                onPressed: () => Navigator.pop(editorContext),
                child: const Text('返回主页'),
              ),
            ),
          ),
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.byKey(const Key('delta-library-search-pull')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delta-library-search')));
    await tester.pump();
    expect(_searchEditable(tester).focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('格式笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-test-editor')));
    await tester.pumpAndSettle();

    expect(_searchEditable(tester).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('card deletion requires confirmation and removes the note', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    final menu = find.byKey(
      ValueKey('delta-note-menu-${store.notes.first.id.value}'),
    );
    expect(tester.getSize(menu), const Size.square(48));
    await tester.tapAt(tester.getRect(menu).topLeft + const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever_outlined), findsNothing);
    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();
    expect(find.text('永久删除？'), findsOneWidget);
    await tester.tap(find.text('永久删除').last);
    await _pump(tester);

    expect(find.text('格式笔记'), findsNothing);
    expect(store.notes, hasLength(1));
  });

  testWidgets(
    'image notes keep images inline with the document instead of a side cover',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final asset = _imageAsset('61.png');
      store.notes
        ..clear()
        ..add(
          _note(
            '图片笔记',
            document: Delta()
              ..insert('正文预览\n')
              ..insert(NoteEmbed.attachment(asset.id).toDeltaData())
              ..insert('\n'),
            assets: [asset],
            tags: const ['cc'],
          ),
        );

      await tester.pumpWidget(
        _TestApp(
          child: NoteLibraryPage(
            controller: controller,
            resolveImage: (_) => MemoryImage(_onePixelPng),
          ),
        ),
      );
      await _pump(tester);

      expect(find.textContaining('61.png'), findsNothing);
      final bodyText = find.text('正文预览', findRichText: true);
      expect(bodyText, findsOneWidget);
      expect(
        find.byKey(ValueKey('delta-note-cover-${store.notes.single.id.value}')),
        findsNothing,
      );
      final inlineImage = find.byKey(ValueKey('note-image-${asset.id.value}'));
      expect(inlineImage, findsOneWidget);
      expect(
        find.byKey(ValueKey('note-image-frame-${asset.id.value}')),
        findsNothing,
      );
      expect(
        tester.getRect(bodyText).bottom,
        lessThanOrEqualTo(tester.getRect(inlineImage).top),
      );
      expect(
        find.byKey(
          ValueKey('delta-note-document-${store.notes.single.id.value}'),
        ),
        findsOneWidget,
      );
      final noteId = store.notes.single.id.value;
      final sheetRect = tester.getRect(
        find.byKey(ValueKey('delta-note-$noteId')),
      );
      final timeRect = tester.getRect(
        find.byKey(ValueKey('delta-note-footer-time-$noteId')),
      );
      expect(sheetRect.right - timeRect.right, closeTo(28, 1));

      await tester.drag(
        find.byKey(const Key('delta-library-rolodex')),
        const Offset(0, 220),
      );
      await tester.pumpAndSettle();
      final shelfCover = find.byKey(ValueKey('delta-shelf-note-cover-$noteId'));
      expect(shelfCover, findsOneWidget);
      expect(
        find.descendant(of: shelfCover, matching: find.byType(Image)),
        findsOneWidget,
      );
    },
  );

  testWidgets('long document previews fade into the paper at the cutoff', (
    tester,
  ) async {
    store.notes
      ..clear()
      ..add(
        _note(
          '长笔记',
          document: Delta()
            ..insert(
              List.generate(32, (index) => '第 ${index + 1} 段正文').join('\n'),
            )
            ..insert('\n'),
        ),
      );

    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    expect(find.byKey(const Key('note-document-preview-fade')), findsOneWidget);
    final fade = tester.widget<ShaderMask>(
      find.byKey(const Key('note-document-preview-fade')),
    );
    expect(fade.blendMode, BlendMode.dstIn);
  });

  testWidgets('bulk audio selection reuses the tiled shelf layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final audio = _audioAsset();
    store.notes
      ..clear()
      ..addAll([
        _note(
          '录音笔记',
          document: Delta()
            ..insert(NoteEmbed.attachment(audio.id).toDeltaData())
            ..insert('\n正文\n'),
          assets: [audio],
        ),
        _note('普通笔记', document: Delta()..insert('正文\n')),
      ]);

    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);
    await tester.longPress(
      find.byKey(ValueKey('delta-note-${store.notes.first.id.value}')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delta-library-shelf-grid')), findsOneWidget);
    expect(
      find.byKey(ValueKey('delta-shelf-note-${store.notes.first.id.value}')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Icon>(
            find.byKey(
              ValueKey('delta-shelf-note-kind-${store.notes.first.id.value}'),
            ),
          )
          .icon,
      Icons.graphic_eq_rounded,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press selects notes for bulk pinning and deletion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(child: NoteLibraryPage(controller: controller)),
    );
    await _pump(tester);

    final first = find.byKey(
      ValueKey('delta-note-${store.notes.first.id.value}'),
    );
    await tester.longPress(first);
    await tester.pump();
    expect(
      find.byKey(const Key('delta-library-selection-header')),
      findsOneWidget,
    );
    expect(find.text('选择笔记'), findsOneWidget);
    expect(
      find.byKey(const Key('delta-library-selection-actions')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('delta-library-shelf-grid')), findsOneWidget);
    expect(
      find.byKey(
        ValueKey('delta-shelf-note-selection-${store.notes.first.id.value}'),
      ),
      findsOneWidget,
    );
    expect(find.text('已选择 1 篇'), findsOneWidget);

    final second = find.byKey(
      ValueKey('delta-shelf-note-${store.notes.last.id.value}'),
    );
    await tester.tap(second);
    await tester.pump();
    expect(find.text('已选择 2 篇'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delta-library-pin-selected')));
    await _pump(tester);
    expect(store.notes.every((note) => note.isPinned), isTrue);
    expect(find.text('已选择 2 篇'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delta-library-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('永久删除这 2 篇笔记？'), findsOneWidget);
    await tester.tap(find.text('永久删除').last);
    await tester.pumpAndSettle();

    expect(store.notes, isEmpty);
    expect(
      find.byKey(const Key('delta-library-selection-header')),
      findsNothing,
    );
  });
}

Future<void> _pump(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

EditableText _searchEditable(WidgetTester tester) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('delta-library-search')),
        matching: find.byType(EditableText),
      ),
    );

final class _PageLibraryStore implements NoteLibraryStore {
  _PageLibraryStore(this.notes);

  final List<Note> notes;

  @override
  Future<List<Note>> list() async => List.of(notes);

  @override
  Future<List<Note>> search(String query) async => notes
      .where((note) => note.searchText.contains(query))
      .toList(growable: false);

  @override
  Future<Note> update(Note note) async {
    final persisted = note.copyWith(revision: note.revision + 1);
    final index = notes.indexWhere((candidate) => candidate.id == note.id);
    notes[index] = persisted;
    return persisted;
  }

  @override
  Future<void> deletePermanently(Note note) async {
    notes.removeWhere((candidate) => candidate.id == note.id);
  }
}

Note _note(
  String title, {
  required Delta document,
  List<NoteAsset> assets = const [],
  List<String> tags = const [],
}) {
  final now = DateTime.utc(2026, 7, 23, 12);
  return Note(
    id: NoteId.generate(),
    title: title,
    document: NoteDocument.fromDelta(document),
    assets: assets,
    tags: tags,
    revision: 1,
    createdAt: now,
    updatedAt: now,
  );
}

NoteAsset _imageAsset(String originalName) {
  final now = DateTime.utc(2026, 7, 23, 12);
  return NoteAsset(
    id: NoteAttachmentId.generate(),
    kind: NoteAssetKind.image,
    storageKey: 'notes/images/${NoteAttachmentId.generate().value}.png',
    originalName: originalName,
    byteLength: _onePixelPng.length,
    mimeType: 'image/png',
    createdAt: now,
    updatedAt: now,
  );
}

NoteAsset _audioAsset() {
  final now = DateTime.utc(2026, 7, 23, 12);
  return NoteAsset(
    id: NoteAttachmentId.generate(),
    kind: NoteAssetKind.audio,
    storageKey: 'notes/audio/${NoteAttachmentId.generate().value}.m4a',
    originalName: 'recording.m4a',
    displayName: '语音笔记',
    byteLength: 4096,
    mimeType: 'audio/mp4',
    durationMs: 92340,
    createdAt: now,
    updatedAt: now,
  );
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

final class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}
