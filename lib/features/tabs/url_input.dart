/// Default search URL template; `%s` is replaced by the encoded query.
const defaultSearchTemplate = 'https://www.google.com/search?q=%s';

final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
final _hostLike = RegExp(
  r'^(localhost|[\w-]+(\.[\w-]+)+|\d{1,3}(\.\d{1,3}){3})(:\d+)?([/?#].*)?$',
);

/// Turns whatever the user typed in the address bar into a loadable URL:
/// full URLs pass through, host-like text gets `https://`, anything else
/// becomes a search query.
String resolveInput(
  String input, {
  String searchTemplate = defaultSearchTemplate,
}) {
  final text = input.trim();
  if (text.isEmpty) return 'about:blank';
  if (_scheme.hasMatch(text) || text.startsWith('about:')) return text;
  if (!text.contains(' ') && _hostLike.hasMatch(text)) return 'https://$text';
  return searchTemplate.replaceAll('%s', Uri.encodeQueryComponent(text));
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
