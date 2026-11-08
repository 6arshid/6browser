import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// What whisper heard, and in which language ("fa", "en"...).
class WhisperTranscript {
  const WhisperTranscript(this.text, this.language);

  final String text;
  final String language;
}

/// Offline speech recognition on Windows: records the microphone and runs
/// whisper.cpp on it. Failures are [PlatformException]s whose code is one of
/// `mic_blocked`, `no_microphone`, `mic_busy`, `mic_error` (recording),
/// `no_backend`, `no_model`, `bad_model` (loading), `no_speech`, `aborted`
/// or `failed` (recognition).
class WhisperVoice {
  WhisperVoice() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'level') {
        _levels.add((call.arguments as num).toDouble());
      }
    });
  }

  static const _channel = MethodChannel('whisper_voice');
  final _levels = StreamController<double>.broadcast();

  /// Microphone level (RMS, 0..1) every 50 ms while recording.
  Stream<double> get levels => _levels.stream;

  /// Starts recording the default microphone at 16 kHz.
  Future<void> start() => _channel.invokeMethod('start');

  /// Stops recording and keeps the audio. Returns its length.
  Future<Duration> stop() async {
    final ms = await _channel.invokeMethod<int>('stop');
    return Duration(milliseconds: ms ?? 0);
  }

  /// Stops recording, drops the audio and aborts a recognition in progress.
  Future<void> cancel() => _channel.invokeMethod('cancel');

  /// Loads the ggml model at [path] (kept until [unloadModel] or another
  /// model is loaded).
  Future<void> loadModel(String path) =>
      _channel.invokeMethod('loadModel', {'path': path});

  Future<void> unloadModel() => _channel.invokeMethod('unloadModel');

  /// Recognizes the recording (or [samples]: 16 kHz mono) in [language]
  /// ("fa", "en"), or with "auto" in the most likely of [candidates].
  /// The encoder looks at the recorded length but no less than
  /// [audioContext] steps of 20 ms: the smaller, the faster, but each model
  /// has a size below which it starts to make things up.
  Future<WhisperTranscript> transcribe({
    String language = 'auto',
    List<String> candidates = const ['en'],
    int audioContext = 512,
    Float32List? samples,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'transcribe',
      {
        'language': language,
        'candidates': candidates,
        'audioContext': audioContext,
        'samples': ?samples,
      },
    );
    return WhisperTranscript(
      result?['text'] as String? ?? '',
      result?['language'] as String? ?? language,
    );
  }
}
