import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../engine/browser_engine.dart';

/// Search result pages whose results voice commands can open by number
/// ("open the second link") and page through ("next page").
enum SearchSite {
  google('Google'),
  bing('Bing'),
  duckDuckGo('DuckDuckGo'),
  youtube('YouTube');

  const SearchSite(this.label);
  final String label;

  /// The site's results page that [url] shows, or null.
  static SearchSite? of(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('https') && !uri.isScheme('http')) {
      return null;
    }
    final host = uri.host.toLowerCase();
    final query = uri.queryParameters;
    bool hasQuery(String name) => (query[name] ?? '').trim().isNotEmpty;
    if (_googleHost.hasMatch(host) && uri.path == '/search' && hasQuery('q')) {
      return google;
    }
    if (host == 'www.bing.com' || host == 'bing.com') {
      return uri.path == '/search' && hasQuery('q') ? bing : null;
    }
    if (host == 'duckduckgo.com' || host == 'www.duckduckgo.com') {
      return (uri.path == '/' || uri.path.isEmpty) && hasQuery('q')
          ? duckDuckGo
          : null;
    }
    if (host == 'www.youtube.com' ||
        host == 'youtube.com' ||
        host == 'm.youtube.com') {
      return uri.path == '/results' && hasQuery('search_query')
          ? youtube
          : null;
    }
    return null;
  }

  /// CSS selector for the elements of the results, in page order. The
  /// link is the element or the closest link around it.
  String get resultSelector => switch (this) {
    // Titles are an <h3> inside the link; ads (#tads, #bottomads) are
    // outside #search.
    google => '#search a h3',
    // Ads are li.b_ad.
    bing => '#b_results > li.b_algo h2 a',
    duckDuckGo =>
      'article[data-testid="result"] a[data-testid="result-title-a"]',
    // Videos only: not Shorts, channels or playlists.
    youtube => 'ytd-search ytd-video-renderer a#video-title',
  };
}

final _googleHost = RegExp(r'^(?:www\.)?google\.[a-z]{2,3}(?:\.[a-z]{2})?$');

/// Results per page, as the sites page them.
const _perPage = 10;

/// The page of search results [step] pages on from [url] (-1 back), or
/// page [number]; null when [url]'s site does not page by address
/// (DuckDuckGo and YouTube load more results on the same page) or there is
/// no such page.
String? resultsPageUrl(String url, {int step = 0, int? number}) {
  final site = SearchSite.of(url);
  final uri = Uri.parse(url);
  final query = Map<String, String>.of(uri.queryParameters);
  // Google numbers results from 0 ("start"), Bing from 1 ("first").
  final (String param, int base) = switch (site) {
    SearchSite.google => ('start', 0),
    SearchSite.bing => ('first', 1),
    _ => ('', 0),
  };
  if (param.isEmpty) return null;
  final perPage = site == SearchSite.google
      ? (int.tryParse(query['num'] ?? '') ?? _perPage).clamp(1, 100)
      : _perPage;
  final first = max(0, (int.tryParse(query[param] ?? '') ?? base) - base);
  final current = first ~/ perPage + 1;
  final page = number ?? current + step;
  if (page < 1 || page == current) return null;
  if (page == 1) {
    query.remove(param);
  } else {
    query[param] = '${(page - 1) * perPage + base}';
  }
  // Bing's FORM marks how the page was reached; it would be wrong now.
  if (site == SearchSite.bing) query.remove('FORM');
  return uri.replace(queryParameters: query).toString();
}

/// The page number [url] shows, 1 when it is not a paged results page.
int resultsPageNumber(String url) {
  final site = SearchSite.of(url);
  final query = Uri.parse(url).queryParameters;
  return switch (site) {
    SearchSite.google =>
      (int.tryParse(query['start'] ?? '') ?? 0) ~/
              (int.tryParse(query['num'] ?? '') ?? _perPage).clamp(1, 100) +
          1,
    SearchSite.bing =>
      max(0, (int.tryParse(query['first'] ?? '') ?? 1) - 1) ~/ _perPage + 1,
    _ => 1,
  };
}

