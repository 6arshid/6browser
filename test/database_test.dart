import 'package:browser6/data/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.inMemory());
  tearDown(() => db.close());

  group('bookmarks', () {
    test('add, dedupe by url, remove', () async {
      await db.addBookmark('https://a.com', 'A');
      await db.addBookmark('https://a.com', 'A again');
      await db.addBookmark('https://b.com', '');
      final list = await db.watchBookmarks().first;
      expect(list.length, 2);
      expect(
        list.firstWhere((b) => b.url == 'https://b.com').title,
        'https://b.com',
      ); // empty title falls back to the url
      expect(await db.watchIsBookmarked('https://a.com').first, isTrue);

      await db.removeBookmarkByUrl('https://a.com');
      expect(await db.watchIsBookmarked('https://a.com').first, isFalse);
    });
  });

  group('history', () {
    test('records newest first and filters', () async {
      await db.addHistory('https://one.com', 'First page');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.addHistory('https://two.com', 'Second page');
      final all = await db.watchHistory().first;
      expect(all.map((h) => h.url), ['https://two.com', 'https://one.com']);

      final filtered = await db.watchHistory(query: 'FIRST').first;
      expect(filtered.single.url, 'https://one.com');
    });

    test('delete one and clear all', () async {
      await db.addHistory('https://one.com', 'x');
      await db.addHistory('https://two.com', 'y');
      final first = (await db.watchHistory().first).first;
      await db.deleteHistoryEntry(first.id);
      expect((await db.watchHistory().first).length, 1);
      await db.clearHistory();
      expect(await db.watchHistory().first, isEmpty);
    });

    test('suggest returns unique urls, newest first, respects limit', () async {
      for (var i = 0; i < 3; i++) {
        await db.addHistory('https://flutter.dev', 'Flutter');
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await db.addHistory('https://dart.dev', 'Dart and Flutter');
      expect(await db.suggest('flutter'), [
        'https://dart.dev',
        'https://flutter.dev',
      ]);
      expect(await db.suggest('flutter', limit: 1), ['https://dart.dev']);
      expect(await db.suggest('  '), isEmpty);
    });
  });

  group('settings', () {
    test('get/set overwrites', () async {
      expect(await db.getSetting('theme'), isNull);
      await db.setSetting('theme', 'dark');
      await db.setSetting('theme', 'light');
      expect(await db.getSetting('theme'), 'light');
    });
  });

  group('downloads', () {
    test(
      'upsert updates progress and clearFinished keeps active ones',
      () async {
        final now = DateTime.now();
        DownloadsCompanion row(int id, String state, int got) =>
            DownloadsCompanion(
              id: Value(id),
              url: const Value('https://x.com/f.zip'),
              fileName: const Value('f.zip'),
              path: const Value('C:/d/f.zip'),
              receivedBytes: Value(got),
              state: Value(state),
              startedAt: Value(now),
            );
        await db.upsertDownload(row(1, 'inProgress', 10));
        await db.upsertDownload(row(1, 'inProgress', 50));
        await db.upsertDownload(row(2, 'complete', 100));
        var list = await db.watchDownloads().first;
        expect(list.length, 2);
        expect(list.firstWhere((d) => d.id == 1).receivedBytes, 50);

        await db.clearFinishedDownloads();
        list = await db.watchDownloads().first;
        expect(list.single.id, 1);
      },
    );
  });
}
