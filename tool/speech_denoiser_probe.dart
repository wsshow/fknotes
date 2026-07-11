import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Regression probe for FKNotes streaming DPDFNet speech enhancement.
///
/// Usage:
///   dart run tool/speech_denoiser_probe.dart
///       `<native-lib-dir>` `<model.onnx>` `<input.wav>` `<output.wav>`
void main(List<String> args) {
  if (args.length != 4) {
    stderr.writeln(
      'Usage: dart run tool/speech_denoiser_probe.dart '
      '<native-lib-dir> <model.onnx> <input.wav> <output.wav>',
    );
    exitCode = 64;
    return;
  }
  sherpa.initBindings(args[0]);
  final denoiser = sherpa.OnlineSpeechDenoiser(
    sherpa.OnlineSpeechDenoiserConfig(
      model: sherpa.OfflineSpeechDenoiserModelConfig(
        dpdfnet: sherpa.OfflineSpeechDenoiserDpdfNetModelConfig(model: args[1]),
        numThreads: 1,
        debug: false,
      ),
    ),
  );
  try {
    final wave = sherpa.readWave(args[2]);
    final output = <double>[];
    final stopwatch = Stopwatch()..start();
    final frameShift = denoiser.frameShiftInSamples;
    for (var start = 0; start < wave.samples.length; start += frameShift) {
      final end = (start + frameShift).clamp(0, wave.samples.length);
      final chunk = denoiser.run(
        samples: Float32List.sublistView(wave.samples, start, end),
        sampleRate: wave.sampleRate,
      );
      output.addAll(chunk.samples);
    }
    output.addAll(denoiser.flush().samples);
    stopwatch.stop();
    sherpa.writeWave(
      filename: args[3],
      samples: Float32List.fromList(output),
      sampleRate: denoiser.sampleRate,
    );
    final audioSeconds = wave.samples.length / wave.sampleRate;
    final rtf = stopwatch.elapsedMicroseconds / 1000000 / audioSeconds;
    stdout.writeln(
      'sampleRate=${denoiser.sampleRate} frameShift=$frameShift '
      'input=${wave.samples.length} output=${output.length} '
      'rtf=${rtf.toStringAsFixed(3)}',
    );
  } finally {
    denoiser.free();
  }
}
