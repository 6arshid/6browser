import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:whisper_voice/whisper_voice.dart';

import 'voice_language.dart';

export 'voice_language.dart';

/// Progress of one listening session.
sealed class SpeechEvent {
  const SpeechEvent();
}

/// Loudness for the animation, 0 (silence) to 1.
class SpeechLevel extends SpeechEvent {
  const SpeechLevel(this.level);
  final double level;
}

/// What was understood so far (Android shows words as they come).
class SpeechPartial extends SpeechEvent {
  const SpeechPartial(this.text);
  final String text;
}

/// Listening ended; the speech is being recognized.
class SpeechRecognizing extends SpeechEvent {
  const SpeechRecognizing();
}

/// The session's last event on success.
class SpeechResult extends SpeechEvent {
  const SpeechResult(this.text);
  final String text;
}

/// The session's last event on failure.
class SpeechFailed extends SpeechEvent {
  const SpeechFailed(this.error);
  final SpeechError error;
}

enum SpeechError {
  noSpeech("Didn't catch that. Try again."),
  micBlocked(
    'Microphone access is off. Turn it on in Windows Settings > '
    'Privacy & security > Microphone, including "Let desktop apps access '
    'your microphone".',
  ),
  noMicrophone('No microphone was found.'),
  micBusy('The microphone is being used by another app.'),
  permission('6browser is not allowed to use the microphone.'),
  network('Speech recognition needs an internet connection.'),
  language('Speech recognition is not available in this language.'),
  unavailable('This device has no speech recognition service.'),
  modelMissing('The speech model is not downloaded.'),
  badModel('The speech model file is damaged. Download it again.'),
  failed('Speech recognition failed. Try again.');

  const SpeechError(this.message);
  final String message;
}

/// Speech to text for voice commands.
abstract class SpeechInput {
  /// Listens until the speaker stops (or [finish]); ends with a
  /// [SpeechResult] or a [SpeechFailed]. Starting again ends the previous
  /// session.
  Stream<SpeechEvent> listen(VoiceLanguage language);

  /// Stops listening and recognizes what was said so far.
  void finish();

  /// Stops and drops everything.
  void cancel();
}

/// Removes what whisper writes for non-speech ("[BLANK_AUDIO]", "(music)")
/// and stray quotes; empty when nothing was said.
String cleanTranscript(String text) => text
    .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\*[^*]*\*|♪'), ' ')
    .replaceAll(RegExp(r'^[\s"«“.]+|[\s"»”]+$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Whisper's well-known inventions on near-silence: video endings and
/// subtitle credits it saw in training ("Thank you for watching",
/// «زیرنویس توسط ...»). None of them is a command.
bool isWhisperHallucination(String text) {
  final t = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return const {
        'you',
        'thank you',
        'thanks',
        'thank you very much',
        'thanks for watching',
        'thank you for watching',
        'bye',
        'ممنون',
        'مرسی',
        'خداحافظ',
        'ممنون از تماشای شما',
        'ممنونم',
      }.contains(t) ||
      t.contains('زیرنویس') ||
      t.contains('subtitles by') ||
      t.contains('amaraorg') ||
      t.contains('please subscribe');
}

/// Loudness (RMS, 0..1) as a 0..1 level on a decibel scale: -55 dB is
/// silence, -15 dB loud speech.
double displayLevel(double rms) {
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 55) / 40).clamp(0.0, 1.0);
}

/// What [EndpointDetector] decides after a block of audio.
enum Endpoint { listening, done, nothingHeard }

/// Decides from microphone levels when the speaker has finished: after
/// some speech and then [trailingSilence] of quiet. The background noise
/// level is learned as it goes, so a fan or a noisy room is not taken for
/// speech.
class EndpointDetector {
  EndpointDetector({
    this.block = const Duration(milliseconds: 50),
    this.trailingSilence = const Duration(milliseconds: 1200),
    this.waitForSpeech = const Duration(seconds: 6),
    this.maxLength = const Duration(seconds: 10),
  });

