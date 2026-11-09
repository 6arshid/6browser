import '../../ui/browser_commands.dart';
import '../tabs/url_input.dart';

/// Languages whose commands are understood (Whisper codes). In others,
/// what is said is searched for.
const commandLanguages = {'en', 'fa', 'da'};

/// What a spoken command asks the browser to do.
sealed class VoiceAction {
  const VoiceAction();
}

/// Load [url]: a search or a site, in a new tab when [newTab].
class VoiceNavigate extends VoiceAction {
  const VoiceNavigate(this.url, {this.newTab = false});

  final String url;
  final bool newTab;

  @override
  String toString() => 'VoiceNavigate($url${newTab ? ', new tab' : ''})';
}

/// Run a browser command: new tab, back, history...
class VoiceRunCommand extends VoiceAction {
  const VoiceRunCommand(this.command);

  final BrowserCommand command;

  @override
  String toString() => 'VoiceRunCommand(${command.name})';
}

/// Open result [number] (1-based) of the search results on the page ("open
/// the second link", «لینک دوم گوگل رو باز کن»), in a new tab when
/// [newTab].
class VoiceOpenResult extends VoiceAction {
  const VoiceOpenResult(this.number, {this.newTab = false});

  final int number;
  final bool newTab;

  @override
  String toString() => 'VoiceOpenResult($number${newTab ? ', new tab' : ''})';
}

/// Another page of search results: [step] pages on (-1 back), or page
/// [number]. On a page that is not search results [otherwise] runs instead
/// (a plain "next page" means Forward there); without it nothing happens.
class VoiceResultsPage extends VoiceAction {
  const VoiceResultsPage({this.step = 0, this.number, this.otherwise});

  final int step;
  final int? number;
  final BrowserCommand? otherwise;

  @override
  String toString() =>
      'VoiceResultsPage(${number != null ? 'page $number' : 'step $step'}'
      '${otherwise != null ? ', else ${otherwise!.name}' : ''})';
}

/// Which way to scroll the page.
enum ScrollMove {
  /// About a screen down.
  down,

  /// About a screen up.
  up,

  /// To the top of the page.
  top,

  /// To the bottom of the page.
  bottom,
}

/// Scroll the page ("scroll", "scroll up", «برو پایین», "rul ned", "nach
/// unten scrollen", "scroll to the top").
class VoiceScroll extends VoiceAction {
  const VoiceScroll(this.move);

  final ScrollMove move;

  @override
  String toString() => 'VoiceScroll(${move.name})';
}

/// Stop listening for voice commands ("stop listening", «دیگه گوش نده»).
class VoiceStopListening extends VoiceAction {
  const VoiceStopListening();

  @override
  String toString() => 'VoiceStopListening';
}

/// Turns what was heard ("search Iran", «جستجو کن ایران», "open YouTube",
/// «برو به یوتیوب», "new tab", "open the second link"...) into an action.
/// Anything else is treated like text typed in the address bar: a search,
/// or a site when it names one; without [searchFreeText] only an address
/// is, and other words give null. Null also when nothing usable was said
/// (silence, or just "search" with no words to search for).
VoiceAction? parseVoiceCommand(
  String heard, {
  String searchTemplate = defaultSearchTemplate,
  bool searchFreeText = true,
}) {
  var text = _withoutFillers(normalizeSpeech(heard));
  if (text.isEmpty) return null;

  var newTab = false;
  final withoutNewTab = text
      .replaceAll(_inNewTab, ' ')
      .replaceAll(_spaces, ' ')
      .trim();
  if (withoutNewTab != text && withoutNewTab.isNotEmpty) {
    newTab = true;
    text = withoutNewTab;
  }

  if (_stopListening.hasMatch(text)) return const VoiceStopListening();
  // Before pages of results: «اول صفحه» is the top of the page, not page
  // one.
  if (_scrollMove(text) case final move?) return VoiceScroll(move);
  if (_resultsPage(text) case final page?) return page;
  if (_resultNumber(text) case final number?) {
    return VoiceOpenResult(number, newTab: newTab);
  }

  for (final (pattern, command) in _commands) {
    if (pattern.hasMatch(text)) return VoiceRunCommand(command);
  }
  if (_bareVerbs.hasMatch(text)) return null;

  VoiceNavigate go(String url) => VoiceNavigate(url, newTab: newTab);
  String search(String query) =>
      searchTemplate.replaceAll('%s', Uri.encodeQueryComponent(query));

  // A site's name alone ("YouTube", «یوتیوب», "Google Maps") opens it.
  final named = _siteNamed(text);
  if (named != null) return go(named.url);

  for (final pattern in _siteSearches) {
    final m = pattern.firstMatch(text);
    if (m == null) continue;
    // "play ..." without a site searches YouTube.
    final siteName = m.groupNames.contains('site')
        ? m.namedGroup('site')
        : null;
    final site = _siteNamed(siteName ?? 'youtube')!;
    final query = _cleanQuery(m.namedGroup('q')!);
    if (query.isEmpty) return go(site.url);
    return go(site.searchUrl(query));
  }
  for (final pattern in _searches) {
    final m = pattern.firstMatch(text);
    if (m == null) continue;
    final query = _cleanQuery(m.namedGroup('q')!);
    if (query.isEmpty) return null;
    return go(search(query));
  }
  for (final pattern in _opens) {
    final m = pattern.firstMatch(text);
    if (m == null) continue;
    final target = _cleanQuery(m.namedGroup('t')!);
    if (target.isEmpty) return null;
    return go(
      _siteNamed(target)?.url ?? _spokenAddress(target) ?? search(target),
    );
  }

  // "Scroll" in a language without its own words for it. Last, so that
  // "search scroll saw" stays a search.
  if (_scrollAnyLanguage(text) case final move?) return VoiceScroll(move);

  // No command: like typing in the address bar.
  final url = resolveInput(text, searchTemplate: searchTemplate);
  if (!searchFreeText && url == search(text)) return null;
  return go(url);
}

/// 1 to 10 in words, as ordinals and as numbers, in English, Persian and
/// Danish. Persian ordinals also take -ین before the noun («دومین لینک»).
const _numberWords = <String, int>{
  'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5, //
  'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9, 'tenth': 10,
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'top': 1,
  'اول': 1, 'اولی': 1, 'یکم': 1, 'یکمی': 1, 'نخست': 1, 'یک': 1,
  'دوم': 2, 'دومی': 2, 'دو': 2,
  'سوم': 3, 'سومی': 3, 'سیوم': 3, 'سه': 3,
  'چهارم': 4, 'چهارمی': 4, 'چهار': 4,
  'پنجم': 5, 'پنجمی': 5, 'پنج': 5,
  'ششم': 6, 'ششمی': 6, 'شیشم': 6, 'شش': 6, 'شیش': 6,
  'هفتم': 7, 'هفتمی': 7, 'هفت': 7,
  'هشتم': 8, 'هشتمی': 8, 'هشت': 8,
  'نهم': 9, 'نهمی': 9, 'نه': 9,
  'دهم': 10, 'دهمی': 10, 'ده': 10,
  'første': 1, 'anden': 2, 'andet': 2, 'tredje': 3, 'fjerde': 4,
  'femte': 5, 'sjette': 6, 'syvende': 7, 'ottende': 8, 'niende': 9,
  'tiende': 10,
  'en': 1, 'et': 1, 'to': 2, 'tre': 3, 'fire': 4, 'fem': 5, 'seks': 6,
  'syv': 7, 'otte': 8, 'ni': 9, 'ti': 10,
};

