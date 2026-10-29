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
    test('international, IP and intranet hosts', () {
      expect(resolveInput('ایران.ir'), 'http://ایران.ir');
      expect(resolveInput('münchen.de/a'), 'http://münchen.de/a');
      expect(resolveInput('192.168.1.1:8080'), 'http://192.168.1.1:8080');
      expect(resolveInput('[::1]:8080/x'), 'http://[::1]:8080/x');
      expect(resolveInput('nas:5000'), 'http://nas:5000');
      expect(resolveInput('router/admin'), 'http://router/admin');
      expect(resolveInput('localhost'), 'http://localhost');
      expect(resolveInput('example.com/index.html'), startsWith('http://'));
    });
    test('bare schemes and Windows paths', () {
      expect(
        resolveInput('view-source:https://a.com/'),
        'view-source:https://a.com/',
      );
      expect(resolveInput('mailto:a@b.com'), 'mailto:a@b.com');
      expect(resolveInput(r'C:\x\a b.html'), 'file:///C:/x/a%20b.html');
    });
    test('file names, numbers and words are searches', () {
      for (final q in ['node.js', 'index.html', 'v2.0', '1.5', 'router']) {
        expect(resolveInput(q), startsWith('https://www.google.com/search'));
      }
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
