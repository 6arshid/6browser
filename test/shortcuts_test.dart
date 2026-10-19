import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/ui/browser_commands.dart';
import 'package:browser6/ui/find_bar.dart';
import 'package:browser6/ui/shortcuts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'browser_shell_test.dart' show pumpShell;
import 'support/fake_engine.dart';

const _wide = Size(1200, 800);

/// Presses [key] with the given modifiers held.
Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool ctrl = false,
  bool shift = false,
  bool alt = false,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  // Lets drift finish closing streams of providers the key disposed.
  await tester.pump(const Duration(milliseconds: 1));
}

FakeView activeView(ProviderContainer c) =>
    c.read(tabsProvider).active!.view as FakeView;

void main() {
  test('every command but those run from the menu has a shortcut', () {
    for (final c in BrowserCommand.values) {
      expect(browserShortcuts[c], isNotEmpty, reason: c.name);
    }
  });

  test('no two commands share a shortcut', () {
    final seen = <String, BrowserCommand>{};
    for (final MapEntry(key: cmd, value: keys) in browserShortcuts.entries) {
      for (final k in keys) {
        final id =
            '${k.trigger.keyId}-${k.control}-${k.shift}-${k.alt}-${k.meta}';
        expect(seen[id], isNull, reason: '${cmd.name} vs ${seen[id]?.name}');
        seen[id] = cmd;
      }
    }
  });

  testWidgets('tab shortcuts: Ctrl+1..9, PgUp/PgDn, move, reopen', (
    tester,
  ) async {
    final c = await pumpShell(tester, _wide);
    final ctl = c.read(tabsProvider.notifier);
    activeView(c).url.value = 'https://a.example/';
    ctl.newTab(url: 'https://b.example/');
    ctl.newTab(url: 'https://c.example/');
    await tester.pump();
    String activeUrl() => activeView(c).url.value;

    await press(tester, LogicalKeyboardKey.digit1, ctrl: true);
    expect(activeUrl(), 'https://a.example/');
    await press(tester, LogicalKeyboardKey.digit9, ctrl: true);
    expect(activeUrl(), 'https://c.example/');
    await press(tester, LogicalKeyboardKey.digit2, ctrl: true);
    expect(activeUrl(), 'https://b.example/');
    await press(tester, LogicalKeyboardKey.pageDown, ctrl: true);
    expect(activeUrl(), 'https://c.example/');
    await press(tester, LogicalKeyboardKey.pageUp, ctrl: true);
    expect(activeUrl(), 'https://b.example/');

    // Ctrl+Shift+PgUp moves b before a.
    await press(tester, LogicalKeyboardKey.pageUp, ctrl: true, shift: true);
    expect(c.read(tabsProvider).tabs.map((t) => t.view.url.value), [
      'https://b.example/',
      'https://a.example/',
      'https://c.example/',
    ]);

    // Ctrl+F4 closes, Ctrl+Shift+T brings it back.
    await press(tester, LogicalKeyboardKey.f4, ctrl: true);
    expect(c.read(tabsProvider).tabs.length, 2);
    await press(tester, LogicalKeyboardKey.keyT, ctrl: true, shift: true);
    expect(c.read(tabsProvider).tabs.length, 3);
    expect(activeUrl(), 'https://b.example/');
  });

  testWidgets('private tabs are not offered by Ctrl+Shift+T', (tester) async {
    final c = await pumpShell(tester, _wide);
    final ctl = c.read(tabsProvider.notifier);
    final id = ctl.newTab(url: 'https://secret.example/', incognito: true);
    ctl.close(id);
    ctl.reopenClosed();
    expect(
      c.read(tabsProvider).tabs.map((t) => t.view.url.value),
      isNot(contains('https://secret.example/')),
    );
  });

  testWidgets('reload, hard reload, Ctrl+N', (tester) async {
    final c = await pumpShell(tester, _wide);
    await press(tester, LogicalKeyboardKey.f5);
    await press(tester, LogicalKeyboardKey.keyR, ctrl: true);
    expect(activeView(c).reloads, 2);
    await press(tester, LogicalKeyboardKey.keyR, ctrl: true, shift: true);
    await press(tester, LogicalKeyboardKey.f5, shift: true);
    await press(tester, LogicalKeyboardKey.f5, ctrl: true);
    expect(activeView(c).hardReloads, 3);
    await press(tester, LogicalKeyboardKey.keyN, ctrl: true);
    expect(c.read(tabsProvider).tabs.length, 2);
  });

  testWidgets('zoom shortcuts and the zoom chip', (tester) async {
    final c = await pumpShell(tester, _wide);
    activeView(c).url.value = 'https://a.example/';
    await tester.pump();
    expect(find.byKey(const ValueKey('zoom-chip')), findsNothing);

    await press(tester, LogicalKeyboardKey.equal, ctrl: true);
    expect(activeView(c).zoom.value, greaterThan(1));
    expect(find.byKey(const ValueKey('zoom-chip')), findsOneWidget);
    expect(find.text('110%'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.digit0, ctrl: true);
    expect(activeView(c).zoom.value, 1);
    await press(tester, LogicalKeyboardKey.minus, ctrl: true);
    expect(activeView(c).zoom.value, lessThan(1));

    await tester.tap(find.byKey(const ValueKey('zoom-chip')));
    await tester.pump();
    expect(activeView(c).zoom.value, 1);
  });

  testWidgets('Ctrl+F finds; Enter, F3, Shift+F3 step; Esc closes', (
    tester,
  ) async {
    final c = await pumpShell(tester, _wide);
    final view = activeView(c);
    await press(tester, LogicalKeyboardKey.keyF, ctrl: true);
    expect(find.byType(FindBar), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('find-field')), 'cat');
    await tester.pump();
    expect(view.finds.last, '>cat');
    expect(find.text('1/3'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.enter);
    expect(view.finds.last, '>+cat');
    await press(tester, LogicalKeyboardKey.enter, shift: true);
    expect(view.finds.last, '<+cat');
    await press(tester, LogicalKeyboardKey.f3);
    expect(view.finds.last, '>+cat');
    await press(tester, LogicalKeyboardKey.f3, shift: true);
    expect(view.finds.last, '<+cat');

    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(FindBar), findsNothing);
    expect(view.findStopped, isTrue);
  });

  testWidgets('switching tabs closes the find bar', (tester) async {
    final c = await pumpShell(tester, _wide);
    await press(tester, LogicalKeyboardKey.keyF, ctrl: true);
    expect(find.byType(FindBar), findsOneWidget);
    c.read(tabsProvider.notifier).newTab();
    await tester.pump();
    await tester.pump();
    expect(find.byType(FindBar), findsNothing);
  });

  testWidgets('Ctrl+P prints, Ctrl+D bookmarks, Ctrl+U shows the source', (
    tester,
  ) async {
    final c = await pumpShell(tester, _wide);
    final view = activeView(c);
    view.url.value = 'https://a.example/';
    view.title.value = 'A';
    await tester.pump();

    await press(tester, LogicalKeyboardKey.keyP, ctrl: true);
    expect(view.prints, 1);

    expect(find.byTooltip('Bookmark this tab'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyD, ctrl: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byTooltip('Edit bookmark for this tab'), findsOneWidget);
    expect(find.text('Bookmark added'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.keyU, ctrl: true);
    expect(activeView(c).url.value, 'view-source:https://a.example/');

    await press(tester, LogicalKeyboardKey.digit1, ctrl: true);
    await press(tester, LogicalKeyboardKey.keyS, ctrl: true);
    expect(view.downloads, ['https://a.example/']);
  });

  testWidgets('Alt+D focuses the address bar, Esc leaves it', (tester) async {
    await pumpShell(tester, _wide);
    final field = find.byType(TextField).first;
    await press(tester, LogicalKeyboardKey.keyD, alt: true);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await press(tester, LogicalKeyboardKey.escape);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
  });

  testWidgets('Alt+F opens the main menu with the new entries', (tester) async {
    await pumpShell(tester, _wide);
    await press(tester, LogicalKeyboardKey.keyF, alt: true);
    await tester.pumpAndSettle();
    expect(find.text('Find…'), findsOneWidget);
    expect(find.text('Print…'), findsOneWidget);
    expect(find.text('Zoom'), findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
  });

  testWidgets('shortcuts page lists the shortcuts', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ShortcutsPage()));
    expect(find.text('Reopen the last closed tab'), findsOneWidget);
    expect(find.text('Ctrl+Shift+T'), findsOneWidget);
    expect(find.text('Ctrl+1…8'), findsOneWidget);
  });
}
