import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get url => text().unique()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime()();
}

class HistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get url => text()();
  TextColumn get title => text()();
  DateTimeColumn get visitedAt => dateTime()();
}

/// Simple string key/value settings.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class Downloads extends Table {
  /// Engine-assigned download id (stable for the life of the download).
  IntColumn get id => integer()();
  TextColumn get url => text()();
  TextColumn get fileName => text()();
  TextColumn get path => text()();
  IntColumn get receivedBytes => integer().withDefault(const Constant(0))();

  /// -1 when the server did not report a size.
  IntColumn get totalBytes => integer().withDefault(const Constant(-1))();

  /// One of: inProgress, complete, canceled.
  TextColumn get state => text().withDefault(const Constant('inProgress'))();
  DateTimeColumn get startedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// User-pinned tiles on the New Tab page, in [position] order.
class Shortcuts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get url => text().unique()();
  TextColumn get title => text()();
  IntColumn get position => integer()();
}

/// Sites the user removed from the New Tab page; they are no longer offered
/// as "most visited" tiles.
class HiddenSites extends Table {
  TextColumn get url => text()();

  @override
  Set<Column> get primaryKey => {url};
}

/// A frequently visited page (aggregated from history).
class TopSite {
  const TopSite({required this.url, required this.title, required this.visits});
  final String url;
  final String title;
  final int visits;
}