/// Page script that finds result [number] (1-based) of [site] and sends
/// back `{t: token, count, url}` through [post] (the backend's function);
/// url is null when there are fewer results. Hidden results and repeats of
/// the same address are not counted.
String resultLinkScript({
  required SearchSite site,
  required int number,
  required String token,
  required String post,
}) =>
    '''
(function (selector, n, token, post) {
  var seen = {}, links = [];
  function shown(el) {
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 &&
        getComputedStyle(el).visibility !== 'hidden';
  }
  [].forEach.call(document.querySelectorAll(selector), function (el) {
    var a = el.closest('a[href]');
    if (!a || !shown(el)) return;
    var href = a.href;
    if (!/^https?:/i.test(href) || seen[href]) return;
    seen[href] = true;
    links.push(href);
  });
  try {
    post({t: token, count: links.length, url: links[n - 1] || null});
  } catch (e) {}
})(${jsonEncode(site.resultSelector)}, $number, ${jsonEncode(token)}, $post);
''';

/// Page script that presses DuckDuckGo's "More results" button and sends
/// back `{t: token, more: true|false}`.
String moreResultsScript({required String token, required String post}) =>
    '''
(function (token, post) {
  var button = document.querySelector('button#more-results');
  if (button) button.click();
  try { post({t: token, more: !!button}); } catch (e) {}
})(${jsonEncode(token)}, $post);
''';

final _random = Random.secure();

String _newToken() =>
    List.generate(24, (_) => _random.nextInt(16).toRadixString(16)).join();

/// Runs a script built by [script] (given a token and the post function)
/// in [view]'s page and returns the message it sends back, or null when
/// none arrives within [timeout] (the page has no scripts yet, or the
/// backend cannot send back).
Future<Map<String, Object?>?> askPage(
  BrowserView view,
  String Function(String token, String post) script, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final post = view.scriptPostFunction;
  if (post == null) return null;
  final token = _newToken();
  final reply = Completer<Map<String, Object?>?>();
  final sub = view.scriptMessages.listen((raw) {
    try {
      final message = (jsonDecode(raw) as Map).cast<String, Object?>();
      // Only the script just run knows the token.
      if (message['t'] == token && !reply.isCompleted) reply.complete(message);
    } on Object {
      // Someone else's message.
    }
  });
  final timer = Timer(timeout, () {
    if (!reply.isCompleted) reply.complete(null);
  });
  try {
    await view.runScript(script(token, post));
    return await reply.future;
  } finally {
    timer.cancel();
    // Not awaited: cancelling from a message just delivered can wait for
    // the next one.
    unawaited(sub.cancel());
  }
}

/// What looking for a numbered result found.
sealed class ResultLookup {
  const ResultLookup();
}

/// The result's address.
class ResultFound extends ResultLookup {
  const ResultFound(this.url);
  final String url;
}

/// The page has only [count] results.
class ResultMissing extends ResultLookup {
  const ResultMissing(this.count);
  final int count;
}

/// [view] is not a results page voice commands know.
class NotResultsPage extends ResultLookup {
  const NotResultsPage();
}

/// The page did not answer.
class PageSilent extends ResultLookup {
  const PageSilent();
}

/// Finds result [number] (1-based) on the results page [view] shows.
Future<ResultLookup> findResult(BrowserView view, int number) async {
  final site = SearchSite.of(view.url.value);
  if (site == null) return const NotResultsPage();
  final reply = await askPage(
    view,
    (token, post) =>
        resultLinkScript(site: site, number: number, token: token, post: post),
  );
  if (reply == null) return const PageSilent();
  final url = reply['url'];
  // Only web addresses: the page itself could have sent anything.
  if (url is String &&
      (url.startsWith('https://') || url.startsWith('http://'))) {
    return ResultFound(url);
  }
  final count = reply['count'];
  return ResultMissing(count is int ? count : 0);
}
