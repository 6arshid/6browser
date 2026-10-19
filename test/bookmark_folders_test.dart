import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/features/bookmarks/bookmark_tree.dart';
import 'package:browser6/features/bookmarks/bookmarks_page.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/ui/bookmarks_bar.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'browser_shell_test.dart' show pumpShell;
import 'support/fake_engine.dart';

Future<List<String>> titlesIn(AppDatabase db, int? folder) async =>
    BookmarkTree(await db.watchBookmarks().first)
        .children(folder)
        .map((b) => b.title)
        .toList();

/// Drags [from] with the mouse and drops it at [to].
Future<void> mouseDrag(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveBy(const Offset(4, 12));
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.inMemory());
    tearDown(() => db.close());

    test('folders hold bookmarks in order', () async {
      final work = await db.addFolder('Work');
      await db.addBookmark('https://a.test', 'A');
      await db.addBookmark('https://b.test', 'B', folderId: work);
      // Bookmarking a saved URL again keeps it where it is.
      expect(
        await db.addBookmark('https://b.test', 'B again'),
        (await db.bookmarkForUrl('https://b.test'))!.id,
      );
      expect(await titlesIn(db, null), ['Work', 'A']);
      expect(await titlesIn(db, work), ['B']);
    });

    test('move reorders, files into folders, never into itself', () async {
      final a = await db.addBookmark('https://a.test', 'A');
      final b = await db.addBookmark('https://b.test', 'B');
      final f = await db.addFolder('F');
      final sub = await db.addFolder('Sub', parentId: f);

      await db.moveBookmark(f, beforeId: a);
      expect(await titlesIn(db, null), ['F', 'A', 'B']);
      await db.moveBookmark(a, folderId: f, beforeId: sub);
      expect(await titlesIn(db, null), ['F', 'B']);
      expect(await titlesIn(db, f), ['A', 'Sub']);
      await db.moveBookmark(f, folderId: sub);
      expect(await titlesIn(db, null), ['F', 'B']);
      await db.moveBookmark(b, folderId: sub);
      expect(await titlesIn(db, sub), ['B']);
      expect(await titlesIn(db, null), ['F']);
    });

    test('removing a folder removes everything in it', () async {
      final f = await db.addFolder('F');
      final sub = await db.addFolder('Sub', parentId: f);
      await db.addBookmark('https://a.test', 'A', folderId: sub);
      await db.addBookmark('https://b.test', 'B');
      await db.removeBookmark(f);
      expect((await db.watchBookmarks().first).map((b) => b.title), ['B']);
    });

    test('import recreates folders and files loose bookmarks', () async {
      // From an import made before folders existed.
      await db.addBookmark('https://loose.test', 'Loose');
      final mine = await db.addFolder('Mine');
      await db.addBookmark('https://filed.test', 'Filed', folderId: mine);

      final r = await db.importBookmarks([
        (url: 'https://new.test', title: 'New', folders: ['News', 'World']),
        (url: 'https://loose.test', title: 'Loose', folders: ['News']),
        (url: 'https://filed.test', title: 'Filed', folders: ['News']),
        (url: 'https://bar.test', title: 'Bar', folders: <String>[]),
        (url: 'https://new.test', title: 'Dup', folders: <String>[]),
      ]);
      expect(r, (added: 2, moved: 1));
      final tree = BookmarkTree(await db.watchBookmarks().first);
      expect(tree.children(null).map((b) => b.title), ['Mine', 'News', 'Bar']);
      final news = tree.children(null)[1].id;
      expect(tree.children(news).map((b) => b.title), ['World', 'Loose']);
      expect(tree.children(tree.children(news).first.id).single.title, 'New');
      expect(tree.children(mine).single.title, 'Filed');

      // Importing again reuses the folders instead of copying them.
      await db.importBookmarks([
        (url: 'https://more.test', title: 'More', folders: ['News']),
      ]);
      expect(await titlesIn(db, null), ['Mine', 'News', 'Bar']);
      expect(await titlesIn(db, news), ['World', 'Loose', 'More']);
    });

    test('version 2 bookmarks move to the bar in their old order', () async {
      final raw = sqlite3.openInMemory();
      raw.execute('''
        CREATE TABLE bookmarks (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          url TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
          created_at INTEGER NOT NULL);
        INSERT INTO bookmarks (id, url, title, created_at) VALUES
          (1, 'https://new.test', 'Newer', 200),
          (2, 'https://old.test', 'Older', 100);
        PRAGMA user_version = 2;
      ''');
      final old = AppDatabase(NativeDatabase.opened(raw));
      addTearDown(old.close);
      final list = await old.watchBookmarks().first;
      expect(list.map((b) => b.title), ['Older', 'Newer']);
      expect(list.every((b) => b.parentId == null), isTrue);
      // Folders have no URL, which the old table did not allow.
      await old.addFolder('F');
      expect(await titlesIn(old, null), ['Older', 'Newer', 'F']);
    });
  });

  testWidgets('bookmark manager opens folders and reorders by dragging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    late int work;
    await tester.runAsync(() async {
      work = await db.addFolder('Work');
      await db.addBookmark('https://a.test', 'A');
      await db.addBookmark('https://b.test', 'B');
      await db.addBookmark('https://in.test', 'Inside', folderId: work);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: BookmarksPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 bookmark'), findsOneWidget);

    Rect row(String title) => tester.getRect(
      find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    );

    // B above A: drop on the top part of A's row.
    await mouseDrag(
      tester,
      tester.getCenter(find.text('B')),
      row('A').topCenter + const Offset(0, 6),
    );
    expect(await tester.runAsync(() => titlesIn(db, null)), ['Work', 'B', 'A']);

    // A into Work: drop on the middle of the folder's row.
    await mouseDrag(
      tester,
      tester.getCenter(find.text('A')),
      row('Work').center,
    );
    expect(await tester.runAsync(() => titlesIn(db, work)), ['Inside', 'A']);

    // Open the folder, then go back up with the breadcrumb.
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('Inside'), findsOneWidget);
    expect(find.text('B'), findsNothing);
    await tester.tap(find.text('Bookmarks bar'));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);

    // Unmount so drift's stream subscriptions cancel, then flush timers.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('bar folders take dropped bookmarks and open as menus', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(1200, 800));
    final db = c.read(databaseProvider);
    late int work;
    await tester.runAsync(() async {
      work = await db.addFolder('Work');
      await db.addBookmark('https://in.test', 'Inside', folderId: work);
      await db.addBookmark('https://a.test', 'A');
    });
    await tester.pumpAndSettle();
    Finder onBar(String text) => find.descendant(
      of: find.byType(BookmarksBar),
      matching: find.text(text),
    );
    expect(onBar('Work'), findsOneWidget);
    expect(onBar('Inside'), findsNothing);

    await mouseDrag(
      tester,
      tester.getCenter(onBar('A')),
      tester.getCenter(onBar('Work')),
    );
    expect(await tester.runAsync(() => titlesIn(db, work)), ['Inside', 'A']);
    expect(onBar('A'), findsNothing);

    // The folder opens a menu of its bookmarks; picking one loads it.
    await tester.tap(onBar('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inside'));
    await tester.pumpAndSettle();
    expect(c.read(tabsProvider).active!.view.url.value, 'https://in.test');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('the star files a new bookmark in the chosen folder', (
    tester,
  ) async {
    final c = await pumpShell(tester, const Size(1200, 800));
    final db = c.read(databaseProvider);
    final work = await tester.runAsync(() => db.addFolder('Work'));
    final view = c.read(tabsProvider).active!.view as FakeView;
    view.url.value = 'https://page.test/';
    view.title.value = 'Page';
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Bookmark this tab'));
    await tester.pumpAndSettle();
    expect(find.text('Bookmark added'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bookmark-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bookmark-name')),
      'My page',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(await tester.runAsync(() => titlesIn(db, work)), ['My page']);
    expect(find.byTooltip('Edit bookmark for this tab'), findsOneWidget);
  });
}
