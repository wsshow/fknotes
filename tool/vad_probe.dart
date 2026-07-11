import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Regression probe for the Silero VAD runtime used by FKNotes.
///
/// Usage:
///   dart run tool/vad_probe.dart `native-lib-dir model.onnx wav`
///       [threshold]
void main(List<String> args) {
  if (args.length < 3 || args.length > 4) {
    stderr.writeln(
      'Usage: dart run tool/vad_probe.dart '
      '<native-lib-dir> <model.onnx> <wav> [threshold]',
    );
    exitCode = 64;
    return;
  }
  final threshold = args.length == 4 ? double.parse(args[3]) : 0.3;
  sherpa.initBindings(args[0]);
  final wave = sherpa.readWave(args[2]);
  if (wave.sampleRate != 16000) {
    throw StateError('Silero VAD INT8 requires 16 kHz audio');
  }
  final vad = sherpa.VoiceActivityDetector(
    config: sherpa.VadModelConfig(
      sileroVad: sherpa.SileroVadModelConfig(
        model: args[1],
        threshold: threshold,
        minSilenceDuration: 0.5,
        minSpeechDuration: 0.25,
        windowSize: 512,
        maxSpeechDuration: 25,
      ),
      sampleRate: 16000,
      numThreads: 1,
      debug: false,
    ),
    bufferSizeInSeconds: 60,
  );
  try {
    var count = 0;
    var speechSamples = 0;
    const chunkSamples = 16000;

    void drain() {
      while (!vad.isEmpty()) {
        final segment = vad.front();
        vad.pop();
        count++;
        speechSamples += segment.samples.length;
        final start = segment.start / wave.sampleRate;
        final end = (segment.start + segment.samples.length) / wave.sampleRate;
        stdout.writeln(
          'segment=$count start=${start.toStringAsFixed(3)} '
          'end=${end.toStringAsFixed(3)} '
          'duration=${(end - start).toStringAsFixed(3)}',
        );
      }
    }

    for (var offset = 0; offset < wave.samples.length; offset += chunkSamples) {
      final end = (offset + chunkSamples).clamp(0, wave.samples.length);
      vad.acceptWaveform(wave.samples.sublist(offset, end));
      drain();
    }
    vad.flush();
    drain();
    stdout.writeln(
      'segments=$count speechSeconds='
      '${(speechSamples / wave.sampleRate).toStringAsFixed(3)} '
      'totalSeconds='
      '${(wave.samples.length / wave.sampleRate).toStringAsFixed(3)}',
    );
  } finally {
    vad.free();
  }
}
