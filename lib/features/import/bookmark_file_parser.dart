import 'chromium_reader.dart';
import 'import_models.dart';

/// Parses a bookmarks file the user exported from another browser.
///
/// Accepts the Netscape `bookmarks.html` format (Chrome, Edge, Brave, Firefox,
/// Safari and Samsung Internet all export it) and a raw Chromium `Bookmarks`
/// JSON file. This is the only import path on mobile, where the OS sandbox
/// keeps us from reading other apps' profiles directly.
class BookmarkFileParser {
  const BookmarkFileParser._();

  /// Throws [FormatException] when [source] is neither format.
  static List<ImportedBookmark> parse(String source) {
    final trimmed = source.trimLeft();
    if (trimmed.startsWith('{')) {
      return ChromiumReader.parseBookmarksJson(trimmed);
    }
    if (!_looksLikeNetscape(trimmed)) {
      throw const FormatException('Not a bookmarks HTML or JSON file');
    }
    return parseNetscapeHtml(trimmed);
  }

  static bool _looksLikeNetscape(String s) {
    final head = s.length > 2000 ? s.substring(0, 2000) : s;
    return head.contains(
          RegExp('NETSCAPE-Bookmark-file', caseSensitive: false),
        ) ||
        RegExp(r'<DL', caseSensitive: false).hasMatch(s);
  }

  static final _token = RegExp(
    r'<H3([^>]*)>(.*?)</H3>'
    r'|<A\s[^>]*?HREF\s*=\s*"([^"]*)"[^>]*>(.*?)</A>'
    r'|<DL\b'
    r'|</DL>',
    caseSensitive: false,
    dotAll: true,
  );

  static bool _flag(String attributes, String name) =>
      RegExp('$name\\s*=\\s*"true"', caseSensitive: false).hasMatch(attributes);

  /// Exposed for tests: parse the Netscape bookmarks HTML format.
  ///
  /// The folder marked PERSONAL_TOOLBAR_FOLDER is the bookmarks bar. Chrome,
  /// Edge and Firefox list the rest of the bookmarks outside it; those go
  /// into an "Other bookmarks" folder (Firefox's own UNFILED folder becomes
  /// that folder).
  static List<ImportedBookmark> parseNetscapeHtml(String source) {
    final found = <({String url, String title, List<String> path, bool bar})>[];
    var hasBar = false;
    // One entry per open <DL>; null for lists that aren't a named folder.
    final stack = <_Folder?>[];
    _Folder? pending;
    for (final m in _token.allMatches(source)) {
      final text = m.group(0)!;
      if (m.group(2) != null) {
        final attributes = m.group(1)!;
        final bar = _flag(attributes, 'PERSONAL_TOOLBAR_FOLDER');
        hasBar |= bar;
        pending = _Folder(
          _clean(m.group(2)!),
          bar: bar,
          other: _flag(attributes, 'UNFILED_BOOKMARKS_FOLDER'),
        );
      } else if (m.group(3) != null) {
        final url = _decode(m.group(3)!.trim());
        // Firefox smart folders ("place:...") and bookmarklets aren't pages.
        if (url.isEmpty ||
            url.startsWith('place:') ||
            url.startsWith('javascript:')) {
          continue;
        }
        final title = _clean(m.group(4)!);
        final path = <String>[];
        var bar = false;
        for (final f in stack.nonNulls) {
          if (f.bar) {
            bar = true;
            path.clear();
          } else if (f.other) {
            path
              ..clear()
              ..add(otherBookmarksFolder);
          } else if (f.name.isNotEmpty) {
            path.add(f.name);
          }
        }
        found.add((
          url: url,
          title: title.isEmpty ? url : title,
          path: path,
          bar: bar,
        ));
      } else if (text.startsWith('</')) {
        if (stack.isNotEmpty) stack.removeLast();
      } else {
        stack.add(pending);
        pending = null;
      }
    }
    return [
      for (final f in found)
        ImportedBookmark(
          url: f.url,
          title: f.title,
          folders:
              !hasBar || f.bar || f.path.firstOrNull == otherBookmarksFolder
              ? f.path
              : [otherBookmarksFolder, ...f.path],
        ),
    ];
  }

  static String _clean(String html) =>
      _decode(html.replaceAll(RegExp(r'<[^>]*>'), '')).trim();

  static String _decode(String s) => s.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);'),
    (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x')) {
        return String.fromCharCode(int.parse(e.substring(2), radix: 16));
      }
      if (e.startsWith('#')) {
        return String.fromCharCode(int.parse(e.substring(1)));
      }
      return const {
        'amp': '&',
        'lt': '<',
        'gt': '>',
        'quot': '"',
        'apos': "'",
        'nbsp': ' ',
      }[e]!;
    },
  );
}

/// A folder (`<H3>`) of a bookmarks HTML file.
class _Folder {
  const _Folder(this.name, {this.bar = false, this.other = false});

  final String name;

  /// The browser's bookmarks bar (PERSONAL_TOOLBAR_FOLDER).
  final bool bar;

  /// Firefox's "Other Bookmarks" (UNFILED_BOOKMARKS_FOLDER).
  final bool other;
}
