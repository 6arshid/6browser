import 'package:browser6/data/database.dart';
import 'package:browser6/features/downloads/download_utils.dart';
import 'package:browser6/features/downloads/downloads_page.dart';
import 'package:browser6/features/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Download dl(int got, int total) => Download(
  id: 1,
  url: 'u',
  fileName: 'f',
  path: 'p',
  receivedBytes: got,
  totalBytes: total,
  state: 'inProgress',
  startedAt: DateTime(2026),
);

void main() {
  group('AppSettings.fromMap', () {
    test('defaults for empty map', () {
      final s = AppSettings.fromMap({});
      expect(s.themeMode, ThemeMode.system);
      expect(s.homeUrl, defaultHomeUrl);
      expect(s.searchTemplate, contains('%s'));
    });

    test('reads valid values', () {
      final s = AppSettings.fromMap({
        'themeMode': 'dark',
        'searchTemplate': 'https://duckduckgo.com/?q=%s',
        'homeUrl': ' https://example.com ',
      });
      expect(s.themeMode, ThemeMode.dark);
      expect(s.searchTemplate, 'https://duckduckgo.com/?q=%s');
      expect(s.homeUrl, 'https://example.com');
    });

    test('rejects a search template without %s and a bad theme', () {
      final s = AppSettings.fromMap({
        'themeMode': 'neon',
        'searchTemplate': 'https://nope.com/?q=',
      });
      expect(s.themeMode, ThemeMode.system);
      expect(s.searchTemplate, AppSettings.defaults.searchTemplate);
    });
  });

  test('fileNameOf handles Windows and POSIX paths', () {
    expect(fileNameOf(r'C:\Users\me\Downloads\a.zip', fallback: 'x'), 'a.zip');
    expect(fileNameOf('/home/me/a.zip', fallback: 'x'), 'a.zip');
    expect(fileNameOf('', fallback: 'x'), 'x');
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    expect(formatBytes(300 * 1024 * 1024), '300 MB');
  });

  test('downloadProgress', () {
    expect(downloadProgress(dl(50, 100)), 0.5);
    expect(downloadProgress(dl(5, -1)), isNull);
    expect(downloadProgress(dl(200, 100)), 1.0);
  });
}
