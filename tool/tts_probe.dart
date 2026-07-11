import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Regression probe for FKNotes Kokoro Chinese/English text-to-speech.
///
/// Usage:
///   dart run tool/tts_probe.dart `<native-lib-dir>` `<model-dir>`
///       `<output.wav>` [text]
void main(List<String> args) {
  if (args.length < 3 || args.length > 4) {
    stderr.writeln(
      'Usage: dart run tool/tts_probe.dart '
      '<native-lib-dir> <model-dir> <output.wav> [text]',
    );
    exitCode = 64;
    return;
  }
  final modelDir = args[1];
  final text = args.length == 4 ? args[3] : '你好，这里是 FKNotes 离线语音合成。';
  sherpa.initBindings(args[0]);
  final tts = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        kokoro: sherpa.OfflineTtsKokoroModelConfig(
          model: p.join(modelDir, 'model.int8.onnx'),
          voices: p.join(modelDir, 'voices.bin'),
          tokens: p.join(modelDir, 'tokens.txt'),
          dataDir: p.join(modelDir, 'espeak-ng-data'),
          lexicon: [
            p.join(modelDir, 'lexicon-zh.txt'),
            p.join(modelDir, 'lexicon-us-en.txt'),
          ].join(','),
        ),
        numThreads: 2,
        debug: false,
      ),
      ruleFsts: [
        p.join(modelDir, 'phone-zh.fst'),
        p.join(modelDir, 'date-zh.fst'),
        p.join(modelDir, 'number-zh.fst'),
      ].join(','),
      maxNumSenetences: 1,
    ),
  );
  try {
    final audio = tts.generate(text: text, sid: 3, speed: 1);
    if (audio.samples.isEmpty || audio.sampleRate <= 0) {
      throw StateError('Kokoro generated no samples');
    }
    sherpa.writeWave(
      filename: args[2],
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    stdout.writeln(
      'sampleRate=${audio.sampleRate} samples=${audio.samples.length} '
      'duration=${(audio.samples.length / audio.sampleRate).toStringAsFixed(3)}s',
    );
  } finally {
    tts.free();
  }
}
