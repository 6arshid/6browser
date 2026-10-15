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

  static List<ImportedBookmark> _queryBookmarks(Database db) {
    // moz_bookmarks.type 1 = bookmark, 2 = folder. Resolve the folder chain
    // through parent ids.
    final folders = <int, _Folder>{};
    for (final row in db.select(
      'SELECT id, parent, title, type FROM moz_bookmarks',
    )) {
      final id = row['id'] as int;
      if ((row['type'] as int) == 2) {
        folders[id] = _Folder(row['parent'] as int, row['title'] as String?);
      }
    }
    String? folderPath(int parent) {
      final parts = <String>[];
      var cur = parent;
      var guard = 0;
      while (folders.containsKey(cur) && guard++ < 32) {
        final f = folders[cur]!;
        final name = f.title;
        // Skip Firefox root containers that have no user-facing name.
        if (name != null && name.isNotEmpty) parts.insert(0, name);
        cur = f.parent;
      }
      return parts.isEmpty ? null : parts.join('/');
    }

    final out = <ImportedBookmark>[];
    final rows = db.select(
      'SELECT b.title AS title, b.parent AS parent, p.url AS url '
      'FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id '
      "WHERE b.type = 1 AND p.url LIKE 'http%'",
    );
    for (final row in rows) {
      final url = row['url'] as String;
      out.add(
        ImportedBookmark(
          url: url,
          title: (row['title'] as String?)?.trim().isNotEmpty == true
              ? row['title'] as String
              : url,
          folder: folderPath(row['parent'] as int),
        ),
      );
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

class _Folder {
  const _Folder(this.parent, this.title);
  final int parent;
  final String? title;
}
