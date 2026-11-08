import 'package:browser6/features/voice/voice_commands.dart';
import 'package:browser6/ui/browser_commands.dart';
import 'package:flutter_test/flutter_test.dart';

String google(String q) =>
    'https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}';
String youtube(String q) =>
    'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(q)}';

void main() {
  void expectUrl(String heard, String url, {bool newTab = false}) {
    final action = parseVoiceCommand(heard);
    expect(action, isA<VoiceNavigate>(), reason: heard);
    action as VoiceNavigate;
    expect(action.url, url, reason: heard);
    expect(action.newTab, newTab, reason: heard);
  }

  void expectCommand(String heard, BrowserCommand command) {
    final action = parseVoiceCommand(heard);
    expect(action, isA<VoiceRunCommand>(), reason: heard);
    expect((action as VoiceRunCommand).command, command, reason: heard);
  }

  group('normalizeSpeech', () {
    test('unifies Arabic letters, digits and spaces', () {
      expect(normalizeSpeech('كتاب ي'), 'کتاب ی');
      expect(normalizeSpeech('ورزش ۳'), 'ورزش 3');
      expect(normalizeSpeech('می‌خواهم'), 'می خواهم');
      expect(normalizeSpeech('  Search,   Iran.  '), 'search iran');
      expect(normalizeSpeech('«جستجو کن ایران»؟'), 'جستجو کن ایران');
    });

    test('keeps dots inside addresses and drops non-speech markers', () {
      expect(normalizeSpeech('Open example.com.'), 'open example.com');
      expect(normalizeSpeech('[BLANK_AUDIO] (music)'), '');
    });
  });

  group('search', () {
    test('English', () {
      expectUrl('Search Iran', google('iran'));
      expectUrl('Search, Iran.', google('iran'));
      expectUrl(
        'Search for the weather in Tehran.',
        google('the weather in tehran'),
      );
      expectUrl('Google cheap flights', google('cheap flights'));
      expectUrl('look up flutter', google('flutter'));
    });

    test('Persian, verb first or last', () {
      expectUrl('سرچ کن ایران', google('ایران'));
      expectUrl('جستجو کن ایران', google('ایران'));
      expectUrl('ایران رو جستجو کن', google('ایران'));
      expectUrl('ایران را سرچ کن.', google('ایران'));
      expectUrl('دنبال هوای تهران بگرد', google('هوای تهران'));
      expectUrl('لطفا درباره کوروش جستجو کن', google('کوروش'));
    });

    test('anything that is not a command is a search', () {
      expectUrl('What is the capital of France', google('what is the capital of france'));
      expectUrl('ایران', google('ایران'));
    });

    test('uses the chosen search engine', () {
      final action = parseVoiceCommand(
        'search iran',
        searchTemplate: 'https://www.bing.com/search?q=%s',
      );
      expect(
        (action! as VoiceNavigate).url,
        'https://www.bing.com/search?q=iran',
      );
    });

    test('on a site', () {
      expectUrl('search cats on YouTube', youtube('cats'));
      expectUrl('play persian music', youtube('persian music'));
      expectUrl('تو یوتیوب موزیک ایرانی رو سرچ کن', youtube('موزیک ایرانی'));
      expectUrl('موزیک ایرانی رو تو یوتیوب جستجو کن', youtube('موزیک ایرانی'));
      expectUrl(
        'search Tehran on Wikipedia',
        'https://en.wikipedia.org/w/index.php?search=tehran',
      );
      expectUrl(
        'تهران رو تو ویکی پدیا جستجو کن',
        'https://fa.wikipedia.org/w/index.php?search=${Uri.encodeQueryComponent('تهران')}',
      );
      // Not a site: an ordinary search.
      expectUrl('search hotels in tehran', google('hotels in tehran'));
    });

    test('in a new tab', () {
      expectUrl('search iran in a new tab', google('iran'), newTab: true);
      expectUrl('ایران رو تو تب جدید سرچ کن', google('ایران'), newTab: true);
    });
  });

  group('open', () {
    test('sites by name', () {
      expectUrl('Open YouTube.', 'https://www.youtube.com/');
      expectUrl('go to the youtube website', 'https://www.youtube.com/');
      expectUrl('YouTube', 'https://www.youtube.com/');
      expectUrl('برو به یوتیوب', 'https://www.youtube.com/');
      expectUrl('یوتیوب رو باز کن', 'https://www.youtube.com/');
      expectUrl('یوتیوب', 'https://www.youtube.com/');
      expectUrl('لطفا برو به گوگل', 'https://www.google.com/');
      expectUrl('please open google', 'https://www.google.com/');
      expectUrl('Google Maps', 'https://www.google.com/maps');
      expectUrl('گوگل مپ رو باز کن', 'https://www.google.com/maps');
      expectUrl('وارد دیجی کالا شو', 'https://www.digikala.com/');
    });

    test('addresses, spoken or written', () {
      expectUrl('go to example dot com', 'http://example.com');
      expectUrl('example.com', 'http://example.com');
      expectUrl('برو به example.com', 'http://example.com');
    });

    test('an unknown name is searched for', () {
      expectUrl('open my favourite blog', google('my favourite blog'));
    });

    test('in a new tab', () {
      expectUrl(
        'تو تب جدید یوتیوب رو باز کن',
        'https://www.youtube.com/',
        newTab: true,
      );
    });
  });

  group('browser commands', () {
    test('tabs', () {
      expectCommand('new tab', BrowserCommand.newTab);
      expectCommand('Open a new tab.', BrowserCommand.newTab);
      expectCommand('تب جدید', BrowserCommand.newTab);
      expectCommand('یه تب جدید باز کن', BrowserCommand.newTab);
      expectCommand('new incognito tab', BrowserCommand.newIncognitoTab);
      expectCommand('تب ناشناس', BrowserCommand.newIncognitoTab);
      expectCommand('close tab', BrowserCommand.closeTab);
      expectCommand('این تب رو ببند', BrowserCommand.closeTab);
      expectCommand('reopen closed tab', BrowserCommand.reopenClosedTab);
      expectCommand('next tab', BrowserCommand.nextTab);
      expectCommand('تب قبلی', BrowserCommand.previousTab);
    });

    test('navigation', () {
      expectCommand('Go back.', BrowserCommand.back);
      expectCommand('برگرد', BrowserCommand.back);
      expectCommand('go forward', BrowserCommand.forward);
      expectCommand('Reload', BrowserCommand.reload);
      expectCommand('صفحه رو رفرش کن', BrowserCommand.reload);
      expectCommand('go home', BrowserCommand.home);
    });

    test('pages and lists', () {
      expectCommand('zoom in', BrowserCommand.zoomIn);
      expectCommand('bookmark this page', BrowserCommand.bookmarkPage);
      expectCommand('show my bookmarks', BrowserCommand.bookmarks);
      expectCommand('History', BrowserCommand.history);
      expectCommand('تاریخچه رو باز کن', BrowserCommand.history);
      expectCommand('دانلودها', BrowserCommand.downloads);
    });
  });

  group('Danish', () {
    test('search', () {
      expectUrl('Søg efter Iran.', google('iran'));
      expectUrl('søg på vejret i københavn', google('vejret i københavn'));
      expectUrl('kan du søge efter iran', google('iran'));
      expectUrl('søg efter katte på YouTube', youtube('katte'));
      expectUrl('afspil dansk musik', youtube('dansk musik'));
      expectUrl('søg efter iran i en ny fane', google('iran'), newTab: true);
    });

    test('open', () {
      expectUrl('Åbn YouTube.', 'https://www.youtube.com/');
      expectUrl('gå til DR', 'https://www.dr.dk/');
      expectUrl('gå ind på tv 2', 'https://tv2.dk/');
      expectUrl('åbn example punktum dk', 'http://example.dk');
    });

    test('commands', () {
      expectCommand('ny fane', BrowserCommand.newTab);
      expectCommand('Åbn en ny fane.', BrowserCommand.newTab);
      expectCommand('ny privat fane', BrowserCommand.newIncognitoTab);
      expectCommand('luk fanen', BrowserCommand.closeTab);
      expectCommand('gå tilbage', BrowserCommand.back);
      expectCommand('frem', BrowserCommand.forward);
      expectCommand('genindlæs siden', BrowserCommand.reload);
      expectCommand('næste fane', BrowserCommand.nextTab);
      expectCommand('vis historik', BrowserCommand.history);
      expectCommand('mine bogmærker', BrowserCommand.bookmarks);
      expectCommand('zoom ind', BrowserCommand.zoomIn);
    });

    test('nothing to search for', () {
      expect(parseVoiceCommand('søg'), isNull);
      expect(parseVoiceCommand('Søg efter.'), isNull);
    });
  });

  test('nothing usable', () {
    expect(parseVoiceCommand(''), isNull);
    expect(parseVoiceCommand('[BLANK_AUDIO]'), isNull);
    expect(parseVoiceCommand('Search.'), isNull);
    expect(parseVoiceCommand('سرچ کن'), isNull);
  });
}
