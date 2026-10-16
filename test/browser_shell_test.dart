import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/ui/browser_shell.dart';
import 'package:browser6/ui/mobile_chrome.dart';
import 'package:browser6/ui/tab_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_engine.dart';

Future<ProviderContainer> pumpShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      engineProvider.overrideWithValue(FakeEngine()),
      databaseProvider.overrideWithValue(AppDatabase.inMemory()),
    ],
  );
  addTearDown(() async {
    // Unmount so drift's stream subscriptions cancel, then flush their timers.
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

void main() {
  testWidgets('wide layout shows the tab strip and + opens a tab', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(1200, 800));
    expect(find.byType(TabStrip), findsOneWidget);
    expect(c.read(tabsProvider).tabs.length, 1);

    await tester.tap(find.byTooltip('New tab (Ctrl+T)'));
    await tester.pump();
    expect(c.read(tabsProvider).tabs.length, 2);
    expect(find.byType(TabChip), findsNWidgets(2));
  });

  testWidgets('narrow layout hides the strip and shows the bottom bar', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(400, 800));
    expect(find.byType(TabStrip), findsNothing);
    expect(find.byType(MobileBottomBar), findsOneWidget);
    for (final t in ['Back', 'Forward', 'Home', 'Tabs', 'Menu']) {
      expect(
        find.descendant(
          of: find.byType(MobileBottomBar),
          matching: find.byTooltip(t),
        ),
        findsOneWidget,
      );
    }

    c.read(tabsProvider.notifier).newTab();
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Tabs'));
    await tester.pumpAndSettle();
    expect(find.byType(TabSwitcherPage), findsOneWidget);
    expect(find.byType(TabCard), findsNWidgets(2));
  });

  testWidgets('tab switcher selects, closes and opens private tabs', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(400, 800));
    final first = c.read(tabsProvider).active!.id;
    c.read(tabsProvider.notifier).newTab();
    await tester.pump();

    await tester.tap(find.byTooltip('Tabs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TabCard).first);
    await tester.pumpAndSettle();
    expect(find.byType(TabSwitcherPage), findsNothing);
    expect(c.read(tabsProvider).activeId, first);

    await tester.tap(find.byTooltip('Tabs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close tab').first);
    await tester.pumpAndSettle();
    expect(c.read(tabsProvider).tabs.length, 1);

    await tester.tap(find.byTooltip('Private tabs'));
    await tester.pumpAndSettle();
    expect(find.text('No private tabs'), findsOneWidget);
    await tester.tap(find.text('Private tab'));
    await tester.pumpAndSettle();
    expect(c.read(tabsProvider).active!.view.incognito, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone menu opens as a sheet and starts a new tab', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(360, 700));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.add_box_outlined));
    await tester.pumpAndSettle();
    expect(c.read(tabsProvider).tabs.length, 2);
  });

  testWidgets('phone address bar shows the host, full URL while editing', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(400, 800));
    c.read(tabsProvider).active!.view.load('https://www.example.com/a/b?q=1');
    await tester.pump();
    String field() =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;
    expect(field(), 'example.com');

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(field(), 'https://www.example.com/a/b?q=1');
    expect(find.byTooltip('Back'), findsNothing); // bar takes the whole row
    expect(find.byTooltip('Cancel'), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(field(), 'example.com');
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('address bar survives a large system font', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = await pumpShell(tester, const Size(360, 700));
    c.read(tabsProvider).active!.view.load('https://example.com/');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('no overflow when the window is very narrow', (tester) async {
    await pumpShell(tester, const Size(320, 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabs shrink without overflowing when many are open', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(900, 700));
    for (var i = 0; i < 25; i++) {
      c.read(tabsProvider.notifier).newTab();
    }
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Web Store pages show the extensions-unsupported notice', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(1200, 800));
    expect(find.byIcon(Icons.extension_off), findsNothing);
    c
        .read(tabsProvider)
        .active!
        .view
        .load(
          'https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh',
        );
    await tester.pump();
    expect(find.byIcon(Icons.extension_off), findsOneWidget);
    expect(find.text('Install theme'), findsOneWidget);
    // The old URL's bookmark stream was cancelled; flush drift's timer.
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Ctrl+Shift+N opens an incognito tab', (tester) async {
    final c = await pumpShell(tester, const Size(1200, 800));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.read(tabsProvider).tabs.length, 2);
    expect(c.read(tabsProvider).active!.view.incognito, isTrue);
    expect(
      find.descendant(
        of: find.byType(TabStrip),
        matching: find.byIcon(Icons.visibility_off),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Ctrl+T and Ctrl+W shortcuts', (tester) async {
    final c = await pumpShell(tester, const Size(1200, 800));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.read(tabsProvider).tabs.length, 2);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.read(tabsProvider).tabs.length, 1);
  });
}