final _digitNumber = RegExp(r'^(\d{1,2})(?:st|nd|rd|th|م|ام|مین|ین)?$');

/// The number [word] says, 1 to 50, or null.
int? _number(String word) {
  final n =
      int.tryParse(_digitNumber.firstMatch(word)?.group(1) ?? '') ??
      _numberWords[word] ??
      (word.endsWith('ین')
          ? _numberWords[word.substring(0, word.length - 2)]
          : null);
  return n != null && n >= 1 && n <= 50 ? n : null;
}

final _stopListening = _full(
  'stop listening|stop (?:the )?voice(?: commands?| control)?|'
  'turn off (?:the )?(?:mic|microphone|voice(?: commands?| control)?)|'
  '(?:mic|microphone) off|close (?:the )?(?:mic|microphone|voice)|'
  '(?:دیگه |دیگر )?گوش (?:نده|نکن)|'
  '(?:میکروفون|میکروفن|میک)(?: رو| را)? (?:خاموش|ببند|قطع)(?: کن)?|'
  '(?:خاموش|قطع) کن (?:میکروفون|میکروفن|میک)|'
  'stop med at lytte|hold op med at lytte|'
  'sluk (?:for )?(?:mikrofonen|stemmestyring(?:en)?)',
);

// What a numbered result is called. Not "page" or «صفحه»: "second page"
// is a page of results.
const _resultNoun =
    '(?:links?|results?|search results?|sites?|websites?|videos?|options?|'
    'items?|entry|entries|hits?|one|'
    'لینک|نتیجه|سایت|ویدیو|ویدئو|ویدیوی|ویدئوی|کلیپ|گزینه|مورد|آیتم|'
    'linket|resultat|resultatet|søgeresultat|videoen)';
const _resultQualifier = '(?:google|youtube|bing|search|søge)';

/// Verbs around a numbered result, dropped: "open", «روی ... کلیک کن».
final _resultLead = RegExp(
  r'^(?:(?:open|click(?: on)?|go to|visit|play|watch|show(?: me)?|select|'
  r'choose|pick|take me to|tap(?: on)?|load|bring up|launch|'
  r'برو(?: به| تو| توی| روی| رو)?|بریم(?: به| تو)?|روی|کلیک کن(?: روی| رو)?|'
  r'بزن(?: روی| رو)?|باز کن|بازکن|پخش کن|پلی کن|اوپن|'
  r'åbn|klik på|gå til|gå ind på|vælg|afspil|vis(?: mig)?) )+',
  unicode: true,
);
final _resultTail = RegExp(
  r'(?: (?:رو|را|و|باز کن|بازش کن|بازکن|بیار|بالا بیار|نشون بده|نشان بده|'
  r'کلیک کن|بزن|پخش کن|پلی کن|اجرا کن|برو|اوپن کن|'
  // Where the result is: "on Google", «گوگل», «تو نتایج».
  r'(?:on|from|in|of|at) (?:the )?(?:google|bing|duckduckgo|duck duck go|'
  r'youtube|results|search results|search|search page|page|list)|'
  r'(?:(?:از|تو|توی|در|داخل) )?(?:گوگل|بینگ|یوتیوب|داک داک گو|نتایج|'
  r'نتیجه ها|جستجو|سرچ|صفحه|لیست)|'
  r'(?:på|fra|i) (?:google|bing|youtube|resultaterne|søgningen|siden|'
  r'listen)))+$',
  unicode: true,
);
final _resultPatterns = [
  // "the second link", "2nd google result", «دومین لینک», "det andet link"
  _full('(?:the |det |den )?(?<n>\\S+) (?:$_resultQualifier ?)?$_resultNoun'),
  // "link 2", "result number three", «لینک دوم», «لینک شماره دو»
  _full(
    '(?:$_resultQualifier )?$_resultNoun(?: ی)? '
    '(?:number |nummer |no |شماره |نمره )?(?<n>\\S+?)(?: ی| یی)?',
  ),
];

/// The number of the result asked for: "open the second link", «لینک دوم
/// گوگل رو باز کن», "åbn det tredje resultat"; null for anything else.
int? _resultNumber(String text) {
  final core = _strip(text, _resultLead, _resultTail);
  for (final pattern in _resultPatterns) {
    final n = pattern.firstMatch(core)?.namedGroup('n');
    if (n != null && _number(n) != null) return _number(n);
  }
  return null;
}

String _strip(String text, RegExp lead, RegExp tail) =>
    text.replaceFirst(lead, '').replaceFirst(tail, '').trim();

const _pageQualifierEn =
    '(?:the )?(?:google|bing|duckduckgo|duck duck go|youtube|results|'
    'search results|search|google results)';
const _pageQualifierFa =
    '(?:(?:از|تو|توی|در|داخل) )?(?:گوگل|بینگ|یوتیوب|داک داک گو|نتایج|'
    'نتیجه ها|جستجو|سرچ)';
const _pageQualifierDa =
    '(?:google|bing|youtube|resultaterne|søgningen|søgeresultaterne)';
const _page = '(?:صفحه(?: ی)?)';

final _pageLead = RegExp(
  r'^(?:(?:go to|go|show(?: me)?|open|load|take me to|'
  r'برو(?: به| تو)?|بریم(?: به| تو)?|'
  r'gå til|gå|vis(?: mig)?|åbn) )+',
  unicode: true,
);
final _pageTail = RegExp(
  r'(?: (?:رو|را|و|بیار|باز کن|بازکن|نشون بده|نشان بده|برو|بزن))+$',
  unicode: true,
);

/// "next page", «صفحه بعد»: the next results page, or Forward elsewhere.
final _nextPage = _full(
  '(?:the |den )?(?:next page|næste side)|$_page (?:بعد|بعدی)',
);

/// Explicitly about search results: "next page of results", «صفحه بعد
/// گوگل», «نتایج بعدی».
final _nextResults = _full(
  '(?:the )?next page (?:of|on|in) $_pageQualifierEn|'
  '(?:the )?next (?:page of )?(?:the )?(?:google |search )?results|'
  '(?:the )?next (?:google|bing|search|results) page|more results|'
  '$_page (?:بعد|بعدی)(?: ی)? $_pageQualifierFa|'
  '(?:نتایج|نتیجه ها)(?: ی)? (?:بعدی|بیشتر)|(?:بقیه|ادامه)(?: ی)? (?:نتایج|نتیجه ها)|'
  '(?:den )?næste side (?:af|med|i|på) $_pageQualifierDa|'
  '(?:flere|næste) (?:søge)?resultater',
);
final _previousResults = _full(
  '(?:the )?previous page (?:of|on|in) $_pageQualifierEn|'
  '(?:the )?previous (?:page of )?(?:the )?(?:google |search )?results|'
  '(?:the )?previous (?:google|bing|search|results) page|'
  '$_page (?:قبل|قبلی)(?: ی)? $_pageQualifierFa|(?:نتایج|نتیجه ها)(?: ی)? قبلی|'
  '(?:den )?forrige side (?:af|med|i|på) $_pageQualifierDa|'
  'forrige (?:søge)?resultater',
);
final _numberedPage = [
  // "page 2", "page number three of the results", «صفحه دوم گوگل»,
  // «صفحه شماره 3», "side 2"
  _full(
    '(?:the )?(?:page|side|$_page) (?:number |nummer |شماره )?(?<n>\\S+?)'
    '(?: ی)?(?: (?:of|on|in) $_pageQualifierEn| $_pageQualifierFa|'
    ' (?:af|i|på) $_pageQualifierDa)?',
  ),
  // "the second page", «دومین صفحه», "den anden side"
  _full(
    '(?:the |den )?(?<n>\\S+) (?:page|side|$_page)'
    '(?: (?:of|on|in) $_pageQualifierEn| $_pageQualifierFa|'
    ' (?:af|i|på) $_pageQualifierDa)?',
  ),
];

