import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/settings/app_settings.dart';
import 'features/tabs/tabs_controller.dart';
import 'features/themes/theme_service.dart';
import 'ui/browser_shell.dart';
import 'ui/browser_theme.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        launchOptionsProvider.overrideWithValue(LaunchOptions.parse(args)),
      ],
      child: const SixBrowserApp(),
    ),
  );
}

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