  final Duration block;
  final Duration trailingSilence;
  final Duration waitForSpeech;
  final Duration maxLength;

  double _noise = -1;
  int _blocks = 0;
  int _loudBlocks = 0;
  int _quietBlocks = 0;

  bool get heardSpeech => _loudBlocks >= 3;

  Endpoint add(double rms) {
    _blocks++;
    // The noise floor drops at once to quieter input and rises slowly, so
    // speech does not lift it much.
    _noise = _noise < 0 || rms < _noise ? rms : _noise * 0.995 + rms * 0.005;
    // Speech dips between syllables, so the floor stays near the room's
    // noise even when the speaker starts at once.
    final loud = rms > math.max(0.006, _noise * 2);
    if (loud) {
      _loudBlocks++;
      _quietBlocks = 0;
    } else {
      _quietBlocks++;
    }
    final elapsed = block * _blocks;
    if (heardSpeech) {
      if (block * _quietBlocks >= trailingSilence || elapsed >= maxLength) {
        return Endpoint.done;
      }
    } else if (elapsed >= waitForSpeech) {
      return Endpoint.nothingHeard;
    }
    return Endpoint.listening;
  }
}

/// A Whisper model file and the smallest audio context it is accurate with
/// (see [WhisperVoice.transcribe]).
class WhisperModelFile {
  const WhisperModelFile(this.path, this.audioContext);
  final String path;
  final int audioContext;
}

/// Windows: whisper.cpp on this computer; the voice never leaves it. The
/// model loads while the user speaks and is freed after a few idle minutes.
class WhisperSpeechInput implements SpeechInput {
  WhisperSpeechInput(this._voice, this._model);

  final WhisperVoice _voice;

  /// The installed model, or null when it has to be downloaded first.
  final WhisperModelFile? Function() _model;

  static const _keepLoaded = Duration(minutes: 3);

  // Calls reach the plugin in order, so stop or cancel always follow a
  // start that is still on its way.
  StreamController<SpeechEvent>? _out;
  StreamSubscription<double>? _levels;
  Future<Object?>? _loadError;
  WhisperModelFile? _file;
  VoiceLanguage _language = VoiceLanguage.english;
  bool _finishing = false;
  Timer? _unload;

  @override
  Stream<SpeechEvent> listen(VoiceLanguage language) {
    cancel();
    final out = _out = StreamController<SpeechEvent>();
    _language = language;
    _finishing = false;
    _start(out);
    return out.stream;
  }

  Future<void> _start(StreamController<SpeechEvent> out) async {
    final file = _file = _model();
    if (file == null) {
      _fail(out, SpeechError.modelMissing);
      return;
    }
    _unload?.cancel();
    _loadError = _voice
        .loadModel(file.path)
        .then<Object?>((_) => null, onError: (Object e) => e);
    final endpoint = EndpointDetector();
    _levels = _voice.levels.listen((rms) {
      if (_out != out || _finishing) return;
      out.add(SpeechLevel(displayLevel(rms)));
      switch (endpoint.add(rms)) {
        case Endpoint.listening:
          break;
        case Endpoint.done:
          finish();
        case Endpoint.nothingHeard:
          _voice.cancel();
          _fail(out, SpeechError.noSpeech);
      }
    });
    try {
      await _voice.start();
    } on PlatformException catch (e) {
      if (_out == out) _fail(out, _errorFor(e.code));
    } catch (_) {
      if (_out == out) _fail(out, SpeechError.failed);
    }
  }

