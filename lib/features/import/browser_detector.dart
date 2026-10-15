import 'dart:io';

import 'package:path/path.dart' as p;

import 'import_models.dart';

/// Finds installed browsers and their profiles on the current machine.
///
/// Only Windows locations are implemented today (the project's first target);
/// on other platforms [detect] returns an empty list.
class BrowserDetector {
  /// [localAppData]/[appData] default to the real Windows env vars but can be
  /// overridden in tests to point at fixture directories.
  BrowserDetector({String? localAppData, String? appData})
    : _localAppData = localAppData ?? Platform.environment['LOCALAPPDATA'],
      _appData = appData ?? Platform.environment['APPDATA'];

  final String? _localAppData;
  final String? _appData;

  List<BrowserProfile> detect() {
    final out = <BrowserProfile>[];
    final lad = _localAppData;
    if (lad != null) {
      out.addAll(
        _chromium(SourceBrowser.chrome, p.join(lad, 'Google', 'Chrome')),
      );
      out.addAll(
        _chromium(SourceBrowser.edge, p.join(lad, 'Microsoft', 'Edge')),
      );
      out.addAll(
        _chromium(
          SourceBrowser.brave,
          p.join(lad, 'BraveSoftware', 'Brave-Browser'),
        ),
      );
    }
    final ad = _appData;
    if (ad != null) {
      out.addAll(_firefox(p.join(ad, 'Mozilla', 'Firefox')));
    }
    return out;
  }

  Iterable<BrowserProfile> _chromium(SourceBrowser browser, String installRoot) {
    final userData = Directory(p.join(installRoot, 'User Data'));
    if (!userData.existsSync()) return const [];
    final out = <BrowserProfile>[];
    for (final entry in userData.listSync().whereType<Directory>()) {
      final name = p.basename(entry.path);
      final isProfile =
          name == 'Default' ||
          name.startsWith('Profile ') ||
          name == 'Guest Profile';
      if (!isProfile) continue;
      // Require a Preferences or Bookmarks file so empty dirs are skipped.
      final hasData =
          File(p.join(entry.path, 'Preferences')).existsSync() ||
          File(p.join(entry.path, 'Bookmarks')).existsSync();
      if (!hasData) continue;
      out.add(
        BrowserProfile(browser: browser, name: name, path: entry.path),
      );
    }
    return out;
  }

  Iterable<BrowserProfile> _firefox(String installRoot) {
    final profiles = Directory(p.join(installRoot, 'Profiles'));
    if (!profiles.existsSync()) return const [];
    final out = <BrowserProfile>[];
    for (final entry in profiles.listSync().whereType<Directory>()) {
      if (!File(p.join(entry.path, 'places.sqlite')).existsSync()) continue;
      // Folder names look like "xxxxxxxx.default-release"; show the suffix.
      final base = p.basename(entry.path);
      final dot = base.indexOf('.');
      final name = dot >= 0 && dot + 1 < base.length
          ? base.substring(dot + 1)
          : base;
      out.add(
        BrowserProfile(
          browser: SourceBrowser.firefox,
          name: name,
          path: entry.path,
        ),
      );
    }
    return out;
  }
}
