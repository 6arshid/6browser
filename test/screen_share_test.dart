
import 'package:browser6/engine/browser_engine.dart';
import 'package:browser6/features/screen_share/capture_sources.dart';
import 'package:browser6/features/screen_share/screen_share_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_engine.dart';

const _screen = CaptureSource(
  id: 'screen:0:0',
  kind: CaptureKind.screen,
  title: 'Entire screen',
);
const _editor = CaptureSource(
  id: 'window:1234:0',
  kind: CaptureKind.window,
  title: 'Slides - Editor',
);
final _player = CaptureSource(
  id: 'window:5678:0',
  kind: CaptureKind.window,
  title: 'Video player',
  // A 1x1 BMP.
  thumbnail: Uint8List.fromList([
    0x42, 0x4D, 58, 0, 0, 0, 0, 0, 0, 0, 54, 0, 0, 0, 40, 0, 0, 0, //
    1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 24, 0, 0, 0, 0, 0, 4, 0, 0, 0, //
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 0,
  ]),
);

typedef _Answer = ({String? source, bool audio});

ScreenShareRequest _request(List<_Answer> answers, {bool audio = true}) =>
    ScreenShareRequest(
      origin: 'https://meet.google.com',
      audioOffered: audio,
      onAnswer: (source, audio) => answers.add((source: source, audio: audio)),
    );

void main() {
  Future<FakeView> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final view = FakeView('https://meet.google.com/abc');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenShareHost(
            view: view,
            sources: () async => [_screen, _editor, _player],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    return view;
  }

  Future<void> open(
    WidgetTester tester,
    FakeView view,
    ScreenShareRequest r,
  ) async {
    view.screenShareController.add(r);
    await tester.pump();
    await tester.pump();
  }

  /// The picker refreshes its sources on a timer; close it before the end.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('shares the screen with system audio by default', (tester) async {
    final view = await pumpHost(tester);
    final answers = <_Answer>[];
    await open(tester, view, _request(answers));

    expect(find.text('Choose what to share'), findsOneWidget);
    expect(find.textContaining('meet.google.com will be able'), findsOneWidget);
    expect(find.text('Entire screen'), findsWidgets);
    expect(find.text('Also share system audio'), findsOneWidget);
    // The only screen is chosen already.
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(answers, [(source: 'screen:0:0', audio: true)]);
    expect(find.text('Choose what to share'), findsNothing);
    await finish(tester);
  });

  testWidgets('shares a window, without audio when unticked', (tester) async {
    final view = await pumpHost(tester);
    final answers = <_Answer>[];
    await open(tester, view, _request(answers));

    await tester.tap(find.text('Window'));
    await tester.pump();
    expect(find.text('Slides - Editor'), findsOneWidget);
    expect(find.text('Video player'), findsOneWidget);
    // No window is chosen for the user.
    final share = find.widgetWithText(FilledButton, 'Share');
    expect(tester.widget<FilledButton>(share).onPressed, isNull);

    await tester.tap(find.text('Video player'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Also share system audio'));
    await tester.pump();
    await tester.tap(share);
    await tester.pump();
    expect(answers, [(source: 'window:5678:0', audio: false)]);
    await finish(tester);
  });

  testWidgets('no audio choice when the page did not ask for sound', (
    tester,
  ) async {
    final view = await pumpHost(tester);
    final answers = <_Answer>[];
    await open(tester, view, _request(answers, audio: false));
    expect(find.text('Also share system audio'), findsNothing);
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(answers, [(source: 'screen:0:0', audio: false)]);
    await finish(tester);
  });

  testWidgets('Cancel and Escape share nothing', (tester) async {
    final view = await pumpHost(tester);
    final answers = <_Answer>[];
    await open(tester, view, _request(answers));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(answers, [(source: null, audio: false)]);

    await open(tester, view, _request(answers));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(answers.last, (source: null, audio: false));
    expect(find.text('Choose what to share'), findsNothing);
    await finish(tester);
  });

  testWidgets('the picker closes when the page gives up', (tester) async {
    final view = await pumpHost(tester);
    final request = _request(<_Answer>[]);
    await open(tester, view, request);
    request.withdraw();
    await tester.pump();
    expect(find.text('Choose what to share'), findsNothing);
    await finish(tester);
  });

  testWidgets('double-clicking a window shares it', (tester) async {
    final view = await pumpHost(tester);
    final answers = <_Answer>[];
    await open(tester, view, _request(answers, audio: false));
    await tester.tap(find.text('Window'));
    await tester.pump();
    await tester.tap(find.text('Slides - Editor'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Slides - Editor'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(answers, [(source: 'window:1234:0', audio: false)]);
    await finish(tester);
  });
}