/// A page of search results: "next page of Google", «برو صفحه بعد گوگل»,
/// «صفحه سوم», "previous results"; null for anything else.
VoiceResultsPage? _resultsPage(String text) {
  final core = _strip(text, _pageLead, _pageTail);
  if (_nextPage.hasMatch(core)) {
    return const VoiceResultsPage(step: 1, otherwise: BrowserCommand.forward);
  }
  if (_nextResults.hasMatch(core)) return const VoiceResultsPage(step: 1);
  if (_previousResults.hasMatch(core)) return const VoiceResultsPage(step: -1);
  for (final pattern in _numberedPage) {
    final n = pattern.firstMatch(core)?.namedGroup('n');
    if (n != null && _number(n) != null) {
      return VoiceResultsPage(number: _number(n));
    }
  }
  return null;
}

// Scrolling the page and closing the browser are understood in English,
// Persian and Danish like every command, and also in the main other
// languages; and "scroll" is a loanword almost everywhere (see
// _scrollAnyLanguage).

const _aBitEn =
    '(?: (?:a (?:bit|little)(?: more)?|a little bit|some(?: more)?|more|'
    'further|again))?';
const _thePageEn = '(?: (?:the |this )?page| it)?';

const _scrollFa = '(?:اسکرول|اسکرال)';
const _downFa = '(?:پایین|پائین)(?: ?تر)?';
const _upFa = 'بالا(?: ?تر)?';
const _moveFa =
    '(?:برو|بیا|بریم|بکش|بکشش|ببر|ببرش|بده|بدش|بفرست|برو به|'
    '$_scrollFa(?: کن| بکن)?)';
const _aBitFa =
    '(?:(?:یکم|یه کم|یک کم|کمی|یه ذره|یه خورده|یکمی|باز|بازم|بیشتر) )?';
const _pageFa = '(?:صفحه$_object )?';

// Danish, Norwegian and Swedish.
const _scrollNordic =
    '(?:scroll|scrolle|scroller|scrolla|skrol|skrolle|skrolla|rul|rull|'
    'rulle|ruller|rulla|bladr|bladre|bläddra)';
const _downNordic = '(?:ned|nedad|nedover|ner|nedåt)';
const _upNordic = '(?:op|opad|opp|oppover|upp|uppåt)';
const _aBitNordic =
    '(?: (?:lidt|litt|lite|mere|mer|lidt mere|litt mer|lite till|længere|'
    'lengre|igen))?';
const _theSiteNordic = '(?: siden| sidan)?';
// "rul lidt ned"
const _littleNordic = '(?: (?:lidt|litt|lite))?';
const _ofTheSiteNordic = '(?: af siden| av siden| på sidan)?';

const _scrollDe =
    '(?:scroll|scrolle|scrollen|blättere|blätter|blättern|geh|gehe)';
const _scrollFr =
    '(?:fais |faire )?(?:défiler|défile|défilez|scroller|scrolle)'
    '(?: la page)?';
const _pageEs = '(?: la página| la pagina)?';
const _scrollEs =
    '(?:desplázate|desplazate|desplaza|desplazar|haz scroll)$_pageEs';
const _pagePt = '(?: a página| a pagina)?';
const _scrollPt = '(?:rolar|role|rola|deslize|deslizar|desliza)$_pagePt';
const _scrollIt = '(?:scorri|scorrere|scrolla|scrollare)(?: la pagina)?';
const _scrollNl = '(?:scroll|scrollen|scrol)';
const _scrollRu =
    '(?:прокрути|прокрутите|прокрутить|листай|листайте|пролистай|'
    'пролистайте|скролль|скрольни|гортай|прокрутіть)(?: страницу| сторінку)?';
const _scrollHi = 'स्क्र(?:ॉ|ो)ल(?: (?:करो|करें|कीजिए|कर दो))?';
const _scrollZh = '(?:滚动|滾動|滑动|滑動|滑|翻|拉)?(?:一下)?';
const _scrollJa = 'スクロール(?:して|する)?(?:ください)?';
const _scrollKo = '스크롤(?: ?(?:해 ?줘|해|하기))?';
const _pageAr = '(?: الصفحه)?';

final _scrollToTop = _full(
  [
    '(?:(?:scroll|go|jump|move|take me|get me|bring me|head)(?: back)?'
        '(?: all the way)?(?: up)? )?(?:back )?(?:to )?(?:the )?(?:very )?'
        'top(?: of (?:the |this )?page)?',
    '(?:scroll|go|move) all the way up',
    '(?:(?:$_moveFa|برگرد|بپر) )?(?:(?:به|تا) )?(?:بالای|اول|ابتدای|سر)'
        '(?: ی)? صفحه(?: $_moveFa)?',
    '(?:(?:$_moveFa|برگرد) )?تا (?:خود )?بالا(?: $_moveFa)?',
    'برگرد بالا',
    '(?:(?:$_scrollNordic|gå|hop|hopp|spring) )?(?:helt |heilt )?'
        '(?:$_upNordic )?(?:til |till )?toppen$_ofTheSiteNordic',
    '(?:(?:$_scrollNordic|gå) )?(?:helt|heilt|längst) $_upNordic',
    '(?:(?:$_scrollDe|spring|springe) )?(?:ganz nach oben|nach ganz oben|'
        '(?:zum|an den) (?:seiten)?anfang(?: der seite)?)',
    '(?:(?:va|aller|allez|remonte|remonter|retourne|retourner) )?'
        '(?:tout )?en haut(?: de la page)?',
    '(?:(?:va|aller|allez|retourne) )?au début(?: de la page)?',
    '(?:(?:ve|ir|vuelve|volver|vete) )?'
        '(?:al (?:principio|inicio)|hasta arriba|arriba del todo)'
        '(?: de la página| de la pagina)?',
    '(?:(?:vá|va|ir|volte|voltar|volta) )?(?:para o|pro|ao) '
        '(?:topo|início|inicio)(?: da página| da pagina)?',
    "(?:(?:vai|torna) )?(?:all'inizio|in cima)(?: della pagina)?",
    '(?:(?:ga|$_scrollNl) )?(?:helemaal naar boven|'
        'naar de (?:top|bovenkant)(?: van de pagina)?)',
    '(?:sayfanın |sayfanin )?(?:en üste|en yukarı|en yukarıya|başına|basina)'
        ' (?:git|çık|dön)',
    '(?:(?:перейди|вернись|иди|перейдіть|повернись) )?'
        '(?:в начало|к началу|на початок|в самый верх|нагору)'
        '(?: страницы| сторінки)?',
    '(?:przewiń |idź )?na (?:samą górę|początek)(?: strony)?',
    '(?:(?:اذهب|إذهب|ارجع|إرجع) )?(?:إلی|الی) (?:أعلی|اعلی|بدایه|أول|اول)'
        ' الصفحه',
    '(?:לך |עבור )?(?:לראש|להתחלת) הדף',
    '(?:回到|返回|到|去)?(?:顶部|頂部|最上面|页首|頁首)',
    '(?:一番上|ページの先頭|トップ)(?:に|へ)?(?:戻って|移動して|行って)?(?:ください)?',
    '맨 ?위로(?: ?(?:가 ?줘|가|이동))?',
  ].join('|'),
);

