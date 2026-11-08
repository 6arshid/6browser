import '../../ui/browser_commands.dart';
import '../tabs/url_input.dart';

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

/// Turns what was heard ("search Iran", «جستجو کن ایران», "open YouTube",
/// «برو به یوتیوب», "new tab"...) into an action. Anything that is not a
/// command is treated like text typed in the address bar: a search, or a
/// site when it names one. Null when nothing usable was said (silence, or
/// just "search" with no words to search for).
VoiceAction? parseVoiceCommand(
  String heard, {
  String searchTemplate = defaultSearchTemplate,
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

  // No command: like typing in the address bar.
  return go(resolveInput(text, searchTemplate: searchTemplate));
}

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
final _punctuation = RegExp('[!?؟,،;؛:"«»“”„…]|(?<!\\w)\'|\'(?!\\w)');
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
  (
    _full(
      '(?:go )?forward|(?:go to )?(?:the )?next page|'
      '(?:برو )?(?:به )?جلو|(?:برو )?(?:به )?صفحه (?:بعد|بعدی)|فوروارد|'
      '(?:gå )?frem(?:ad)?|(?:gå til )?(?:den )?næste side',
    ),
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
