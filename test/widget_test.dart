import 'package:browser6/features/tabs/url_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveInput', () {
    test('keeps full URLs', () {
      expect(resolveInput('https://example.com/a'), 'https://example.com/a');
    });
    test('adds https to hosts', () {
      expect(resolveInput('example.com'), 'https://example.com');
      expect(resolveInput('localhost:8080/x'), 'https://localhost:8080/x');
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

  test('isSecureUrl', () {
    expect(isSecureUrl('https://a.com'), isTrue);
    expect(isSecureUrl('http://a.com'), isFalse);
  });
}