final _scrollToBottom = _full(
  [
    '(?:(?:scroll|go|jump|move|take me|get me|head)(?: all the way)?'
        '(?: down)? )?(?:to )?(?:the )?(?:very )?'
        '(?:bottom(?: of (?:the |this )?page)?|end of (?:the |this )?page)',
    '(?:(?:scroll|go|jump|move) )?(?:all the way )?(?:down )?to the end',
    '(?:scroll|go|move) all the way down',
    '(?:(?:$_moveFa|بپر) )?(?:(?:به|تا) )?(?:پایین|پائین|آخر|انتهای|ته)'
        '(?: ی)? صفحه(?: $_moveFa)?',
    '(?:$_moveFa )?تا (?:ته|آخر|خود پایین|پایین)(?: $_moveFa)?',
    '(?:(?:$_scrollNordic|gå|hop|hopp|spring) )?(?:helt |heilt )?'
        '(?:$_downNordic )?(?:til |till )?(?:bunden|bunnen|botten)'
        '$_ofTheSiteNordic',
    '(?:(?:$_scrollNordic|gå) )?(?:helt|heilt|längst) $_downNordic',
    '(?:(?:$_scrollDe|spring|springe) )?(?:ganz nach unten|nach ganz unten|'
        '(?:zum|ans) (?:seiten)?ende(?: der seite)?)',
    '(?:(?:va|aller|allez|descends|descendre) )?(?:tout )?en bas'
        '(?: de la page)?',
    '(?:(?:va|aller|allez) )?(?:à la|a la) fin(?: de la page)?',
    '(?:(?:ve|ir|vete) )?(?:al final|hasta abajo|abajo del todo)'
        '(?: de la página| de la pagina)?',
    '(?:(?:vá|va|ir) )?(?:para o|pro|ao) (?:fim|final)'
        '(?: da página| da pagina)?',
    '(?:vai )?(?:alla fine|in fondo)(?: della pagina)?',
    '(?:(?:ga|$_scrollNl) )?(?:helemaal naar beneden|'
        'naar (?:de onderkant|het einde)(?: van de pagina)?)',
    '(?:sayfanın |sayfanin )?(?:en alta|en aşağı|en aşağıya|sonuna)'
        ' (?:git|in)',
    '(?:(?:перейди|иди) )?(?:в конец|к концу|в кінець|в самый низ)'
        '(?: страницы| сторінки)?',
    '(?:przewiń |idź )?na (?:sam dół|koniec)(?: strony)?',
    '(?:(?:اذهب|إذهب) )?(?:إلی|الی) (?:أسفل|اسفل|نهایه|آخر|اخر) الصفحه',
    '(?:לך |עבור )?(?:לסוף|לתחתית) הדף',
    '(?:到|去)?(?:底部|最下面|页尾|頁尾)',
    '(?:一番下|ページの最後|ページの一番下)(?:に|へ)?(?:移動して|行って)?(?:ください)?',
    '맨 ?(?:아래|밑)로(?: ?(?:가 ?줘|가|이동))?',
  ].join('|'),
);

final _scrollUp = _full(
  [
    '(?:scroll|scrolling)$_thePageEn(?: back)? up(?:wards?)?'
        '(?: the page)?$_aBitEn',
    '(?:page|move|go) up(?: the page)?$_aBitEn',
    'up(?:wards?)?$_aBitEn',
    '$_aBitFa$_pageFa(?:$_moveFa )?(?:(?:به|رو به|سمت) )?$_upFa'
        '(?: $_moveFa)?',
    '$_scrollNordic$_theSiteNordic$_littleNordic $_upNordic$_aBitNordic',
    '(?:(?:gå|kør|kjør|side) )?(?:(?:lidt|litt|lite) )?$_upNordic$_aBitNordic',
    '(?:$_scrollDe )?(?:mal )?(?:nach oben|hoch|rauf)'
        '(?: (?:scrollen|blättern|gehen))?',
    '$_scrollFr vers le haut',
    '(?:monte|monter|montez|remonte|remonter|remontez)(?: la page)?'
        '(?: un peu)?',
    'vers le haut',
    '$_scrollEs (?:hacia |para )?arriba',
    '(?:sube|subir|suba)$_pageEs(?: un poco)?',
    '(?:hacia |para )?arriba',
    '$_scrollPt (?:para|pra) cima',
    '(?:sobe|subir|suba)$_pagePt(?: um pouco)?',
    '(?:para|pra) cima',
    "$_scrollIt (?:verso l'alto|in alto|su)",
    '(?:vai |torna )?su(?: un po)?',
    '(?:$_scrollNl )?(?:naar boven|omhoog)(?: $_scrollNl)?',
    '(?:sayfayı |sayfayi )?(?:yukarı|yukari)(?: (?:kaydır|kaydir|çık|cik|git))?',
    '$_scrollRu (?:вверх|наверх|вгору|догори)',
    '(?:вверх|наверх|вгору|догори)',
    'przewiń(?: stronę)? (?:w górę|do góry)',
    '(?:w górę|do góry)',
    '(?:اصعد|إصعد|اطلع)(?: (?:لفوق|فوق|للأعلی|لأعلی|للاعلی|لاعلی))?',
    '(?:مرر|اسحب|حرک)$_pageAr (?:لأعلی|للأعلی|لاعلی|للاعلی|إلی الأعلی|'
        'الی الاعلی|الی الأعلی|إلی الاعلی|لفوق|فوق)',
    'גלול למעלה',
    '(?:עלה|תעלה|לעלות) למעלה',
    'ऊपर $_scrollHi',
    'ऊपर (?:जाओ|जाएं|जाइए|चलो)',
    '(?:向上|往上)$_scrollZh',
    '上滑',
    '(?:上に?|上へ)$_scrollJa',
    '(?:위로 )$_scrollKo',
    '스크롤 ?업(?: ?(?:해 ?줘|해))?',
    '위로 (?:올려 ?줘|올려|가 ?줘)',
    '(?:gulir|scroll|geser)(?: ke)? atas',
    'cuộn lên(?: trên)?',
  ].join('|'),
);

