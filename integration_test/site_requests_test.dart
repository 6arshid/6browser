// What pages ask the user, end to end in the real engine (Windows): alert(),
// confirm() and prompt(), a microphone permission request, and screen
// sharing with system audio through the getDisplayMedia shim.
//
//   flutter drive --profile -d windows --driver=test_driver/integration_test.dart
//     --target=integration_test/site_requests_test.dart
//
// Shares this test's own window. For the audio check two quiet tones play
// for a few seconds: 440 Hz from another process (must be shared) and
// 1000 Hz from the page itself (must be left out, no echo).
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:browser6/engine/browser_engine.dart';
import 'package:browser6/engine/cef_engine.dart';
import 'package:browser6/features/screen_share/capture_sources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _page = r'''<!doctype html>
<title>site requests</title>
<script>
const post = (o) => external.JavaScriptChannel('sixbrowserPage', o);
const wait = (ms) => new Promise(r => setTimeout(r, ms));
let go;
const started = new Promise(r => go = r);
window.startShare = () => go();
async function run() {
  alert('hello from the page');
  post({step: 'alert'});
  post({step: 'confirm', ok: confirm('continue?')});
  post({step: 'prompt', text: prompt('name?', 'default')});
  try {
    const s = await navigator.mediaDevices.getUserMedia({audio: true});
    post({step: 'mic', ok: true});
    s.getTracks().forEach(t => t.stop());
  } catch (e) {
    post({step: 'mic', ok: false, error: e.name});
  }
  await started;
  try {
    const stream = await navigator.mediaDevices.getDisplayMedia({video: true, audio: true});
    const v = stream.getVideoTracks()[0];
    const a = stream.getAudioTracks()[0];
    post({step: 'share', video: !!v, audio: !!a, surface: v.getSettings().displaySurface});
    const video = document.createElement('video');
    video.muted = true;
    video.srcObject = new MediaStream([v]);
    await video.play();
    await wait(1500);
    post({step: 'frames', width: video.videoWidth, height: video.videoHeight});
    if (a) {
      const ctx = new AudioContext();
      const tone = ctx.createOscillator();
      tone.frequency.value = 1000;
      const quiet = ctx.createGain();
      quiet.gain.value = 0.03;
      tone.connect(quiet).connect(ctx.destination);
      tone.start();
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 8192;
      analyser.smoothingTimeConstant = 0;
      ctx.createMediaStreamSource(new MediaStream([a])).connect(analyser);
      post({step: 'listening'});
      const bins = new Float32Array(analyser.frequencyBinCount);
      const loudest = new Float32Array(analyser.frequencyBinCount).fill(-200);
      for (let i = 0; i < 30; i++) {
        await wait(100);
        analyser.getFloatFrequencyData(bins);
        for (let b = 0; b < bins.length; b++) loudest[b] = Math.max(loudest[b], bins[b]);
      }
      const bin = (f) => Math.round(f * analyser.fftSize / ctx.sampleRate);
      const near = (f) => Math.max(...[-2, -1, 0, 1, 2].map(d => loudest[bin(f) + d]));
      const sorted = Array.from(loudest.slice(bin(200), bin(4000))).sort((x, y) => x - y);
      post({step: 'audio', at440: near(440), at1000: near(1000), floor: sorted[sorted.length >> 1]});
      tone.stop();
      ctx.close();
    }
    stream.getTracks().forEach(t => t.stop());
    post({step: 'stopped'});
  } catch (e) {
    post({step: 'share', error: e.name + ': ' + e.message});
  }
}
addEventListener('load', run);
</script>''';

/// A 16-bit mono WAV of a sine at [hz].
Uint8List _toneWav(double hz, Duration length, double volume) {
  const rate = 48000;
  final count = rate * length.inMilliseconds ~/ 1000;
  final data = ByteData(44 + count * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + count * 2, Endian.little);
  ascii(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, count * 2, Endian.little);
  for (var i = 0; i < count; i++) {
    final v = sin(2 * pi * hz * i / rate) * volume * 32767;
    data.setInt16(44 + i * 2, v.round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('page requests reach the app and are carried out', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('6b_site_requests');
    final server = await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server!.listen((request) {
      request.response
        ..headers.contentType = ContentType.html
        ..write(_page)
        ..close();
    });
    final engine = CefEngine(cachePath: '${temp.path}\\profile');
    await tester.runAsync(engine.initialize);
    final view = engine.createView(
      initialUrl: 'http://127.0.0.1:${server.port}/',
    );

    final messages = <Map<String, Object?>>[];
    final dialogs = <PageDialogRequest>[];
    final permissions = <PermissionRequest>[];
    final shares = <ScreenShareRequest>[];
    String? sharedId;
    view.scriptMessages.listen(
      (m) => messages.add(jsonDecode(m) as Map<String, Object?>),
    );
    view.pageDialogs.listen((d) {
      dialogs.add(d);
      d.respond(true, d.type == PageDialogType.prompt ? 'Sara' : '');
    });
    view.permissionRequests.listen((r) {
      permissions.add(r);
      r.respond(PermissionAnswer.allow);
    });
    view.screenShareRequests.listen((r) async {
      shares.add(r);
      final sources = await listCaptureSources();
      final own = sources.where((s) => s.title == '6browser').firstOrNull;
      sharedId = (own ?? sources.first).id;
      r.share(sharedId!, audio: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            // The widget exists once the browser does, as in the app.
            child: ValueListenableBuilder<bool>(
              valueListenable: view.isReady,
              builder: (_, ready, _) =>
                  ready ? view.widget : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    Future<Map<String, Object?>> step(String name, {int seconds = 20}) async {
      for (var i = 0; i < seconds * 10; i++) {
        final found = messages.where((m) => m['step'] == name).firstOrNull;
        if (found != null) return found;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      fail('The page never reported "$name". Messages: $messages');
    }

    // Page dialogs.
    await step('alert', seconds: 30);
    expect(dialogs.first.type, PageDialogType.alert);
    expect(dialogs.first.message, 'hello from the page');
    expect(dialogs.first.origin, 'http://127.0.0.1:${server.port}');
    expect((await step('confirm'))['ok'], isTrue);
    expect((await step('prompt'))['text'], 'Sara');
    expect(dialogs.map((d) => d.type), [
      PageDialogType.alert,
      PageDialogType.confirm,
      PageDialogType.prompt,
    ]);
    expect(dialogs[2].defaultText, 'default');

    // Microphone: asked through the app (Chromium's prompt, then the
    // device request), allowed.
    final mic = await step('mic');
    expect(permissions, isNotEmpty);
    for (final p in permissions) {
      expect(p.permissions, {SitePermission.microphone});
      expect(p.origin, 'http://127.0.0.1:${server.port}');
    }
    // Without a microphone or with it in use the device fails, but the
    // permission itself must not be refused.
    expect(mic['error'], isNot('NotAllowedError'), reason: '$mic');

    // Screen sharing.
    final audioSupported = await tester.runAsync(
      CefEngine.systemAudioSupported,
    );
    await view.runScript('startShare()');
    final share = await step('share');
    expect(
      share['error'],
      isNull,
      reason: '$share; requests: ${shares.length}, shared: $sharedId',
    );
    expect(shares.single.origin, 'http://127.0.0.1:${server.port}');
    expect(shares.single.audioOffered, audioSupported);
    expect(share['video'], isTrue);
    expect(share['audio'], audioSupported);
    expect(
      share['surface'],
      sharedId!.startsWith('window') ? 'window' : 'monitor',
    );
    final frames = await step('frames');
    expect(frames['width'] as int, greaterThan(0), reason: '$frames');
    expect(frames['height'] as int, greaterThan(0), reason: '$frames');

    if (audioSupported == true) {
      await step('listening');
      final wav = File('${temp.path}\\tone.wav')
        ..writeAsBytesSync(_toneWav(440, const Duration(seconds: 5), 0.05));
      final player = await tester.runAsync(
        () => Process.start('powershell', [
          '-NoProfile',
          '-Command',
          "(New-Object Media.SoundPlayer '${wav.path}').PlaySync()",
        ]),
      );
      final audio = await step('audio');
      player!.kill();
      final at440 = (audio['at440'] as num).toDouble();
      final at1000 = (audio['at1000'] as num).toDouble();
      final floor = (audio['floor'] as num).toDouble();
      // ignore: avoid_print
      print(
        'system audio: 440 Hz $at440 dB, 1000 Hz $at1000 dB, floor $floor dB',
      );
      expect(at440, greaterThan(floor + 20), reason: 'other apps are shared');
      expect(
        at1000,
        lessThan(at440 - 20),
        reason: "6browser's own sound is left out",
      );
    }
    await step('stopped');

    await tester.pumpWidget(const SizedBox());
    await view.dispose();
    await tester.runAsync(() => server.close(force: true));
  });
}
