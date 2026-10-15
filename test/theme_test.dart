import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/features/settings/app_settings.dart';
import 'package:browser6/features/themes/chrome_theme.dart';
import 'package:browser6/features/themes/theme_service.dart';
import 'package:browser6/ui/browser_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List zip(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((name, bytes) => a.add(ArchiveFile.bytes(name, bytes)));
  return Uint8List.fromList(ZipEncoder().encodeBytes(a));
}

Uint8List u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

Uint8List crx3(Uint8List zipBytes) {
  const header = [1, 2, 3, 4, 5];
  return (BytesBuilder()
        ..add(ascii.encode('Cr24'))
        ..add(u32(3))
        ..add(u32(header.length))
        ..add(header)
        ..add(zipBytes))
      .toBytes();
}

const id = 'abcdefghijklmnopabcdefghijklmnop';

const themeManifest = {
  'manifest_version': 3,
  'name': '__MSG_appName__',
  'default_locale': 'en',
  'theme': {
    'images': {'theme_frame': 'images/frame.png'},
    'colors': {
      'frame': [10, 20, 30],
      'toolbar': [250, 250, 250],
      'ntp_text': [0, 0, 0, 0.5],
    },
    'tints': {
      'buttons': [0.5, 0.5, 0.5],
    },
    'properties': {
      'ntp_background_alignment': 'bottom right',
      'ntp_background_repeat': 'repeat-x',
    },
  },
};

void main() {
  group('ChromeTheme.parse', () {
    test('reads colors, tints and properties', () {
      final t = ChromeTheme.parse(
        themeManifest,
        messages: {'appname': 'Ocean'},
      );
      expect(t.name, 'Ocean');
      expect(t.colors['frame'], const Color.fromARGB(255, 10, 20, 30));
      expect(t.colors['ntp_text']!.a, closeTo(0.5, 0.01));
      expect(t.tints['buttons']!.h, 0.5);
      expect(t.ntpAlignment, Alignment.bottomRight);
      expect(t.ntpRepeat, ImageRepeat.repeatX);
    });

    test('a normal extension is refused', () {
      expect(
        () => ChromeTheme.parse({'name': 'uBlock', 'manifest_version': 3}),
        throwsFormatException,
      );
    });

    test('tints follow Chrome HSL shift rules', () {
      const c = Color(0xFF3366CC);
      expect(const HslTint(-1, -1, -1).apply(c), c);
      expect(const HslTint(-1, -1, 0).apply(c).computeLuminance(), 0);
      expect(
        const HslTint(-1, -1, 1).apply(c).computeLuminance(),
        closeTo(1, 0.001),
      );
      final grey = const HslTint(-1, 0, -1).apply(c);
      expect(grey.r, closeTo(grey.b, 0.01));
    });
  });

  test('crxToZip handles CRX3, CRX2 and plain zip', () {
    final z = zip({'a.txt': utf8.encode('hi')});
    expect(crxToZip(crx3(z)), z);
    expect(crxToZip(z), z);
    final crx2 = BytesBuilder()
      ..add(ascii.encode('Cr24'))
      ..add(u32(2))
      ..add(u32(2))
      ..add(u32(3))
      ..add([9, 9, 8, 8, 8])
      ..add(z);
    expect(crxToZip(crx2.toBytes()), z);
    expect(
      () => crxToZip(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  test('webStoreItemId', () {
    expect(
      webStoreItemId('https://chromewebstore.google.com/detail/ocean/$id'),
      id,
    );
    expect(
      webStoreItemId('https://chrome.google.com/webstore/detail/x/$id?hl=en'),
      id,
    );
    expect(
      webStoreItemId('https://chromewebstore.google.com/category/themes'),
      isNull,
    );
    expect(webStoreItemId('https://example.com/detail/$id'), isNull);
  });

  group('ThemeService', () {
    late Directory tmp;
    late ProviderContainer c;
    late AppDatabase db;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('themes_test');
      db = AppDatabase.inMemory();
      c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          themesDirProvider.overrideWith((ref) async => tmp),
        ],
      );
      // Keep the settings stream alive between reads.
      c.listen(appSettingsProvider, (_, _) {});
    });

    tearDown(() async {
      c.dispose();
      await db.close();
      await tmp.delete(recursive: true);
    });

    Future<AppSettings> settled() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return c.read(appSettingsProvider);
    }

    test('installs a .crx, applies it and resets', () async {
      await db.setSetting('colorSeed', '${0xFF00FF00}');
      final bytes = crx3(
        zip({
          'manifest.json': utf8.encode(jsonEncode(themeManifest)),
          '_locales/en/messages.json': utf8.encode(
            jsonEncode({
              'appName': {'message': 'Ocean'},
            }),
          ),
          'images/frame.png': [137, 80, 78, 71],
          '../evil.txt': utf8.encode('x'),
        }),
      );
      final theme = await c
          .read(themeServiceProvider)
          .installBytes(bytes, id: id);
      expect(theme.name, 'Ocean');
      expect(theme.frameImage, isNotNull);
      expect(File('${tmp.path}/evil.txt').existsSync(), isFalse);
      expect(File('${tmp.parent.path}/evil.txt').existsSync(), isFalse);

      var s = await settled();
      expect(s.chromeTheme, id);
      expect(s.colorSeed, isNull, reason: 'a theme replaces the palette');
      expect((await c.read(chromeThemeProvider.future))?.name, 'Ocean');

      await c.read(themeServiceProvider).reset();
      s = await settled();
      expect(s.chromeTheme, isEmpty);
      expect(Directory('${tmp.path}/$id').existsSync(), isFalse);
    });

    test('an extension package is refused, leaving nothing behind', () async {
      final bytes = crx3(
        zip({
          'manifest.json': utf8.encode(jsonEncode({'name': 'Ext'})),
        }),
      );
      await expectLater(
        c.read(themeServiceProvider).installBytes(bytes, id: 'ext'),
        throwsFormatException,
      );
      expect(tmp.listSync(), isEmpty);
      expect((await settled()).chromeTheme, isEmpty);
    });
  });

  test('a dark Chrome theme gets readable text and a dark app theme', () {
    const t = ChromeTheme(
      name: 'Night',
      colors: {'frame': Color(0xFF101010), 'toolbar': Color(0xFF202020)},
    );
    final colors = BrowserColors.fromChromeTheme(t);
    expect(colors.brightness, Brightness.dark);
    expect(colors.tabText.computeLuminance(), greaterThan(0.5));
    expect(colors.tabBackgroundText.computeLuminance(), greaterThan(0.5));
    expect(buildChromeTheme(t).brightness, Brightness.dark);
  });
}