final _scrollDown = _full(
  [
    // "Scroll" alone scrolls down.
    '(?:keep )?(?:scroll|scrolling)$_thePageEn(?: down(?:wards?)?)?'
        '(?: the page)?$_aBitEn',
    '(?:page|move|go) down(?: the page)?$_aBitEn',
    'down(?:wards?)?$_aBitEn',
    '$_pageFa$_scrollFa(?: کن| بکن)?',
    '$_aBitFa$_pageFa(?:$_moveFa )?(?:(?:به|رو به|سمت) )?$_downFa'
        '(?: $_moveFa)?',
    '$_scrollNordic$_theSiteNordic$_littleNordic(?: $_downNordic)?$_aBitNordic',
    '(?:(?:gå|kør|kjør|side) )?(?:(?:lidt|litt|lite) )?$_downNordic$_aBitNordic',
    '(?:$_scrollDe )?(?:mal )?(?:nach unten|runter)'
        '(?: (?:scrollen|blättern|gehen))?',
    'scrolle|scrollen',
    '$_scrollFr(?: vers le bas)?',
    '(?:descends|descendre|descend|descendez)(?: la page)?(?: un peu)?',
    'vers le bas',
    '$_scrollEs(?: (?:hacia |para )?abajo)?',
    '(?:baja|bajar|baje)$_pageEs(?: un poco)?',
    '(?:hacia |para )?abajo',
    '$_scrollPt(?: (?:para|pra) baixo)?',
    '(?:desce|descer|desça)$_pagePt(?: um pouco)?',
    '(?:para|pra) baixo',
    '$_scrollIt(?: (?:verso il basso|in basso|giù|giu))?',
    '(?:vai |va )?(?:giù|giu)(?: un po)?',
    '(?:$_scrollNl )?(?:naar beneden|omlaag)(?: $_scrollNl)?',
    '(?:sayfayı |sayfayi )?(?:aşağı|asagi)(?: (?:kaydır|kaydir|in|git))?',
    '$_scrollRu(?: вниз| донизу)?',
    '(?:вниз|донизу)',
    'przewiń(?: stronę)?(?: w dół| na dół)?',
    '(?:w|na) dół',
    '(?:انزل|إنزل|نزل)(?: (?:لتحت|تحت|للأسفل|لأسفل|للاسفل|لاسفل))?',
    '(?:مرر|اسحب|حرک)$_pageAr(?: (?:لأسفل|للأسفل|لاسفل|للاسفل|إلی الأسفل|'
        'الی الاسفل|الی الأسفل|إلی الاسفل|لتحت|تحت))?',
    'גלול(?: למטה)?',
    '(?:רד|תרד|לרדת) למטה',
    '(?:नीचे )?$_scrollHi',
    'नीचे (?:जाओ|जाएं|जाइए|चलो)',
    '(?:向下|往下)$_scrollZh',
    '下滑|下拉|(?:滚动|滾動)(?:一下)?',
    '(?:下に?|下へ)?$_scrollJa',
    '(?:(?:아래|밑)로 )?$_scrollKo',
    '스크롤 ?다운(?: ?(?:해 ?줘|해))?',
    '(?:아래|밑)로 (?:내려 ?줘|내려|가 ?줘)',
    '(?:gulir|scroll|geser)(?: ke)? bawah',
    'cuộn xuống(?: dưới)?',
  ].join('|'),
);

/// Whole words, in the order tried: the top and bottom of the page before
/// "up" and "down".
final _scrolls = [
  (_scrollToTop, ScrollMove.top),
  (_scrollToBottom, ScrollMove.bottom),
  (_scrollUp, ScrollMove.up),
  (_scrollDown, ScrollMove.down),
];

/// Which way the page should scroll: "scroll", "scroll up", «برو پایین»,
/// «برو بالای صفحه», "rul ned", "nach unten scrollen"; null for anything
/// else.
ScrollMove? _scrollMove(String text) {
  for (final (pattern, move) in _scrolls) {
    if (pattern.hasMatch(text)) return move;
  }
  return null;
}

/// The word "scroll" as it is borrowed in most languages, at the start of a
/// word ("scrollaa", "scrollen", «اسکرول», "скролл").
final _scrollLoanword = RegExp(
  '(?:^|\\s)(?:scroll|skrol|skroll|скрол|اسکرول|سکرول|סקרול|σκρολ)',
  unicode: true,
);

/// "Up" in the languages where "scroll" is borrowed.
final _upWord = RegExp(
  '(?:^|\\s)(?:up|upp|opp|op|hoch|oben|rauf|haut|arriba|cima|su|boven|'
  'omhoog|yukarı|yukari|вверх|наверх|вгору|górę|góry|ylös|nahoru|nahor|'
  'hore|fel|felfelé|sus|lên|atas|بالا|فوق|أعلی|اعلی|למעלה|πάνω)'
  '(?=\\s|\$)',
  unicode: true,
);

/// A short phrase with the word "scroll" in a language whose words for it
/// are not known ("skrollaa alas", "scrollează în sus"): down, or up when it
/// says so. Null for anything else.
ScrollMove? _scrollAnyLanguage(String text) {
  if (!_scrollLoanword.hasMatch(text) || text.split(' ').length > 4) {
    return null;
  }
  return _upWord.hasMatch(text) ? ScrollMove.up : ScrollMove.down;
}

/// Closing the browser (the whole app, every tab): "close the browser",
/// «مرورگر رو ببند», "luk browseren", "Browser schließen".
const _browserFa =
    '(?:مرورگر|براوزر|بروزر|برازر|برنامه|پنجره|شش ?براوزر|سیکس ?براوزر|'
    'browser)';
final _closeBrowser = _full(
  [
    '(?:close|exit|quit|shut(?: down)?)(?: the| this)? (?:browser|window|app|'
        'application|program|6 ?browser|six browser)',
    '(?:close|exit|quit) everything',
    '(?:این )?$_browserFa$_object (?:ببند|ببندش|بسته کن|خاموش کن|کلوز کن)',
    '(?:ببند|بستن|کلوز)(?: این)? $_browserFa$_object',
    'از $_browserFa (?:خارج شو|بیا بیرون|برو بیرون)',
    'luk(?: for)? (?:browseren|browser|vinduet|programmet|appen|6 ?browser)',
    'afslut (?:browseren|browser|programmet|appen)',
    'stäng (?:webbläsaren|browsern|fönstret)',
    'lukk (?:nettleseren|browseren|vinduet)',
    '(?:den )?browser (?:schließen|schliessen|beenden|zumachen)',
    '(?:schließe|schließ|schliesse|schliess|beende|mach)(?: den)? browser'
        '(?: zu)?',
    '(?:ferme|fermer|fermez|quitte|quitter|quittez)(?: le)? navigateur',
    '(?:cierra|cerrar|cierre)(?: el)? navegador',
    '(?:sal|salir) del navegador',
    '(?:chiudi|chiudere)(?: il)? browser',
    '(?:esci|uscire) dal browser',
    '(?:fechar|feche|fecha)(?: o)? navegador',
    '(?:sair|saia) do navegador',
    '(?:sluit|sluiten)(?: de)? browser',
    '(?:de )?browser sluiten',
    '(?:tarayıcıyı|tarayiciyi) (?:kapat|kapa)',
    '(?:закрой|закройте|закрыть|закрий|закрийте|закрити)(?: этот| цей)?'
        ' браузер',
    'zamknij(?: tę)? (?:przeglądarkę|przegladarke)',
    '(?:أغلق|اغلق|إغلاق|اغلاق|سکر|أقفل|اقفل) المتصفح',
    'סגור (?:את )?הדפדפן',
    'ब्राउ(?:ज़|ज़?)र (?:बंद|बन्द) (?:करो|करें|कर दो|कीजिए)',
    '(?:关闭|关掉|關閉|關掉)(?:浏览器|瀏覽器)',
    'ブラウザー?を?閉じ(?:て|る)(?:ください)?',
    '브라우저(?:를)? ?(?:닫아 ?줘|닫아|닫기|꺼 ?줘|꺼)',
    'tutup (?:browser|peramban)',
    'đóng trình duyệt',
  ].join('|'),
);

