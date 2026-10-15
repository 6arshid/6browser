import '../../engine/browser_engine.dart';

/// One browser tab: an engine view plus UI-level flags.
class BrowserTab {
  const BrowserTab({required this.id, required this.view, this.pinned = false});

  final int id;
  final BrowserView view;
  final bool pinned;

  BrowserTab copyWith({bool? pinned}) =>
      BrowserTab(id: id, view: view, pinned: pinned ?? this.pinned);
}

/// Immutable tab-strip state. Pinned tabs are always kept before unpinned.
class TabsState {
  const TabsState({this.tabs = const [], this.activeId});

  final List<BrowserTab> tabs;
  final int? activeId;

  int get activeIndex {
    final i = tabs.indexWhere((t) => t.id == activeId);
    return i < 0 ? 0 : i;
  }

  BrowserTab? get active => tabs.isEmpty ? null : tabs[activeIndex];

  int get pinnedCount => tabs.where((t) => t.pinned).length;
}
