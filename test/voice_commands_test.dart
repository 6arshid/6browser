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
      expectUrl(
        'What is the capital of France',
        google('what is the capital of france'),
      );
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

  group('numbered results', () {
    void expectResult(String heard, int number, {bool newTab = false}) {
      final action = parseVoiceCommand(heard);
      expect(action, isA<VoiceOpenResult>(), reason: heard);
      action as VoiceOpenResult;
      expect(action.number, number, reason: heard);
      expect(action.newTab, newTab, reason: heard);
    }

    test('Persian', () {
      expectResult('لینک دوم گوگل رو باز کن', 2);
      expectResult('لینک دوم رو باز کن', 2);
      expectResult('لینک اول', 1);
      expectResult('دومین لینک رو باز کن', 2);
      expectResult('اولین نتیجه', 1);
      expectResult('نتیجه سوم', 3);
      expectResult('برو لینک چهارم', 4);
      expectResult('روی لینک پنجم کلیک کن', 5);
      expectResult('لینک شماره شش رو باز کن', 6);
      expectResult('لینک ۷ رو باز کن', 7);
      expectResult('لینک هشتم تو گوگل', 8);
      expectResult('سایت نهم رو باز کن', 9);
      expectResult('لینک دهم رو باز کن', 10);
      expectResult('ویدیوی دوم رو پخش کن', 2);
      expectResult('لطفا لینک‌ دوم رو باز کن', 2);
      expectResult('لینک سوم رو تو تب جدید باز کن', 3, newTab: true);
    });

    test('English', () {
      expectResult('Open the second link.', 2);
      expectResult('open the second Google result', 2);
      expectResult('first result', 1);
      expectResult('click on the third link', 3);
      expectResult('open link 4', 4);
      expectResult('open result number five', 5);
      expectResult('the 6th one', 6);
      expectResult('play the second video', 2);
      expectResult('open the tenth link on Google', 10);
      expectResult('open the second link in a new tab', 2, newTab: true);
    });

    test('Danish', () {
      expectResult('Åbn det andet link.', 2);
      expectResult('første resultat', 1);
      expectResult('klik på det tredje link', 3);
      expectResult('link nummer fire', 4);
    });

    test('other words stay what they were', () {
      expectUrl('open YouTube', 'https://www.youtube.com/');
      expectUrl('play one direction', youtube('one direction'));
      expectUrl('سایت دیوار رو باز کن', 'https://divar.ir/');
      expectCommand('next tab', BrowserCommand.nextTab);
    });
  });

  group('pages of results', () {
    void expectPage(
      String heard, {
      int step = 0,
      int? number,
      BrowserCommand? otherwise,
    }) {
      final action = parseVoiceCommand(heard);
      expect(action, isA<VoiceResultsPage>(), reason: heard);
      action as VoiceResultsPage;
      expect(action.step, step, reason: heard);
      expect(action.number, number, reason: heard);
      expect(action.otherwise, otherwise, reason: heard);
    }

    test('next and previous', () {
      expectPage('برو صفحه بعد گوگل', step: 1);
      expectPage('صفحه بعدی نتایج', step: 1);
      expectPage('نتایج بعدی', step: 1);
      expectPage('next page of Google', step: 1);
      expectPage('more results', step: 1);
      expectPage('næste side af resultaterne', step: 1);
      expectPage('صفحه قبل گوگل', step: -1);
      expectPage('previous page of results', step: -1);
    });

    test('a plain "next page" is Forward away from results', () {
      for (final heard in [
        'next page',
        'go to the next page',
        'برو صفحه بعد',
        'صفحه بعدی',
        'næste side',
      ]) {
        expectPage(heard, step: 1, otherwise: BrowserCommand.forward);
      }
      // "previous page" stays Back.
      expectCommand('previous page', BrowserCommand.back);
      expectCommand('برو صفحه قبل', BrowserCommand.back);
    });

    test('by number', () {
      expectPage('صفحه دوم گوگل', number: 2);
      expectPage('برو صفحه سوم', number: 3);
      expectPage('دومین صفحه', number: 2);
      expectPage('page 4', number: 4);
      expectPage('go to the second page of the results', number: 2);
      expectPage('side 2', number: 2);
      // Not page numbers.
      expectCommand('برو صفحه اصلی', BrowserCommand.home);
      expectCommand('home page', BrowserCommand.home);
    });
  });

  test('stop listening', () {
    for (final heard in [
      'Stop listening.',
      'turn off the microphone',
      'دیگه گوش نده',
      'میکروفون رو خاموش کن',
      'stop med at lytte',
    ]) {
      expect(
        parseVoiceCommand(heard),
        isA<VoiceStopListening>(),
        reason: heard,
      );
    }
    // Stop loading stays.
    expectCommand('stop', BrowserCommand.stop);
  });

  group('scrolling', () {
    void expectScroll(String heard, ScrollMove move) {
      // The same whether or not other words are searched for.
      for (final searchFreeText in [true, false]) {
        final action = parseVoiceCommand(heard, searchFreeText: searchFreeText);
        expect(action, isA<VoiceScroll>(), reason: heard);
        expect((action as VoiceScroll).move, move, reason: heard);
      }
    }

    test('English', () {
      expectScroll('Scroll.', ScrollMove.down);
      expectScroll('scroll down', ScrollMove.down);
      expectScroll('Scroll down a bit, please.', ScrollMove.down);
      expectScroll('scroll the page down', ScrollMove.down);
      expectScroll('keep scrolling', ScrollMove.down);
      expectScroll('page down', ScrollMove.down);
      expectScroll('go down', ScrollMove.down);
      expectScroll('scroll up', ScrollMove.up);
      expectScroll('Scroll back up.', ScrollMove.up);
      expectScroll('page up', ScrollMove.up);
      expectScroll('scroll to the top', ScrollMove.top);
      expectScroll('back to top', ScrollMove.top);
      expectScroll('go to the top of the page', ScrollMove.top);
      expectScroll('scroll to the bottom', ScrollMove.bottom);
      expectScroll('go to the end', ScrollMove.bottom);
      expectScroll('bottom of the page', ScrollMove.bottom);
    });

    test('Persian', () {
      expectScroll('اسکرول', ScrollMove.down);
      expectScroll('اسکرول کن.', ScrollMove.down);
      expectScroll('اسکرول کن پایین', ScrollMove.down);
      expectScroll('پایین اسکرول کن', ScrollMove.down);
      expectScroll('صفحه رو اسکرول کن', ScrollMove.down);
      expectScroll('برو پایین', ScrollMove.down);
      expectScroll('یکم برو پایین‌تر', ScrollMove.down);
      expectScroll('صفحه رو بکش پایین', ScrollMove.down);
      expectScroll('لطفا بیا پایین', ScrollMove.down);
      expectScroll('برو بالا', ScrollMove.up);
      expectScroll('اسکرول به بالا', ScrollMove.up);
      expectScroll('بالا', ScrollMove.up);
      expectScroll('برو بالای صفحه', ScrollMove.top);
      expectScroll('اول صفحه', ScrollMove.top);
      expectScroll('برگرد بالا', ScrollMove.top);
      expectScroll('برو آخر صفحه', ScrollMove.bottom);
      expectScroll('ته صفحه', ScrollMove.bottom);
      expectScroll('برو تا پایین', ScrollMove.bottom);
    });

    test('Danish', () {
      expectScroll('Scroll ned.', ScrollMove.down);
      expectScroll('rul ned', ScrollMove.down);
      expectScroll('kan du rulle lidt ned', ScrollMove.down);
      expectScroll('rul op', ScrollMove.up);
      expectScroll('gå op', ScrollMove.up);
      expectScroll('til toppen', ScrollMove.top);
      expectScroll('gå til bunden af siden', ScrollMove.bottom);
      expectScroll('rul helt ned', ScrollMove.bottom);
    });

    test('other languages', () {
      expectScroll('Nach unten scrollen.', ScrollMove.down);
      expectScroll('Scroll mal hoch.', ScrollMove.up);
      expectScroll('Ganz nach oben', ScrollMove.top);
      expectScroll('Défile vers le bas.', ScrollMove.down);
      expectScroll('Fais défiler vers le haut', ScrollMove.up);
      expectScroll('Desplázate hacia abajo.', ScrollMove.down);
      expectScroll('¡Sube!', ScrollMove.up);
      expectScroll('Rolar para baixo', ScrollMove.down);
      expectScroll("Scorri verso l'alto", ScrollMove.up);
      expectScroll('Naar beneden scrollen', ScrollMove.down);
      expectScroll('Scrolla ner', ScrollMove.down);
      expectScroll('Aşağı kaydır.', ScrollMove.down);
      expectScroll('Прокрути вниз.', ScrollMove.down);
      expectScroll('Прокрути вверх', ScrollMove.up);
      expectScroll('Przewiń w dół', ScrollMove.down);
      expectScroll('انزل للأسفل', ScrollMove.down);
      expectScroll('向下滚动。', ScrollMove.down);
      expectScroll('下にスクロールしてください。', ScrollMove.down);
      expectScroll('위로 스크롤해줘', ScrollMove.up);
    });

    test('"scroll" said in any other language', () {
      expectScroll('Skrollaa alas.', ScrollMove.down); // Finnish
      expectScroll('Skrollaa ylös.', ScrollMove.up);
      expectScroll('Scrollează în sus', ScrollMove.up); // Romanian
    });

    test('other words stay what they were', () {
      expectUrl('search scroll saw', google('scroll saw'));
      expectUrl('open my scrolling app', google('my scrolling'));
      expectCommand('go back', BrowserCommand.back);
      expectCommand('go home', BrowserCommand.home);
      expect(
        (parseVoiceCommand('the top result')! as VoiceOpenResult).number,
        1,
      );
      expect(
        (parseVoiceCommand('صفحه اول گوگل')! as VoiceResultsPage).number,
        1,
      );
    });
  });

  test('close the browser', () {
    for (final heard in [
      'Close the browser.',
      'close browser',
      'exit the app',
      'مرورگر رو ببند',
      'براوزر رو ببند',
      'ببند مرورگر رو',
      'لطفا از مرورگر خارج شو',
      'Luk browseren.',
      'Browser schließen',
      'Ferme le navigateur.',
      'Cierra el navegador',
      'Закрой браузер.',
    ]) {
      expectCommand(heard, BrowserCommand.closeWindow);
    }
    // A plain "close" is still the tab.
    expectCommand('close', BrowserCommand.closeTab);
    expectCommand('ببند', BrowserCommand.closeTab);
    expectCommand('این تب رو ببند', BrowserCommand.closeTab);
    expectCommand('luk fanen', BrowserCommand.closeTab);
  });

  test('without free text, only commands and addresses', () {
    VoiceAction? strict(String heard) =>
        parseVoiceCommand(heard, searchFreeText: false);
    expect(strict('and then we went to the market'), isNull);
    expect(strict('ایران'), isNull);
    expect(strict('search Iran'), isA<VoiceNavigate>());
    expect(strict('YouTube'), isA<VoiceNavigate>());
    expect(
      (strict('digikala.com') as VoiceNavigate).url,
      'http://digikala.com',
    );
    expect(strict('go back'), isA<VoiceRunCommand>());
  });
}