/// Lower-case text with Arabic letter forms turned Persian, Persian digits
/// turned Latin, and punctuation and whisper's non-speech markers
/// ("[BLANK_AUDIO]", "(music)") removed. Dots inside words stay
/// ("example.com").
String normalizeSpeech(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    buffer.writeCharCode(switch (rune) {
      0x064A || 0x0649 => 0x06CC, // ي ى -> ی
      0x0643 => 0x06A9, // ك -> ک
      0x0629 => 0x0647, // ة -> ه
      >= 0x06F0 && <= 0x06F9 => rune - 0x06F0 + 0x30, // ۰-۹
      >= 0x0660 && <= 0x0669 => rune - 0x0660 + 0x30, // ٠-٩
      0x200C || 0x200D || 0x00A0 => 0x20, // ZWNJ, ZWJ, no-break space
      0x2019 => 0x27, // ’ -> '
      _ => rune,
    });
  }
  return buffer
      .toString()
      .replaceAll(_diacritics, '')
      .replaceAll(_nonSpeech, ' ')
      .replaceAll(_punctuation, ' ')
      .replaceAll(_looseDots, ' ')
      .toLowerCase()
      .replaceAll(_spaces, ' ')
      .trim();
}

final _diacritics = RegExp('[ً-ٰٟـ]');
final _nonSpeech = RegExp(r'\[[^\]]*\]|\([^)]*\)|\*[^*]*\*|♪');
final _punctuation = RegExp('[!?؟,،;؛:"«»“”„…¡¿。，、！？；：]|(?<!\\w)\'|\'(?!\\w)');
final _looseDots = RegExp(r'\.+(?=\s|$)|(?<=\s|^)\.+');
final _spaces = RegExp(r'\s+');

RegExp _full(String pattern) => RegExp('^(?:$pattern)\$', unicode: true);

// Polite openings and endings that change nothing.
final _leadingFillers = RegExp(
  r'^(?:please|hey|ok|okay|so|can you|could you|would you|will you|'
  r"i want to|i'd like to|i would like to|let's|lets|"
  r'kan du|vil du|venligst|jeg vil gerne|jeg vil|lad os|okay så|hej|'
  r'لطفا|لطفاً|خواهشا|بی زحمت|میشه|می شه|میشود|می شود|میتونی|می تونی|'
  r'میخوام|می خوام|میخواهم|می خواهم|برام|برای من|خب|اوکی|باشه) ',
  unicode: true,
);
final _trailingFillers = RegExp(
  r' (?:please|for me|thanks|thank you|now|tak|venligst|for mig|nu|'
  r'لطفا|برام|برای من|ممنون|مرسی|الان)$',
  unicode: true,
);

String _withoutFillers(String text) {
  var t = text;
  while (true) {
    final next = t
        .replaceFirst(_leadingFillers, '')
        .replaceFirst(_trailingFillers, '');
    if (next == t) return t;
    t = next;
  }
}

final _inNewTab = RegExp(
  r'(?:^|\s)(?:in|on) (?:a )?new tab(?=\s|$)|'
  r'(?:^|\s)i (?:en )?ny fane(?=\s|$)|'
  r'(?:^|\s)(?:تو|توی|در|داخل) (?:یه |یک )?(?:تب|زبانه) (?:جدید|تازه)(?=\s|$)',
  unicode: true,
);

// "search" or «باز کن» with nothing to search for or open.
final _bareVerbs = _full(
  'search|search for|look up|open|go to|google|play|'
  'søg|søg efter|søg på|åbn|gå til|find|afspil|'
  'جستجو|جستجو کن|جست و جو کن|سرچ|سرچ کن|بگرد|باز کن|بازکن|برو|برو به|پخش کن',
);

const _tab = '(?:تب|زبانه)';
const _object = '(?: رو| را| و)?';
const _show = '(?: باز کن| بازکن| نشون بده| نشان بده| بیار| رو بیار)?';

final _commands = <(RegExp, BrowserCommand)>[
  (
    _full(
      '(?:open )?(?:a )?new (?:private|incognito) (?:tab|window)|'
      '(?:go )?incognito(?: mode)?|private (?:tab|window|mode)|'
      '(?:یه |یک )?(?:$_tab|پنجره) (?:خصوصی|ناشناس)(?: جدید)?$_show|'
      '(?:برو )?(?:به )?حالت (?:خصوصی|ناشناس)|اینکاگنیتو|اینکگنیتو|'
      '(?:åbn )?(?:en |et )?(?:nyt? )?(?:privat|inkognito) ?(?:fane|vindue)|'
      '(?:inkognito|privat) ?tilstand',
    ),
    BrowserCommand.newIncognitoTab,
  ),
  (
    _full(
      '(?:open )?(?:a )?(?:new|another) (?:tab|window)|'
      '(?:یه |یک )?(?:$_tab|پنجره) (?:جدید|تازه|دیگه|دیگر)'
      '(?: باز کن| بازکن| بیار| میخوام| می خوام)?|'
      '(?:باز کردن|بازکردن) $_tab جدید|نیو تب|اوپن نیو تب|'
      '(?:åbn )?(?:en )?ny fane|(?:åbn )?(?:et )?nyt vindue',
    ),
    BrowserCommand.newTab,
  ),
  (
    _full(
      '(?:re ?open|restore|bring back)(?: the)?(?: last)?(?: closed)? tab|'
      'undo close tab|'
      '(?:اون |آخرین )?$_tab(?: ی)? (?:بسته شده|که بستم|که بسته شد)$_object'
      ' (?:دوباره )?(?:باز کن|برگردون|بیار)|'
      '(?:genåbn|gendan)(?: den)?(?: sidste)?(?: lukkede)? fanen?',
    ),
    BrowserCommand.reopenClosedTab,
  ),
  // Before closing the tab: a plain "close" or «ببند» is the tab.
  (_closeBrowser, BrowserCommand.closeWindow),
  (
    _full(
      'close(?: this| the| current)?(?: tab)?|close it|'
      '(?:(?:این |همین )?$_tab(?: فعلی| جاری)?$_object )?ببندش?|'
      'بستن $_tab|کلوز(?: تب)?|'
      'luk(?: denne| den)?(?: fane| fanen)?',
    ),
    BrowserCommand.closeTab,
  ),
  (
    _full(
      '(?:go to |switch to )?(?:the )?next tab|'
      '(?:برو )?(?:به )?$_tab (?:بعدی|بعد)|'
      '(?:gå til |skift til )?(?:den )?næste fane',
    ),
    BrowserCommand.nextTab,
  ),
  (
    _full(
      '(?:go to |switch to )?(?:the )?previous tab|'
      '(?:برو )?(?:به )?$_tab (?:قبلی|قبل)|'
      '(?:gå til |skift til )?(?:den )?forrige fane',
    ),
    BrowserCommand.previousTab,
  ),
  (
    _full(
      '(?:go )?back|(?:go to )?(?:the )?previous page|'
      'برگرد(?: عقب)?|برو عقب|عقب|بازگشت|برگشت|'
      '(?:برو )?(?:به )?صفحه (?:قبل|قبلی)|بک|گو بک|'
      '(?:gå )?tilbage|(?:gå til )?(?:den )?forrige side',
    ),
    BrowserCommand.back,
  ),
  // "next page" is a page of search results there, else Forward (see
  // _resultsPage).
  (
    _full('(?:go )?forward|(?:برو )?(?:به )?جلو|فوروارد|(?:gå )?frem(?:ad)?'),
    BrowserCommand.forward,
  ),
  (
    _full(
      '(?:reload|refresh)(?: the| this)?(?: page)?|'
      '(?:(?:این )?صفحه$_object )?'
      '(?:رفرش|ریفرش|بارگذاری مجدد|دوباره بارگذاری|بارگیری مجدد|تازه|ری لود|ریلود)'
      '(?: کن| بکن)?|'
      '(?:genindlæs|opdater)(?: siden)?',
    ),
    BrowserCommand.reload,
  ),
  (
    _full('stop(?: loading)?|توقف|متوقف کن|استاپ(?: کن)?|stop indlæsningen'),
    BrowserCommand.stop,
  ),
  (
    _full(
      '(?:go )?home|(?:go to )?(?:the )?home ?page|'
      '(?:برو )?(?:به )?(?:صفحه اصلی|صفحه خانه|خانه|خونه|هوم)|'
      '(?:gå )?hjem|(?:gå til )?startsiden?',
    ),
    BrowserCommand.home,
  ),
  (
    _full(
      'zoom in|make (?:it|the text|text) bigger|'
      'بزرگ ?نمایی(?: کن)?|زوم این|زوم کن|بزرگ ?ترش کن|بزرگش کن|بزرگ کن|'
      'zoom ind|gør (?:det|teksten) større',
    ),
    BrowserCommand.zoomIn,
  ),
  (
    _full(
      'zoom out|make (?:it|the text|text) smaller|'
      '(?:کوچک|کوچیک) ?نمایی(?: کن)?|زوم اوت|(?:کوچک|کوچیک) ?ترش کن|'
      '(?:کوچک|کوچیک)ش کن|(?:کوچک|کوچیک) کن|'
      'zoom ud|gør (?:det|teksten) mindre',
    ),
    BrowserCommand.zoomOut,
  ),
  (
    _full(
      '(?:reset|normal|actual) (?:zoom|size)|reset the zoom|zoom reset|'
      '(?:اندازه|زوم)$_object (?:عادی|معمولی|ریست)(?: کن)?|'
      'nulstil zoom(?:en)?|normal størrelse',
    ),
    BrowserCommand.zoomReset,
  ),
  (
    _full(
      '(?:enter |exit |toggle )?full ?screen(?: mode)?|'
      '(?:تمام ?صفحه|فول ?اسکرین)(?: کن)?|'
      'fuld ?skærm(?:stilstand)?',
    ),
    BrowserCommand.fullscreen,
  ),
  (
    _full(
      'print(?: this| the)?(?: page)?|'
      '(?:(?:این )?صفحه$_object )?(?:چاپ|پرینت)(?: کن| بگیر)?|'
      '(?:udskriv|print)(?: denne side| siden)?',
    ),
    BrowserCommand.print,
  ),
  (
    _full(
      'bookmark(?: this| the)?(?: page| site)?|'
      'add(?: this)?(?: page)? to(?: my)? bookmarks|'
      '(?:(?:این )?(?:صفحه|سایت)$_object )?(?:بوکمارک|نشانک) کن|'
      '(?:این )?(?:صفحه|سایت)$_object (?:بوکمارک|نشانک|ذخیره) کن|'
      'bogmærk(?: denne side| siden)?|'
      '(?:tilføj|gem)(?: denne side| siden)? (?:til|som) (?:mine )?bogmærker?',
    ),
    BrowserCommand.bookmarkPage,
  ),
  (
    _full(
      '(?:open |show )?(?:my )?bookmarks|'
      '(?:بوکمارک ?ها|نشانک ?ها|علاقه ?مندی ?ها)(?:ی من)?$_object$_show|'
      '(?:åbn |vis )?(?:mine )?bogmærker(?:ne)?',
    ),
    BrowserCommand.bookmarks,
  ),
  (
    _full(
      '(?:open |show )?(?:my )?(?:browsing )?history|'
      '(?:تاریخچه|هیستوری)$_object$_show|'
      '(?:åbn |vis )?(?:min )?(?:browser)?historik(?:ken)?',
    ),
    BrowserCommand.history,
  ),
  (
    _full(
      '(?:open |show )?(?:my )?downloads|'
      '(?:دانلود ?ها|دانلودهام|دانلودهای من)$_object$_show|'
      '(?:åbn |vis )?(?:mine )?(?:downloads|overførsler)(?:ne)?',
    ),
    BrowserCommand.downloads,
  ),
];

