// Renders the real 6browser UI at store sizes and writes PNGs to
// store_listing/screenshots/raw. Web pages are drawn by MockPage (the
// engine is faked), everything else is the app's own widgets.
//
//   flutter test tool/store_screenshots/store_screenshots_test.dart
//
// Then run `python tool/store_screenshots/frame.py` for the framed versions.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/engine/browser_engine.dart';
import 'package:browser6/features/bookmarks/bookmarks_page.dart';
import 'package:browser6/features/downloads/downloads_page.dart';
import 'package:browser6/features/history/history_page.dart';
import 'package:browser6/features/settings/app_settings.dart';
import 'package:browser6/features/settings/appearance_settings.dart';
import 'package:browser6/features/settings/settings_page.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/ui/browser_shell.dart';
import 'package:browser6/ui/browser_theme.dart';
import 'package:browser6/ui/toolbar.dart' show openPage;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_pages.dart';

const outDir = 'store_listing/screenshots/raw';

class ShotView implements BrowserView {
  ShotView(String initial, {this.incognito = false})
    : url = ValueNotifier(initial),
      title = ValueNotifier(mockTitle(initial));

  @override
  final bool incognito;
  @override
  final ValueNotifier<String> url;
  @override
  final ValueNotifier<String> title;
  @override
  final ValueNotifier<bool> isLoading = ValueNotifier(false);
  @override
  final ValueNotifier<bool> isReady = ValueNotifier(true);
  @override
  Widget get widget => ValueListenableBuilder<String>(
    valueListenable: url,
    builder: (_, u, _) => MockPage(url: u),
  );
  @override
  bool get supportsStop => false;
  @override
  Future<void> load(String u) async {
    url.value = u;
    title.value = mockTitle(u);
  }

  @override
  Future<void> goBack() async {}
  @override
  Future<void> goForward() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> reloadIgnoringCache() async {}
  @override
  Future<void> openDevTools() async {}
  @override
  bool get supportsPageTools => false;
  @override
  final ValueNotifier<double> zoom = ValueNotifier(1);
  @override
  Future<void> zoomStep(int direction) async {}
  @override
  Future<void> find(
    String text, {
    bool forward = true,
    bool findNext = false,
  }) async {}
  @override
  Future<void> stopFinding() async {}
  @override
  final ValueNotifier<FindResult> findResult = ValueNotifier(FindResult.none);
  @override
  Future<void> printPage() async {}
  final menus = StreamController<PageContextMenu>.broadcast();
  @override
  Stream<PageContextMenu> get contextMenus => menus.stream;
  @override
  Future<void> editCommand(EditCommand command) async {}
  @override
  Future<void> download(String url) async {}
  @override
  Future<void> inspectAt(Offset pagePosition) async {}
  @override
  Future<void> dispose() async {}
}

class ShotEngine implements BrowserEngine {
  @override
  Stream<DownloadEvent> get downloads => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  BrowserView createView({required String initialUrl, bool incognito = false}) =>
      ShotView(initialUrl, incognito: incognito);
  @override
  Future<void> shutdown() async {}
}

Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  final mat = '$root/bin/cache/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('MaterialIcons', ['$mat/materialicons-regular.otf']);
  await family('Roboto', [
    for (final w in ['regular', 'medium', 'bold', 'light']) '$mat/roboto-$w.ttf',
  ]);
  const win = 'C:/Windows/Fonts';
  await family('Segoe UI', [
    for (final f in ['segoeui', 'segoeuib', 'segoeuisl', 'seguisb']) '$win/$f.ttf',
  ]);
}

