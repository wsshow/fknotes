import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/l10n.dart';

final class NoteVideoPlayerPage extends StatefulWidget {
  const NoteVideoPlayerPage({
    required this.filePath,
    required this.title,
    super.key,
  });

  final String filePath;
  final String title;

  @override
  State<NoteVideoPlayerPage> createState() => _NoteVideoPlayerPageState();
}

final class _NoteVideoPlayerPageState extends State<NoteVideoPlayerPage> {
  late final VideoPlayerController _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..addListener(_onVideoChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(false);
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() {});
  }

  void _onVideoChanged() {
    if (mounted && _controller.value.isInitialized) setState(() {});
  }

  Future<void> _togglePlayback() async {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      if (_controller.value.position >= _controller.value.duration) {
        await _controller.seekTo(Duration.zero);
      }
      await _controller.play();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onVideoChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.l10n.videoPlaybackFailed,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : !value.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: value.aspectRatio > 0
                            ? value.aspectRatio
                            : 16 / 9,
                        child: GestureDetector(
                          key: const Key('note-video-surface'),
                          onTap: _togglePlayback,
                          child: VideoPlayer(_controller),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    color: const Color(0xE6161B22),
                    padding: const EdgeInsets.fromLTRB(12, 6, 16, 10),
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('note-video-playback-toggle'),
                          tooltip: value.isPlaying
                              ? context.l10n.pause
                              : context.l10n.playVideo,
                          onPressed: _togglePlayback,
                          color: Colors.white,
                          icon: Icon(
                            value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: value.position.inMilliseconds
                                .clamp(
                                  0,
                                  value.duration.inMilliseconds.clamp(
                                    1,
                                    1 << 31,
                                  ),
                                )
                                .toDouble(),
                            max: value.duration.inMilliseconds
                                .clamp(1, 1 << 31)
                                .toDouble(),
                            onChanged: (position) => _controller.seekTo(
                              Duration(milliseconds: position.round()),
                            ),
                          ),
                        ),
                        Text(
                          '${_formatDuration(value.position)} / '
                          '${_formatDuration(value.duration)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final totalSeconds = value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final short =
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
  return hours == 0 ? short : '${hours.toString().padLeft(2, '0')}:$short';
}