/// A site that can be opened (and searched) by name.
class _Site {
  const _Site(this.url, this.names, {this.search});

  final String url;
  final List<String> names;

  /// Search URL, `%s` for the query.
  final String? search;

  String searchUrl(String query) {
    // Persian queries go to Persian Wikipedia.
    final template = url == _wikipedia && _persian.hasMatch(query)
        ? 'https://fa.wikipedia.org/w/index.php?search=%s'
        : search!;
    return template.replaceAll('%s', Uri.encodeQueryComponent(query));
  }
}

const _wikipedia = 'https://www.wikipedia.org/';
final _persian = RegExp('[؀-ۿ]');

const _sites = [
  _Site('https://www.youtube.com/', [
    'youtube',
    'you tube',
    'یوتیوب',
    'یوتوب',
    'یوتیوپ',
    'یو تیوب',
  ], search: 'https://www.youtube.com/results?search_query=%s'),
  _Site('https://www.google.com/', ['google', 'گوگل']),
  _Site('https://mail.google.com/', [
    'gmail',
    'g mail',
    'google mail',
    'جیمیل',
    'جی میل',
  ]),
  _Site('https://www.google.com/maps', [
    'google maps',
    'maps',
    'گوگل مپ',
    'گوگل مپس',
    'نقشه گوگل',
    'نقشه',
  ], search: 'https://www.google.com/maps/search/%s'),
  _Site('https://translate.google.com/', [
    'google translate',
    'translate',
    'گوگل ترنسلیت',
    'ترنسلیت',
    'مترجم گوگل',
    'گوگل ترجمه',
  ]),
  _Site('https://drive.google.com/', ['google drive', 'گوگل درایو']),
  _Site('https://news.google.com/', ['google news', 'گوگل نیوز', 'اخبار گوگل']),
  _Site(_wikipedia, [
    'wikipedia',
    'wiki',
    'ویکی پدیا',
    'ویکیپدیا',
    'ویکی',
  ], search: 'https://en.wikipedia.org/w/index.php?search=%s'),
  _Site('https://github.com/', [
    'github',
    'git hub',
    'گیت هاب',
    'گیتهاب',
  ], search: 'https://github.com/search?q=%s'),
  _Site('https://www.instagram.com/', [
    'instagram',
    'insta',
    'اینستاگرام',
    'اینستا',
  ]),
  _Site('https://www.facebook.com/', ['facebook', 'فیسبوک', 'فیس بوک']),
  _Site('https://x.com/', [
    'twitter',
    'x',
    'توییتر',
    'تویتر',
    'توئیتر',
    'ایکس',
  ], search: 'https://x.com/search?q=%s'),
  _Site('https://web.telegram.org/', ['telegram', 'تلگرام']),
  _Site('https://web.whatsapp.com/', [
    'whatsapp',
    'whats app',
    'واتساپ',
    'واتس اپ',
    'واتس آپ',
  ]),
  _Site('https://www.linkedin.com/', [
    'linkedin',
    'linked in',
    'لینکدین',
    'لینکداین',
  ]),
  _Site('https://www.reddit.com/', [
    'reddit',
    'ردیت',
  ], search: 'https://www.reddit.com/search/?q=%s'),
  _Site('https://www.amazon.com/', [
    'amazon',
    'آمازون',
  ], search: 'https://www.amazon.com/s?k=%s'),
  _Site('https://www.netflix.com/', ['netflix', 'نتفلیکس']),
  _Site('https://open.spotify.com/', ['spotify', 'اسپاتیفای']),
  _Site('https://chatgpt.com/', [
    'chatgpt',
    'chat gpt',
    'چت جی پی تی',
    'چت جیپیتی',
  ]),
  _Site('https://claude.ai/', ['claude', 'کلود']),
  _Site('https://stackoverflow.com/', [
    'stack overflow',
    'stackoverflow',
    'استک اورفلو',
  ]),
  _Site('https://outlook.live.com/', [
    'outlook',
    'hotmail',
    'اوتلوک',
    'هاتمیل',
  ]),
  _Site('https://www.bing.com/', ['bing', 'بینگ']),
  _Site('https://duckduckgo.com/', [
    'duckduckgo',
    'duck duck go',
    'داک داک گو',
  ]),
  _Site('https://www.yahoo.com/', ['yahoo', 'یاهو']),
  _Site('https://www.tiktok.com/', ['tiktok', 'tik tok', 'تیک تاک']),
  _Site('https://www.pinterest.com/', ['pinterest', 'پینترست']),
  _Site('https://www.twitch.tv/', ['twitch', 'توییچ']),
  _Site('https://www.bbc.com/persian', ['bbc persian', 'بی بی سی فارسی']),
  _Site('https://www.bbc.com/', ['bbc', 'بی بی سی']),
  _Site('https://www.digikala.com/', [
    'digikala',
    'digi kala',
    'دیجی کالا',
    'دیجیکالا',
  ], search: 'https://www.digikala.com/search/?q=%s'),
  _Site('https://www.aparat.com/', [
    'aparat',
    'آپارات',
  ], search: 'https://www.aparat.com/search/%s'),
  _Site('https://divar.ir/', ['divar', 'دیوار']),
  _Site('https://www.varzesh3.com/', [
    'varzesh3',
    'varzesh 3',
    'ورزش سه',
    'ورزش 3',
  ]),
  _Site('https://www.dr.dk/', ['dr', 'dr dk', 'danmarks radio']),
  _Site('https://tv2.dk/', ['tv2', 'tv 2', 'tv to']),
  _Site('https://www.borger.dk/', ['borger dk', 'borger']),
];

