import 'package:browser6/features/tabs/url_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveInput', () {
    test('keeps full URLs', () {
      expect(resolveInput('https://example.com/a'), 'https://example.com/a');
    });
    test('adds http to hosts (the engine upgrades to https)', () {
      expect(resolveInput('example.com'), 'http://example.com');
      expect(resolveInput('localhost:8080/x'), 'http://localhost:8080/x');
      expect(resolveInput('http://neverssl.com'), 'http://neverssl.com');
    });
    test('turns text into a search', () {
      expect(
        resolveInput('flutter cef'),
        'https://www.google.com/search?q=flutter+cef',
      );
    });
    test('empty input is about:blank', () {
      expect(resolveInput('  '), 'about:blank');
    });
    test('custom search template', () {
      expect(
        resolveInput('hi there', searchTemplate: 'https://d.com/?q=%s'),
        'https://d.com/?q=hi+there',
      );
    });
  });

  test('httpsUpgradeOf', () {
    expect(
      httpsUpgradeOf('http://example.com/a?b=1'),
      'https://example.com/a?b=1',
    );
    expect(httpsUpgradeOf('http://example.com:80/'), 'https://example.com/');
    expect(httpsUpgradeOf('https://example.com/'), isNull);
    expect(httpsUpgradeOf('http://example.com:8080/'), isNull);
    expect(httpsUpgradeOf('http://localhost/'), isNull);
    expect(httpsUpgradeOf('http://router/'), isNull);
    expect(httpsUpgradeOf('http://192.168.1.1/'), isNull);
    expect(httpsUpgradeOf('http://[::1]/'), isNull);
    expect(httpsUpgradeOf('http://printer.local/'), isNull);
  });

  test('isWebStoreUrl', () {
    expect(
      isWebStoreUrl('https://chromewebstore.google.com/detail/x/abc'),
      isTrue,
    );
    expect(
      isWebStoreUrl('https://chrome.google.com/webstore/detail/x'),
      isTrue,
    );
    expect(
      isWebStoreUrl('https://www.google.com/search?q=chromewebstore'),
      isFalse,
    );
  });

  test('isSecureUrl', () {
    expect(isSecureUrl('https://a.com'), isTrue);
    expect(isSecureUrl('http://a.com'), isFalse);
  });
}
