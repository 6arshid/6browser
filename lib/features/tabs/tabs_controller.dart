import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/browser_engine.dart';
import '../../engine/cef_engine.dart';
import 'tabs_state.dart';

const homeUrl = 'https://www.google.com';

/// The engine backend. Overridden in tests with a fake.
final engineProvider = Provider<BrowserEngine>((ref) => CefEngine());

final tabsProvider = NotifierProvider<TabsController, TabsState>(
  TabsController.new,
);

/// Owns the list of tabs and every operation on it.
class TabsController extends Notifier<TabsState> {
  int _nextId = 1;

  BrowserEngine get _engine => ref.read(engineProvider);

  @override
  TabsState build() {
    // Riverpod forbids reading state/ref inside onDispose, so keep a snapshot.
    final engine = _engine;
    var live = const <BrowserTab>[];
    listenSelf((_, next) => live = next.tabs);
    ref.onDispose(() {
      for (final t in live) {
        t.view.dispose();
      }
      engine.shutdown();
    });
    return const TabsState();
  }

  /// Starts the engine and opens the first tab.
  Future<void> start() async {
    await _engine.initialize();
    newTab();
  }

  /// Opens a tab and (by default) selects it. Returns its id.
  int newTab({String url = homeUrl, bool activate = true}) {
    final tab = BrowserTab(
      id: _nextId++,
      view: _engine.createView(initialUrl: url),
    );
    state = TabsState(
      tabs: [...state.tabs, tab],
      activeId: activate ? tab.id : state.activeId ?? tab.id,
    );
    return tab.id;
  }

  void select(int id) {
    if (state.tabs.any((t) => t.id == id)) {
      state = TabsState(tabs: state.tabs, activeId: id);
    }
  }

  /// Selects the next/previous tab, wrapping around.
  void cycle({int delta = 1}) {
    if (state.tabs.isEmpty) return;
    final n = state.tabs.length;
    select(state.tabs[(state.activeIndex + delta) % n].id);
  }

  /// Closes a tab. Closing the last tab opens a fresh home tab.
  void close(int id) {
    final i = state.tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final closing = state.tabs[i];
    final remaining = [...state.tabs]..removeAt(i);
    var active = state.activeId;
    if (active == id && remaining.isNotEmpty) {
      active = remaining[i.clamp(0, remaining.length - 1)].id;
    }
    state = TabsState(tabs: remaining, activeId: active);
    closing.view.dispose();
    if (remaining.isEmpty) newTab();
  }

  /// Opens a copy of a tab (same URL) right after it.
  void duplicate(int id) {
    final i = state.tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final url = state.tabs[i].view.url.value;
    final copy = BrowserTab(
      id: _nextId++,
      view: _engine.createView(initialUrl: url.isEmpty ? homeUrl : url),
    );
    final tabs = [...state.tabs]..insert(i + 1, copy);
    state = TabsState(tabs: _pinnedFirst(tabs), activeId: copy.id);
  }

  void togglePin(int id) {
    final tabs = [
      for (final t in state.tabs)
        t.id == id ? t.copyWith(pinned: !t.pinned) : t,
    ];
    state = TabsState(tabs: _pinnedFirst(tabs), activeId: state.activeId);
  }

  /// [newIndex] is the final index (ReorderableListView.onReorderItem).
  void reorder(int oldIndex, int newIndex) {
    final tabs = [...state.tabs];
    tabs.insert(newIndex, tabs.removeAt(oldIndex));
    state = TabsState(tabs: _pinnedFirst(tabs), activeId: state.activeId);
  }

  /// Stable partition: pinned tabs first, relative order otherwise kept.
  List<BrowserTab> _pinnedFirst(List<BrowserTab> tabs) => [
    ...tabs.where((t) => t.pinned),
    ...tabs.where((t) => !t.pinned),
  ];
}
