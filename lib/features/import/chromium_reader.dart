import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'import_models.dart';

/// Reads bookmarks and the installed-extension list from a Chromium-based
/// profile (Chrome, Edge, Brave). Pure file parsing — no decryption here.
class ChromiumReader {
  const ChromiumReader(this.profilePath);

  final String profilePath;

  // ---- bookmarks ----

  /// Parses `<profile>/Bookmarks` (JSON). Returns an empty list if the file is
  /// missing; throws [FormatException] if present but malformed.
  List<ImportedBookmark> readBookmarks() {
    final file = File(p.join(profilePath, 'Bookmarks'));
    if (!file.existsSync()) return const [];
    return parseBookmarksJson(file.readAsStringSync());
  }

  /// Exposed for tests: parse the Chromium Bookmarks JSON string.
  static List<ImportedBookmark> parseBookmarksJson(String source) {
    final data = jsonDecode(source);
    if (data is! Map || data['roots'] is! Map) {
      throw const FormatException('Not a Chromium Bookmarks file');
    }
    final out = <ImportedBookmark>[];
    final roots = data['roots'] as Map;
    for (final root in roots.values) {
      if (root is Map) _walk(root, null, out);
    }
    return out;
  }

  static void _walk(Map node, String? folder, List<ImportedBookmark> out) {
    final type = node['type'];
    if (type == 'url') {
      final url = node['url'];
      if (url is String && url.isNotEmpty) {
        out.add(
          ImportedBookmark(
            url: url,
            title: (node['name'] as String?) ?? url,
            folder: folder,
          ),
        );
      }
    } else if (type == 'folder' && node['children'] is List) {
      final name = node['name'] as String?;
      final child = (folder == null || folder.isEmpty) ? name : '$folder/$name';
      for (final c in node['children'] as List) {
        if (c is Map) _walk(c, child, out);
      }
    }
  }

  // ---- extensions (list only) ----

  /// Reads the installed-extension list by merging `Preferences` and
  /// `Secure Preferences`. Component/default/theme extensions are skipped.
  List<ImportedExtension> readExtensions() {
    final merged = <String, ImportedExtension>{};
    for (final name in const ['Preferences', 'Secure Preferences']) {
      final file = File(p.join(profilePath, name));
      if (!file.existsSync()) continue;
      for (final e in parseExtensionPrefs(file.readAsStringSync())) {
        merged[e.id] = e;
      }
    }
    final list = merged.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Exposed for tests: parse a Chromium (Secure) Preferences JSON string into
  /// the user-installed extension list.
  static List<ImportedExtension> parseExtensionPrefs(String source) {
    final data = jsonDecode(source);
    final settings = (data is Map ? data['extensions'] : null) is Map
        ? ((data['extensions'] as Map)['settings'])
        : null;
    if (settings is! Map) return const [];

    final out = <ImportedExtension>[];
    settings.forEach((id, value) {
      if (id is! String || value is! Map) return;
      // location: 5 = component, 10 = external component — not user extensions.
      final location = value['location'];
      if (location == 5 || location == 10) return;
      final manifest = value['manifest'];
      if (manifest is! Map) return; // no manifest → not a real extension
      if (manifest['theme'] != null) return; // themes, not extensions

      var name = (manifest['name'] as String?)?.trim() ?? '';
      if (name.isEmpty || name.startsWith('__MSG_')) {
        name = id; // honest fallback rather than a placeholder token
      }
      final state = value['state'];
      out.add(
        ImportedExtension(
          id: id,
          name: name,
          version: manifest['version'] as String?,
          enabled: state == null || state == 1,
          webStoreUrl: 'https://chromewebstore.google.com/detail/$id',
        ),
      );
    });
    return out;
  }
}
