import 'dart:convert';
import 'dart:io';

import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/features/import/bookmark_file_parser.dart';
import 'package:browser6/features/import/browser_detector.dart';
import 'package:browser6/features/import/chromium_reader.dart';
import 'package:browser6/features/import/firefox_reader.dart';
import 'package:browser6/features/import/import_models.dart';
import 'package:browser6/features/import/import_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('BookmarkFileParser', () {
    test('parses Netscape HTML with nested folders and entities', () {
      const html = '''
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><H3 ADD_DATE="1" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
    <DL><p>
        <DT><A HREF="https://example.com/?a=1&amp;b=2" ADD_DATE="1">Tom &amp; Jerry</A>
        <DT><H3>News</H3>
        <DL><p>
            <DT><A HREF="https://news.test">News site</A>
        </DL><p>
        <DT><A HREF="https://after.test"></A>
    </DL><p>
    <DT><A HREF="place:sort=8">Recent</A>
    <DT><A HREF="https://root.test">Root</A>
</DL><p>
''';
      final marks = BookmarkFileParser.parse(html);
      expect(marks.map((m) => m.url), [
        'https://example.com/?a=1&b=2',
        'https://news.test',
        'https://after.test',
        'https://root.test',
      ]);
      expect(marks[0].title, 'Tom & Jerry');
      // The toolbar folder is our bookmarks bar; the rest is "Other".
      expect(marks[0].folders, isEmpty);
      expect(marks[1].folders, ['News']);
      expect(marks[2].folders, isEmpty);
      expect(marks[2].title, 'https://after.test');
      expect(marks[3].folders, ['Other bookmarks']);
    });

    test("maps Firefox's Other Bookmarks folder without nesting it", () {
      const html = '''
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<DL><p>
    <DT><A HREF="https://menu.test">Menu item</A>
    <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Toolbar</H3>
    <DL><p>
        <DT><A HREF="https://bar.test">Bar</A>
    </DL><p>
    <DT><H3 UNFILED_BOOKMARKS_FOLDER="true">Other Bookmarks</H3>
    <DL><p>
        <DT><H3>Work</H3>
        <DL><p>
            <DT><A HREF="https://work.test">Work</A>
        </DL><p>
    </DL><p>
</DL><p>
''';
      final marks = BookmarkFileParser.parse(html);
      expect(marks.map((m) => [m.url, ...m.folders]), [
        ['https://menu.test', 'Other bookmarks'],
        ['https://bar.test'],
        ['https://work.test', 'Other bookmarks', 'Work'],
      ]);
    });

    test('accepts Chromium Bookmarks JSON', () {
      final json = jsonEncode({
        'roots': {
          'other': {
            'type': 'folder',
            'name': 'Other',
            'children': [
              {'type': 'url', 'name': 'X', 'url': 'https://x.test'},
            ],
          },
        },
      });
      expect(BookmarkFileParser.parse(json).single.url, 'https://x.test');
    });

    test('rejects unrelated files', () {
      expect(
        () => BookmarkFileParser.parse('name,url,username,password'),
        throwsFormatException,
      );
    });
  });

  group('ChromiumReader.parseBookmarksJson', () {
    test('flattens nested folders with folder paths', () {
      const json = '''
      {"roots":{"bookmark_bar":{"type":"folder","name":"Bookmarks bar",
        "children":[
          {"type":"url","name":"Example","url":"https://example.com"},
          {"type":"folder","name":"News","children":[
            {"type":"url","name":"Site","url":"https://news.test"}
          ]}
        ]},
       "other":{"type":"folder","name":"Other","children":[
          {"type":"url","name":"Elsewhere","url":"https://other.test"}
       ]}}}
      ''';
      final marks = ChromiumReader.parseBookmarksJson(json);
      expect(marks.map((m) => m.url), [
        'https://example.com',
        'https://news.test',
        'https://other.test',
      ]);
      expect(marks[0].folders, isEmpty);
      expect(marks[1].folders, ['News']);
      expect(marks[2].folders, ['Other']);
    });

    test('rejects non-Chromium JSON', () {
      expect(
        () => ChromiumReader.parseBookmarksJson('{"foo":1}'),
        throwsFormatException,
      );
    });
  });

  group('ChromiumReader.parseExtensionPrefs', () {
    test('keeps user extensions, drops components and themes', () {
      final prefs = jsonEncode({
        'extensions': {
          'settings': {
            'realid1234567890123456789012345': {
              'manifest': {'name': 'uBlock Origin', 'version': '1.2.3'},
              'state': 1,
            },
            'component0000000000000000000000': {
              'manifest': {'name': 'Component'},
              'location': 5,
            },
            'theme00000000000000000000000000': {
              'manifest': {'name': 'A Theme', 'theme': {}},
            },
            'placeholder00000000000000000000': {
              'manifest': {'name': '__MSG_appName__', 'version': '2.0'},
              'state': 0,
            },
          },
        },
      });
      final exts = ChromiumReader.parseExtensionPrefs(prefs);
      expect(exts.map((e) => e.name), containsAll(['uBlock Origin']));
      expect(exts.any((e) => e.name == 'Component'), isFalse);
      expect(exts.any((e) => e.name == 'A Theme'), isFalse);
      // Placeholder falls back to the id (no faked name), and state 0 -> off.
      final ph = exts.firstWhere((e) => e.id.startsWith('placeholder'));
      expect(ph.name, ph.id);
      expect(ph.enabled, isFalse);
    });
  });

  group('FirefoxReader.parseExtensionsJson', () {
    test('reads active profile extensions only', () {
      final json = jsonEncode({
        'addons': [
          {
            'id': 'addon@one',
            'type': 'extension',
            'location': 'app-profile',
            'version': '3.1',
            'active': true,
            'defaultLocale': {'name': 'Addon One'},
          },
          {
            'id': 'system@builtin',
            'type': 'extension',
            'location': 'app-system-defaults',
            'defaultLocale': {'name': 'System'},
          },
          {'id': 'dict@x', 'type': 'dictionary', 'location': 'app-profile'},
        ],
      });
      final exts = FirefoxReader.parseExtensionsJson(json);
      expect(exts.length, 1);
      expect(exts.first.name, 'Addon One');
      expect(exts.first.enabled, isTrue);
    });
  });

  test('BrowserDetector finds Chrome and Firefox profiles in fixtures', () {
    final root = Directory.systemTemp.createTempSync('6b_det_');
    addTearDown(() => root.deleteSync(recursive: true));
    final lad = p.join(root.path, 'Local');
    final ad = p.join(root.path, 'Roaming');

    // Chrome Default profile with a Bookmarks file.
    final chromeDefault = Directory(
      p.join(lad, 'Google', 'Chrome', 'User Data', 'Default'),
    )..createSync(recursive: true);
    File(p.join(chromeDefault.path, 'Bookmarks')).writeAsStringSync('{}');

    // Firefox profile with places.sqlite.
    final ffProfile = Directory(
      p.join(ad, 'Mozilla', 'Firefox', 'Profiles', 'abc123.default-release'),
    )..createSync(recursive: true);
    File(p.join(ffProfile.path, 'places.sqlite')).writeAsStringSync('x');

    final profiles = BrowserDetector(localAppData: lad, appData: ad).detect();

    expect(profiles.any((pr) => pr.browser == SourceBrowser.chrome), isTrue);
    final ff = profiles.firstWhere((pr) => pr.browser == SourceBrowser.firefox);
    expect(ff.name, 'default-release');
  });

  test('FirefoxReader reads bookmarks from a places.sqlite fixture', () {
    final dir = Directory.systemTemp.createTempSync('6b_ff_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final dbPath = p.join(dir.path, 'places.sqlite');
    final db = sqlite3.open(dbPath);
    db.execute('''
      CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT);
      CREATE TABLE moz_bookmarks(
        id INTEGER PRIMARY KEY, type INTEGER, parent INTEGER,
        position INTEGER, fk INTEGER, title TEXT, guid TEXT);
      INSERT INTO moz_places(id, url) VALUES
        (10, 'https://moz.test'), (11, 'https://news.test'),
        (12, 'https://menu.test');
      INSERT INTO moz_bookmarks(id, type, parent, position, fk, title, guid)
      VALUES
        (1, 2, 0, 0, NULL, '', 'root________'),
        (2, 2, 1, 0, NULL, 'menu', 'menu________'),
        (3, 2, 1, 1, NULL, 'toolbar', 'toolbar_____'),
        (4, 2, 1, 2, NULL, 'tags', 'tags________'),
        (5, 2, 3, 1, NULL, 'News', 'folder000001'),
        (6, 1, 3, 0, 10, 'Mozilla', 'bookmark0001'),
        (7, 1, 5, 0, 11, 'News site', 'bookmark0002'),
        (8, 1, 2, 0, 12, 'Menu item', 'bookmark0003'),
        (9, 2, 4, 0, NULL, 'some tag', 'tag000000001'),
        (10, 1, 9, 0, 10, NULL, 'tagentry0001');
    ''');
    db.close();

    final marks = FirefoxReader(dir.path).readBookmarks();
    // Toolbar first, in Firefox's order; tag entries are not bookmarks.
    expect(marks.map((m) => [m.url, ...m.folders]), [
      ['https://moz.test'],
      ['https://news.test', 'News'],
      ['https://menu.test', 'Bookmarks Menu'],
    ]);
  });

  test('AppDatabase.addBookmarks de-dupes by URL', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    await db.addBookmark('https://a.test', 'A');

    final added = await db.addBookmarks([
      (url: 'https://a.test', title: 'dup'), // already there
      (url: 'https://b.test', title: 'B'),
      (url: 'https://b.test', title: 'B again'), // dup in batch
      (url: '', title: 'empty'),
    ]);
    expect(added, 1);
    final all = await db.watchBookmarks().first;
    expect(all.map((b) => b.url).toSet(), {'https://a.test', 'https://b.test'});
  });

  testWidgets('ImportPage scans a fixture profile and shows counts', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('6b_page_');
    addTearDown(() => root.deleteSync(recursive: true));
    final lad = p.join(root.path, 'Local');
    final profile = Directory(
      p.join(lad, 'Google', 'Chrome', 'User Data', 'Default'),
    )..createSync(recursive: true);
    File(p.join(profile.path, 'Bookmarks')).writeAsStringSync(
      jsonEncode({
        'roots': {
          'bookmark_bar': {
            'type': 'folder',
            'name': 'bar',
            'children': [
              {'type': 'url', 'name': 'X', 'url': 'https://x.test'},
            ],
          },
        },
      }),
    );

    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: ImportPage(
            detector: BrowserDetector(localAppData: lad, appData: null),
          ),
        ),
      ),
    );

    expect(find.text('Scan'), findsOneWidget);
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('1 found'), findsOneWidget); // bookmarks count
    await tester.ensureVisible(find.text('Import 1'));
    await tester.tap(find.text('Import 1'));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(() => db.watchBookmarks().first);
    expect(saved, hasLength(1));
  });

  testWidgets('ImportPage offers file import when no profiles are found', (
    tester,
  ) async {
    final empty = Directory.systemTemp.createTempSync('6b_empty_').path;
    addTearDown(() => Directory(empty).deleteSync(recursive: true));
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: ImportPage(
            detector: BrowserDetector(localAppData: empty, appData: empty),
          ),
        ),
      ),
    );
    expect(find.text('Scan'), findsNothing);
    expect(find.text('Choose bookmarks file'), findsOneWidget);
  });
}
