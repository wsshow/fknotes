import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Command-line probe for the exact streaming ASR runtime used by FKNotes.
///
/// Usage:
///   dart run tool/streaming_asr_probe.dart `native-lib-dir model-dir wav`
///       [--endpoint]
void main(List<String> args) {
  if (args.length < 3 || args.length > 4) {
    stderr.writeln(
      'Usage: dart run tool/streaming_asr_probe.dart '
      '<native-lib-dir> <model-dir> <wav> [--endpoint]',
    );
    exitCode = 64;
    return;
  }

  final nativeLibDir = args[0];
  final modelDir = args[1];
  final wavPath = args[2];
  final enableEndpoint = args.length == 4 && args[3] == '--endpoint';
  sherpa.initBindings(nativeLibDir);

  final wave = sherpa.readWave(wavPath);
  if (wave.samples.isEmpty) {
    throw StateError('Unable to read samples from $wavPath');
  }
  stdout.writeln(
    'wave=${wave.samples.length} samples, sampleRate=${wave.sampleRate}, '
    'duration=${(wave.samples.length / wave.sampleRate).toStringAsFixed(3)}s',
  );
  _printSignalStats(wave.samples);

  final recognizer = sherpa.OnlineRecognizer(
    sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: '$modelDir/encoder.int8.onnx',
          decoder: '$modelDir/decoder.onnx',
          joiner: '$modelDir/joiner.int8.onnx',
        ),
        tokens: '$modelDir/tokens.txt',
        numThreads: 2,
        debug: true,
        modelType: '',
        modelingUnit: 'cjkchar',
      ),
      enableEndpoint: enableEndpoint,
      rule1MinTrailingSilence: 15,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 20,
    ),
  );
  final stream = recognizer.createStream();
  final segments = <String>[];
  var lastText = '';
  var decodeCalls = 0;
  const chunkSamples = 1600;
  for (var offset = 0; offset < wave.samples.length; offset += chunkSamples) {
    final end = math.min(offset + chunkSamples, wave.samples.length);
    stream.acceptWaveform(
      samples: Float32List.sublistView(wave.samples, offset, end),
      sampleRate: wave.sampleRate,
    );
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
      decodeCalls++;
    }
    final text = recognizer.getResult(stream).text;
    if (text != lastText) {
      stdout.writeln(
        'partial @ ${(end / wave.sampleRate).toStringAsFixed(1)}s: $text',
      );
      lastText = text;
    }
    if (enableEndpoint && recognizer.isEndpoint(stream)) {
      stdout.writeln(
        'endpoint @ ${(end / wave.sampleRate).toStringAsFixed(1)}s: $text',
      );
      if (text.isNotEmpty) {
        segments.add(text.trim());
        recognizer.reset(stream);
        lastText = '';
      }
    }
  }
  stream.inputFinished();
  while (recognizer.isReady(stream)) {
    recognizer.decode(stream);
    decodeCalls++;
  }
  final result = recognizer.getResult(stream);
  if (result.text.trim().isNotEmpty) segments.add(result.text.trim());
  stdout.writeln('decodeCalls=$decodeCalls');
  stdout.writeln('transcript=${segments.join()}');
  stdout.writeln('currentResult=${result.text}');
  stdout.writeln('tokens=${result.tokens}');
  stdout.writeln('timestamps=${result.timestamps}');
  stream.free();
  recognizer.free();
}

void _printSignalStats(Float32List samples) {
  var squares = 0.0;
  var peak = 0.0;
  var nonFinite = 0;
  for (final sample in samples) {
    if (!sample.isFinite) {
      nonFinite++;
      continue;
    }
    squares += sample * sample;
    peak = math.max(peak, sample.abs());
  }
  final rms = math.sqrt(squares / samples.length);
  double db(double value) =>
      value == 0 ? double.negativeInfinity : 20 * math.log(value) / math.ln10;
  stdout.writeln(
    'rms=${db(rms).toStringAsFixed(1)}dBFS, '
    'peak=${db(peak).toStringAsFixed(1)}dBFS, nonFinite=$nonFinite',
  );
}
