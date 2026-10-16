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
    r'<H3[^>]*>(.*?)</H3>'
    r'|<A\s[^>]*?HREF\s*=\s*"([^"]*)"[^>]*>(.*?)</A>'
    r'|<DL\b'
    r'|</DL>',
    caseSensitive: false,
    dotAll: true,
  );

  /// Exposed for tests: parse the Netscape bookmarks HTML format.
  static List<ImportedBookmark> parseNetscapeHtml(String source) {
    final out = <ImportedBookmark>[];
    // One entry per open <DL>; null for lists that aren't a named folder.
    final stack = <String?>[];
    String? pendingFolder;
    for (final m in _token.allMatches(source)) {
      final text = m.group(0)!;
      if (m.group(1) != null) {
        pendingFolder = _clean(m.group(1)!);
      } else if (m.group(2) != null) {
        final url = _decode(m.group(2)!.trim());
        // Firefox smart folders ("place:...") and bookmarklets aren't pages.
        if (url.isEmpty ||
            url.startsWith('place:') ||
            url.startsWith('javascript:')) {
          continue;
        }
        final title = _clean(m.group(3)!);
        final path = stack.whereType<String>().join('/');
        out.add(
          ImportedBookmark(
            url: url,
            title: title.isEmpty ? url : title,
            folder: path.isEmpty ? null : path,
          ),
        );
      } else if (text.startsWith('</')) {
        if (stack.isNotEmpty) stack.removeLast();
      } else {
        stack.add(pendingFolder);
        pendingFolder = null;
      }
    }
    return out;
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
