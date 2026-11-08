// The Windows speech plugin end to end: whisper.cpp with a real model on
// recorded commands, and the microphone starting and stopping.
//
//   flutter test integration_test/whisper_voice_test.dart -d windows
//     --dart-define=WHISPER_MODEL=<path to ggml-small-q5_1.bin>
//     --dart-define=WHISPER_AUDIO=<folder of 16 kHz mono .wav files>
//
// Each file is named after what it says ("search_iran.wav" says "search
// Iran"). Skipped without the defines.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whisper_voice/whisper_voice.dart';

const _model = String.fromEnvironment('WHISPER_MODEL');
const _audio = String.fromEnvironment('WHISPER_AUDIO');

/// 16-bit PCM samples of a WAV file as floats.
Float32List readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      final count = size ~/ 2;
      return Float32List.fromList([
        for (var i = 0; i < count; i++)
          data.getInt16(offset + 8 + i * 2, Endian.little) / 32768,
      ]);
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw FormatException('No audio in $path');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recognizes recorded commands', (tester) async {
    final voice = WhisperVoice();
    await tester.runAsync(() async {
      await voice.loadModel(_model);
      final files =
          Directory(_audio)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.wav'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty);
      for (final file in files) {
        final expected = file.uri.pathSegments.last
            .replaceAll('.wav', '')
            .replaceAll('_', ' ');
        final clock = Stopwatch()..start();
        final heard = await voice.transcribe(
          candidates: const ['fa', 'en'],
          samples: readWav(file.path),
        );
        // ignore: avoid_print
        print(
          '${file.uri.pathSegments.last}: [${heard.language}] '
          '"${heard.text}" in ${clock.elapsedMilliseconds} ms',
        );
        final words = heard.text.toLowerCase().replaceAll(
          RegExp(r'[^a-z ]'),
          '',
        );
        expect(words, contains(expected.split(' ').last), reason: heard.text);
      }

      // Pure silence is not speech.
      await expectLater(
        voice.transcribe(samples: Float32List(16000 * 2)),
        throwsA(
          isA<Exception>().having((e) => '$e', 'code', contains('no_speech')),
        ),
      );
      await voice.unloadModel();
    });
  }, skip: _model.isEmpty || _audio.isEmpty);

  testWidgets('the microphone starts, reports levels and stops', (
    tester,
  ) async {
    final voice = WhisperVoice();
    await tester.runAsync(() async {
      final levels = <double>[];
      final sub = voice.levels.listen(levels.add);
      await voice.start();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final length = await voice.stop();
      await sub.cancel();
      // The recording is dropped, never recognized or kept.
      await voice.cancel();
      // ignore: avoid_print
      print('recorded ${length.inMilliseconds} ms, ${levels.length} levels');
      expect(length.inMilliseconds, inInclusiveRange(1000, 2000));
      expect(levels.length, greaterThan(15));
    });
  }, skip: _model.isEmpty);
}
