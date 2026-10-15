import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../tabs/url_input.dart';

/// Most tiles the New Tab page shows (shortcuts first, then most visited).
const maxTiles = 16;

/// One tile on the New Tab page.
class NewTabTile {
  const NewTabTile({
    required this.url,
    required this.title,
    required this.custom,
  });

  final String url;
  final String title;

  /// Added or arranged by the user; otherwise filled in from history.
  final bool custom;

  (String, String) get entry => (url, title);
}

/// Shortcuts in order, then the most visited pages that are not already
/// shown and were not removed by the user, up to [max] tiles.
List<NewTabTile> buildTiles(
  List<Shortcut> shortcuts,
  List<TopSite> topSites,
  Set<String> hidden, {
  int max = maxTiles,
}) {
  final tiles = [
    for (final s in shortcuts.take(max))
      NewTabTile(url: s.url, title: s.title, custom: true),
  ];
  final shown = {for (final t in tiles) t.url};
  for (final s in topSites) {
    if (tiles.length >= max) break;
    if (hidden.contains(s.url) || isNewTabUrl(s.url) || !shown.add(s.url)) {
      continue;
    }
    tiles.add(NewTabTile(url: s.url, title: s.title, custom: false));
  }
  return tiles;
}

final _shortcuts = StreamProvider<List<Shortcut>>(
  (ref) => ref.watch(databaseProvider).watchShortcuts(),
);
final _topSites = StreamProvider<List<TopSite>>(
  (ref) => ref.watch(databaseProvider).watchTopSites(),
);
final _hidden = StreamProvider<Set<String>>(
  (ref) => ref.watch(databaseProvider).watchHiddenSites(),
);

/// Tiles for the New Tab page; null until the database has answered.
final newTabTilesProvider = Provider<List<NewTabTile>?>((ref) {
  final shortcuts = ref.watch(_shortcuts).value;
  final top = ref.watch(_topSites).value;
  final hidden = ref.watch(_hidden).value;
  if (shortcuts == null || top == null || hidden == null) return null;
  return buildTiles(shortcuts, top, hidden);
});

/// Edits to the tile list. Rearranging or editing a most-visited tile turns
/// it (and every tile before it) into a shortcut so the order sticks.
class NewTabActions {
  NewTabActions(this.db, this.tiles);

  final AppDatabase db;
  final List<NewTabTile> tiles;

  int get _customCount => tiles.where((t) => t.custom).length;

  Future<void> _keep(List<NewTabTile> list, int upTo) => db.setShortcuts([
    for (final t in list.take(math.max(upTo + 1, _customCount))) t.entry,
  ]);

  Future<void> add(String url, String title) => db.addShortcut(url, title);

  Future<void> move(int from, int to) {
    if (from == to) return Future.value();
    final list = [...tiles];
    list.insert(to, list.removeAt(from));
    return _keep(list, math.max(from, to));
  }

  Future<void> edit(int index, String url, String title) async {
    final old = tiles[index].url;
    final list = [...tiles];
    list[index] = NewTabTile(url: url, title: title, custom: true);
    await _keep(list, index);
    if (old != url) {
      // The old address would otherwise come back as a most-visited tile.
      await db.hideSite(old);
      await db.unhideSite(url);
    }
  }

  /// Removes a tile; the returned callback undoes it.
  Future<Future<void> Function()> remove(int index) async {
    final url = tiles[index].url;
    final before = [
      for (final t in tiles)
        if (t.custom) t.entry,
    ];
    await db.hideSite(url);
    return () async {
      await db.unhideSite(url);
      await db.setShortcuts(before);
    };
  }
}

/// Normalises what the user typed as a shortcut URL; null if unusable.
String? normalizeShortcutUrl(String input) {
  var text = input.trim();
  if (text.isEmpty || text.contains(' ')) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  if (uri.host.isEmpty ||
      !(uri.host.contains('.') || uri.host == 'localhost')) {
    return null;
  }
  return uri.toString();
}
