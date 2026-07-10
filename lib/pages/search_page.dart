import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/note_entry.dart';
import '../services/note_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/note_card.dart';
import 'note_editor_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _service = NoteService.instance;
  Timer? _debounce;
  List<NoteEntry> _results = const [];
  NoteType? _type;
  bool _searching = false;
  int _requestId = 0;

  String get _query => _controller.text.trim();
  List<NoteEntry> get _visibleResults => _type == null
      ? _results
      : _results.where((entry) => entry.containsType(_type!)).toList();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final query = _query;
    setState(() {
      if (query.isEmpty) {
        _results = const [];
        _searching = false;
      } else {
        _searching = true;
      }
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(query));
  }

  Future<void> _search(String query) async {
    final request = ++_requestId;
    final results = await _service.searchLike(query);
    if (!mounted || request != _requestId || query != _query) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _open(NoteEntry entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(existingEntry: entry)),
    );
    if (_query.isNotEmpty) await _search(_query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: '搜索你的本地知识库',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清空',
                                onPressed: _controller.clear,
                                icon: const Icon(Icons.close_rounded),
                              ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _FilterChip(
                    label: '全部',
                    selected: _type == null,
                    onTap: () => setState(() => _type = null),
                  ),
                  for (final type in NoteType.values)
                    _FilterChip(
                      label: type.label,
                      icon: NoteCard.iconForType(type),
                      selected: _type == type,
                      onTap: () => setState(() => _type = type),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 120),
        children: [
          Text(
            '一次搜遍所有内容',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '标题、正文、标签、文件名和 OCR 文字均会被检索。',
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          const _SearchCapability(
            icon: Icons.document_scanner_rounded,
            title: 'OCR 文字',
            subtitle: '找到藏在图片里的内容',
            color: AppColors.softBlue,
          ),
          const SizedBox(height: 12),
          const _SearchCapability(
            icon: Icons.sell_rounded,
            title: '标签与说明',
            subtitle: '附件笔记和文字笔记统一命中',
            color: AppColors.softLavender,
          ),
        ],
      );
    }

    if (_searching) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    final results = _visibleResults;
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        message: '没有找到“$_query”',
        description: _type == null ? '试试更短的关键词' : '可以切换到其他内容类型',
      );
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
      itemCount: results.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${results.length} 条匹配',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          );
        }
        final entry = results[index - 1];
        return _SearchHitCard(
          entry: entry,
          query: _query,
          onTap: () => _open(entry),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

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
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        pressElevation: 0,
        chipAnimationStyle: ChipAnimationStyle(
          selectAnimation: AnimationStyle.noAnimation,
          avatarDrawerAnimation: AnimationStyle.noAnimation,
        ),
        avatar: icon == null
            ? null
            : Icon(
                icon,
                size: 16,
                color: selected ? AppColors.moss : AppColors.muted,
              ),
        label: Text(label),
      ),
    ),
  );
}

class _SearchCapability extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  const _SearchCapability({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.moss, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SearchHitCard extends StatelessWidget {
  final NoteEntry entry;
  final String query;
  final VoidCallback onTap;
  const _SearchHitCard({
    required this.entry,
    required this.query,
    required this.onTap,
  });

  String get _source {
    final q = query.toLowerCase();
    if (entry.title.toLowerCase().contains(q)) return '标题命中';
    if (entry.tags.any((tag) => tag.toLowerCase().contains(q))) return '标签命中';
    if (entry.aggregateOcr.toLowerCase().contains(q)) return 'OCR 命中';
    if (entry.allAttachments.any(
      (item) => item.fileName.toLowerCase().contains(q),
    )) {
      return '文件名命中';
    }
    return '正文命中';
  }

  @override
  Widget build(BuildContext context) {
    final color = NoteCard.colorForType(entry.primaryType);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      NoteCard.iconForType(entry.primaryType),
                      color: color,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.title.isEmpty ? '无标题' : entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ],
              ),
              if (entry.previewText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  entry.previewText.replaceAll('\n', ' '),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, height: 1.5),
                ),
              ],
              const SizedBox(height: 13),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  _source,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.moss,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
