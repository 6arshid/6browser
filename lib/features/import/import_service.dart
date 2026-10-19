import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/database.dart';
import 'chromium_crypto.dart';
import 'chromium_reader.dart';
import 'firefox_reader.dart';
import 'import_models.dart';
import 'sqlite_copy.dart';

/// Reads a browser profile into an in-memory [ProfileImport] and applies the
/// selected parts to our own database.
class ImportService {
  const ImportService(this.db);

  final AppDatabase db;

  /// Reads everything we can from [profile]. Never throws: unreadable
  /// categories are reported as [ImportIssue]s so the UI can stay honest.
  ProfileImport read(BrowserProfile profile) {
    final bookmarks = <ImportedBookmark>[];
    final logins = <ImportedLogin>[];
    final extensions = <ImportedExtension>[];
    final issues = <ImportIssue>[];

    if (profile.browser.isChromium) {
      final reader = ChromiumReader(profile.path);
      _guard(
        issues,
        'Bookmarks',
        () => bookmarks.addAll(reader.readBookmarks()),
      );
      _guard(
        issues,
        'Extensions',
        () => extensions.addAll(reader.readExtensions()),
      );
      _guard(
        issues,
        'Passwords',
        () => logins.addAll(_readChromiumLogins(profile, issues)),
      );
    } else {
      final reader = FirefoxReader(profile.path);
      _guard(
        issues,
        'Bookmarks',
        () => bookmarks.addAll(reader.readBookmarks()),
      );
      _guard(
        issues,
        'Extensions',
        () => extensions.addAll(reader.readExtensions()),
      );
      final count = reader.loginCount();
      if (count > 0) {
        issues.add(
          ImportIssue(
            'Passwords',
            '$count saved logins found, but Firefox password decryption '
                '(NSS / key4.db) is not supported yet.',
          ),
        );
      }
    }

    return ProfileImport(
      profile: profile,
      bookmarks: bookmarks,
      logins: logins,
      extensions: extensions,
      issues: issues,
    );
  }

  List<ImportedLogin> _readChromiumLogins(
    BrowserProfile profile,
    List<ImportIssue> issues,
  ) {
    final loginData = File(p.join(profile.path, 'Login Data'));
    if (!loginData.existsSync()) return const [];
    if (!Platform.isWindows) {
      issues.add(
        const ImportIssue(
          'Passwords',
          'Chromium password decryption is only supported on Windows.',
        ),
      );
      return const [];
    }
    final userData = p.dirname(profile.path);
    final decryptor = ChromiumDecryptor.forUserData(userData);
    return withSqliteCopy(loginData.path, (sdb) {
      final out = <ImportedLogin>[];
      final rows = sdb.select(
        'SELECT origin_url, username_value, password_value FROM logins',
      );
      for (final row in rows) {
        final pwd = row['password_value'];
        final clear = pwd is List<int> ? decryptor.decrypt(pwd) : '';
        if (clear.isEmpty) continue;
        out.add(
          ImportedLogin(
            url: (row['origin_url'] as String?) ?? '',
            username: (row['username_value'] as String?) ?? '',
            password: clear,
          ),
        );
      }
      return out;
    });
  }

  /// Inserts [bookmarks] into our Bookmarks table (duplicates ignored by URL).
  /// Returns the number inserted.
  Future<int> importBookmarks(List<ImportedBookmark> bookmarks) async {
    if (bookmarks.isEmpty) return 0;
    return db.addBookmarks([
      for (final b in bookmarks) (url: b.url, title: b.title),
    ]);
  }

  void _guard(List<ImportIssue> issues, String category, void Function() body) {
    try {
      body();
    } catch (e) {
      issues.add(ImportIssue(category, 'Could not read $category: $e'));
    }
  }
}
