import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../app.dart';
import '../models/note_entry.dart';
import '../providers/note_provider.dart';
import '../services/file_storage_service.dart';
import '../services/note_service.dart';
import '../services/ocr_service.dart';
import '../widgets/empty_state.dart';
import 'note_editor_page.dart';

class MediaDetailPage extends StatefulWidget {
  final NoteEntry entry;
  final NoteAttachment? attachment;
  const MediaDetailPage({super.key, required this.entry, this.attachment});

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  final _storage = FileStorageService.instance;
  late NoteEntry _entry;
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  bool _recognizing = false;

  NoteEntry get entry => _entry;
  NoteAttachment? get attachment {
    final requested = widget.attachment;
    if (requested == null) return entry.primaryAttachment;
    for (final item in entry.allAttachments) {
      if (item.filePath == requested.filePath) return item;
    }
    return requested;
  }

  File? get _file {
    final path = attachment?.filePath;
    if (path == null) return null;
    final file = File(_storage.absolutePath(path));
    return file.existsSync() ? file : null;
  }

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _initMedia();
  }

  Future<void> _initMedia() async {
    final file = _file;
    if (file == null) return;
    if (attachment?.type == NoteType.video) {
      _video = VideoPlayerController.file(file);
      await _video!.initialize();
      _video!.addListener(_mediaChanged);
    } else if (attachment?.type == NoteType.audio) {
      _audio = AudioPlayer();
      await _audio!.setFilePath(file.path);
      _audio!.positionStream.listen((position) {
        if (mounted) setState(() => _audioPosition = position);
      });
      _audio!.durationStream.listen((duration) {
        if (duration != null && mounted) {
          setState(() => _audioDuration = duration);
        }
      });
    }
    if (mounted) setState(() {});
  }

  void _mediaChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorPage(existingEntry: entry)),
    );
    if (!mounted || entry.id == null) return;
    final refreshed = await NoteService.instance.getEntry(entry.id!);
    if (refreshed != null && mounted) setState(() => _entry = refreshed);
  }

  Future<void> _openExternal() async {
    final file = _file;
    if (file == null) return;
    final result = await OpenFile.open(file.path);
    if (!mounted || result.type == ResultType.done) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _copyOcr() async {
    await Clipboard.setData(ClipboardData(text: attachment?.ocrText ?? ''));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('识别文字已复制')));
    }
  }

  Future<void> _recognizeText() async {
    final file = _file;
    if (file == null || attachment?.type != NoteType.image || _recognizing) {
      return;
    }
    setState(() => _recognizing = true);
    final result = await OcrService.instance.recognizeText(file.path);
    if (!mounted) return;
    if (!result.hasText) {
      setState(() => _recognizing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.didFail ? 'OCR 识别失败：${result.errorMessage}' : '未识别到清晰文字',
          ),
        ),
      );
      return;
    }
    final activePath = attachment!.filePath;
    final updated = entry.copyWith(
      attachments: [
        for (final item in entry.allAttachments)
          item.filePath == activePath
              ? item.copyWith(ocrText: result.text)
              : item,
      ],
      updatedAt: DateTime.now(),
    );
    await context.read<NoteProvider>().updateEntry(updated);
    if (mounted) {
      setState(() {
        _entry = updated;
        _recognizing = false;
      });
    }
  }

  @override
  void dispose() {
    _video?.removeListener(_mediaChanged);
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasOcr = attachment?.type == NoteType.image;
    return DefaultTabController(
      length: hasOcr ? 3 : 2,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title.isEmpty ? entry.primaryType.label : entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                attachment?.fileName ?? entry.primaryType.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            if (_file != null)
              IconButton(
                tooltip: '用其他应用打开',
                onPressed: _openExternal,
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            if (widget.attachment == null)
              IconButton(
                tooltip: '编辑信息',
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined),
              ),
            const SizedBox(width: 6),
          ],
          bottom: TabBar(
            dividerColor: AppColors.line,
            indicatorColor: AppColors.moss,
            indicatorWeight: 2,
            labelColor: AppColors.ink,
            unselectedLabelColor: AppColors.muted,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            tabs: [
              const Tab(text: '预览'),
              if (hasOcr) const Tab(text: '识别文字'),
              const Tab(text: '信息'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PreviewTab(
              attachment: attachment,
              file: _file,
              video: _video,
              audio: _audio,
              audioPosition: _audioPosition,
              audioDuration: _audioDuration,
            ),
            if (hasOcr) _buildOcrTab(),
            _buildInfoTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildOcrTab() {
    final text = attachment?.ocrText?.trim() ?? '';
    final hasRecognizedText = text.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '图片中的文字',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (hasRecognizedText)
              IconButton.filledTonal(
                tooltip: '复制全部',
                onPressed: _copyOcr,
                icon: const Icon(Icons.copy_all_rounded),
              ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: hasRecognizedText ? '重新识别' : '识别文字',
              onPressed: _recognizing ? null : _recognizeText,
              icon: _recognizing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (!hasRecognizedText)
          EmptyState(
            icon: Icons.text_snippet_outlined,
            message: '暂无识别文字',
            description: '需要时可对这张图片进行本地文字识别',
            actionLabel: _recognizing ? '正在识别…' : '识别文字',
            onAction: _recognizing ? null : _recognizeText,
          )
        else
          SelectableText(
            text,
            style: const TextStyle(
              fontSize: 17,
              height: 1.72,
              color: AppColors.ink,
            ),
          ),
      ],
    );
  }

  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _InfoCard(
          title: '笔记信息',
          children: [
            _InfoRow('类型', attachment?.type.label ?? entry.primaryType.label),
            _InfoRow('创建', _formatDate(entry.createdAt)),
            _InfoRow('更新', _formatDate(entry.updatedAt)),
            if (entry.tags.isNotEmpty)
              _InfoRow('标签', entry.tags.map((tag) => '#$tag').join('  ')),
          ],
        ),
        const SizedBox(height: 14),
        _InfoCard(
          title: '文件信息',
          children: [
            if (attachment != null) _InfoRow('文件名', attachment!.fileName),
            if (attachment != null)
              _InfoRow('大小', _formatSize(attachment!.fileSize)),
            if (attachment?.durationMs != null)
              _InfoRow(
                '时长',
                _formatDuration(
                  Duration(milliseconds: attachment!.durationMs!),
                ),
              ),
            _InfoRow('保存状态', _file == null ? '文件不存在' : '已保存在统一目录'),
          ],
        ),
        if (entry.content?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 14),
          _InfoCard(
            title: '说明',
            children: [
              Text(entry.readableContent, style: const TextStyle(height: 1.6)),
            ],
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  String _formatSize(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1048576
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';
  String _formatDuration(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _PreviewTab extends StatelessWidget {
  final NoteAttachment? attachment;
  final File? file;
  final VideoPlayerController? video;
  final AudioPlayer? audio;
  final Duration audioPosition;
  final Duration audioDuration;
  const _PreviewTab({
    required this.attachment,
    required this.file,
    required this.video,
    required this.audio,
    required this.audioPosition,
    required this.audioDuration,
  });

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return const EmptyState(
        icon: Icons.link_off_rounded,
        message: '原文件不存在',
        description: '可以保留笔记信息或将它移到回收站',
      );
    }
    return switch (attachment?.type ?? NoteType.text) {
      NoteType.image => Container(
        color: const Color(0xFF111815),
        padding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          minScale: .8,
          maxScale: 5,
          boundaryMargin: const EdgeInsets.all(80),
          child: Center(child: Image.file(file!, fit: BoxFit.contain)),
        ),
      ),
      NoteType.video => _VideoPreview(controller: video),
      NoteType.audio => _AudioPreview(
        player: audio,
        position: audioPosition,
        duration: audioDuration,
      ),
      NoteType.document => _DocumentPreview(
        fileName: attachment?.fileName,
        file: file!,
      ),
      NoteType.text => const SizedBox.shrink(),
    };
  }
}

class _VideoPreview extends StatelessWidget {
  final VideoPlayerController? controller;
  const _VideoPreview({required this.controller});
  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final c = controller!;
    return Container(
      color: const Color(0xFF111815),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
            const SizedBox(height: 16),
            IconButton.filled(
              onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
              iconSize: 34,
              icon: Icon(
                c.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioPreview extends StatelessWidget {
  final AudioPlayer? player;
  final Duration position;
  final Duration duration;
  const _AudioPreview({
    required this.player,
    required this.position,
    required this.duration,
  });
  @override
  Widget build(BuildContext context) {
    final max = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 54, 24, 120),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              const _Waveform(active: true),
              const SizedBox(height: 30),
              Slider(
                value: position.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                max: max,
                onChanged: player == null
                    ? null
                    : (value) =>
                          player!.seek(Duration(milliseconds: value.round())),
              ),
              Row(
                children: [
                  Text(_durationText(position)),
                  const Spacer(),
                  Text(_durationText(duration)),
                ],
              ),
              const SizedBox(height: 18),
              StreamBuilder<bool>(
                stream: player?.playingStream,
                initialData: false,
                builder: (_, snapshot) => IconButton.filled(
                  onPressed: player == null
                      ? null
                      : () => snapshot.data == true
                            ? player!.pause()
                            : player!.play(),
                  iconSize: 38,
                  icon: Icon(
                    snapshot.data == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _durationText(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _Waveform extends StatelessWidget {
  final bool active;
  const _Waveform({required this.active});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(24, (index) {
        final heights = [18.0, 28.0, 42.0, 24.0, 54.0, 34.0, 48.0, 22.0];
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 4,
          height: heights[index % heights.length],
          decoration: BoxDecoration(
            color: (active ? AppColors.moss : AppColors.muted).withValues(
              alpha: index.isEven ? 1 : .45,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    ),
  );
}

class _DocumentPreview extends StatelessWidget {
  final String? fileName;
  final File file;
  const _DocumentPreview({required this.fileName, required this.file});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.description_rounded,
              size: 64,
              color: Color(0xFF77665B),
            ),
            const SizedBox(height: 16),
            Text(
              fileName ?? '文件',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => OpenFile.open(file.path),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('用本地应用打开'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _InfoCard({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 15),
        ...children,
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
