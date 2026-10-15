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
