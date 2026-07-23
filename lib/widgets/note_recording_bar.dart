import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';

final class NoteRecordingBar extends StatelessWidget {
  const NoteRecordingBar({
    required this.preparing,
    required this.saving,
    required this.paused,
    required this.elapsed,
    required this.amplitudes,
    required this.onCancel,
    required this.onPauseOrResume,
    required this.onFinish,
    super.key,
  });

  final bool preparing;
  final bool saving;
  final bool paused;
  final Duration elapsed;
  final List<double> amplitudes;
  final VoidCallback? onCancel;
  final VoidCallback? onPauseOrResume;
  final VoidCallback? onFinish;

  bool get _busy => preparing || saving;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      boxShadow: [
        BoxShadow(
          color: Color(0x0F202124),
          blurRadius: 18,
          offset: Offset(0, -4),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
        child: Row(
          children: [
            IconButton(
              key: const Key('cancel-note-recording'),
              tooltip: context.l10n.cancel,
              onPressed: onCancel,
              color: AppColors.muted,
              icon: const Icon(Icons.close_rounded),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: '${_statusLabel(context)}，${_formatDuration(elapsed)}',
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: paused || _busy
                            ? AppColors.subtle
                            : AppColors.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _busy
                          ? Row(
                              children: [
                                const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    _statusLabel(context),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                if (paused) ...[
                                  Text(
                                    context.l10n.paused,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: SizedBox(
                                    height: 30,
                                    child: CustomPaint(
                                      key: const Key('note-recording-waveform'),
                                      painter: _RecordingWaveformPainter(
                                        samples: amplitudes,
                                        paused: paused,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _formatDuration(elapsed),
                                  key: const Key('note-recording-duration'),
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (!_busy)
              IconButton(
                key: const Key('pause-resume-note-recording'),
                tooltip: paused ? context.l10n.resume : context.l10n.pause,
                onPressed: onPauseOrResume,
                color: AppColors.muted,
                icon: Icon(
                  paused ? Icons.mic_none_rounded : Icons.pause_rounded,
                ),
              ),
            const SizedBox(width: 2),
            FilledButton.icon(
              key: const Key('finish-note-recording'),
              onPressed: onFinish,
              style: FilledButton.styleFrom(
                minimumSize: const Size(82, 42),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(context.l10n.finishRecording),
            ),
          ],
        ),
      ),
    ),
  );

  String _statusLabel(BuildContext context) {
    if (preparing) return context.l10n.preparingMicrophone;
    if (saving) return context.l10n.savingRecording;
    if (paused) return context.l10n.paused;
    return context.l10n.recording;
  }

  static String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

final class _RecordingWaveformPainter extends CustomPainter {
  const _RecordingWaveformPainter({
    required this.samples,
    required this.paused,
  });

  final List<double> samples;
  final bool paused;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.isEmpty) return;
    final paint = Paint()
      ..color = paused ? AppColors.subtle : AppColors.accent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;
    final step = size.width / samples.length;
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index].clamp(.06, 1.0);
      final height = (4 + sample * (size.height - 4)).clamp(4.0, size.height);
      final x = step * index + step / 2;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RecordingWaveformPainter oldDelegate) =>
      paused != oldDelegate.paused || samples != oldDelegate.samples;
}
