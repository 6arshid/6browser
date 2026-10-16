import 'package:browser6/engine/browser_engine.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/ui/page_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'browser_shell_test.dart' show pumpShell;
import 'support/fake_engine.dart';

List<PageMenuAction> actions(PageContextMenu m) =>
    pageMenuEntries(m).whereType<PageMenuEntry>().map((e) => e.action).toList();

void main() {
  test('plain page menu has back, forward, reload and inspect', () {
    final a = actions(const PageContextMenu(position: Offset.zero));
    expect(a, [
      PageMenuAction.back,
      PageMenuAction.forward,
      PageMenuAction.reload,
      PageMenuAction.inspect,
    ]);
  });

  test('link menu offers link actions and still has reload', () {
    final a = actions(
      const PageContextMenu(
        position: Offset.zero,
        linkUrl: 'https://example.com/a',
        pageUrl: 'https://example.com/',
      ),
    );
    expect(a, contains(PageMenuAction.openLinkInNewTab));
    expect(a, contains(PageMenuAction.copyLink));
    expect(a, contains(PageMenuAction.reload));
    expect(a, isNot(contains(PageMenuAction.back)));
  });

  test('text field menu disables what the page says it cannot do', () {
    final entries = pageMenuEntries(
      const PageContextMenu(
        position: Offset.zero,
        isEditable: true,
        canPaste: true,
      ),
    ).whereType<PageMenuEntry>();
    bool enabled(PageMenuAction a) =>
        entries.firstWhere((e) => e.action == a).enabled;
    expect(enabled(PageMenuAction.paste), isTrue);
    expect(enabled(PageMenuAction.cut), isFalse);
    expect(entries.map((e) => e.action), contains(PageMenuAction.reload));
  });

  testWidgets('right click on a page shows the menu and Reload reloads', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(1200, 800));
    final view = c.read(tabsProvider).active!.view as FakeView;
    view.url.value = 'https://example.com/';
    await tester.pump();

    view.contextMenuController.add(
      const PageContextMenu(position: Offset(300, 300), canGoBack: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reload'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(view.reloads, 1);
    expect(find.text('Reload'), findsNothing);
  });

  testWidgets('Open link in new tab opens a background tab', (tester) async {
    final c = await pumpShell(tester, const Size(1200, 800));
    final view = c.read(tabsProvider).active!.view as FakeView;
    view.url.value = 'https://example.com/';
    await tester.pump();

    view.contextMenuController.add(
      const PageContextMenu(
        position: Offset(300, 300),
        linkUrl: 'https://example.com/next',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open link in new tab'));
    await tester.pumpAndSettle();

    final tabs = c.read(tabsProvider);
    expect(tabs.tabs.length, 2);
    expect(tabs.tabs.last.view.url.value, 'https://example.com/next');
    expect(tabs.activeId, tabs.tabs.first.id);
  });
}
