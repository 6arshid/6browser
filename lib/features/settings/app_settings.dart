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

const defaultHomeUrl = 'https://www.google.com';

/// User settings, persisted as string key/values in the database.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.searchTemplate = 'https://www.google.com/search?q=%s',
    this.homeUrl = defaultHomeUrl,
  });

  final ThemeMode themeMode;
  final String searchTemplate;
  final String homeUrl;

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
  );
}

final _settingsStream = StreamProvider<AppSettings>(
  (ref) => ref.watch(databaseProvider).watchSettings().map(AppSettings.fromMap),
);

/// Current settings (defaults until the database has answered).
final appSettingsProvider = Provider<AppSettings>(
  (ref) => ref.watch(_settingsStream).value ?? AppSettings.defaults,
);
