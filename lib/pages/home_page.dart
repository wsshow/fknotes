import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models/note_entry.dart';
import '../providers/note_provider.dart';
import '../services/backup_service.dart';
import '../services/file_storage_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_popup_menu.dart';
import '../widgets/brand_mark.dart';
import '../widgets/note_card.dart';
import '../widgets/navigation_icons.dart';
import 'note_editor_page.dart';
import 'record_audio_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  bool _fabExpanded = true;

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        _tab == 2) {
      return false;
    }
    if (notification is! ScrollUpdateNotification ||
        notification.scrollDelta == null ||
        notification.scrollDelta == 0) {
      return false;
    }
    final expanded = notification.scrollDelta! < 0;
    if (expanded != _fabExpanded) setState(() => _fabExpanded = expanded);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NoteProvider>(
      builder: (context, provider, _) => Scaffold(
        extendBody: true,
        body: NotificationListener<ScrollNotification>(
          onNotification: _handleScroll,
          child: IndexedStack(
            index: _tab,
            children: [
              _OverviewTab(
                provider: provider,
                onSearch: _openSearch,
                onOpenLibrary: () => setState(() => _tab = 1),
                onCreateText: _createTextNote,
                onPickImage: _pickImage,
                onRecordAudio: _openRecorder,
                onPickDocument: _pickDocument,
                noteBuilder: _buildCard,
              ),
              _LibraryTab(
                provider: provider,
                onSearch: _openSearch,
                noteBuilder: _buildCard,
              ),
              _DataTab(
                provider: provider,
                onOpenLibrary: () => setState(() => _tab = 1),
              ),
            ],
          ),
        ),
        floatingActionButton: _tab == 2
            ? null
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _fabExpanded
                    ? FloatingActionButton.extended(
                        key: const ValueKey('new-expanded'),
                        heroTag: null,
                        onPressed: _showCaptureSheet,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text(
                          '新建',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      )
                    : FloatingActionButton(
                        key: const ValueKey('new-compact'),
                        heroTag: null,
                        onPressed: _showCaptureSheet,
                        tooltip: '新建',
                        child: const Icon(Icons.add_rounded),
                      ),
              ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) {
                setState(() {
                  _tab = index;
                  _fabExpanded = true;
                });
                if (index == 0 && provider.scope != NoteScope.active) {
                  provider.setScope(NoteScope.active);
                }
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_outlined),
                  label: '主页',
                ),
                NavigationDestination(
                  icon: LibrarySpinesIcon(),
                  selectedIcon: LibrarySpinesIcon(),
                  label: '资料库',
                ),
                NavigationDestination(
                  icon: Icon(Icons.pie_chart_outline_rounded),
                  selectedIcon: Icon(Icons.pie_chart_outline_rounded),
                  label: '数据',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(NoteEntry entry, {bool compact = false}) {
    final provider = context.read<NoteProvider>();
    return NoteCard(
      entry: entry,
      compact: compact,
      onTap: () => _openEntry(entry),
      onEdit: entry.isDeleted ? null : () => _editEntry(entry),
      onFavorite: entry.isDeleted ? null : () => provider.toggleFavorite(entry),
      onPin: entry.isDeleted || entry.isArchived
          ? null
          : () => provider.togglePinned(entry),
      onArchive: entry.isDeleted ? null : () => provider.toggleArchived(entry),
      onRestore: entry.isDeleted ? () => provider.restore(entry) : null,
      onDelete: () =>
          entry.isDeleted ? _deleteForever(entry) : _moveToTrash(entry),
    );
  }

  Future<void> _openEntry(NoteEntry entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(existingEntry: entry)),
    );
  }

  Future<void> _editEntry(NoteEntry entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(existingEntry: entry)),
    );
  }

  void _openSearch() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SearchPage()),
  );

  Future<void> _moveToTrash(NoteEntry entry) async {
    final provider = context.read<NoteProvider>();
    await provider.moveToTrash(entry);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已移到回收站'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => provider.restore(entry),
        ),
      ),
    );
  }

  Future<void> _deleteForever(NoteEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除？'),
        content: const Text('笔记和关联文件将无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<NoteProvider>().deletePermanently(entry);
    }
  }

  void _showCaptureSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '捕捉此刻',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '离线保存，你的内容只属于你',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 10,
                childAspectRatio: .83,
                children: [
                  _CaptureAction(
                    Icons.edit_note_rounded,
                    '笔记',
                    AppColors.moss,
                    () {
                      _afterSheetClose(sheetContext, _createTextNote);
                    },
                  ),
                  _CaptureAction(
                    Icons.camera_alt_rounded,
                    '拍照',
                    const Color(0xFF9B654E),
                    () {
                      _afterSheetClose(sheetContext, _takePhoto);
                    },
                  ),
                  _CaptureAction(
                    Icons.image_rounded,
                    '图片',
                    const Color(0xFF75665A),
                    () {
                      _afterSheetClose(sheetContext, _pickImage);
                    },
                  ),
                  _CaptureAction(
                    Icons.mic_rounded,
                    '录音',
                    const Color(0xFFA66742),
                    () {
                      _afterSheetClose(sheetContext, _openRecorder);
                    },
                  ),
                  _CaptureAction(
                    Icons.audio_file_rounded,
                    '音频',
                    const Color(0xFFA66742),
                    () {
                      _afterSheetClose(sheetContext, _pickAudio);
                    },
                  ),
                  _CaptureAction(
                    Icons.video_file_rounded,
                    '视频',
                    const Color(0xFFA94F46),
                    () {
                      _afterSheetClose(sheetContext, _pickVideo);
                    },
                  ),
                  _CaptureAction(
                    Icons.upload_file_rounded,
                    '文件',
                    const Color(0xFF77665B),
                    () {
                      _afterSheetClose(sheetContext, _pickDocument);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _afterSheetClose(BuildContext sheetContext, VoidCallback action) {
    Navigator.pop(sheetContext);
    Future<void>.delayed(const Duration(milliseconds: 260), action);
  }

  void _createTextNote() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const NoteEditorPage()),
  );

  Future<void> _openRecorder() async {
    final attachment = await Navigator.push<NoteAttachment>(
      context,
      MaterialPageRoute(
        builder: (_) => const RecordAudioPage(returnAttachment: true),
      ),
    );
    if (attachment != null) {
      await _createNoteWithAttachments('语音笔记', [attachment]);
    }
  }

  Future<void> _pickImage() async {
    await _startAttachmentImport(NoteType.image);
  }

  Future<void> _takePhoto() async {
    await _startAttachmentImport(NoteType.image, camera: true);
  }

  Future<void> _pickVideo() => _startAttachmentImport(NoteType.video);

  Future<void> _pickAudio() => _startAttachmentImport(NoteType.audio);

  Future<void> _pickDocument() => _startAttachmentImport(NoteType.document);

  Future<void> _startAttachmentImport(
    NoteType type, {
    bool camera = false,
  }) async {
    try {
      final provider = context.read<NoteProvider>();
      final jobs = await provider.startAttachmentImport(type, camera: camera);
      if (jobs.isEmpty || !mounted || jobs.first.noteId == null) return;
      final entry = provider.getEntryById(jobs.first.noteId!);
      if (entry == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteEditorPage(
            existingEntry: entry,
            initialImportJobIds: jobs.map((job) => job.id).toList(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is PlatformException
          ? error.message ?? '${type.label}导入失败'
          : error.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _createNoteWithAttachments(
    String title,
    List<NoteAttachment> attachments,
  ) async {
    if (attachments.isEmpty || !mounted) return;
    final provider = context.read<NoteProvider>();
    final now = DateTime.now();
    final id = await provider.addEntry(
      NoteEntry(
        type: attachments.first.type,
        title: title,
        attachments: attachments,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    final entry = provider.getEntryById(id);
    if (entry != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NoteEditorPage(existingEntry: entry)),
      );
    }
  }
}

typedef NoteBuilder = Widget Function(NoteEntry entry, {bool compact});

class _OverviewTab extends StatelessWidget {
  final NoteProvider provider;
  final VoidCallback onSearch;
  final VoidCallback onOpenLibrary;
  final VoidCallback onCreateText;
  final VoidCallback onPickImage;
  final VoidCallback onRecordAudio;
  final VoidCallback onPickDocument;
  final NoteBuilder noteBuilder;

  const _OverviewTab({
    required this.provider,
    required this.onSearch,
    required this.onOpenLibrary,
    required this.onCreateText,
    required this.onPickImage,
    required this.onRecordAudio,
    required this.onPickDocument,
    required this.noteBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final entries = provider.activeEntries;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: provider.loadEntries,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              sliver: SliverList.list(
                children: [
                  const _BrandHeader(),
                  const SizedBox(height: 22),
                  _SearchButton(onTap: onSearch),
                  const SizedBox(height: 28),
                  _LocalHero(provider: provider),
                  const SizedBox(height: 18),
                  _QuickActions(
                    onCreateText: onCreateText,
                    onPickImage: onPickImage,
                    onRecordAudio: onRecordAudio,
                    onPickDocument: onPickDocument,
                  ),
                  const SizedBox(height: 30),
                  _SectionHeader(
                    title: '最近更新',
                    action: entries.isEmpty ? null : '更多',
                    onTap: onOpenLibrary,
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            if (provider.isLoading && entries.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (entries.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: AppColors.moss),
                        SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '从一个念头开始',
                                style: TextStyle(
                                  fontFamily: 'serif',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                '点击“新建”，内容会安全留在本机。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.separated(
                  itemCount: entries.take(5).length,
                  itemBuilder: (_, index) =>
                      noteBuilder(entries[index], compact: true),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 150)),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const BrandMark(size: 48),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '非空笔记',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
              ),
            ),
            const Text(
              '完全本地 · 私密可靠',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SearchButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchButton({required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.softAmber,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: AppColors.muted),
            SizedBox(width: 12),
            Expanded(
              child: Text('搜索笔记', style: TextStyle(color: AppColors.muted)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LocalHero extends StatelessWidget {
  final NoteProvider provider;
  const _LocalHero({required this.provider});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('所有笔记', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 18),
      IntrinsicHeight(
        child: Row(
          children: [
            _OverviewStat('${provider.activeEntries.length}', '条笔记'),
            const VerticalDivider(width: 28),
            _OverviewStat('${provider.attachmentCount}', '个附件'),
            const VerticalDivider(width: 28),
            const Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 17,
                    color: AppColors.moss,
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '仅保存在本机',
                      maxLines: 2,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Divider(),
    ],
  );
}

class _OverviewStat extends StatelessWidget {
  final String value;
  final String label;
  const _OverviewStat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: AppColors.moss,
          fontFamily: 'serif',
          fontSize: 28,
          height: 1,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          height: 1.35,
        ),
      ),
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;
  const _SectionHeader({required this.title, this.action, this.onTap});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                action!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 17),
            ],
          ),
        ),
    ],
  );
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onCreateText;
  final VoidCallback onPickImage;
  final VoidCallback onRecordAudio;
  final VoidCallback onPickDocument;

  const _QuickActions({
    required this.onCreateText,
    required this.onPickImage,
    required this.onRecordAudio,
    required this.onPickDocument,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 78,
    child: Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.notes_rounded,
            label: '笔记',
            onTap: onCreateText,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _QuickAction(
            icon: Icons.image_outlined,
            label: '图片',
            onTap: onPickImage,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _QuickAction(
            icon: Icons.mic_none_rounded,
            label: '录音',
            onTap: onRecordAudio,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _QuickAction(
            icon: Icons.description_outlined,
            label: '文件',
            onTap: onPickDocument,
          ),
        ),
      ],
    ),
  );
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.ink, size: 25),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 13,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class _LibraryTab extends StatelessWidget {
  final NoteProvider provider;
  final VoidCallback onSearch;
  final NoteBuilder noteBuilder;
  const _LibraryTab({
    required this.provider,
    required this.onSearch,
    required this.noteBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final entries = provider.entries;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _scopeTitle(provider.scope),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.4,
                            ),
                      ),
                      Text(
                        '${entries.length} 个条目',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded),
                  tooltip: '搜索',
                ),
                if (provider.scope == NoteScope.trash &&
                    provider.trashCount > 0)
                  IconButton(
                    tooltip: '清空回收站',
                    onPressed: () => _confirmEmptyTrash(context),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                PopupMenuButton<NoteSort>(
                  tooltip: '排序',
                  icon: const Icon(Icons.swap_vert_rounded),
                  onSelected: provider.setSort,
                  itemBuilder: (_) => [
                    AppPopupMenuItem.action(
                      value: NoteSort.updated,
                      icon: Icons.update_rounded,
                      label: '最近更新',
                    ),
                    AppPopupMenuItem.action(
                      value: NoteSort.created,
                      icon: Icons.schedule_rounded,
                      label: '创建时间',
                    ),
                    AppPopupMenuItem.action(
                      value: NoteSort.title,
                      icon: Icons.sort_by_alpha_rounded,
                      label: '标题',
                    ),
                    AppPopupMenuItem.action(
                      value: NoteSort.size,
                      icon: Icons.data_usage_rounded,
                      label: '文件大小',
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _ScopeChip(
                  '全部',
                  provider.scope == NoteScope.active,
                  () => provider.setScope(NoteScope.active),
                ),
                _ScopeChip(
                  '收藏',
                  provider.scope == NoteScope.favorites,
                  () => provider.setScope(NoteScope.favorites),
                ),
                _ScopeChip(
                  '归档',
                  provider.scope == NoteScope.archived,
                  () => provider.setScope(NoteScope.archived),
                ),
                _ScopeChip(
                  '回收站',
                  provider.scope == NoteScope.trash,
                  () => provider.setScope(NoteScope.trash),
                ),
              ],
            ),
          ),
          if (provider.scope == NoteScope.active ||
              provider.scope == NoteScope.favorites)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _TypeChip(null, provider),
                  for (final type in NoteType.values) _TypeChip(type, provider),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: provider.isLoading && entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                ? EmptyState(
                    icon: _scopeIcon(provider.scope),
                    message: _emptyMessage(provider.scope),
                  )
                : RefreshIndicator(
                    onRefresh: provider.loadEntries,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 150),
                      itemCount: entries.length,
                      itemBuilder: (_, index) => noteBuilder(entries[index]),
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _scopeTitle(NoteScope scope) => switch (scope) {
    NoteScope.active => '资料库',
    NoteScope.favorites => '收藏',
    NoteScope.archived => '归档',
    NoteScope.trash => '回收站',
  };
  static IconData _scopeIcon(NoteScope scope) => switch (scope) {
    NoteScope.active => Icons.folder_open_rounded,
    NoteScope.favorites => Icons.star_outline_rounded,
    NoteScope.archived => Icons.archive_outlined,
    NoteScope.trash => Icons.delete_outline_rounded,
  };
  static String _emptyMessage(NoteScope scope) => switch (scope) {
    NoteScope.active => '当前筛选下没有内容',
    NoteScope.favorites => '收藏的内容会出现在这里',
    NoteScope.archived => '归档箱是空的',
    NoteScope.trash => '回收站是空的',
  };

  Future<void> _confirmEmptyTrash(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空回收站？'),
        content: Text('将永久删除 ${provider.trashCount} 条内容和关联文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) await provider.emptyTrash();
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ScopeChip(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    ),
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        pressElevation: 0,
        chipAnimationStyle: ChipAnimationStyle(
          selectAnimation: AnimationStyle.noAnimation,
        ),
        onSelected: (_) => onTap(),
      ),
    ),
  );
}

class _TypeChip extends StatelessWidget {
  final NoteType? type;
  final NoteProvider provider;
  const _TypeChip(this.type, this.provider);
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    ),
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(type?.label ?? '所有类型'),
        avatar: type == null
            ? null
            : Icon(
                NoteCard.iconForType(type!),
                size: 16,
                color: provider.typeFilter == type
                    ? AppColors.moss
                    : AppColors.muted,
              ),
        selected: provider.typeFilter == type,
        showCheckmark: false,
        pressElevation: 0,
        chipAnimationStyle: ChipAnimationStyle(
          selectAnimation: AnimationStyle.noAnimation,
          avatarDrawerAnimation: AnimationStyle.noAnimation,
        ),
        onSelected: (_) => provider.setTypeFilter(type),
      ),
    ),
  );
}

class _DataTab extends StatefulWidget {
  final NoteProvider provider;
  final VoidCallback onOpenLibrary;
  const _DataTab({required this.provider, required this.onOpenLibrary});
  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  int? _actualSize;
  bool _backupBusy = false;
  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  @override
  void didUpdateWidget(covariant _DataTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshSize();
  }

  Future<void> _refreshSize() async {
    final size = await FileStorageService.instance.storageSize();
    if (mounted) setState(() => _actualSize = size);
  }

  @override
  Widget build(BuildContext context) {
    final storage = FileStorageService.instance;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 140),
        children: [
          Text(
            '本地数据',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '数据不上传，不跟踪，完全由你掌控。',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.softGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.verified_user_outlined,
                          size: 19,
                          color: AppColors.moss,
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      '本地优先',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Spacer(),
                    Text(
                      '离线安全',
                      style: TextStyle(
                        color: AppColors.moss,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _DataStat('${widget.provider.allEntries.length}', '总条目'),
                    _DataStat('${widget.provider.attachmentCount}', '附件'),
                    _DataStat(
                      _formatBytes(
                        _actualSize ?? widget.provider.totalFileSize,
                      ),
                      '占用',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '统一存储',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.folder_rounded,
                title: '本机统一目录',
                subtitle: '数据库、附件和缩略图集中保存',
                onTap: () => _showStoragePath(storage.baseDir),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '备份与迁移',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.ios_share_rounded,
                title: '导出完整备份',
                subtitle: '通过系统面板保存，包含所有笔记和附件',
                onTap: _backupBusy ? null : _exportBackup,
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.settings_backup_restore_rounded,
                title: '从备份恢复',
                subtitle: '恢复前会进行完整性检查',
                onTap: _backupBusy ? null : _restoreBackup,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '整理与安全',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _SettingCard(
            children: [
              _SettingRow(
                icon: Icons.archive_outlined,
                title: '归档',
                subtitle: '${widget.provider.archiveCount} 条内容',
                onTap: () {
                  widget.provider.setScope(NoteScope.archived);
                  widget.onOpenLibrary();
                },
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.delete_outline_rounded,
                title: '回收站',
                subtitle: '${widget.provider.trashCount} 条内容',
                onTap: () {
                  widget.provider.setScope(NoteScope.trash);
                  widget.onOpenLibrary();
                },
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.refresh_rounded,
                title: '重建数据索引',
                subtitle: '刷新数据库与便携清单',
                onTap: () async {
                  await widget.provider.loadEntries();
                  await _refreshSize();
                  if (!context.mounted) return;
                  {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('索引已更新')));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              '非空笔记  ·  所有处理均在设备端完成',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showStoragePath(String path) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '本机存储位置',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '这是系统分配给非空笔记的私有目录。日常备份请使用“导出完整备份”。',
                style: TextStyle(color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 16),
              SelectableText(
                path,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: path));
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制路径'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    setState(() => _backupBusy = true);
    try {
      final size = MediaQuery.sizeOf(context);
      final exported = await BackupService.instance.exportBackup(
        sharePositionOrigin: Rect.fromLTWH(
          size.width / 2,
          size.height / 2,
          1,
          1,
        ),
      );
      await widget.provider.loadEntries();
      if (exported && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备份已交给系统保存')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复完整备份？'),
        content: const Text('当前内容将被备份中的内容替换。建议先导出一份当前数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择备份'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _backupBusy = true);
    try {
      final restored = await BackupService.instance.restoreBackup();
      if (restored) {
        await widget.provider.loadEntries();
        await _refreshSize();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('备份已安全恢复')));
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('恢复失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

class _DataStat extends StatelessWidget {
  final String value;
  final String label;
  const _DataStat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(children: children),
  );
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.moss, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    ),
  );
}

class _CaptureAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _CaptureAction(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: color, size: 27),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
