import 'package:browser6/engine/browser_engine.dart';
import 'package:browser6/features/page_dialogs/page_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_engine.dart';

typedef _Answer = ({bool ok, String text});

PageDialogRequest _dialog(
  List<_Answer> answers,
  PageDialogType type, {
  String message = 'Hello',
  String defaultText = '',
  String origin = 'https://example.com',
  bool isReload = false,
}) => PageDialogRequest(
  type: type,
  origin: origin,
  message: message,
  defaultText: defaultText,
  isReload: isReload,
  onAnswer: (ok, text) => answers.add((ok: ok, text: text)),
);

void main() {
  Future<FakeView> pumpHost(WidgetTester tester) async {
    final view = FakeView('https://example.com/');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageDialogHost(view: view, child: const SizedBox.expand()),
        ),
      ),
    );
    return view;
  }

  Future<void> show(
    WidgetTester tester,
    FakeView view,
    PageDialogRequest r,
  ) async {
    view.pageDialogController.add(r);
    await tester.pump();
  }

  testWidgets('alert says which site speaks; OK answers', (tester) async {
    final view = await pumpHost(tester);
    final answers = <_Answer>[];
    await show(tester, view, _dialog(answers, PageDialogType.alert));
    expect(find.text('example.com says'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(answers, [(ok: true, text: '')]);
    expect(find.text('example.com says'), findsNothing);
    // The page gets the keyboard back.
    expect(view.focusRequests, 1);
  });

  testWidgets('confirm: Cancel and Escape answer false', (tester) async {
    final view = await pumpHost(tester);
    final answers = <_Answer>[];
    await show(tester, view, _dialog(answers, PageDialogType.confirm));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await show(tester, view, _dialog(answers, PageDialogType.confirm));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(answers, [(ok: false, text: ''), (ok: false, text: '')]);
  });

  testWidgets('prompt returns the typed text', (tester) async {
    final view = await pumpHost(tester);
    final answers = <_Answer>[];
    await show(
      tester,
      view,
      _dialog(answers, PageDialogType.prompt, defaultText: 'Ali'),
    );
    expect(find.text('Ali'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('page-dialog-text')),
      'Sara',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(answers, [(ok: true, text: 'Sara')]);
  });

  testWidgets('"Leave site?" and "Reload site?"', (tester) async {
    final view = await pumpHost(tester);
    final answers = <_Answer>[];
    await show(tester, view, _dialog(answers, PageDialogType.leave));
    expect(find.text('Leave site?'), findsOneWidget);
    expect(
      find.text('Changes that you made may not be saved.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Leave'));
    await tester.pump();
    await show(
      tester,
      view,
      _dialog(answers, PageDialogType.leave, isReload: true),
    );
    expect(find.text('Reload site?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(answers, [(ok: true, text: ''), (ok: false, text: '')]);
  });

  testWidgets('dialogs come one at a time; a withdrawn one goes away', (
    tester,
  ) async {
    final view = await pumpHost(tester);
    final answers = <_Answer>[];
    final first = _dialog(answers, PageDialogType.alert, message: 'One');
    await show(tester, view, first);
    await show(
      tester,
      view,
      _dialog(answers, PageDialogType.alert, message: 'Two', origin: ''),
    );
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsNothing);
    first.withdraw();
    await tester.pump();
    await tester.pump();
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('This page says'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(answers, [(ok: true, text: '')]);
  });
}
