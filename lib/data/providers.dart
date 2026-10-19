import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// The browser profile's data folder (database, themes, site data); null
/// for the app data folder. Set in main() on desktop.
final dataDirProvider = Provider<Directory?>((ref) => null);

/// The app database. Tests override this with [AppDatabase.inMemory].
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.persistent(ref.watch(dataDirProvider));
  ref.onDispose(db.close);
  return db;
});

/// Whether [url] is bookmarked; cached per URL so widgets don't re-subscribe
/// to a fresh database stream on every rebuild.
final isBookmarkedProvider = StreamProvider.autoDispose.family<bool, String>(
  (ref, url) => ref.watch(databaseProvider).watchIsBookmarked(url),
);

/// All bookmarks, newest first (see [AppDatabase.watchBookmarks]).
final bookmarksProvider = StreamProvider<List<Bookmark>>(
  (ref) => ref.watch(databaseProvider).watchBookmarks(),
);
