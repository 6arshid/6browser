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

@DriftDatabase(tables: [Bookmarks, HistoryEntries, Settings, Downloads])
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
  int get schemaVersion => 1;

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
