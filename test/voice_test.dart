import 'dart:async';
import 'dart:typed_data';

import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/data/system_proxy.dart';
import 'package:browser6/engine/browser_engine.dart';
import 'package:browser6/features/new_tab/new_tab_page.dart';
import 'package:browser6/features/settings/app_settings.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/features/voice/speech_input.dart';
import 'package:browser6/features/voice/voice_panel.dart';
import 'package:browser6/features/voice/voice_tour.dart';
import 'package:browser6/features/voice/whisper_models.dart';
import 'package:browser6/ui/browser_shell.dart';
import 'package:browser6/ui/toolbar.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_voice/whisper_voice.dart';

import 'support/fake_engine.dart';

/// Records calls; the test plays the microphone and the recognizer.
class FakeWhisper implements WhisperVoice {
  final calls = <String>[];
  final levelsOut = StreamController<double>.broadcast();
  PlatformException? startError;
  Object? transcribeError;
  String heard = 'Search Iran.';
  Map<String, Object?>? lastTranscribe;

  @override
  Stream<double> get levels => levelsOut.stream;

  @override
  Future<void> start() async {
    calls.add('start');
    if (startError case final e?) throw e;
  }

  @override
  Future<Duration> stop() async {
    calls.add('stop');
    return const Duration(seconds: 2);
  }

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  Future<void> loadModel(String path) async => calls.add('load $path');

  @override
  Future<void> unloadModel() async => calls.add('unload');

  @override
  Future<WhisperTranscript> transcribe({
    String language = 'auto',
    List<String> candidates = const ['en'],
    int audioContext = 512,
    Float32List? samples,
  }) async {
    calls.add('transcribe');
    lastTranscribe = {
      'language': language,
      'candidates': candidates,
      'audioContext': audioContext,
    };
    if (transcribeError case final e?) throw e;
    return WhisperTranscript(heard, 'en');
  }
}

/// The panel's view of speech: the test says what was heard.
class FakeSpeechInput implements SpeechInput {
  StreamController<SpeechEvent>? session;
  final languages = <VoiceLanguage>[];
  int finishes = 0;
  int cancels = 0;

  @override
  Stream<SpeechEvent> listen(VoiceLanguage language) {
    languages.add(language);
    final controller = session = StreamController<SpeechEvent>();
    return controller.stream;
  }

  @override
  void finish() => finishes++;

  @override
  void cancel() => cancels++;

  void say(String text) => session!
    ..add(const SpeechRecognizing())
    ..add(SpeechResult(text))
    ..close();

  void fail(SpeechError error) => session!
    ..add(SpeechFailed(error))
    ..close();
}

class FixedModels extends WhisperModels {
  FixedModels(this.initial);
  final WhisperModelsState initial;

  @override
  WhisperModelsState build() => initial;
}

