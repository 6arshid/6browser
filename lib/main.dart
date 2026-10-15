import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/settings/app_settings.dart';
import 'ui/browser_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SixBrowserApp()));
}

class SixBrowserApp extends ConsumerWidget {
  const SixBrowserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: '6browser',
    debugShowCheckedModeBanner: false,
    themeMode: ref.watch(appSettingsProvider).themeMode,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const BrowserShell(),
  );
}
