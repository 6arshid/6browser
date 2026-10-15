import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_engine.dart';

void main() {
  late ProviderContainer c;
  TabsController ctl() => c.read(tabsProvider.notifier);

  setUp(() async {
    c = ProviderContainer(
      overrides: [engineProvider.overrideWithValue(FakeEngine())],
    );
    addTearDown(c.dispose);
    await ctl().start();
  });

  test('start opens one active tab', () {
    final s = c.read(tabsProvider);
    expect(s.tabs.length, 1);
    expect(s.active!.id, s.tabs.first.id);
  });

  test('newTab activates, select switches', () {
    final first = c.read(tabsProvider).tabs.first.id;
    final second = ctl().newTab();
    expect(c.read(tabsProvider).activeId, second);
    ctl().select(first);
    expect(c.read(tabsProvider).activeId, first);
  });

  test('closing the active tab selects a neighbour and disposes the view', () {
    final first = c.read(tabsProvider).tabs.first;
    final second = ctl().newTab();
    ctl().close(second);
    expect(c.read(tabsProvider).activeId, first.id);
    ctl().newTab();
    ctl().close(first.id);
    expect((first.view as FakeView).disposed, isTrue);
  });

  test('closing the last tab opens a fresh one', () {
    final only = c.read(tabsProvider).tabs.first.id;
    ctl().close(only);
    final s = c.read(tabsProvider);
    expect(s.tabs.length, 1);
    expect(s.tabs.first.id, isNot(only));
  });

  test('duplicate copies the url next to the original', () {
    final first = c.read(tabsProvider).tabs.first;
    first.view.load('https://example.com');
    ctl().duplicate(first.id);
    final s = c.read(tabsProvider);
    expect(s.tabs.length, 2);
    expect(s.tabs[1].view.url.value, 'https://example.com');
    expect(s.activeId, s.tabs[1].id);
  });

  test('pinned tabs stay first, also after reorder', () {
    final a = c.read(tabsProvider).tabs.first.id;
    final b = ctl().newTab();
    final d = ctl().newTab();
    ctl().togglePin(d);
    expect(c.read(tabsProvider).tabs.map((t) => t.id), [d, a, b]);
    ctl().reorder(0, 2); // try to push the pinned tab to the end
    expect(c.read(tabsProvider).tabs.first.id, d);
    ctl().reorder(1, 2); // a after b
    expect(c.read(tabsProvider).tabs.map((t) => t.id), [d, b, a]);
  });

  test('cycle wraps around', () {
    final a = c.read(tabsProvider).tabs.first.id;
    ctl().newTab();
    ctl().cycle();
    expect(c.read(tabsProvider).activeId, a);
  });
}
