import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Regression probe for FKNotes offline SenseVoice transcription.
///
/// Usage:
///   dart run tool/offline_asr_probe.dart
///       `native-lib-dir model.int8.onnx tokens.txt wav` [vad.onnx]
void main(List<String> args) {
  if (args.length < 4 || args.length > 5) {
    stderr.writeln(
      'Usage: dart run tool/offline_asr_probe.dart '
      '<native-lib-dir> <model.int8.onnx> <tokens.txt> <wav> [vad.onnx]',
    );
    exitCode = 64;
    return;
  }
  sherpa.initBindings(args[0]);
  final wave = sherpa.readWave(args[3]);
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        senseVoice: sherpa.OfflineSenseVoiceModelConfig(
          model: args[1],
          language: '',
          useInverseTextNormalization: true,
        ),
        tokens: args[2],
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  final pieces = <String>[];

  void recognize(Float32List samples) {
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text.trim();
      if (text.isNotEmpty) pieces.add(text);
    } finally {
      stream.free();
    }
  }

  sherpa.VoiceActivityDetector? vad;
  try {
    if (args.length == 5 && wave.sampleRate == 16000) {
      final activeVad = sherpa.VoiceActivityDetector(
        config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: args[4],
            threshold: 0.3,
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
      vad = activeVad;

      void drain() {
        while (!activeVad.isEmpty()) {
          final segment = activeVad.front();
          activeVad.pop();
          recognize(segment.samples);
        }
      }

      const chunkSamples = 16000;
      for (
        var offset = 0;
        offset < wave.samples.length;
        offset += chunkSamples
      ) {
        final end = math.min(offset + chunkSamples, wave.samples.length);
        activeVad.acceptWaveform(
          Float32List.sublistView(wave.samples, offset, end),
        );
        drain();
      }
      activeVad.flush();
      drain();
    } else {
      const chunkSeconds = 25;
      final chunkSamples = wave.sampleRate * chunkSeconds;
      for (
        var offset = 0;
        offset < wave.samples.length;
        offset += chunkSamples
      ) {
        final end = math.min(offset + chunkSamples, wave.samples.length);
        recognize(Float32List.sublistView(wave.samples, offset, end));
      }
    }
    stdout.writeln('segments=${pieces.length}');
    stdout.writeln('transcript=${pieces.join('\n')}');
  } finally {
    vad?.free();
    recognizer.free();
  }
}