@DriftDatabase(
  tables: [
    Bookmarks,
    HistoryEntries,
    Settings,
    Downloads,
    Shortcuts,
    HiddenSites,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the persistent database inside the user's profile directory.
  factory AppDatabase.persistent() => AppDatabase(
    LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, '6browser.sqlite'));
      return NativeDatabase.createInBackground(file);
    }),
  );

  /// In-memory database for tests.
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(shortcuts);
        await m.createTable(hiddenSites);
      }
    },
  );

  // ---- bookmarks ----

  Stream<List<Bookmark>> watchBookmarks() =>
      (select(bookmarks)..orderBy([
            (b) => OrderingTerm.desc(b.createdAt),
            (b) => OrderingTerm.desc(b.id),
          ]))
          .watch();

  Stream<bool> watchIsBookmarked(String url) => (select(
    bookmarks,
  )..where((b) => b.url.equals(url))).watch().map((r) => r.isNotEmpty);

  Future<void> addBookmark(String url, String title) => into(bookmarks).insert(
    BookmarksCompanion.insert(
      url: url,
      title: title.isEmpty ? url : title,
      createdAt: DateTime.now(),
    ),
    mode: InsertMode.insertOrIgnore,
  );

  Future<void> removeBookmarkByUrl(String url) =>
      (delete(bookmarks)..where((b) => b.url.equals(url))).go();

  Future<void> removeBookmark(int id) =>
      (delete(bookmarks)..where((b) => b.id.equals(id))).go();

  // ---- history ----

  Future<void> addHistory(String url, String title) {
    return into(historyEntries).insert(
      HistoryEntriesCompanion.insert(
        url: url,
        title: title.isEmpty ? url : title,
        visitedAt: DateTime.now(),
      ),
    );
  }

  /// Newest first; [query] filters by title or URL (case-insensitive).
  Stream<List<HistoryEntry>> watchHistory({String query = ''}) {
    final q = select(historyEntries)
      ..orderBy([
        (h) => OrderingTerm.desc(h.visitedAt),
        (h) => OrderingTerm.desc(h.id),
      ])
      ..limit(500);
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((h) => h.title.lower().like(like) | h.url.lower().like(like));
    }
    return q.watch();
  }

  Future<void> deleteHistoryEntry(int id) =>
      (delete(historyEntries)..where((h) => h.id.equals(id))).go();

  Future<void> clearHistory() => delete(historyEntries).go();

  /// Most visited / most recent matches for address-bar autocomplete.
  Future<List<String>> suggest(String prefix, {int limit = 6}) async {
    final text = prefix.trim().toLowerCase();
    if (text.isEmpty) return const [];
    final like = '%$text%';
    final rows =
        await (select(historyEntries)
              ..where(
                (h) => h.url.lower().like(like) | h.title.lower().like(like),
              )
              ..orderBy([
                (h) => OrderingTerm.desc(h.visitedAt),
                (h) => OrderingTerm.desc(h.id),
              ])
              ..limit(limit * 4))
            .get();
    final seen = <String>{};
    return [
      for (final r in rows)
        if (seen.add(r.url)) r.url,
    ].take(limit).toList();
  }

  /// Pages ordered by visit count (then by last visit), newest title kept.
  Stream<List<TopSite>> watchTopSites({int limit = 50}) =>
      customSelect(
        // SQLite returns the bare `title` column from the row holding MAX().
        'SELECT url, title, COUNT(*) AS visits, MAX(visited_at) AS last '
        'FROM history_entries GROUP BY url '
        'ORDER BY visits DESC, last DESC LIMIT ?',
        variables: [Variable.withInt(limit)],
        readsFrom: {historyEntries},
      ).watch().map(
        (rows) => [
          for (final r in rows)
            TopSite(
              url: r.read<String>('url'),
              title: r.read<String>('title'),
              visits: r.read<int>('visits'),
            ),
        ],
      );

  // ---- new tab shortcuts ----

  Stream<List<Shortcut>> watchShortcuts() => (select(
    shortcuts,
  )..orderBy([(s) => OrderingTerm.asc(s.position)])).watch();

  Stream<Set<String>> watchHiddenSites() =>
      select(hiddenSites).watch().map((r) => {for (final h in r) h.url});

  /// Adds [url] as the last shortcut (or renames it if it already exists)
  /// and un-hides it.
  Future<void> addShortcut(String url, String title) => transaction(() async {
    await (delete(hiddenSites)..where((h) => h.url.equals(url))).go();
    final existing = await (select(
      shortcuts,
    )..where((s) => s.url.equals(url))).getSingleOrNull();
    if (existing != null) {
      await (update(shortcuts)..where((s) => s.id.equals(existing.id))).write(
        ShortcutsCompanion(title: Value(title)),
      );
      return;
    }
    final last = shortcuts.position.max();
    final max = await (selectOnly(
      shortcuts,
    )..addColumns([last])).map((r) => r.read(last)).getSingle();
    await into(shortcuts).insert(
      ShortcutsCompanion.insert(
        url: url,
        title: title,
        position: (max ?? -1) + 1,
      ),
    );
  });

  /// Replaces all shortcuts with [tiles] (url, title) in this order.
  Future<void> setShortcuts(List<(String, String)> tiles) =>
      transaction(() async {
        await delete(shortcuts).go();
        for (final (i, (url, title)) in tiles.indexed) {
          await into(shortcuts).insert(
            ShortcutsCompanion.insert(url: url, title: title, position: i),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });

  /// Removes [url] from the shortcuts and stops offering it as most visited.
  Future<void> hideSite(String url) => transaction(() async {
    await (delete(shortcuts)..where((s) => s.url.equals(url))).go();
    await into(hiddenSites).insert(
      HiddenSitesCompanion.insert(url: url),
      mode: InsertMode.insertOrIgnore,
    );
  });

  Future<void> unhideSite(String url) =>
      (delete(hiddenSites)..where((h) => h.url.equals(url))).go();

  // ---- settings ----

  Future<String?> getSetting(String key) async {
    final row = await (select(
      settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) => into(settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  Stream<Map<String, String>> watchSettings() =>
      select(settings)
          .watch()
          .map((rows) => {for (final r in rows) r.key: r.value});

  // ---- downloads ----

  Stream<List<Download>> watchDownloads() => (select(
    downloads,
  )..orderBy([(d) => OrderingTerm.desc(d.startedAt)])).watch();

  Future<void> upsertDownload(DownloadsCompanion d) =>
      into(downloads).insertOnConflictUpdate(d);

  Future<void> removeDownload(int id) =>
      (delete(downloads)..where((d) => d.id.equals(id))).go();

  Future<void> clearFinishedDownloads() => (delete(
    downloads,
  )..where((d) => d.state.equals('inProgress').not())).go();
}
