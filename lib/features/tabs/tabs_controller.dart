import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../engine/browser_engine.dart';
import '../../engine/cef_engine.dart';
import '../../data/providers.dart';
import '../downloads/download_utils.dart';
import '../settings/app_settings.dart';
import 'tabs_state.dart';

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
    _recordDownloads();
    newTab();
  }

  /// Mirrors engine download events into the database.
  void _recordDownloads() {
    final started = <int, DateTime>{};
    final sub = _engine.downloads.listen((e) {
      final path = e.path;
      ref
          .read(databaseProvider)
          .upsertDownload(
            DownloadsCompanion(
              id: Value(e.id),
              url: Value(e.url),
              fileName: Value(fileNameOf(path, fallback: e.url)),
              path: Value(path),
              receivedBytes: Value(e.receivedBytes),
              totalBytes: Value(e.totalBytes),
              state: Value(e.state.name),
              startedAt: Value(started.putIfAbsent(e.id, DateTime.now)),
            ),
          );
    });
    ref.onDispose(sub.cancel);
  }

  /// Opens a tab and (by default) selects it. Returns its id.
  int newTab({String? url, bool activate = true}) {
    final view = _engine.createView(
      initialUrl: url ?? ref.read(appSettingsProvider).homeUrl,
    );
    _recordHistory(view);
    final tab = BrowserTab(id: _nextId++, view: view);
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
    final view = _engine.createView(
      initialUrl: url.isEmpty ? ref.read(appSettingsProvider).homeUrl : url,
    );
    _recordHistory(view);
    final copy = BrowserTab(id: _nextId++, view: view);
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

  /// Saves a history entry when a page finishes loading. The title usually
  /// arrives just after load-end, so wait briefly and read the current one.
  void _recordHistory(BrowserView view) {
    var wasLoading = false;
    String? lastRecorded;
    view.isLoading.addListener(() {
      final loading = view.isLoading.value;
      if (wasLoading && !loading) {
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          final url = view.url.value;
          // Sub-frames and redirects fire extra load-end events for the same
          // page, so skip a URL that was just recorded for this tab.
          if (!isRecordableUrl(url) || url == lastRecorded) return;
          lastRecorded = url;
          ref.read(databaseProvider).addHistory(url, view.title.value);
        });
      }
      wasLoading = loading;
    });
  }

  /// Stable partition: pinned tabs first, relative order otherwise kept.
  List<BrowserTab> _pinnedFirst(List<BrowserTab> tabs) => [
    ...tabs.where((t) => t.pinned),
    ...tabs.where((t) => !t.pinned),
  ];
}

/// Only real web pages go to history (not blank/internal pages).
bool isRecordableUrl(String url) =>
    url.startsWith('http://') || url.startsWith('https://');