void main() {
  group('EndpointDetector', () {
    test('ends after speech and a pause', () {
      final d = EndpointDetector();
      for (var i = 0; i < 10; i++) {
        expect(d.add(0.002), Endpoint.listening);
      }
      for (var i = 0; i < 20; i++) {
        expect(d.add(i.isEven ? 0.08 : 0.03), Endpoint.listening);
      }
      expect(d.heardSpeech, isTrue);
      // 1.2 s of quiet at 50 ms a block.
      for (var i = 0; i < 23; i++) {
        expect(d.add(0.002), Endpoint.listening);
      }
      expect(d.add(0.002), Endpoint.done);
    });

    test('a short pause between words does not end it', () {
      final d = EndpointDetector();
      for (var i = 0; i < 10; i++) {
        d.add(0.05);
      }
      for (var i = 0; i < 12; i++) {
        expect(d.add(0.002), Endpoint.listening);
      }
      for (var i = 0; i < 10; i++) {
        expect(d.add(0.05), Endpoint.listening);
      }
    });

    test('steady background noise is not speech', () {
      final d = EndpointDetector();
      var result = Endpoint.listening;
      for (var i = 0; i < 120 && result == Endpoint.listening; i++) {
        result = d.add(0.02 + (i % 3) * 0.002); // a fan
      }
      expect(result, Endpoint.nothingHeard);
      expect(d.heardSpeech, isFalse);
    });

    test('stops at the maximum length', () {
      final d = EndpointDetector();
      var result = Endpoint.listening;
      var blocks = 0;
      // Talking from the first moment, with the usual dips between
      // syllables.
      while (result == Endpoint.listening) {
        result = d.add(blocks.isEven ? 0.1 : 0.03);
        blocks++;
      }
      expect(result, Endpoint.done);
      expect(blocks, 200); // 10 s
    });
  });

  group('VoiceLanguage', () {
    test('defaults to the first system language that can be spoken', () {
      expect(
        VoiceLanguage.fromLocales(const [Locale('ku'), Locale('da', 'DK')]),
        VoiceLanguage.danish,
      );
      expect(
        VoiceLanguage.fromLocales(const [Locale('fa', 'IR'), Locale('en')]),
        VoiceLanguage.persian,
      );
      expect(VoiceLanguage.fromLocales(const [Locale('nb')]).code, 'no');
      expect(
        VoiceLanguage.fromLocales(const [Locale('ku')]),
        VoiceLanguage.english,
      );
    });

    test('a saved choice wins over the system language', () {
      expect(
        AppSettings.fromMap({'voiceLanguage': 'da'}).voiceLanguage,
        VoiceLanguage.danish,
      );
      // Settings saved before languages were chosen by hand.
      expect(VoiceLanguage.byCode('auto'), isNull);
    });

    test('every language has a unique code and an Android tag', () {
      final codes = voiceLanguages.map((l) => l.code).toSet();
      expect(codes, hasLength(voiceLanguages.length));
      for (final l in voiceLanguages) {
        expect(
          l.androidTag,
          startsWith(
            l.code == 'no'
                ? 'nb'
                : l.code == 'tl'
                ? 'fil'
                : l.code,
          ),
        );
      }
    });
  });

  test('cleanTranscript drops whisper markers and quotes', () {
    expect(cleanTranscript(' [BLANK_AUDIO] '), '');
    expect(cleanTranscript('(music) Search Iran.'), 'Search Iran.');
    expect(cleanTranscript('"Open YouTube"'), 'Open YouTube');
    expect(cleanTranscript('«جستجو کن ایران»'), 'جستجو کن ایران');
  });

  test('whisper inventions on silence are recognized', () {
    expect(isWhisperHallucination('Thank you.'), isTrue);
    expect(isWhisperHallucination(' Thanks for watching! '), isTrue);
    expect(isWhisperHallucination('زیرنویس توسط امیر'), isTrue);
    expect(isWhisperHallucination('ممنون.'), isTrue);
    expect(isWhisperHallucination('Search Iran'), isFalse);
    expect(isWhisperHallucination('جستجو کن ایران'), isFalse);
  });

  test('displayLevel maps loudness to 0..1', () {
    expect(displayLevel(0), 0);
    expect(displayLevel(0.001), 0); // -60 dB
    expect(displayLevel(0.2), 1); // -14 dB
    expect(displayLevel(0.02), closeTo(0.53, 0.02)); // -34 dB
  });

  group('WindowsProxy', () {
    test('one proxy for every scheme', () {
      const proxy = WindowsProxy('127.0.0.1:10809');
      expect(
        proxy.proxyFor(Uri.parse('https://huggingface.co/x')),
        'PROXY 127.0.0.1:10809; DIRECT',
      );
    });

    test('per-scheme lists and bypass rules', () {
      const proxy = WindowsProxy(
        'http=10.0.0.1:8080;https=10.0.0.2:8443;socks=10.0.0.3:1080',
        bypass: 'localhost;*.lan;<local>',
      );
      expect(
        proxy.proxyFor(Uri.parse('https://a.com/')),
        'PROXY 10.0.0.2:8443; DIRECT',
      );
      expect(
        proxy.proxyFor(Uri.parse('http://a.com/')),
        'PROXY 10.0.0.1:8080; DIRECT',
      );
      expect(proxy.proxyFor(Uri.parse('http://nas.lan/')), 'DIRECT');
      expect(proxy.proxyFor(Uri.parse('http://router/')), 'DIRECT');
      expect(proxy.proxyFor(Uri.parse('http://localhost:3000/')), 'DIRECT');
    });

    test('a SOCKS-only setting connects directly', () {
      const proxy = WindowsProxy('socks=127.0.0.1:1080');
      expect(proxy.proxyFor(Uri.parse('https://a.com/')), 'DIRECT');
    });
  });

  group('WhisperSpeechInput', () {
    late FakeWhisper whisper;
    late WhisperSpeechInput input;
    WhisperModelFile? model;

    setUp(() {
      whisper = FakeWhisper();
      model = const WhisperModelFile(r'C:\models\small.bin', 512);
      input = WhisperSpeechInput(whisper, () => model);
    });

    Future<List<SpeechEvent>> speak(
      Stream<SpeechEvent> events,
      List<double> levels,
    ) async {
      final out = <SpeechEvent>[];
      final done = events.forEach(out.add);
      await Future<void>.delayed(Duration.zero);
      for (final level in levels) {
        whisper.levelsOut.add(level);
      }
      await done;
      return out;
    }

    test('records, stops after the speaker pauses and recognizes', () async {
      final events = await speak(input.listen(VoiceLanguage.english), [
        ...List.filled(6, 0.002),
        ...List.filled(12, 0.06),
        ...List.filled(30, 0.002),
      ]);
      expect(whisper.calls, [
        r'load C:\models\small.bin',
        'start',
        'stop',
        'transcribe',
      ]);
      // The chosen language only: no guessing.
      expect(whisper.lastTranscribe?['language'], 'en');
      expect(whisper.lastTranscribe?['audioContext'], 512);
      expect(events.whereType<SpeechLevel>(), isNotEmpty);
      expect(events.whereType<SpeechRecognizing>(), hasLength(1));
      expect((events.last as SpeechResult).text, 'Search Iran.');
    });

    test('the chosen language is passed on', () async {
      for (final language in [VoiceLanguage.persian, VoiceLanguage.danish]) {
        final events = input.listen(language);
        final last = events.last;
        await Future<void>.delayed(Duration.zero);
        input.finish();
        await last;
        expect(whisper.lastTranscribe?['language'], language.code);
      }
    });

    test('no model: asks for the download', () async {
      model = null;
      final events = await input.listen(VoiceLanguage.english).toList();
      expect((events.single as SpeechFailed).error, SpeechError.modelMissing);
      expect(whisper.calls, isEmpty);
    });

    test('a blocked microphone is reported', () async {
      whisper.startError = PlatformException(code: 'mic_blocked');
      final events = await input.listen(VoiceLanguage.english).toList();
      expect((events.last as SpeechFailed).error, SpeechError.micBlocked);
    });

    test('silence gives up without recognizing', () async {
      final events = await speak(
        input.listen(VoiceLanguage.english),
        List.filled(130, 0.002),
      );
      expect((events.last as SpeechFailed).error, SpeechError.noSpeech);
      expect(whisper.calls, contains('cancel'));
      expect(whisper.calls, isNot(contains('transcribe')));
    });

    test('an invented "Thank you." is not taken as speech', () async {
      whisper.heard = ' Thank you.';
      final events = input.listen(VoiceLanguage.english);
      final last = events.last;
      await Future<void>.delayed(Duration.zero);
      input.finish();
      expect(((await last) as SpeechFailed).error, SpeechError.noSpeech);
    });

    test('nothing but noise in the recording', () async {
      whisper.transcribeError = PlatformException(code: 'no_speech');
      final events = input.listen(VoiceLanguage.english);
      final last = events.last;
      await Future<void>.delayed(Duration.zero);
      input.finish();
      expect(((await last) as SpeechFailed).error, SpeechError.noSpeech);
    });

    test('cancel stops the recording and ends the session', () async {
      final events = input.listen(VoiceLanguage.english).toList();
      await Future<void>.delayed(Duration.zero);
      input.cancel();
      expect(await events, isEmpty);
      expect(whisper.calls.last, 'cancel');
    });
  });

  group('voice panel', () {
    late FakeSpeechInput speech;

    Future<ProviderContainer> pump(
      WidgetTester tester, {
      bool whisper = false,
      WhisperModelsState models = const WhisperModelsState(folder: 'x'),
      bool tour = false,
      Size size = const Size(1200, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      speech = FakeSpeechInput();
      final container = ProviderContainer(
        overrides: [
          engineProvider.overrideWithValue(FakeEngine()),
          databaseProvider.overrideWithValue(AppDatabase.inMemory()),
          speechInputProvider.overrideWithValue(speech),
          usesWhisperModelsProvider.overrideWithValue(whisper),
          whisperModelsProvider.overrideWith(() => FixedModels(models)),
          voiceTourEnabledProvider.overrideWithValue(tour),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 10));
        container.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: BrowserShell()),
        ),
      );
      await tester.pump();
      return container;
    }

    String activeUrl(ProviderContainer c) =>
        c.read(tabsProvider).active!.view.url.value;

    /// Leaves the New Tab page (and its microphone) for a web page.
    Future<void> openPage(WidgetTester tester, ProviderContainer c) async {
      (c.read(tabsProvider).active!.view as FakeView).url.value =
          'https://example.com/';
      await tester.pumpAndSettle();
      expect(find.byType(NewTabPage), findsNothing);
    }

    const toolbarMic = 'Voice command (Ctrl+Shift+Space)';

    /// The tour animates for ever, so time is pumped by hand.
    Future<void> frames(WidgetTester tester, [int ms = 600]) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(Duration(milliseconds: ms ~/ 4));
      }
    }

    Future<String?> seen(ProviderContainer c) =>
        c.read(databaseProvider).getSetting(voiceTourSeenSetting);

    testWidgets('the address bar mic works on every page', (tester) async {
      final c = await pump(tester);
      await openPage(tester, c);
      await tester.tap(find.byTooltip(toolbarMic));
      await tester.pumpAndSettle();
      expect(find.text('Listening…'), findsOneWidget);

      speech.say('open YouTube');
      await tester.pumpAndSettle();
      expect(activeUrl(c), 'https://www.youtube.com/');
    });

    testWidgets('Ctrl+Shift+Space listens, and only one panel opens', (
      tester,
    ) async {
      final c = await pump(tester);
      // On the New Tab page the address bar has the keyboard.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Listening…'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(VoicePanel), findsNothing);

      // On a web page the page sees the key first and passes it on.
      await openPage(tester, c);
      final view = c.read(tabsProvider).active!.view as FakeView;
      for (var i = 0; i < 2; i++) {
        view.unhandledKeyController.add(
          const PageKey(0x20, control: true, shift: true),
        );
        await tester.pumpAndSettle();
      }
      expect(find.byType(VoicePanel), findsOneWidget);
      expect(speech.languages, hasLength(2));

      speech.say('new tab');
      await tester.pumpAndSettle();
      expect(c.read(tabsProvider).tabs, hasLength(2));
    });

    testWidgets('the mic does not open a second panel', (tester) async {
      final c = await pump(tester);
      await openPage(tester, c);
      final mic = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(CupertinoIcons.mic),
          matching: find.byType(IconButton),
        ),
      );
      mic.onPressed!();
      mic.onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(VoicePanel), findsOneWidget);
      expect(speech.languages, hasLength(1));
    });

    testWidgets('the main menu has a voice command', (tester) async {
      final c = await pump(tester);
      await openPage(tester, c);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voice command…'));
      await tester.pumpAndSettle();
      expect(find.text('Listening…'), findsOneWidget);
    });

    testWidgets('phones have the mic in the address bar', (tester) async {
      final c = await pump(tester, size: const Size(400, 800));
      await openPage(tester, c);
      final mic = find.descendant(
        of: find.byType(BrowserToolbar),
        matching: find.byType(VoiceMicButton),
      );
      expect(mic, findsOneWidget);
      await tester.tap(mic);
      await tester.pumpAndSettle();
      expect(find.text('Listening…'), findsOneWidget);
    });

    testWidgets('the first launch tours voice control, then tries it', (
      tester,
    ) async {
      final c = await pump(tester, tour: true);
      await frames(tester, 1400);
      await frames(tester);
      expect(find.text('Talk to 6browser'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      // The spotlight found the microphone in the address bar.
      final hole = tester.getCenter(
        find.byKey(const ValueKey('voice-tour-mic')),
      );
      expect(hole, tester.getCenter(find.byTooltip(toolbarMic)));

      await tester.tap(find.text('Next'));
      await frames(tester);
      expect(find.text('Just say it'), findsOneWidget);
      // The demo speaks a command and shows what it does.
      await frames(tester, 2400);
      expect(find.textContaining('search Iran'), findsOneWidget);
      expect(find.text('Searches the web'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await frames(tester);
      expect(find.text('Made for you'), findsOneWidget);
      expect(find.textContaining('Ctrl+Shift+Space'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);

      await tester.tap(find.text('Try it now'));
      await frames(tester);
      await tester.pumpAndSettle();
      expect(find.text('Talk to 6browser'), findsNothing);
      expect(find.text('Listening…'), findsOneWidget);
      expect(await seen(c), 'true');
    });

    testWidgets('the tour can be skipped and does not come back', (
      tester,
    ) async {
      final c = await pump(tester, tour: true);
      await frames(tester, 1400);
      await frames(tester);
      await tester.tap(find.text('Skip'));
      await frames(tester);
      await tester.pumpAndSettle();
      expect(find.text('Talk to 6browser'), findsNothing);
      expect(find.byType(VoicePanel), findsNothing);
      expect(await seen(c), 'true');
    });

    testWidgets('the tour shows in Persian and starts from the spotlight', (
      tester,
    ) async {
      final c = await pump(tester, tour: true);
      await c.read(databaseProvider).setSetting('voiceLanguage', 'fa');
      await frames(tester, 1400);
      await frames(tester);
      await tester.tap(find.text('Next'));
      await frames(tester, 2400);
      expect(find.textContaining('جستجو کن ایران'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('voice-tour-mic')));
      await frames(tester);
      await tester.pumpAndSettle();
      expect(find.text('Listening…'), findsOneWidget);
      expect(speech.languages, [VoiceLanguage.persian]);
    });

    testWidgets('a tour already seen stays away until asked for', (
      tester,
    ) async {
      final c = await pump(tester, tour: true);
      await c.read(databaseProvider).setSetting(voiceTourSeenSetting, 'true');
      await frames(tester, 1400);
      await frames(tester);
      expect(find.text('Talk to 6browser'), findsNothing);

      // Settings > Voice commands > Show the voice tour.
      c.read(voiceTourRequestProvider.notifier).show();
      await frames(tester);
      await frames(tester);
      expect(find.text('Talk to 6browser'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(tester);
      await tester.pumpAndSettle();
      expect(find.text('Talk to 6browser'), findsNothing);
    });

    testWidgets('the New Tab mic searches what was said', (tester) async {
      final c = await pump(tester);
      await tester.tap(find.byTooltip('Voice command'));
      await tester.pumpAndSettle();
      expect(find.text('Listening…'), findsOneWidget);
      expect(speech.languages, [VoiceLanguage.english]);

      speech.say('Search Iran.');
      await tester.pumpAndSettle();
      expect(find.text('Listening…'), findsNothing);
      expect(activeUrl(c), 'https://www.google.com/search?q=iran');
    });

    testWidgets('Persian commands open sites and run browser commands', (
      tester,
    ) async {
      final c = await pump(tester);
      await tester.tap(find.byTooltip('Voice command'));
      await tester.pumpAndSettle();
      speech.say('برو به یوتیوب');
      await tester.pumpAndSettle();
      expect(activeUrl(c), 'https://www.youtube.com/');

      c.read(tabsProvider.notifier).newTab();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Voice command'));
      await tester.pumpAndSettle();
      speech.say('یه تب جدید باز کن');
      await tester.pumpAndSettle();
      expect(c.read(tabsProvider).tabs, hasLength(3));
    });

    testWidgets('failures explain and the mic tries again', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Voice command'));
      await tester.pumpAndSettle();
      speech.fail(SpeechError.micBusy);
      await tester.pumpAndSettle();
      expect(find.text(SpeechError.micBusy.message), findsOneWidget);

      await tester.tap(find.byTooltip('Try again'));
      await tester.pumpAndSettle();
      expect(speech.languages, hasLength(2));
      expect(find.text('Listening…'), findsOneWidget);

      // Something that is not a command stays on screen.
      speech.say('search');
      await tester.pumpAndSettle();
      expect(find.text('Not sure what to do with that.'), findsOneWidget);
      expect(find.text('“search”'), findsOneWidget);
    });

    testWidgets('Done stops listening; closing cancels', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Voice command'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      expect(speech.finishes, 1);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(speech.cancels, greaterThan(0));
      expect(find.text('Listening…'), findsNothing);
    });

    testWidgets('choosing a language listens in it and keeps it', (
      tester,
    ) async {
      final c = await pump(tester);
      await tester.tap(find.byTooltip('Voice command'));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsOneWidget);
      expect(find.textContaining('“search Iran”'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('voice-language')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Danish (Dansk)').last,
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Danish (Dansk)').last);
      await tester.pumpAndSettle();
      expect(speech.languages, [VoiceLanguage.english, VoiceLanguage.danish]);
      expect(find.text('Dansk'), findsOneWidget);
      expect(find.textContaining('“søg efter Iran”'), findsOneWidget);
      // Saved: the settings (read from the database) have it.
      expect(c.read(appSettingsProvider).voiceLanguage, VoiceLanguage.danish);

      // Danish words become commands.
      speech.say('Søg efter Iran.');
      await tester.pumpAndSettle();
      expect(activeUrl(c), 'https://www.google.com/search?q=iran');
    });

    testWidgets('the panel uses the language chosen in settings', (
      tester,
    ) async {
      final c = await pump(tester);
      c.read(databaseProvider).setSetting('voiceLanguage', 'fa');
      await tester.pumpAndSettle();
      expect(c.read(appSettingsProvider).voiceLanguage, VoiceLanguage.persian);
      await tester.tap(find.byTooltip('Voice command'));
      await tester.pumpAndSettle();
      expect(speech.languages, [VoiceLanguage.persian]);
      expect(find.text('فارسی'), findsOneWidget);
    });

    testWidgets('Windows without a model offers the download', (tester) async {
      await pump(tester, whisper: true);
      await tester.tap(find.byTooltip('Voice command'));
      await tester.pumpAndSettle();
      expect(find.text('Download the speech model'), findsOneWidget);
      expect(find.text('Download (190 MB)'), findsOneWidget);
      expect(speech.languages, isEmpty);
    });

    testWidgets('Windows with the model listens at once', (tester) async {
      await pump(
        tester,
        whisper: true,
        models: const WhisperModelsState(
          folder: 'x',
          installed: {WhisperModel.standard},
        ),
      );
      await tester.tap(find.byTooltip('Voice command'));
      await tester.pumpAndSettle();
      expect(find.text('Listening…'), findsOneWidget);
      expect(speech.languages, [VoiceLanguage.english]);
    });
  });
}
