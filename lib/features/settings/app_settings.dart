import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// A search engine preset; `%s` in [template] is the encoded query.
class SearchEngine {
  const SearchEngine(this.name, this.template);
  final String name;
  final String template;
}

const searchEngines = [
  SearchEngine('Google', 'https://www.google.com/search?q=%s'),
  SearchEngine('DuckDuckGo', 'https://duckduckgo.com/?q=%s'),
  SearchEngine('Bing', 'https://www.bing.com/search?q=%s'),
];

/// The New Tab page (see `newTabUrl`) unless the user picks another page.
const defaultHomeUrl = 'about:blank';

/// User settings, persisted as string key/values in the database.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.searchTemplate = 'https://www.google.com/search?q=%s',
    this.homeUrl = defaultHomeUrl,
    this.colorSeed,
    this.chromeTheme = '',
    this.showBookmarksBar = false,
    this.savePasswords = true,
    this.fillPasswords = true,
  });

  final ThemeMode themeMode;
  final String searchTemplate;
  final String homeUrl;

  /// Accent color picked under Appearance; null for the default look.
  final Color? colorSeed;

  /// Folder name of the installed Chrome theme in use; empty for none.
  final String chromeTheme;

  /// Show the bookmarks bar on every page (otherwise only on New Tab).
  final bool showBookmarksBar;

  /// Offer to save passwords typed into sign-in forms.
  final bool savePasswords;

  /// Fill saved passwords into sign-in forms when a page opens.
  final bool fillPasswords;

  static const defaults = AppSettings();

  factory AppSettings.fromMap(Map<String, String> m) => AppSettings(
    themeMode: ThemeMode.values.firstWhere(
      (t) => t.name == m['themeMode'],
      orElse: () => ThemeMode.system,
    ),
    // A template without %s would ignore the query, so fall back.
    searchTemplate: (m['searchTemplate'] ?? '').contains('%s')
        ? m['searchTemplate']!
        : defaults.searchTemplate,
    homeUrl: (m['homeUrl'] ?? '').trim().isEmpty
        ? defaultHomeUrl
        : m['homeUrl']!.trim(),
    colorSeed: switch (int.tryParse(m['colorSeed'] ?? '')) {
      final v? => Color(v),
      null => null,
    },
    chromeTheme: m['chromeTheme'] ?? '',
    showBookmarksBar: m['bookmarksBar'] == 'true',
    savePasswords: m['passwordsSave'] != 'false',
    fillPasswords: m['passwordsFill'] != 'false',
  );
}

final _settingsStream = StreamProvider<AppSettings>(
  (ref) => ref.watch(databaseProvider).watchSettings().map(AppSettings.fromMap),
);

/// Current settings (defaults until the database has answered).
final appSettingsProvider = Provider<AppSettings>(
  (ref) => ref.watch(_settingsStream).value ?? AppSettings.defaults,
);
