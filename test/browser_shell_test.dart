import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/ui/browser_shell.dart';
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

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(c.read(tabsProvider).tabs.length, 2);
    expect(find.byType(TabChip), findsNWidgets(2));
  });

  testWidgets('narrow layout hides the strip, shows count button and menu', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(400, 800));
    expect(find.byType(TabStrip), findsNothing);
    expect(find.byTooltip('Tabs'), findsOneWidget);
    expect(find.byTooltip('Forward'), findsNothing); // moved into the menu

    c.read(tabsProvider.notifier).newTab();
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Tabs'));
    await tester.pumpAndSettle();
    expect(find.text('2 tabs'), findsOneWidget);
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