Future<void> seed(AppDatabase db) async {
  // Most visited: later entries are visited more often.
  const sites = [
    ('https://news.example.com/', 'Example News'),
    ('https://travel.example.org/', 'Wander — Travel guides'),
    ('https://recipes.example.net/', 'Fresh Kitchen Recipes'),
    ('https://video.example.com/', 'Example Video'),
    ('https://mail.example.com/', 'Example Mail'),
    ('https://maps.example.org/', 'Example Maps'),
    ('https://shop.example.net/', 'Example Shop'),
    ('https://music.example.com/', 'Example Music'),
  ];
  for (var i = 0; i < sites.length; i++) {
    for (var n = 0; n < sites.length - i; n++) {
      await db.addHistory(sites[i].$1, sites[i].$2);
    }
  }
  const more = [
    ('https://news.example.com/tech/fastest-browsers-2026', 'The fastest browsers of 2026, tested'),
    ('https://travel.example.org/japan/kyoto', 'Kyoto in 3 days — Wander'),
    ('https://recipes.example.net/pasta/lemon-garlic', 'Lemon garlic pasta in 15 minutes'),
    ('https://docs.example.com/getting-started', 'Getting started — Example Docs'),
  ];
  for (final s in more) {
    await db.addHistory(s.$1, s.$2);
  }
  for (final b in [
    ('https://news.example.com/', 'News'),
    ('https://mail.example.com/', 'Mail'),
    ('https://travel.example.org/', 'Travel'),
    ('https://recipes.example.net/', 'Recipes'),
    ('https://docs.example.com/', 'Docs'),
    ('https://shop.example.net/', 'Shop'),
    ('https://music.example.com/', 'Music'),
  ]) {
    await db.addBookmark(b.$1, b.$2);
  }
  final now = DateTime.now();
  final files = [
    ('travel-guide-kyoto.pdf', 4200000, 4200000, 'complete'),
    ('vacation-photos.zip', 31000000, 52000000, 'inProgress'),
    ('budget-2026.xlsx', 86000, 86000, 'complete'),
    ('podcast-episode-42.mp3', 48000000, 48000000, 'complete'),
    ('setup-tools.exe', 12500000, 12500000, 'complete'),
  ];
  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    await db.upsertDownload(
      DownloadsCompanion(
        id: Value(i + 1),
        url: Value('https://files.example.com/${f.$1}'),
        fileName: Value(f.$1),
        path: Value('C:\\Users\\You\\Downloads\\${f.$1}'),
        receivedBytes: Value(f.$2),
        totalBytes: Value(f.$3),
        state: Value(f.$4),
        startedAt: Value(now.subtract(Duration(minutes: 7 * i))),
      ),
    );
  }
}

class Shot {
  const Shot(this.name, this.setup, {this.dark = false, this.seed});
  final String name;
  final bool dark;
  final Color? seed;
  final Future<void> Function(WidgetTester t, ProviderContainer c) setup;
}

String _url(String host) => 'https://$host';

Future<void> open(ProviderContainer c, List<String> urls, {int active = -1}) async {
  final ctl = c.read(tabsProvider.notifier);
  final first = c.read(tabsProvider).active!;
  await first.view.load(urls.first);
  for (final u in urls.skip(1)) {
    ctl.newTab(url: u);
  }
  final tabs = c.read(tabsProvider).tabs;
  ctl.select(tabs[active < 0 ? tabs.length + active : active].id);
}

BuildContext shellContext(WidgetTester t) =>
    t.element(find.byType(BrowserShell));

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, GlobalKey key, String file, double dpr) async {
  await t.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$outDir/$file.png')..createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void runShots({
  required String prefix,
  required TargetPlatform platform,
  required Size size,
  required double dpr,
  required List<Shot> shots,
}) {
  for (final s in shots) {
    testWidgets('$prefix ${s.name}', (t) async {
      await t.runAsync(loadFonts);
      t.view.physicalSize = size * dpr;
      t.view.devicePixelRatio = dpr;
      debugDefaultTargetPlatformOverride = platform;
      // Tests draw shadows as black outlines unless told otherwise.
      debugDisableShadows = false;
      // Mouse/touch look: no keyboard focus rings.
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      final db = AppDatabase.inMemory();
      await t.runAsync(() async {
        await seed(db);
        if (s.dark) await db.setSetting('themeMode', 'dark');
        if (s.seed != null) {
          await db.setSetting('colorSeed', '${s.seed!.toARGB32()}');
        }
      });
      final c = ProviderContainer(
        overrides: [
          engineProvider.overrideWithValue(ShotEngine()),
          databaseProvider.overrideWithValue(db),
        ],
      );
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: UncontrolledProviderScope(container: c, child: const _App()),
        ),
      );
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await settle(t);
      await s.setup(t, c);
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await settle(t);
      await capture(t, key, '$prefix-${s.name}', dpr);

      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      c.dispose();
      await t.pump(const Duration(seconds: 1));
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
      t.view.reset();
    });
  }
}

class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode == ThemeMode.system
          ? ThemeMode.light
          : settings.themeMode,
      theme: buildTheme(brightness: Brightness.light, seed: settings.colorSeed),
      darkTheme: buildTheme(brightness: Brightness.dark, seed: settings.colorSeed),
      home: const BrowserShell(),
    );
  }
}