  @override
  Future<void> finish() async {
    final out = _out;
    if (out == null || _finishing) return;
    _finishing = true;
    await _levels?.cancel();
    _levels = null;
    out.add(const SpeechRecognizing());
    try {
      await _voice.stop();
      final loadError = await _loadError;
      if (loadError != null) throw loadError;
      final heard = await _voice.transcribe(
        language: _language.code,
        audioContext: _file!.audioContext,
      );
      if (_out != out) return;
      final text = cleanTranscript(heard.text);
      if (text.isEmpty || isWhisperHallucination(text)) {
        _fail(out, SpeechError.noSpeech);
        return;
      }
      _out = null;
      out
        ..add(SpeechResult(text))
        ..close();
    } on PlatformException catch (e) {
      if (_out == out) _fail(out, _errorFor(e.code));
    } catch (_) {
      if (_out == out) _fail(out, SpeechError.failed);
    } finally {
      _scheduleUnload();
    }
  }

  @override
  void cancel() {
    final out = _out;
    _out = null;
    _levels?.cancel();
    _levels = null;
    if (out != null) {
      _voice.cancel();
      out.close();
      _scheduleUnload();
    }
  }

  void _fail(StreamController<SpeechEvent> out, SpeechError error) {
    _levels?.cancel();
    _levels = null;
    if (_out == out) _out = null;
    out
      ..add(SpeechFailed(error))
      ..close();
  }

  void _scheduleUnload() {
    _unload?.cancel();
    _unload = Timer(_keepLoaded, () => _voice.unloadModel());
  }

  static SpeechError _errorFor(String code) => switch (code) {
    'mic_blocked' => SpeechError.micBlocked,
    'no_microphone' => SpeechError.noMicrophone,
    'mic_busy' => SpeechError.micBusy,
    'no_speech' => SpeechError.noSpeech,
    'no_model' => SpeechError.modelMissing,
    'bad_model' => SpeechError.badModel,
    _ => SpeechError.failed,
  };
}

/// Android: the phone's speech recognizer (Google's on most phones), which
/// shows words as they are recognized and decides itself when the speaker
/// has finished.
class AndroidSpeechInput implements SpeechInput {
  AndroidSpeechInput() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('6browser/voice');

  StreamController<SpeechEvent>? _out;

  @override
  Stream<SpeechEvent> listen(VoiceLanguage language) {
    cancel();
    final out = _out = StreamController<SpeechEvent>();
    _channel
        .invokeMethod<void>('start', {'language': language.androidTag})
        .catchError((Object e) {
          if (_out == out) {
            _end(
              SpeechFailed(switch (e) {
                PlatformException(code: 'permission') => SpeechError.permission,
                PlatformException(code: 'unavailable') =>
                  SpeechError.unavailable,
                PlatformException(code: 'busy') => SpeechError.micBusy,
                _ => SpeechError.failed,
              }),
            );
          }
        });
    return out.stream;
  }

  @override
  void finish() => _channel.invokeMethod<void>('stop');

  @override
  void cancel() {
    final out = _out;
    _out = null;
    if (out != null) {
      _channel.invokeMethod<void>('cancel');
      out.close();
    }
  }

  Future<void> _onCall(MethodCall call) async {
    final out = _out;
    if (out == null) return;
    switch (call.method) {
      case 'level':
        out.add(SpeechLevel((call.arguments as num).toDouble()));
      case 'partial':
        out.add(SpeechPartial(cleanTranscript(call.arguments as String)));
      case 'endOfSpeech':
        out.add(const SpeechRecognizing());
      case 'result':
        final text = cleanTranscript(call.arguments as String? ?? '');
        _end(
          text.isEmpty
              ? const SpeechFailed(SpeechError.noSpeech)
              : SpeechResult(text),
        );
      case 'error':
        _end(
          SpeechFailed(switch (call.arguments as String?) {
            'no_speech' || 'no_match' => SpeechError.noSpeech,
            'permission' => SpeechError.permission,
            'network' => SpeechError.network,
            'language' => SpeechError.language,
            'busy' => SpeechError.micBusy,
            _ => SpeechError.failed,
          }),
        );
    }
  }

  void _end(SpeechEvent last) {
    final out = _out;
    _out = null;
    out
      ?..add(last)
      ..close();
  }
}
