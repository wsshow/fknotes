import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app.dart';
import '../models/note_entry.dart';
import '../providers/note_provider.dart';
import '../services/file_storage_service.dart';

enum _RecorderStage { ready, recording, paused, review, saving }

class RecordAudioPage extends StatefulWidget {
  final bool returnAttachment;
  const RecordAudioPage({super.key, this.returnAttachment = false});

  @override
  State<RecordAudioPage> createState() => _RecordAudioPageState();
}

class _RecordAudioPageState extends State<RecordAudioPage> {
  final _recorder = AudioRecorder();
  final _storage = FileStorageService.instance;
  final _title = TextEditingController();
  AudioPlayer? _player;
  Timer? _timer;
  _RecorderStage _stage = _RecorderStage.ready;
  int _seconds = 0;
  String? _temporaryPath;
  bool _starting = false;

  bool get _hasRecording => _stage != _RecorderStage.ready;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _player?.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) status = await Permission.microphone.request();
    if (status.isGranted) return true;
    if (!mounted) return false;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要麦克风权限'),
        content: const Text('录音只会保存在本机。请允许麦克风权限后再开始。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('前往设置'),
          ),
        ],
      ),
    );
    if (openSettings == true) await openAppSettings();
    return false;
  }

  Future<void> _start() async {
    if (_starting) return;
    final alreadyGranted = await Permission.microphone.isGranted;
    if (mounted) setState(() => _starting = true);
    if (!await _ensurePermission()) {
      if (mounted) setState(() => _starting = false);
      return;
    }
    // Let Android finish the permission dialog transition before the native
    // recorder allocates its audio session. This also prevents focus ANRs on
    // slower devices and software-rendered emulators.
    if (!alreadyGranted) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
    try {
      final path =
          '${Directory.systemTemp.path}/fknotes_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      HapticFeedback.mediumImpact();
      setState(() {
        _starting = false;
        _temporaryPath = path;
        _seconds = 0;
        _stage = _RecorderStage.recording;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _stage == _RecorderStage.recording) {
          setState(() => _seconds++);
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法开始录音：$error')));
      }
    }
  }

  Future<void> _pauseOrResume() async {
    if (_stage == _RecorderStage.recording) {
      await _recorder.pause();
      setState(() => _stage = _RecorderStage.paused);
    } else if (_stage == _RecorderStage.paused) {
      await _recorder.resume();
      setState(() => _stage = _RecorderStage.recording);
    }
    HapticFeedback.selectionClick();
  }

  Future<void> _stop() async {
    final path = await _recorder.stop();
    _timer?.cancel();
    if (path == null || !await File(path).exists()) {
      if (mounted) setState(() => _stage = _RecorderStage.ready);
      return;
    }
    _temporaryPath = path;
    _player = AudioPlayer();
    await _player!.setFilePath(path);
    final now = DateTime.now();
    _title.text =
        '语音笔记 ${now.month}月${now.day}日 ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    HapticFeedback.mediumImpact();
    if (mounted) setState(() => _stage = _RecorderStage.review);
  }

  Future<void> _discard() async {
    if (_stage == _RecorderStage.recording || _stage == _RecorderStage.paused) {
      await _recorder.stop();
    }
    _timer?.cancel();
    await _player?.dispose();
    _player = null;
    final path = _temporaryPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    if (mounted) {
      setState(() {
        _temporaryPath = null;
        _seconds = 0;
        _stage = _RecorderStage.ready;
      });
    }
  }

  Future<void> _save() async {
    final provider = context.read<NoteProvider>();
    final path = _temporaryPath;
    if (path == null || _stage == _RecorderStage.saving) return;
    setState(() => _stage = _RecorderStage.saving);
    String? storedPath;
    try {
      final file = File(path);
      storedPath = await _storage.moveTemporaryFile(file, 'audio');
      final now = DateTime.now();
      final attachment = NoteAttachment(
        type: NoteType.audio,
        filePath: storedPath,
        fileName: '${now.millisecondsSinceEpoch}.m4a',
        fileSize: await _storage.getFileSize(storedPath),
        mimeType: 'audio/mp4',
        durationMs: _seconds * 1000,
        createdAt: now,
      );
      if (widget.returnAttachment) {
        if (await file.exists()) await file.delete();
        if (mounted) Navigator.pop(context, attachment);
        return;
      }
      await provider.addEntry(
        NoteEntry(
          type: NoteType.audio,
          title: _title.text.trim().isEmpty ? '语音笔记' : _title.text.trim(),
          attachments: [attachment],
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (await file.exists()) await file.delete();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (storedPath != null) {
        _temporaryPath = _storage.absolutePath(storedPath);
      }
      if (mounted) {
        setState(() => _stage = _RecorderStage.review);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }

  Future<void> _close() async {
    if (!_hasRecording) return Navigator.pop(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃这段录音？'),
        content: const Text('还没有保存的录音将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (discard == true) {
      await _discard();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasRecording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          leading: IconButton(
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
          ),
          title: const Text(
            '语音笔记',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: AppColors.moss,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '仅本机',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.moss,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: _stage == _RecorderStage.ready
                ? _buildReady()
                : _stage == _RecorderStage.review ||
                      _stage == _RecorderStage.saving
                ? _buildReview()
                : _buildRecording(),
          ),
        ),
      ),
    );
  }

  Widget _buildReady() => Padding(
    key: const ValueKey('ready'),
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
    child: Column(
      children: [
        const Spacer(),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Icon(Icons.mic_rounded, size: 42, color: AppColors.moss),
        ),
        const SizedBox(height: 24),
        const Text(
          '记录一段想法',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          '录音不会上传，保存后可以继续添加标签和说明。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, height: 1.55),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: _starting ? null : _start,
            icon: _starting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mic_rounded),
            label: Text(
              _starting ? '正在准备麦克风…' : '开始录音',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildRecording() => Padding(
    key: const ValueKey('recording'),
    padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
    child: Column(
      children: [
        const Spacer(),
        _LiveWaveform(tick: _seconds, paused: _stage == _RecorderStage.paused),
        const SizedBox(height: 34),
        Text(
          _time(_seconds),
          style: const TextStyle(
            fontSize: 54,
            fontWeight: FontWeight.w500,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _stage == _RecorderStage.paused ? '已暂停' : '正在录音',
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundAction(
              icon: _stage == _RecorderStage.paused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              label: _stage == _RecorderStage.paused ? '继续' : '暂停',
              onTap: _pauseOrResume,
            ),
            const SizedBox(width: 28),
            _RoundAction(
              icon: Icons.stop_rounded,
              label: '完成',
              color: AppColors.coral,
              foreground: Colors.white,
              large: true,
              onTap: _stop,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildReview() => ListView(
    key: const ValueKey('review'),
    padding: const EdgeInsets.fromLTRB(24, 26, 24, 40),
    children: [
      TextField(
        controller: _title,
        style: const TextStyle(
          fontFamily: 'serif',
          fontSize: 25,
          fontWeight: FontWeight.w700,
        ),
        decoration: const InputDecoration(
          labelText: '标题',
          prefixIcon: Icon(Icons.edit_note_rounded),
        ),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            const _ReviewWaveform(),
            const SizedBox(height: 22),
            Text(
              _time(_seconds),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            StreamBuilder<bool>(
              stream: _player?.playingStream,
              initialData: false,
              builder: (_, snapshot) => IconButton.filled(
                onPressed: _player == null
                    ? null
                    : () => snapshot.data == true
                          ? _player!.pause()
                          : _player!.play(),
                iconSize: 34,
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
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _stage == _RecorderStage.saving ? null : _discard,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('重录'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _stage == _RecorderStage.saving ? null : _save,
              icon: _stage == _RecorderStage.saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('保存语音笔记'),
            ),
          ),
        ],
      ),
    ],
  );

  String _time(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _LiveWaveform extends StatelessWidget {
  final int tick;
  final bool paused;
  const _LiveWaveform({required this.tick, required this.paused});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(28, (index) {
        final value = ((index * 17 + tick * 13) % 78 + 22).toDouble();
        return AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          width: 5,
          height: paused ? 12 : value,
          decoration: BoxDecoration(
            color: AppColors.moss.withValues(alpha: index.isEven ? 1 : .42),
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    ),
  );
}

class _ReviewWaveform extends StatelessWidget {
  const _ReviewWaveform();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 72,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(
        26,
        (index) => Container(
          width: 4,
          height: ((index * 19) % 48 + 16).toDouble(),
          decoration: BoxDecoration(
            color: AppColors.moss.withValues(alpha: index.isEven ? 1 : .4),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    ),
  );
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final Color? foreground;
  final bool large;
  final VoidCallback onTap;
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.foreground,
    this.large = false,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: color ?? AppColors.surface,
        elevation: color == null ? 0 : 1,
        shape: CircleBorder(
          side: BorderSide(
            color: color == null ? AppColors.line : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: large ? 82 : 66,
            height: large ? 82 : 66,
            child: Icon(
              icon,
              size: large ? 36 : 28,
              color: foreground ?? AppColors.ink,
            ),
          ),
        ),
      ),
      const SizedBox(height: 9),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );
}
