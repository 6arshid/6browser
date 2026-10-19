import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Bookmarks and bookmark folders, as a tree under the bookmarks bar.
class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The folder holding this item; null for items on the bookmarks bar.
  IntColumn get parentId => integer().nullable()();

  /// The page address; null for a folder.
  TextColumn get url => text().nullable().unique()();
  TextColumn get title => text()();

  /// Order among the items of the same folder.
  IntColumn get position => integer().withDefault(const Constant(0))();
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

/// Saved sign-ins. [password] is encrypted with the device user's key (see
/// SecretBox); [origin] is the sign-in page's scheme, host and port.
class Logins extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get origin => text()();
  TextColumn get username => text()();
  BlobColumn get password => blob()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {origin, username},
  ];
}

/// Sites where the user chose "Never" when offered to save a password.
class NeverSavePasswords extends Table {
  TextColumn get origin => text()();

  @override
  Set<Column> get primaryKey => {origin};
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
    Logins,
    NeverSavePasswords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the persistent database in [dir] (the browser profile's folder),
  /// or in the app data folder.
  factory AppDatabase.persistent([Directory? dir]) => AppDatabase(
    LazyDatabase(() async {
      final folder = dir ?? await getApplicationSupportDirectory();
      await folder.create(recursive: true);
      final file = File(p.join(folder.path, '6browser.sqlite'));
      return NativeDatabase.createInBackground(file);
    }),
  );

  /// In-memory database for tests.
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(shortcuts);
        await m.createTable(hiddenSites);
      }
      if (from < 3) {
        // Folders: url becomes optional, items get a parent and an order.
        await m.alterTable(
          TableMigration(
            bookmarks,
            newColumns: [bookmarks.parentId, bookmarks.position],
          ),
        );
        // Keep the bar's old order: oldest first.
        await customStatement(
          'UPDATE bookmarks SET position = (SELECT COUNT(*) FROM bookmarks b '
          'WHERE b.created_at < bookmarks.created_at '
          'OR (b.created_at = bookmarks.created_at AND b.id < bookmarks.id))',
        );
      }
      if (from < 4) {
        await m.createTable(logins);
        await m.createTable(neverSavePasswords);
      }
    },
  );

  // ---- bookmarks ----

  /// Every bookmark and folder, each folder's items in display order.
  Stream<List<Bookmark>> watchBookmarks() =>
      (select(bookmarks)..orderBy([
            (b) => OrderingTerm.asc(b.position),
            (b) => OrderingTerm.asc(b.id),
          ]))
          .watch();

  Stream<bool> watchIsBookmarked(String url) => (select(
    bookmarks,
  )..where((b) => b.url.equals(url))).watch().map((r) => r.isNotEmpty);

  Future<Bookmark?> bookmarkForUrl(String url) =>
      (select(bookmarks)..where((b) => b.url.equals(url))).getSingleOrNull();

  /// The position after the last item in [folderId] (the bar when null).
  Future<int> _nextPosition(int? folderId) async {
    final last = bookmarks.position.max();
    final query = selectOnly(bookmarks)
      ..addColumns([last])
      ..where(
        folderId == null
            ? bookmarks.parentId.isNull()
            : bookmarks.parentId.equals(folderId),
      );
    return ((await query.map((r) => r.read(last)).getSingle()) ?? -1) + 1;
  }

  /// Adds [url] at the end of [folderId] (the bookmarks bar when null) and
  /// returns its id. A URL that is already bookmarked stays where it is.
  Future<int> addBookmark(String url, String title, {int? folderId}) =>
      transaction(() async {
        final existing = await bookmarkForUrl(url);
        if (existing != null) return existing.id;
        return into(bookmarks).insert(
          BookmarksCompanion.insert(
            url: Value(url),
            title: title.isEmpty ? url : title,
            parentId: Value(folderId),
            position: Value(await _nextPosition(folderId)),
            createdAt: DateTime.now(),
          ),
        );
      });

  /// Creates a folder at the end of [parentId] and returns its id.
  Future<int> addFolder(String title, {int? parentId}) => transaction(() async {
    return into(bookmarks).insert(
      BookmarksCompanion.insert(
        title: title,
        parentId: Value(parentId),
        position: Value(await _nextPosition(parentId)),
        createdAt: DateTime.now(),
      ),
    );
  });

  /// Adds bookmarks to the end of the bar, ignoring any whose URL already
  /// exists. Returns the number of new rows actually added.
  Future<int> addBookmarks(List<({String url, String title})> items) =>
      transaction(() async {
        final existing = <String>{
          for (final r in await (selectOnly(
            bookmarks,
          )..addColumns([bookmarks.url])).get())
            ?r.read(bookmarks.url),
        };
        var position = await _nextPosition(null);
        final now = DateTime.now();
        var added = 0;
        for (final it in items) {
          if (it.url.isEmpty || !existing.add(it.url)) continue;
          await into(bookmarks).insert(
            BookmarksCompanion.insert(
              url: Value(it.url),
              title: it.title.isEmpty ? it.url : it.title,
              position: Value(position++),
              createdAt: now,
            ),
          );
          added++;
        }
        return added;
      });

  /// Adds bookmarks read from another browser, recreating their folders
  /// (matched by name, so importing twice does not duplicate them). A
  /// bookmark already saved loose on the bar is moved into its folder; one
  /// the user filed in a folder is left alone.
  Future<({int added, int moved})> importBookmarks(
    List<({String url, String title, List<String> folders})> items,
  ) => transaction(() async {
    final all = await select(bookmarks).get();
    final byUrl = {
      for (final b in all)
        if (b.url != null) b.url!: b,
    };
    final next = <int?, int>{};
    for (final b in all) {
      if (b.position >= (next[b.parentId] ?? 0)) {
        next[b.parentId] = b.position + 1;
      }
    }
    int take(int? folder) {
      final position = next[folder] ?? 0;
      next[folder] = position + 1;
      return position;
    }

    final folders = <(int?, String), int>{};
    for (final b in all) {
      if (b.url == null) folders.putIfAbsent((b.parentId, b.title), () => b.id);
    }
    final now = DateTime.now();
    Future<int?> folderFor(List<String> path) async {
      int? parent;
      for (final name in path) {
        final key = (parent, name);
        parent =
            folders[key] ??
            (folders[key] = await into(bookmarks).insert(
              BookmarksCompanion.insert(
                title: name,
                parentId: Value(parent),
                position: Value(take(parent)),
                createdAt: now,
              ),
            ));
      }
      return parent;
    }

    final seen = <String>{};
    var added = 0, moved = 0;
    for (final it in items) {
      if (it.url.isEmpty || !seen.add(it.url)) continue;
      final existing = byUrl[it.url];
      if (existing != null) {
        if (existing.parentId == null && it.folders.isNotEmpty) {
          final parent = await folderFor(it.folders);
          await (update(
            bookmarks,
          )..where((b) => b.id.equals(existing.id))).write(
            BookmarksCompanion(
              parentId: Value(parent),
              position: Value(take(parent)),
            ),
          );
          moved++;
        }
        continue;
      }
      final parent = await folderFor(it.folders);
      await into(bookmarks).insert(
        BookmarksCompanion.insert(
          url: Value(it.url),
          title: it.title.isEmpty ? it.url : it.title,
          parentId: Value(parent),
          position: Value(take(parent)),
          createdAt: now,
        ),
      );
      added++;
    }
    return (added: added, moved: moved);
  });

  /// Moves [id] into [folderId] (the bar when null), before the item
  /// [beforeId] there, or to the end when [beforeId] is null. Moving a
  /// folder into itself or into one of its subfolders does nothing.
  Future<void> moveBookmark(int id, {int? folderId, int? beforeId}) =>
      transaction(() async {
        final all = await select(bookmarks).get();
        final byId = {for (final b in all) b.id: b};
        final item = byId[id];
        if (item == null || beforeId == id) return;
        for (int? f = folderId; f != null; f = byId[f]?.parentId) {
          if (f == id) return;
        }
        List<Bookmark> itemsIn(int? folder) =>
            all.where((b) => b.parentId == folder && b.id != id).toList()..sort(
              (a, b) => a.position != b.position
                  ? a.position.compareTo(b.position)
                  : a.id.compareTo(b.id),
            );
        Future<void> renumber(List<Bookmark> list, int? folder) async {
          for (final (i, b) in list.indexed) {
            if (b.id == id || b.position != i) {
              await (update(bookmarks)..where((t) => t.id.equals(b.id))).write(
                BookmarksCompanion(parentId: Value(folder), position: Value(i)),
              );
            }
          }
        }

        final target = itemsIn(folderId);
        final at = target.indexWhere((b) => b.id == beforeId);
        target.insert(at < 0 ? target.length : at, item);
        await renumber(target, folderId);
        if (item.parentId != folderId) {
          await renumber(itemsIn(item.parentId), item.parentId);
        }
      });

  Future<void> removeBookmarkByUrl(String url) =>
      (delete(bookmarks)..where((b) => b.url.equals(url))).go();

  /// Deletes a bookmark, or a folder with everything in it.
  Future<void> removeBookmark(int id) => transaction(() async {
    final all = await select(bookmarks).get();
    final doomed = {id};
    for (var grew = true; grew;) {
      grew = false;
      for (final b in all) {
        if (doomed.contains(b.parentId) && doomed.add(b.id)) grew = true;
      }
    }
    await (delete(bookmarks)..where((b) => b.id.isIn(doomed))).go();
  });

  Future<void> renameBookmark(int id, String title) =>
      (update(bookmarks)..where((b) => b.id.equals(id))).write(
        BookmarksCompanion(title: Value(title)),
      );

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

  // ---- saved passwords ----

  Stream<List<Login>> watchLogins() =>
      (select(logins)..orderBy([
            (l) => OrderingTerm.asc(l.origin),
            (l) => OrderingTerm.asc(l.username),
          ]))
          .watch();

  /// Sign-ins for [origin], the most recently used first.
  Future<List<Login>> loginsFor(String origin) =>
      (select(logins)
            ..where((l) => l.origin.equals(origin))
            ..orderBy([
              (l) => OrderingTerm(
                expression: l.lastUsedAt,
                mode: OrderingMode.desc,
                nulls: NullsOrder.last,
              ),
              (l) => OrderingTerm.desc(l.updatedAt),
            ]))
          .get();

  /// Saves the (already encrypted) [password] for [username] on [origin],
  /// replacing the one saved before for that user name.
  Future<void> saveLogin(String origin, String username, Uint8List password) {
    final now = DateTime.now();
    return into(logins).insert(
      LoginsCompanion.insert(
        origin: origin,
        username: username,
        password: password,
        createdAt: now,
        updatedAt: now,
        lastUsedAt: Value(now),
      ),
      onConflict: DoUpdate(
        (_) => LoginsCompanion(
          password: Value(password),
          updatedAt: Value(now),
          lastUsedAt: Value(now),
        ),
        target: [logins.origin, logins.username],
      ),
    );
  }

  /// Changes a saved sign-in; [password] is encrypted.
  Future<void> updateLogin(int id, {String? username, Uint8List? password}) =>
      (update(logins)..where((l) => l.id.equals(id))).write(
        LoginsCompanion(
          username: username == null ? const Value.absent() : Value(username),
          password: password == null ? const Value.absent() : Value(password),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> touchLogin(int id) =>
      (update(logins)..where((l) => l.id.equals(id))).write(
        LoginsCompanion(lastUsedAt: Value(DateTime.now())),
      );

  Future<void> deleteLogin(int id) =>
      (delete(logins)..where((l) => l.id.equals(id))).go();

  Future<void> restoreLogin(Login login) =>
      into(logins).insert(login, mode: InsertMode.insertOrReplace);

  Stream<List<String>> watchNeverSavePasswords() =>
      (select(neverSavePasswords)..orderBy([(n) => OrderingTerm.asc(n.origin)]))
          .watch()
          .map((rows) => [for (final r in rows) r.origin]);

  Future<bool> isNeverSavePasswords(String origin) async =>
      await (select(
        neverSavePasswords,
      )..where((n) => n.origin.equals(origin))).getSingleOrNull() !=
      null;

  Future<void> neverSavePasswordsFor(String origin) =>
      into(neverSavePasswords).insert(
        NeverSavePasswordsCompanion.insert(origin: origin),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> allowSavingPasswordsFor(String origin) =>
      (delete(neverSavePasswords)..where((n) => n.origin.equals(origin))).go();

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
