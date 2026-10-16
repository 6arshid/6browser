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
  final shown = {for (final t in tiles) tileKey(t.url)};
  final hiddenKeys = {for (final h in hidden) tileKey(h)};
  for (final s in topSites) {
    if (tiles.length >= max) break;
    final key = tileKey(s.url);
    if (hiddenKeys.contains(key) || isNewTabUrl(s.url) || !shown.add(key)) {
      continue;
    }
    tiles.add(NewTabTile(url: s.url, title: s.title, custom: false));
  }
  return tiles;
}

/// Query parameters that name a search, by which search pages are told apart.
const _searchParams = ['q', 'query', 'text', 'wd', 'search_query'];

/// Parameters that only track the visit and never change the page.
bool _isTracking(String name) =>
    name.startsWith('utm_') ||
    const {
      'ei',
      'ved',
      'sxsrf',
      'oq',
      'gs_lp',
      'gs_lcrp',
      'sclient',
      'sca_esv',
      'sca_upv',
      'source',
      'sourceid',
      'ie',
      'oe',
      'client',
      'uact',
      'iflsig',
      'bih',
      'biw',
      'dpr',
      'rlz',
      'aqs',
      'hl',
      'gl',
      'sa',
      'fbclid',
      'gclid',
      'mc_cid',
      'mc_eid',
      'ref',
      'ref_src',
      'spm',
      'si',
      'form',
      'pc',
      'cvid',
    }.contains(name);

/// Same key for URLs that show the same page, so most visited lists each
/// page once: scheme, `www.`, the fragment, tracking parameters and a
/// trailing slash are ignored, and a search is known by its terms alone
/// (google.com and google.dk searching the same words are one tile).
String tileKey(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasAuthority) return url.trim();
  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  var path = uri.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  final params = uri.queryParameters;
  for (final name in _searchParams) {
    final terms = params[name]?.trim().toLowerCase();
    if (terms != null && terms.isNotEmpty) {
      // Country domains (google.dk, google.co.uk) count as one engine.
      final engine = host
          .split('.')
          .firstWhere((part) => part.length > 3, orElse: () => host);
      return 'search:$engine$path?${terms.split(RegExp(r'\s+')).join(' ')}';
    }
  }
  final kept = [
    for (final e in params.entries)
      if (!_isTracking(e.key)) '${e.key}=${e.value}',
  ]..sort();
  return '$host$path${kept.isEmpty ? '' : '?${kept.join('&')}'}';
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
