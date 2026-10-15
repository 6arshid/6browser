import 'dart:convert';
import 'dart:io';

import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
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
       "other":{"type":"folder","name":"Other","children":[]}}}
      ''';
      final marks = ChromiumReader.parseBookmarksJson(json);
      expect(marks.map((m) => m.url), [
        'https://example.com',
        'https://news.test',
      ]);
      expect(marks[0].folder, 'Bookmarks bar');
      expect(marks[1].folder, 'Bookmarks bar/News');
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

    final profiles = BrowserDetector(
      localAppData: lad,
      appData: ad,
    ).detect();

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
        fk INTEGER, title TEXT);
      INSERT INTO moz_places(id, url) VALUES (10, 'https://moz.test');
      INSERT INTO moz_bookmarks(id,type,parent,fk,title)
        VALUES (1,2,0,NULL,'Toolbar');
      INSERT INTO moz_bookmarks(id,type,parent,fk,title)
        VALUES (2,1,1,10,'Mozilla');
    ''');
    db.close();

    final marks = FirefoxReader(dir.path).readBookmarks();
    expect(marks.length, 1);
    expect(marks.first.url, 'https://moz.test');
    expect(marks.first.folder, 'Toolbar');
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
    await tester.tap(find.text('Import 1'));
    await tester.pumpAndSettle();
    expect(await db.watchBookmarks().first, hasLength(1));
  });
}
