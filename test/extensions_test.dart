import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:browser6/features/extensions/crx.dart';
import 'package:browser6/features/extensions/extension_install.dart';
import 'package:browser6/features/extensions/extension_manifest.dart';
import 'package:browser6/features/extensions/extension_service.dart';
import 'package:browser6/features/extensions/extension_toolbar.dart';
import 'package:browser6/features/extensions/extensions_page.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:browser6/engine/browser_engine.dart';

import 'support/fake_engine.dart';

/// Keeps the views it creates.
class RecordingEngine extends FakeEngine {
  final views = <FakeView>[];

  @override
  BrowserView createView({required String initialUrl, bool incognito = false}) {
    final v = FakeView(initialUrl, incognito: incognito);
    views.add(v);
    return v;
  }
}

/// uBlock Origin Lite's public key (from its Web Store package).
const ubolKey =
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqJE6DLdtfHXfeaGDSKdUuCvvb3pY'
    'EpH7jsuYMdExgIqmKRux2dknlJAnYkamBMcirGBfwCFjqE++TAkCs8AcrYLOGRRMt8oa7DXu'
    'FWzgtQpkwigI1+dnIuYLzERLQx/O02/p//fHdDQfxWKvySnN+VHdINOHsUD6OcoC5I7CXIBS'
    'rateRpRGpFxxR6F4nWvK3aq2j3L6A/qRg+pr0QVqL8p1TOJG+vSh234YHnsO9Dsys+VNbT0k'
    '0n8enCm/VsOCMjihgHpmftd1bSfSr8s1IwBuFdaLVQKghyDn1PvhFNBkuAXu+J/z0/o5Nio+'
    '/bIz406ECI9Qtkr9kqVboFDtzwIDAQAB';
const ubolId = 'ddkjiahejlhfcafbddmgiahcphecmpfh';

Uint8List zip(Map<String, Object> files) {
  final a = Archive();
  files.forEach(
    (name, content) => a.add(
      ArchiveFile.bytes(
        name,
        content is String ? utf8.encode(content) : content as List<int>,
      ),
    ),
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(a));
}

Uint8List u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

List<int> varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  return out..add(v);
}

/// A length-delimited protobuf field.
List<int> field(int number, List<int> value) => [
  ...varint(number << 3 | 2),
  ...varint(value.length),
  ...value,
];

/// A CRX3 package signed (in its header) by [keys]; [crxId] picks the
/// developer key, as in real Web Store packages.
Uint8List crx3(Uint8List zipBytes, List<Uint8List> keys, String crxId) {
  final idBytes = [
    for (var i = 0; i < 32; i += 2)
      (crxId.codeUnitAt(i) - 0x61) << 4 | (crxId.codeUnitAt(i + 1) - 0x61),
  ];
  final header = [
    for (final k in keys)
      ...field(2, [
        ...field(1, k),
        ...field(2, [9, 9]),
      ]),
    ...field(10000, field(1, idBytes)),
  ];
  return (BytesBuilder()
        ..add(ascii.encode('Cr24'))
        ..add(u32(3))
        ..add(u32(header.length))
        ..add(header)
        ..add(zipBytes))
      .toBytes();
}

const manifest = {
  'manifest_version': 3,
  'name': '__MSG_extName__',
  'version': '1.2',
  'default_locale': 'en',
  'action': {
    'default_popup': 'popup.html',
    'default_icon': {'16': 'i16.png', '48': 'i48.png'},
  },
  'options_ui': {'page': 'options.html'},
  'permissions': ['storage', 'tabs', 'declarativeNetRequest'],
  'host_permissions': ['https://*.example.com/*'],
};

Map<String, Object> extensionFiles([Map<String, Object> m = manifest]) => {
  'manifest.json': jsonEncode(m),
  '_locales/en/messages.json': jsonEncode({
    'extName': {'message': 'Blocker'},
  }),
  'popup.html': '<p>hi</p>',
  'i48.png': [1, 2, 3],
};

