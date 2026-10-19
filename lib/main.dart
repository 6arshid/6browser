import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'data/providers.dart';
import 'features/profiles/profile_instance.dart';
import 'features/profiles/profiles.dart';
import 'features/settings/app_settings.dart';
import 'features/settings/factory_reset.dart';
import 'features/tabs/tabs_controller.dart';
import 'features/themes/theme_service.dart';
import 'ui/browser_shell.dart';
import 'ui/browser_theme.dart';
import 'ui/window_caption.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final launch = LaunchOptions.parse(args);
  final support = await getApplicationSupportDirectory();

  // Desktop windows each run one profile in their own process.
  ActiveProfile? active;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final store = ProfileStore(support);
    final list = await store.load();
    final profile =
        list.byId(launch.profile ?? list.lastUsed) ?? list.profiles.first;
    final dir = store.dataDir(profile.id);
    final ProfileInstance? instance;
    try {
      instance = await ProfileInstance.acquire(dir);
    } on Object catch (e) {
      return _fail('6browser could not open its data folder:\n${dir.path}\n$e');
    }
    if (instance == null) {
      // The profile is open in another window: give it this command line.
      WindowCaption.allowOthersToFocus();
      if (await ProfileInstance.handOver(dir, args)) exit(0);
      return _fail(
        '6browser is already open with the profile "${profile.name}" but '
        'does not respond. Close it and try again.',
      );
    }
    try {
      await store.setLastUsed(profile.id);
    } on Object {
      // Only decides which profile opens next time.
    }
    active = ActiveProfile(profile: profile, store: store, instance: instance);
  }

  try {
    await FactoryResetStore(active?.dataDir ?? support).applyPending();
  } catch (_) {
    return _fail(
      'Factory reset could not finish. Close other 6browser windows and '
      'reopen the app to retry.',
    );
  }
  runApp(
    ProviderScope(
      overrides: [
        launchOptionsProvider.overrideWithValue(launch),
        if (active != null) ...[
          activeProfileProvider.overrideWithValue(active),
          dataDirProvider.overrideWithValue(active.dataDir),
        ],
      ],
      child: const SixBrowserApp(),
    ),
  );
}

void _fail(String message) => runApp(
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    ),
  ),
);

class SixBrowserApp extends ConsumerWidget {
  const SixBrowserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final chrome = ref.watch(chromeThemeProvider).value;
    if (chrome != null) {
      final theme = buildChromeTheme(chrome);
      return MaterialApp(
        title: '6browser',
        debugShowCheckedModeBanner: false,
        theme: theme,
        darkTheme: theme,
        home: const BrowserShell(),
      );
    }
    return MaterialApp(
      title: '6browser',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(brightness: Brightness.light, seed: settings.colorSeed),
      darkTheme: buildTheme(
        brightness: Brightness.dark,
        seed: settings.colorSeed,
      ),
      home: const BrowserShell(),
    );
  }
}
