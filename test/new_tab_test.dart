import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/features/new_tab/new_tab_page.dart';
import 'package:browser6/features/new_tab/new_tab_tiles.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/features/tabs/url_input.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'browser_shell_test.dart' show pumpShell;

Future<void> visit(AppDatabase db, String url, int times) async {
  for (var i = 0; i < times; i++) {
    await db.addHistory(url, 'Title of $url');
  }
}

void main() {
  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.inMemory());
    tearDown(() => db.close());

    test('top sites are ordered by visit count', () async {
      await visit(db, 'https://a.com/', 1);
      await visit(db, 'https://b.com/', 3);
      await visit(db, 'https://c.com/', 2);
      final top = await db.watchTopSites().first;
      expect(top.map((t) => t.url), [
        'https://b.com/',
        'https://c.com/',
        'https://a.com/',
      ]);
      expect(top.first.visits, 3);
      expect(top.first.title, 'Title of https://b.com/');
    });

    test('shortcuts keep their order; hiding removes and hides', () async {
      await db.addShortcut('https://x.com/', 'X');
      await db.addShortcut('https://y.com/', 'Y');
      await db.addShortcut('https://x.com/', 'X renamed');
      var list = await db.watchShortcuts().first;
      expect(list.map((s) => s.title), ['X renamed', 'Y']);

      await db.hideSite('https://x.com/');
      list = await db.watchShortcuts().first;
      expect(list.map((s) => s.url), ['https://y.com/']);
      expect(await db.watchHiddenSites().first, {'https://x.com/'});

      // Adding it again brings it back.
      await db.addShortcut('https://x.com/', 'X');
      expect(await db.watchHiddenSites().first, isEmpty);
    });
  });

  group('tiles', () {
    Shortcut sc(int i, String url) =>
        Shortcut(id: i, url: url, title: url, position: i);
    TopSite top(String url, int n) => TopSite(url: url, title: url, visits: n);

    test('shortcuts first, then unhidden most visited, capped', () {
      final tiles = buildTiles(
        [sc(0, 'https://s.com/')],
        [
          top('https://s.com/', 9),
          top('https://hidden.com/', 8),
          top('https://a.com/', 5),
          top('https://b.com/', 4),
        ],
        {'https://hidden.com/'},
        max: 2,
      );
      expect(tiles.map((t) => t.url), ['https://s.com/', 'https://a.com/']);
      expect(tiles.map((t) => t.custom), [true, false]);
    });

    test('the same page or search shows once', () {
      final tiles = buildTiles(
        [sc(0, 'https://a.com/')],
        [
          top('https://www.google.com/search?q=x+y&ei=1&sxsrf=2', 9),
          top('https://www.google.com/search?q=x%20y&ei=3', 8),
          top('https://www.google.dk/search?q=X+y&hl=da', 7),
          top('http://www.a.com/?utm_source=z#top', 6),
          top('https://b.com/?id=1', 5),
          top('https://b.com/?id=2', 4),
        ],
        {},
      );
      expect(tiles.map((t) => t.url), [
        'https://a.com/',
        'https://www.google.com/search?q=x+y&ei=1&sxsrf=2',
        'https://b.com/?id=1',
        'https://b.com/?id=2',
      ]);
    });

    test('normalizeShortcutUrl', () {
      expect(normalizeShortcutUrl('example.com'), 'https://example.com');
      expect(normalizeShortcutUrl(' http://a.b/c '), 'http://a.b/c');
      expect(normalizeShortcutUrl('not a url'), isNull);
      expect(normalizeShortcutUrl('foo'), isNull);
      expect(normalizeShortcutUrl('ftp://a.com'), isNull);
    });

    test('moving a most-visited tile pins tiles up to it', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final tiles = [
        const NewTabTile(url: 'https://a.com/', title: 'A', custom: true),
        const NewTabTile(url: 'https://b.com/', title: 'B', custom: false),
        const NewTabTile(url: 'https://c.com/', title: 'C', custom: false),
        const NewTabTile(url: 'https://d.com/', title: 'D', custom: false),
      ];
      await NewTabActions(db, tiles).move(2, 0);
      final list = await db.watchShortcuts().first;
      expect(list.map((s) => s.title), ['C', 'A', 'B']);
    });

    test('remove can be undone', () async {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      await db.addShortcut('https://a.com/', 'A');
      await db.addShortcut('https://b.com/', 'B');
      final tiles = buildTiles(await db.watchShortcuts().first, const [], {});
      final undo = await NewTabActions(db, tiles).remove(0);
      expect((await db.watchShortcuts().first).map((s) => s.title), ['B']);
      await undo();
      expect((await db.watchShortcuts().first).map((s) => s.title), ['A', 'B']);
      expect(await db.watchHiddenSites().first, isEmpty);
    });
  });

  group('page', () {
    testWidgets('new tabs show the New Tab page until they navigate', (
      tester,
    ) async {
      final c = await pumpShell(tester, const Size(1200, 800));
      await tester.pump();
      final view = c.read(tabsProvider).active!.view;
      expect(view.url.value, newTabUrl);
      expect(find.byType(NewTabPage), findsOneWidget);
      expect(find.text('New tab'), findsOneWidget); // tab title

      await tester.enterText(
        find.byKey(const ValueKey('newtab-search')),
        'cats',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(view.url.value, 'https://www.google.com/search?q=cats');
      expect(find.byType(NewTabPage), findsNothing);
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('add, open and remove a shortcut', (tester) async {
      final c = await pumpShell(tester, const Size(1200, 800));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add shortcut'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('shortcut-title')),
        'Ex',
      );
      await tester.enterText(
        find.byKey(const ValueKey('shortcut-url')),
        'example.com',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Ex'), findsOneWidget);
      final db = c.read(databaseProvider);
      final saved = await tester.runAsync(() => db.watchShortcuts().first);
      expect(saved!.single.url, 'https://example.com');

      // Right-click > Remove, then Undo.
      await tester.tap(find.text('Ex'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Ex'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Ex'), findsOneWidget);

      await tester.tap(find.text('Ex'));
      await tester.pump();
      expect(
        c.read(tabsProvider).active!.view.url.value,
        'https://example.com',
      );
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('most visited sites appear and can be dragged', (tester) async {
      final c = await pumpShell(tester, const Size(1200, 800));
      final db = c.read(databaseProvider);
      await tester.runAsync(() async {
        await visit(db, 'https://a.com/', 3);
        await visit(db, 'https://b.com/', 2);
      });
      await tester.pumpAndSettle();
      final a = find.text('Title of https://a.com/');
      final b = find.text('Title of https://b.com/');
      expect(a, findsOneWidget);
      expect(b, findsOneWidget);
      expect(tester.getCenter(a).dx, lessThan(tester.getCenter(b).dx));

      final drag = await tester.startGesture(tester.getCenter(b));
      await tester.pump(const Duration(milliseconds: 50));
      await drag.moveBy(const Offset(-20, 0));
      await tester.pump();
      await drag.moveTo(tester.getCenter(a));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      final saved = await tester.runAsync(() => db.watchShortcuts().first);
      expect(saved!.map((s) => s.url), ['https://b.com/', 'https://a.com/']);
      expect(tester.getCenter(b).dx, lessThan(tester.getCenter(a).dx));
    });

    testWidgets('tiles fill two rows at most', (tester) async {
      final c = await pumpShell(tester, const Size(1200, 800));
      final db = c.read(databaseProvider);
      await tester.runAsync(() async {
        for (var i = 0; i < 20; i++) {
          await visit(db, 'https://site$i.com/', 1);
        }
      });
      await tester.pumpAndSettle();
      // 8 per row at this width: 15 sites and the add button.
      final shown = find.textContaining('Title of https://site');
      expect(shown, findsNWidgets(15));
      expect(find.text('Add shortcut'), findsOneWidget);
      final rows = {
        for (var i = 0; i < 15; i++) tester.getTopLeft(shown.at(i)).dy,
      };
      expect(rows, hasLength(2));
    });

    testWidgets('incognito New Tab page has no tiles', (tester) async {
      final c = await pumpShell(tester, const Size(1200, 800));
      c.read(tabsProvider.notifier).newIncognitoTab();
      await tester.pumpAndSettle();
      expect(find.text('You are browsing privately'), findsOneWidget);
      expect(find.text('Add shortcut', skipOffstage: false), findsOneWidget);
    });
  });
}