Future<void> tapTip(WidgetTester t, String tip) async {
  await t.tap(find.byTooltip(tip).last);
  await settle(t);
}

void main() {
  final phone = <Shot>[
    Shot('01-new-tab', (t, c) async {}),
    Shot('02-article', (t, c) async {
      await open(c, [_url('news.example.com/tech/fastest-browsers-2026')]);
    }),
    Shot('03-tabs', (t, c) async {
      await open(c, [
        _url('news.example.com/tech/fastest-browsers-2026'),
        _url('travel.example.org/japan/kyoto'),
        _url('recipes.example.net/pasta/lemon-garlic'),
        _url('shop.example.net/'),
        _url('docs.example.com/getting-started'),
        'about:blank',
      ], active: 1);
      await tapTip(t, 'Tabs');
    }),
    Shot('04-menu', (t, c) async {
      await open(c, [_url('travel.example.org/japan/kyoto')]);
      await tapTip(t, 'Menu');
    }),
    Shot('05-private', (t, c) async {
      c.read(tabsProvider.notifier).newIncognitoTab();
    }),
    Shot('06-dark', dark: true, (t, c) async {
      await open(c, [_url('recipes.example.net/pasta/lemon-garlic')]);
    }),
    Shot('07-bookmarks', (t, c) async {
      openPage(shellContext(t), const BookmarksPage());
    }),
    Shot('08-appearance', seed: const Color(0xFF00897B), (t, c) async {
      await open(c, [_url('travel.example.org/japan/kyoto')]);
      unawaited(showCustomizePanel(shellContext(t)));
    }),
  ];

  final desktop = <Shot>[
    Shot('01-new-tab', (t, c) async {
      await open(c, [
        _url('news.example.com/tech/fastest-browsers-2026'),
        _url('travel.example.org/japan/kyoto'),
        'about:blank',
      ]);
    }),
    Shot('02-article', (t, c) async {
      await c.read(databaseProvider).setSetting('bookmarksBar', 'true');
      await open(c, [
        _url('news.example.com/tech/fastest-browsers-2026'),
        _url('travel.example.org/japan/kyoto'),
        _url('recipes.example.net/pasta/lemon-garlic'),
        _url('docs.example.com/getting-started'),
      ], active: 0);
    }),
    Shot('03-menu', (t, c) async {
      await open(c, [
        _url('travel.example.org/japan/kyoto'),
        _url('shop.example.net/'),
      ], active: 0);
      await tapTip(t, 'Menu');
    }),
    Shot('04-context-menu', (t, c) async {
      await open(c, [_url('news.example.com/tech/fastest-browsers-2026')]);
      final v = c.read(tabsProvider).active!.view as ShotView;
      v.menus.add(
        const PageContextMenu(
          position: Offset(560, 330),
          pageUrl: 'https://news.example.com/tech/fastest-browsers-2026',
          linkUrl: 'https://news.example.com/tech/benchmarks',
          canCopy: true,
          canSelectAll: true,
          canGoBack: true,
        ),
      );
    }),
    Shot('05-dark', dark: true, seed: const Color(0xFF5C6BC0), (t, c) async {
      await open(c, [
        _url('recipes.example.net/pasta/lemon-garlic'),
        _url('music.example.com/'),
        'about:blank',
      ], active: 0);
    }),
    Shot('06-private', (t, c) async {
      await open(c, [_url('news.example.com/')]);
      c.read(tabsProvider.notifier).newIncognitoTab();
    }),
    Shot('07-history', (t, c) async {
      openPage(shellContext(t), const HistoryPage());
    }),
    Shot('08-downloads', (t, c) async {
      openPage(shellContext(t), const DownloadsPage());
    }),
    Shot('09-appearance', seed: const Color(0xFFE65100), (t, c) async {
      await open(c, ['about:blank']);
      unawaited(showCustomizePanel(shellContext(t)));
    }),
    Shot('10-settings', (t, c) async {
      openPage(shellContext(t), const SettingsPage());
    }),
  ];

  runShots(
    prefix: 'android',
    platform: TargetPlatform.android,
    size: const Size(360, 640),
    dpr: 3,
    shots: phone,
  );
  runShots(
    prefix: 'windows',
    platform: TargetPlatform.windows,
    size: const Size(1280, 720),
    dpr: 1.5,
    shots: desktop,
  );
}