final _siteNames = {
  for (final site in _sites)
    for (final name in site.names) name: site,
};

_Site? _siteNamed(String text) {
  final name = text
      .replaceFirst(RegExp(r'^(?:the |سایت |siden )'), '')
      .replaceFirst(
        RegExp(r' (?:website|site|page|app|سایت|hjemmeside|siden)$'),
        '',
      );
  return _siteNames[name] ?? _siteNames[name.replaceAll(' ', '')];
}

// Sites with a search page, longest names first so "google maps" wins over
// "google". One-letter names ("x") would turn "hotels in x" into a search
// on X.
final _searchableSites = ([
  for (final site in _sites)
    if (site.search != null) ...site.names.where((n) => n.length > 1),
]..sort((a, b) => b.length.compareTo(a.length))).map(RegExp.escape).join('|');

const _searchVerbEn = '(?:search|look up|find|google)(?: for)?';
const _searchVerbFa = '(?:جستجو|جست و جو|سرچ|پیدا|گوگل)(?: کن| بکن| کنید)?';
// «گوگل» alone is the site; as a verb it takes «کن».
const _searchVerbFaStrict =
    '(?:(?:جستجو|جست و جو|جستجوی|سرچ)(?: کن| بکن| کنید)?|گوگل(?: کن| بکن))';
const _inFa = '(?:تو|توی|در|داخل)';
const _searchVerbDa = '(?:søg|søge|find|finde)(?: efter| på| om)?';

/// Searches on a site: "Iran on YouTube", «ایران رو تو یوتیوب سرچ کن»,
/// "søg efter Iran på YouTube". Patterns without a site group search
/// YouTube ("play ...").
final _siteSearches = [
  _full('$_searchVerbEn (?<q>.+?) (?:on|in|at) (?<site>$_searchableSites)'),
  _full('search (?<site>$_searchableSites) for (?<q>.+)'),
  _full('(?:play|watch) (?<q>.+?)(?: on (?<site>youtube|aparat))?'),
  _full('$_searchVerbDa (?<q>.+?) (?:på|i) (?<site>$_searchableSites)'),
  _full('søg på (?<site>$_searchableSites) efter (?<q>.+)'),
  _full('(?:afspil|spil) (?<q>.+?)(?: på (?<site>youtube))?'),
  _full('(?<q>.+?)$_object $_inFa (?<site>$_searchableSites) $_searchVerbFa'),
  _full('$_inFa (?<site>$_searchableSites) (?<q>.+?)$_object $_searchVerbFa'),
  _full('$_inFa (?<site>$_searchableSites) $_searchVerbFa (?<q>.+)'),
  _full('$_searchVerbFa (?<q>.+?) $_inFa (?<site>$_searchableSites)'),
  _full('(?<q>.+?)$_object (?:پخش|پلی) کن'),
  _full('(?:پخش|پلی) کن (?<q>.+)'),
];

final _searches = [
  _full(
    '(?:search|google|look up|search up|look for)(?: for| about| up)? (?<q>.+)',
  ),
  _full('$_searchVerbFaStrict(?: برای| درباره| در مورد| دنبال)? (?<q>.+)'),
  _full('(?<q>.+?)$_object $_searchVerbFaStrict'),
  _full('دنبال (?<q>.+?) بگرد'),
  _full('بگرد دنبال (?<q>.+)'),
  _full('$_searchVerbDa (?<q>.+)'),
];

final _opens = [
  _full(
    '(?:open|go to|goto|visit|navigate to|take me to|launch|load|bring up)'
    '(?: the)? (?<t>.+?)(?: website| site| page| app)?',
  ),
  _full(
    '(?:برو به|برو تو|برو توی|برو|بریم به|بریم تو|بریم|باز کن|بازکن|اوپن|وارد)'
    '(?: سایت)? (?<t>.+?)(?: شو| بشو)?',
  ),
  _full(
    '(?:سایت )?(?<t>.+?)$_object '
    '(?:باز کن|بازکن|بازش کن|بیار|بالا بیار|نشون بده|نشان بده|اوپن کن)',
  ),
  _full(
    '(?:åbn|gå til|gå ind på|besøg|tag mig til)'
    '(?: siden| hjemmesiden)? (?<t>.+?)(?: hjemmeside| siden)?',
  ),
];

String _cleanQuery(String text) => text
    .replaceFirst(RegExp(r'^(?:درباره|در مورد|برای|دنبال) '), '')
    .replaceFirst(RegExp(r' (?:رو|را)$'), '')
    .trim();

// Domain words as heard in Persian: «دیجی کالا دات کام».
const _spokenTopLevel = {
  'کام': 'com',
  'نت': 'net',
  'اورگ': 'org',
  'او آر جی': 'org',
  'آی آر': 'ir',
  'ای ار': 'ir',
  'آی ار': 'ir',
  'آیو': 'io',
};

/// A web address said aloud ("example dot com"), or null.
String? _spokenAddress(String text) {
  var t = text.replaceAll(
    RegExp(r'\s*(?:\bdot\b|\bpunktum\b|دات|نقطه)\s*'),
    '.',
  );
  for (final MapEntry(:key, :value) in _spokenTopLevel.entries) {
    if (t.endsWith('.$key')) {
      t = '${t.substring(0, t.length - key.length)}$value';
    }
  }
  t = t.replaceAll(' ', '');
  if (!t.contains('.')) return null;
  final url = resolveInput(t);
  return url.startsWith('http://') || url.startsWith('https://') ? url : null;
}
