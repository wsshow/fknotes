import 'dart:ffi';
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Regression probe for FKNotes offline speaker diarization.
///
/// Usage:
///   dart run tool/speaker_diarization_probe.dart `<native-lib-dir>`
///       `<segmentation.onnx>` `<embedding.onnx>` `<input.wav>` [speakers]
void main(List<String> args) {
  if (args.length < 4 || args.length > 5) {
    stderr.writeln(
      'Usage: dart run tool/speaker_diarization_probe.dart '
      '<native-lib-dir> <segmentation.onnx> <embedding.onnx> '
      '<input.wav> [speakers]',
    );
    exitCode = 64;
    return;
  }
  final speakerCount = args.length == 5 ? int.parse(args[4]) : -1;
  sherpa.initBindings(args[0]);
  final diarizer = sherpa.OfflineSpeakerDiarization(
    sherpa.OfflineSpeakerDiarizationConfig(
      segmentation: sherpa.OfflineSpeakerSegmentationModelConfig(
        pyannote: sherpa.OfflineSpeakerSegmentationPyannoteModelConfig(
          model: args[1],
        ),
        numThreads: 1,
        debug: false,
      ),
      embedding: sherpa.SpeakerEmbeddingExtractorConfig(
        model: args[2],
        numThreads: 1,
        debug: false,
      ),
      clustering: sherpa.FastClusteringConfig(
        numClusters: speakerCount,
        threshold: 0.75,
      ),
      minDurationOn: 0.3,
      minDurationOff: 0.5,
    ),
  );
  try {
    if (diarizer.ptr == nullptr) throw StateError('Unable to load diarizer');
    final wave = sherpa.readWave(args[3]);
    if (wave.sampleRate != diarizer.sampleRate) {
      throw StateError(
        'Expected ${diarizer.sampleRate} Hz, got ${wave.sampleRate} Hz',
      );
    }
    final stopwatch = Stopwatch()..start();
    final segments = diarizer.process(samples: wave.samples);
    stopwatch.stop();
    final speakers = segments.map((segment) => segment.speaker).toSet();
    stdout.writeln(
      'segments=${segments.length} speakers=${speakers.length} '
      'elapsed=${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(3)}s',
    );
    for (final segment in segments) {
      stdout.writeln(
        '${segment.start.toStringAsFixed(3)} -- '
        '${segment.end.toStringAsFixed(3)} speaker_${segment.speaker + 1}',
      );
    }
  } finally {
    diarizer.free();
  }
}