void main() {
  group('crx', () {
    test('extension id of a real key', () {
      expect(extensionIdForKey(base64.decode(ubolKey)), ubolId);
    });

    test('picks the developer key of a CRX3 package', () {
      final store = Uint8List.fromList(List.generate(40, (i) => i));
      final developer = base64.decode(ubolKey);
      final bytes = crx3(zip({'a': 'b'}), [store, developer], ubolId);
      expect(crxPublicKey(bytes), ubolKey);
      expect(crxPublicKey(bytes, expectedId: ubolId), ubolKey);
      expect(crxPublicKey(bytes, expectedId: 'a' * 32), isNull);
      expect(crxPublicKey(zip({'a': 'b'})), isNull);
    });
  });

  group('ExtensionManifest', () {
    final m = ExtensionManifest.parse(
      jsonEncode(manifest),
      readMessages: (l) => l == 'en'
          ? jsonEncode({
              'EXTNAME': {'message': 'Blocker'},
            })
          : null,
    );

    test('reads name, pages and icons', () {
      expect(m.name, 'Blocker');
      expect(m.isTheme, isFalse);
      expect(m.popup, 'popup.html');
      expect(m.optionsPage, 'options.html');
      expect(m.icon(16), 'i16.png');
      expect(m.icon(32), 'i48.png');
      expect(m.icon(128), 'i48.png');
    });

    test('warnings like Chrome', () {
      expect(m.warnings, [
        'Read and change your data on example.com',
        'Read your browsing history',
        'Block content on any page',
      ]);
      final all = ExtensionManifest.parse(
        jsonEncode({
          'content_scripts': [
            {
              'matches': ['<all_urls>'],
            },
          ],
        }),
      );
      expect(all.warnings, ['Read and change all your data on all websites']);
    });

    test('tolerates a byte order mark and comments', () {
      final m = ExtensionManifest.parse(
        '﻿{\n  // comment\n  "name": "A // not a comment", /* x */\n'
        '  "version": "1"\n}',
      );
      expect(m.name, 'A // not a comment');
    });
  });

  group('ExtensionsController', () {
    late Directory root;
    late FakeExtensionHost host;
    late ProviderContainer c;

    ProviderContainer container() => ProviderContainer(
      overrides: [
        engineProvider.overrideWithValue(FakeEngine()..extensions = host),
        extensionsDirProvider.overrideWith((ref) async => root),
      ],
    );

    setUp(() {
      root = Directory.systemTemp.createTempSync('ext_test');
      host = FakeExtensionHost();
      c = container();
    });

    tearDown(() {
      c.dispose();
      root.deleteSync(recursive: true);
    });

    ExtensionsController ctl() => c.read(extensionsProvider.notifier);

    test('installs a Web Store package under its store id', () async {
      final bytes = crx3(zip(extensionFiles()), [
        base64.decode(ubolKey),
      ], ubolId);
      final x = await ctl().installBytes(bytes, webStoreId: ubolId);
      expect(x.id, ubolId);
      expect(x.name, 'Blocker');
      expect(x.popupUrl, 'chrome-extension://$ubolId/popup.html');
      expect(host.loaded.keys, [ubolId]);
      final written = jsonDecode(
        File('${root.path}/$ubolId/manifest.json').readAsStringSync(),
      );
      expect(written['key'], ubolKey);
      expect(File('${root.path}/extensions.json').existsSync(), isTrue);
    });

    test('a theme is refused', () async {
      final bytes = zip({
        'manifest.json': jsonEncode({'name': 'T', 'theme': {}}),
      });
      await expectLater(
        ctl().installBytes(bytes),
        throwsA(isA<NotAnExtensionException>()),
      );
    });

    test('installed extensions load again at the next start', () async {
      await ctl().installBytes(
        crx3(zip(extensionFiles()), [base64.decode(ubolKey)], ubolId),
      );
      await ctl().setPinned(ubolId, true);
      c.dispose();
      host = FakeExtensionHost();
      c = container();
      await ctl().loadInstalled();
      final x = c.read(extensionsProvider).single;
      expect(x.pinned, isTrue);
      expect(x.running, isTrue);
      expect(host.loaded.keys, [ubolId]);
    });

    test('turning off applies at the next start; removing deletes', () async {
      await ctl().installBytes(
        crx3(zip(extensionFiles()), [base64.decode(ubolKey)], ubolId),
      );
      await ctl().setEnabled(ubolId, false);
      expect(c.read(extensionsProvider).single.pendingRestart, isTrue);
      expect(host.loaded, contains(ubolId)); // data kept, still running

      c.dispose();
      host = FakeExtensionHost();
      c = container();
      await ctl().loadInstalled();
      expect(host.loaded, isEmpty);
      await ctl().setEnabled(ubolId, true);
      expect(host.loaded.keys, [ubolId]);

      await ctl().remove(ubolId);
      expect(host.loaded, isEmpty);
      expect(c.read(extensionsProvider), isEmpty);
      expect(Directory('${root.path}/$ubolId').existsSync(), isFalse);
    });

    test('load unpacked keeps the folder in place', () async {
      final dir = Directory('${root.path}/../ext_src_${root.hashCode}')
        ..createSync();
      addTearDown(() => dir.deleteSync(recursive: true));
      final archive = ZipDecoder().decodeBytes(zip(extensionFiles()));
      for (final f in archive) {
        File('${dir.path}/${f.name}')
          ..createSync(recursive: true)
          ..writeAsBytesSync(f.readBytes()!);
      }
      final x = await ctl().loadUnpacked(dir.path);
      expect(x.copied, isFalse);
      await ctl().remove(x.id);
      expect(dir.existsSync(), isTrue);
    });
  });

  testWidgets('install dialog lists warnings', (tester) async {
    final (m, icon) = readPackage(zip(extensionFiles()));
    await tester.pumpWidget(
      MaterialApp(
        home: ExtensionInstallDialog(manifest: m, icon: icon),
      ),
    );
    expect(find.text('Add "Blocker"?'), findsOneWidget);
    expect(find.text('Read your browsing history'), findsOneWidget);
    expect(find.text('Add extension'), findsOneWidget);
  });

  testWidgets('extensions page without engine support', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [engineProvider.overrideWithValue(FakeEngine())],
        child: const MaterialApp(home: ExtensionsPage()),
      ),
    );
    expect(find.textContaining('not supported yet'), findsOneWidget);
  });

  testWidgets('popup sizes itself to the page and closes on window.close', (
    tester,
  ) async {
    final engine = RecordingEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => Center(
                child: ExtensionPopupView(
                  engine: engine,
                  url: 'chrome-extension://$ubolId/popup.html',
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    final view = engine.views.single;
    expect(view.url.value, 'chrome-extension://$ubolId/popup.html');

    // Load finished: the size/close helper is injected.
    view.isLoading.value = true;
    view.isLoading.value = false;
    expect(view.scripts.single, contains('ResizeObserver'));

    view.scriptController.add(
      jsonEncode({'extensionPopup': 'size', 'width': 300, 'height': 2000}),
    );
    await tester.pumpAndSettle();
    final box = tester.getSize(find.byType(ExtensionPopupView));
    expect(box, const Size(300, 600)); // Chrome's maximum height

    view.scriptController.add(jsonEncode({'extensionPopup': 'close'}));
    await tester.pumpAndSettle();
    expect(find.byType(ExtensionPopupView), findsNothing);
    expect(view.disposed, isTrue);
  });
}
