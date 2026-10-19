import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../engine/android_engine.dart';
import '../../engine/browser_engine.dart';
import '../../engine/cef_engine.dart';
import '../../data/providers.dart';
import '../downloads/download_utils.dart';
import '../profiles/profiles.dart';
import 'tabs_state.dart';
import 'url_input.dart';

/// The engine backend, chosen by platform: the WebView backend on Android,
/// CEF on desktop (with the profile's data folder). Overridden in tests
/// with a fake.
final engineProvider = Provider<BrowserEngine>(
  (ref) => defaultTargetPlatform == TargetPlatform.android
      ? AndroidEngine()
      : CefEngine(cachePath: ref.read(activeProfileProvider)?.cachePath),
);

/// Command-line options the app was started with.
class LaunchOptions {
  const LaunchOptions({this.incognito = false, this.url, this.profile});

  /// Start with a private first tab (`--incognito`).
  final bool incognito;

  /// Optional URL to open as the first tab (first non-flag argument).
  final String? url;

  /// Profile to open (`--profile=<id>`); null for the one used last.
  final String? profile;

  factory LaunchOptions.parse(List<String> args) => LaunchOptions(
    incognito: args.contains('--incognito'),
    url: args.where((a) => !a.startsWith('-')).firstOrNull,
    profile: args
        .where((a) => a.startsWith('--profile='))
        .map((a) => a.substring('--profile='.length))
        .firstOrNull,
  );
}

final launchOptionsProvider = Provider<LaunchOptions>(
  (ref) => const LaunchOptions(),
);

final tabsProvider = NotifierProvider<TabsController, TabsState>(
  TabsController.new,
);

/// Owns the list of tabs and every operation on it.
class TabsController extends Notifier<TabsState> {
  int _nextId = 1;

  /// URLs of recently closed normal tabs, newest last (Ctrl+Shift+T).
  /// Private tabs are never remembered.
  final _closed = <String>[];

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
    final launch = ref.read(launchOptionsProvider);
    newTab(url: launch.url, incognito: launch.incognito);
  }

  /// Mirrors engine download events into the database.
  void _recordDownloads() {
    final started = <int, DateTime>{};
    final sub = _engine.downloads.listen((e) {
      if (e.incognito) return; // private downloads are not listed
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

  /// Opens a tab (the New Tab page unless [url] is given) and, by default,
  /// selects it. Returns its id.
  int newTab({String? url, bool activate = true, bool incognito = false}) {
    final view = _engine.createView(
      initialUrl: url ?? newTabUrl,
      incognito: incognito,
    );
    _recordHistory(view);
    final tab = BrowserTab(id: _nextId++, view: view);
    state = TabsState(
      tabs: [...state.tabs, tab],
      activeId: activate ? tab.id : state.activeId ?? tab.id,
    );
    return tab.id;
  }

  /// Opens a private tab: no history, no persisted cookies/cache/storage and
  /// no download list entries.
  int newIncognitoTab() => newTab(incognito: true);

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

  /// Selects the tab at [index] (Ctrl+1..8); out of range does nothing.
  void selectIndex(int index) {
    if (index >= 0 && index < state.tabs.length) select(state.tabs[index].id);
  }

  /// Selects the rightmost tab (Ctrl+9).
  void selectLast() {
    if (state.tabs.isNotEmpty) select(state.tabs.last.id);
  }

  /// Moves the active tab one place left (-1) or right (1), staying within
  /// its pinned / unpinned group (Ctrl+Shift+PgUp / PgDn).
  void moveActive(int delta) {
    final i = state.activeIndex;
    final j = i + delta;
    if (state.tabs.isEmpty || j < 0 || j >= state.tabs.length) return;
    if (state.tabs[i].pinned != state.tabs[j].pinned) return;
    reorder(i, j);
  }

  /// Reopens the most recently closed tab (Ctrl+Shift+T).
  void reopenClosed() {
    if (_closed.isNotEmpty) newTab(url: _closed.removeLast());
  }

  /// Closes a tab. Closing the last tab opens a fresh home tab.
  void close(int id) {
    final i = state.tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final closing = state.tabs[i];
    final closingUrl = closing.view.url.value;
    if (!closing.view.incognito && isRecordableUrl(closingUrl)) {
      _closed.add(closingUrl);
      if (_closed.length > 25) _closed.removeAt(0);
    }
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
      initialUrl: url.isEmpty ? newTabUrl : url,
      incognito: state.tabs[i].view.incognito,
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
          if (view.incognito) return; // private tabs leave no history
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
