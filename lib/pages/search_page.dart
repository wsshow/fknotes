import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../services/search_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/editor_context_menu.dart';
import '../widgets/note_card.dart';
import 'local_chat_page.dart';
import 'note_editor_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _service = SearchService.instance;
  Timer? _debounce;
  List<LocalSearchResult> _results = const [];
  LocalSearchFilter _filter = LocalSearchFilter.all;
  bool _searching = false;
  int _requestId = 0;

  String get _query => _controller.text.trim();
  List<LocalSearchResult> get _visibleResults =>
      _results.where((result) => result.matches(_filter)).toList();

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
    final results = await _service.search(query);
    if (!mounted || request != _requestId || query != _query) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _open(LocalSearchResult result) async {
    if (result.note != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteEditorPage(existingEntry: result.note),
        ),
      );
    } else if (result.chatSessionId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LocalChatPage(initialSessionId: result.chatSessionId),
        ),
      );
    }
    if (_query.isNotEmpty) await _search(_query);
  }

  void _cancelSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.maybePop(context);
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
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Semantics(
                        textField: true,
                        label: '搜索本地知识库',
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          contextMenuBuilder: buildAppEditableTextContextMenu,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (value) {
                            final query = value.trim();
                            if (query.isNotEmpty) _search(query);
                          },
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
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _cancelSearch,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      minimumSize: const Size(64, 56),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final filter in LocalSearchFilter.values)
                      _FilterChip(
                        label: filter.label,
                        icon: switch (filter) {
                          LocalSearchFilter.all => null,
                          LocalSearchFilter.notes => Icons.note_outlined,
                          LocalSearchFilter.attachments =>
                            Icons.attach_file_rounded,
                          LocalSearchFilter.conversations =>
                            Icons.chat_bubble_outline_rounded,
                        },
                        selected: _filter == filter,
                        onTap: () => setState(() => _filter = filter),
                      ),
                  ],
                ),
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
            '标题、正文、标签、附件、OCR、语音转写和本地对话均会被检索。',
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
          const SizedBox(height: 12),
          const _SearchCapability(
            icon: Icons.graphic_eq_rounded,
            title: '语音转写',
            subtitle: '找到录音里说过的内容',
            color: AppColors.softAmber,
          ),
          const SizedBox(height: 12),
          const _SearchCapability(
            icon: Icons.forum_outlined,
            title: '本地对话',
            subtitle: '搜索角色设定和历史消息',
            color: AppColors.softGreen,
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
        description: _filter == LocalSearchFilter.all
            ? '试试更短的关键词'
            : '可以切换到其他搜索范围',
      );
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
      itemCount: results.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${results.length} 条匹配',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          );
        }
        final result = results[index - 1];
        return _SearchHitCard(result: result, onTap: () => _open(result));
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
  final LocalSearchResult result;
  final VoidCallback onTap;
  const _SearchHitCard({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final note = result.note;
    final color = note == null
        ? AppColors.moss
        : NoteCard.colorForType(note.primaryType);
    final semanticLabel = [
      result.title,
      result.sourceLabel,
      if (result.snippet.isNotEmpty) result.snippet,
    ].join('，');
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Card(
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
                        note == null
                            ? Icons.chat_bubble_outline_rounded
                            : NoteCard.iconForType(note.primaryType),
                        color: color,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        result.title,
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
                if (result.snippet.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    result.snippet,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                ],
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.softGreen,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    result.sourceLabel,
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
      ),
    );
  }
}
