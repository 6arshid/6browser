import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'import_models.dart';
import 'sqlite_copy.dart';

/// Reads bookmarks and the installed-extension list from a Firefox profile.
///
/// Firefox saved logins (`logins.json` + `key4.db`) are encrypted through NSS
/// and are intentionally **not** decrypted here — see [loginCount]/the import
/// service, which reports them as unsupported rather than faking values.
class FirefoxReader {
  const FirefoxReader(this.profilePath);

  final String profilePath;

  // ---- bookmarks ----

  List<ImportedBookmark> readBookmarks() {
    final src = File(p.join(profilePath, 'places.sqlite'));
    if (!src.existsSync()) return const [];
    return withSqliteCopy(src.path, (db) => _queryBookmarks(db));
  }

  /// Firefox's root folders by guid, and where their contents go: the
  /// toolbar is the bookmarks bar, the others become folders on it. Tags
  /// (folders of bookmark copies) are left out.
  static const _roots = [
    ('toolbar_____', <String>[]),
    ('menu________', ['Bookmarks Menu']),
    ('unfiled_____', [otherBookmarksFolder]),
    ('mobile______', ['Mobile Bookmarks']),
  ];

  static List<ImportedBookmark> _queryBookmarks(Database db) {
    // moz_bookmarks.type 1 = bookmark, 2 = folder; position orders the
    // items of a folder.
    final rows = db.select(
      'SELECT b.id AS id, b.type AS type, b.parent AS parent, '
      'b.title AS title, b.guid AS guid, p.url AS url '
      'FROM moz_bookmarks b LEFT JOIN moz_places p ON b.fk = p.id '
      'ORDER BY b.parent, b.position, b.id',
    );
    final children = <int, List<Row>>{};
    final roots = <String, int>{};
    for (final row in rows) {
      (children[row['parent'] as int] ??= []).add(row);
      if (row['guid'] case final String guid) roots[guid] = row['id'] as int;
    }
    final out = <ImportedBookmark>[];
    void walk(int folder, List<String> path) {
      if (path.length > 32) return;
      for (final row in children[folder] ?? const <Row>[]) {
        final title = (row['title'] as String?)?.trim() ?? '';
        switch (row['type']) {
          case 1:
            final url = row['url'] as String?;
            if (url == null || !url.startsWith('http')) continue;
            out.add(
              ImportedBookmark(
                url: url,
                title: title.isEmpty ? url : title,
                folders: path,
              ),
            );
          case 2:
            walk(row['id'] as int, [...path, title.isEmpty ? 'Folder' : title]);
        }
      }
    }

    for (final (guid, path) in _roots) {
      if (roots[guid] case final id?) walk(id, path);
    }
    return out;
  }

  // ---- extensions (list only) ----

  List<ImportedExtension> readExtensions() {
    final file = File(p.join(profilePath, 'extensions.json'));
    if (!file.existsSync()) return const [];
    return parseExtensionsJson(file.readAsStringSync());
  }

  /// Exposed for tests: parse Firefox `extensions.json`.
  static List<ImportedExtension> parseExtensionsJson(String source) {
    final data = jsonDecode(source);
    final addons = (data is Map ? data['addons'] : null);
    if (addons is! List) return const [];
    final out = <ImportedExtension>[];
    for (final a in addons) {
      if (a is! Map) continue;
      if (a['type'] != 'extension') continue;
      final location = a['location'];
      if (location != 'app-profile' && location != null) continue;
      final id = a['id'] as String?;
      if (id == null) continue;
      final name =
          ((a['defaultLocale'] as Map?)?['name'] as String?)?.trim() ?? id;
      out.add(
        ImportedExtension(
          id: id,
          name: name.isEmpty ? id : name,
          version: a['version'] as String?,
          enabled: a['active'] == true,
        ),
      );
    }
    out.sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
    return out;
  }

  /// Number of saved logins (for an honest "N found, decryption unsupported"
  /// message). Returns 0 when there is no logins file.
  int loginCount() {
    final file = File(p.join(profilePath, 'logins.json'));
    if (!file.existsSync()) return 0;
    try {
      final data = jsonDecode(file.readAsStringSync());
      final logins = (data is Map ? data['logins'] : null);
      return logins is List ? logins.length : 0;
    } catch (_) {
      return 0;
    }
  }
}
