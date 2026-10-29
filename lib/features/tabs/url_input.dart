/// Default search URL template; `%s` is replaced by the encoded query.
const defaultSearchTemplate = 'https://www.google.com/search?q=%s';

final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

/// Schemes that are typed without `//`.
const _bareSchemes = ['about:', 'view-source:', 'data:', 'mailto:', 'chrome:'];

// A host and optional port, path, query or fragment. Labels may be in any
// script (IDN hosts such as ایران.ir); the top-level domain must be letters,
// so "v2.0" and "1.5" stay searches.
final _domain = RegExp(
  r'^[\p{L}\p{N}_-]+(?:\.[\p{L}\p{N}_-]+)*\.(\p{L}{2,63}|xn--[a-z0-9-]+)\.?(?::\d{1,5})?(?:[/?#].*)?$',
  unicode: true,
);
final _ipHost = RegExp(
  r'^(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:.]+\])(?::\d{1,5})?(?:[/?#].*)?$',
);
// localhost, or an intranet name followed by a port or a path ("nas:5000",
// "router/admin"), as Chrome treats them.
final _intranet = RegExp(
  r'^(?:localhost|[\p{L}\p{N}_-]+(?::\d{1,5}(?:[/?#].*)?|[/?#].*))$',
  unicode: true,
);
final _windowsPath = RegExp(r'^(?:[a-zA-Z]:[\\/]|\\\\[^\\])');

/// File names typed alone ("index.html", "node.js") are searches: these are
/// not top-level domains.
const _notTopLevelDomains = {
  'js', 'ts', 'html', 'htm', 'php', 'css', 'json', 'txt', 'py', 'exe', //
  'dll', 'jpg', 'jpeg', 'png', 'gif', 'pdf', 'doc', 'docx', 'xls', 'xlsx',
  'ppt', 'pptx', 'mp3', 'mp4', 'cpp', 'java', 'dart', 'yaml', 'yml', 'xml',
};

bool _looksLikeHost(String text) {
  if (_ipHost.hasMatch(text) || _intranet.hasMatch(text)) return true;
  final match = _domain.firstMatch(text);
  if (match == null) return false;
  // "index.html" alone is a file name; "example.com/index.html" is a URL.
  return !_notTopLevelDomains.contains(match.group(1)!.toLowerCase());
}

/// Turns whatever the user typed in the address bar into a loadable URL:
/// full URLs pass through, host-like text gets `http://`, anything else
/// becomes a search query.
///
/// Like Chrome's address bar, the engine then tries HTTPS first and falls
/// back to HTTP only when the site has no working HTTPS (Chromium's HTTPS
/// Upgrades on desktop, [httpsUpgradeOf] on Android). Sending `https://`
/// here instead made HTTP-only sites and local servers fail to load.
String resolveInput(
  String input, {
  String searchTemplate = defaultSearchTemplate,
}) {
  final text = input.trim();
  if (text.isEmpty) return 'about:blank';
  if (_scheme.hasMatch(text)) return text;
  final lower = text.toLowerCase();
  if (_bareSchemes.any(lower.startsWith)) return text;
  if (_windowsPath.hasMatch(text)) {
    return Uri.file(text, windows: true).toString();
  }
  if (!text.contains(RegExp(r'\s')) && _looksLikeHost(text)) {
    return 'http://$text';
  }
  return searchTemplate.replaceAll('%s', Uri.encodeQueryComponent(text));
}

final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
const _localSuffixes = [
  '.localhost',
  '.local',
  '.test',
  '.internal',
  '.lan',
  '.home.arpa',
];

/// The `https://` form of an `http://` [url] worth trying first, or null
/// when it should load as is. Mirrors Chromium's HTTPS Upgrades: local and
/// intranet hosts, IP addresses and non-default ports are left alone.
String? httpsUpgradeOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'http' || uri.hasPort && uri.port != 80) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty ||
      !host.contains('.') ||
      host.contains(':') ||
      _ipv4.hasMatch(host) ||
      _localSuffixes.any(host.endsWith)) {
    return null;
  }
  return uri.replace(scheme: 'https', port: 443).toString();
}

/// True when [url] is served over HTTPS (drives the lock indicator).
bool isSecureUrl(String url) => url.startsWith('https://');

/// True on the Chrome Web Store, where "Add to Chrome" cannot work in this
/// engine (see docs/ENGINE.md).
bool isWebStoreUrl(String url) =>
    url.startsWith('https://chromewebstore.google.com/') ||
    url.startsWith('https://chrome.google.com/webstore');

/// Only real web pages can be bookmarked (not blank/internal pages).
bool isBookmarkable(String url) =>
    url.startsWith('http://') || url.startsWith('https://');

/// Address of the built-in New Tab page. The engine shows a blank page and
/// the app draws the New Tab UI on top of it.
const newTabUrl = 'about:blank';

/// True while a tab shows the New Tab page.
bool isNewTabUrl(String url) => url.isEmpty || url == newTabUrl;

/// Short form of [url] for an unfocused address bar on small screens, like
/// Chrome on Android: just the host, without `www.`. Non-web addresses are
/// shown as they are.
String displayHost(String url) {
  if (!isBookmarkable(url)) return url;
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return url;
  return host.startsWith('www.') ? host.substring(4) : host;
}
