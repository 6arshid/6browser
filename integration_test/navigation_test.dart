// Typing an address and clicking a link, end to end in the full app with
// the real engine (Windows), with voice commands off and on.
//
//   flutter drive --profile -d windows --driver=test_driver/integration_test.dart
//     --target=integration_test/navigation_test.dart
import 'dart:async';
import 'dart:io';

import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/engine/browser_engine.dart';
import 'package:browser6/engine/cef_engine.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/features/voice/speech_input.dart';
import 'package:browser6/features/voice/voice_panel.dart';
import 'package:browser6/features/voice/voice_tour.dart';
import 'package:browser6/ui/browser_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// A page that is one big link to [to].
String _page(String name, String to) => '''<!doctype html><title>$name</title>
<style>html,body{margin:0;height:100%}a{display:block;height:100%;font:40px sans-serif}</style>
<a id="link" href="$to">$name: go to $to</a>''';

/// A noisy room, as Whisper hears it: the level moves for 1.5 s, then
/// 0.75 s of recognizing, then words that are not a command; over and over.
class _NoisySpeech implements SpeechInput {
  StreamController<SpeechEvent>? _out;
  Timer? _timer;

  @override
  Stream<SpeechEvent> listen(VoiceLanguage language) {
    cancel();
    final out = _out = StreamController<SpeechEvent>();
    var ticks = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      ticks++;
      if (ticks < 30) {
        out.add(SpeechLevel((ticks % 7) / 7));
      } else if (ticks == 30) {
        out.add(const SpeechRecognizing());
      } else if (ticks >= 45) {
        timer.cancel();
        _out = null;
        out
          ..add(const SpeechResult('نمیمینی'))
          ..close();
      }
    });
    return out.stream;
  }

  @override
  void finish() {}

  @override
  void cancel() {
    _timer?.cancel();
    _out?.close();
    _out = null;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typed addresses and clicked links open', (tester) async {
    // Typing goes through the test's keyboard, not the system's.
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final temp = Directory.systemTemp.createTempSync('6b_navigation');
    final server = await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server!.listen((request) {
      final path = request.uri.path;
      request.response
        ..headers.contentType = ContentType.html
        ..write(switch (path) {
          '/a' => _page('A', '/b'),
          '/c' => _page('C', '/d'),
          _ => _page(path.substring(1).toUpperCase(), '/a'),
        })
        ..close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    final engine = CefEngine(cachePath: '${temp.path}\\profile');
    final c = ProviderContainer(
      overrides: [
        engineProvider.overrideWithValue(engine),
        databaseProvider.overrideWithValue(AppDatabase.inMemory()),
        // Its own folder: otherwise the extensions installed in the real
        // profile are loaded.
        dataDirProvider.overrideWithValue(temp),
        launchOptionsProvider.overrideWithValue(LaunchOptions(url: '$base/a')),
        speechInputProvider.overrideWithValue(_NoisySpeech()),
        usesWhisperModelsProvider.overrideWithValue(false),
        voiceTourEnabledProvider.overrideWithValue(false),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: BrowserShell()),
      ),
    );

    BrowserView view() => c.read(tabsProvider).active!.view;

    Future<void> waitFor(String what, bool Function() done) async {
      for (var i = 0; i < 300; i++) {
        if (done()) return;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      fail(
        'Timed out waiting for $what (url: ${view().url.value}, '
        'title: ${view().title.value})',
      );
    }

    Future<void> loaded(String path) => waitFor(
      '$path to load',
      () =>
          c.read(tabsProvider).tabs.isNotEmpty &&
          view().url.value == '$base$path' &&
          !view().isLoading.value &&
          view().title.value == path.substring(1).toUpperCase(),
    );

    Future<void> clickLink(String from, String to) async {
      await loaded(from);
      // Let the page paint before clicking it.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 800)),
      );
      await tester.pump();
      final page = tester.getRect(find.byWidget(view().widget));
      await tester.tapAt(page.topLeft + const Offset(120, 60));
      await loaded(to);
    }

    Future<void> typeAddress(String path) async {
      final field = find
          .descendant(
            of: find.byType(BrowserShell),
            matching: find.byType(TextField),
          )
          .first;
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, '$base$path');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller?.text, '$base$path');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      await loaded(path);
    }

    await loaded('/a');
    await clickLink('/a', '/b');
    // The engine's own load, without the address bar.
    await view().load('$base/a');
    await loaded('/a');
    await clickLink('/a', '/b');
    await typeAddress('/c');
    await clickLink('/c', '/d');

    // The same with voice commands on.
    c.read(voiceModeProvider.notifier).start();
    await tester.pump();
    expect(find.byType(VoiceDock), findsOneWidget);
    await typeAddress('/a');
    await clickLink('/a', '/b');
    await typeAddress('/c');
    await clickLink('/c', '/d');

    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.runAsync(() => server.close(force: true));
  });
}
