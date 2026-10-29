import 'package:browser6/engine/browser_engine.dart';
import 'package:browser6/features/external_links/external_link_prompt.dart';
import 'package:browser6/features/external_links/external_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_engine.dart';

/// Apps by scheme (null: none installed); records what was opened.
class FakeApps extends ExternalApps {
  FakeApps(this.apps, {this.opens = _always});

  static bool _always(String url) => true;

  final Map<String, String?> apps;

  /// Whether an app takes [url] when it is opened.
  final bool Function(String url) opens;
  final opened = <String>[];

  @override
  Future<String?> appFor(String scheme) async => apps[scheme];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return opens(url);
  }
}

const _tg = 'tg://resolve?domain=shzir405_bot';
const _whatsAppIntent =
    'intent://send/?phone=989121234567#Intent;scheme=whatsapp;'
    'package=com.whatsapp;'
    'S.browser_fallback_url=https%3A%2F%2Fwww.whatsapp.com%2Fdownload;end';

void main() {
  test('only app links are handed to the system', () {
    expect(AppLink.parse(_tg)?.scheme, 'tg');
    expect(AppLink.parse('mailto:a@b.com')?.scheme, 'mailto');
    expect(AppLink.parse('tel:+989121234567')?.scheme, 'tel');
    expect(AppLink.parse('MS-Settings:display')?.scheme, 'ms-settings');
    expect(AppLink.parse('zoommtg://zoom.us/join?confno=1')?.scheme, 'zoommtg');
    // Can run files or scripts; drive letters are not schemes.
    expect(AppLink.parse('javascript:alert(1)'), isNull);
    expect(AppLink.parse('vbscript:msgbox'), isNull);
    expect(AppLink.parse('file:///C:/Windows/notepad.exe'), isNull);
    expect(AppLink.parse('shell:startup'), isNull);
    expect(AppLink.parse(r'c:\Windows\notepad.exe'), isNull);
    expect(AppLink.parse('no scheme'), isNull);
    expect(AppLink.parse('bad scheme:x'), isNull);
    expect(AppLink.parse('intent://x#Intent;scheme=javascript;end'), isNull);
  });

  test('reads Android intent links', () {
    final link = AppLink.parse(_whatsAppIntent)!;
    expect(link.scheme, 'intent');
    expect(link.target, 'whatsapp');
    expect(link.package, 'com.whatsapp');
    expect(link.fallbackUrl, 'https://www.whatsapp.com/download');
    // Only web pages are shown instead.
    expect(
      AppLink.parse(
        'intent://x#Intent;scheme=a;S.browser_fallback_url=javascript%3Ax;end',
      )!.fallbackUrl,
      isNull,
    );
  });

  test('finds the number or address to copy', () {
    expect(AppLink.parse('tel:+98%20912%20123')!.address, '+98 912 123');
    expect(AppLink.parse('sms:+98912?body=hi')!.address, '+98912');
    expect(AppLink.parse('mailto:a@b.com?subject=x')!.address, 'a@b.com');
    expect(AppLink.parse(_tg)!.address, isNull);
  });

  test('mail opens directly; calls, texts and WhatsApp only on phones', () {
    bool direct(String url, {required bool phone}) =>
        opensWithoutAsking(AppLink.parse(url)!, phone: phone);
    expect(direct('mailto:a@b.com', phone: false), isTrue);
    expect(direct('tel:+98912', phone: false), isFalse);
    expect(direct('tel:+98912', phone: true), isTrue);
    expect(direct('sms:+98912', phone: true), isTrue);
    expect(direct('whatsapp://send?phone=98912', phone: true), isTrue);
    expect(direct(_whatsAppIntent, phone: true), isTrue);
    expect(direct(_tg, phone: true), isFalse);
  });

  Future<(FakeView, FakeApps)> pumpHost(
    WidgetTester tester, {
    Map<String, String?> apps = const {'tg': 'Telegram Desktop'},
    bool Function(String url) opens = FakeApps._always,
  }) async {
    final view = FakeView('https://t.me/shzir405_bot');
    final fake = FakeApps(apps, opens: opens);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [externalAppsProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Scaffold(
            body: ExternalLinkHost(view: view, child: const SizedBox.expand()),
          ),
        ),
      ),
    );
    return (view, fake);
  }

  Future<void> request(
    WidgetTester tester,
    FakeView view,
    String url, {
    String source = 'https://t.me/shzir405_bot',
  }) async {
    view.externalLinkController.add(ExternalLinkRequest(url, source: source));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('asks before opening a Telegram link in its app', (tester) async {
    final (view, apps) = await pumpHost(tester);
    await request(tester, view, _tg);

    expect(find.text('Open Telegram Desktop?'), findsOneWidget);
    expect(find.text('t.me wants to open this app.'), findsOneWidget);
    expect(apps.opened, isEmpty);

    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(apps.opened, [_tg]);
    expect(find.byType(ExternalLinkPrompt), findsNothing);
  });

  testWidgets('Cancel opens nothing', (tester) async {
    final (view, apps) = await pumpHost(tester);
    await request(tester, view, _tg);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(apps.opened, isEmpty);
    expect(find.byType(ExternalLinkPrompt), findsNothing);
  });

  testWidgets('a typed link names no site', (tester) async {
    final (view, _) = await pumpHost(tester);
    await request(tester, view, _tg, source: '');
    expect(find.text('Open Telegram Desktop?'), findsOneWidget);
    expect(find.textContaining('wants to open'), findsNothing);
  });

  testWidgets('the question goes away when the tab navigates', (tester) async {
    final (view, apps) = await pumpHost(tester);
    await request(tester, view, _tg);
    view.url.value = 'https://telegram.org/';
    await tester.pump();
    expect(find.byType(ExternalLinkPrompt), findsNothing);
    expect(apps.opened, isEmpty);
  });

  testWidgets('mailto opens without asking', (tester) async {
    final (view, apps) = await pumpHost(tester, apps: {'mailto': 'Outlook'});
    await request(tester, view, 'mailto:a@b.com');
    expect(find.byType(ExternalLinkPrompt), findsNothing);
    expect(apps.opened, ['mailto:a@b.com']);
  });

  testWidgets('says so when no app opens the link', (tester) async {
    final (view, apps) = await pumpHost(tester, apps: {'tg': null});
    await request(tester, view, _tg);
    expect(find.byType(ExternalLinkPrompt), findsNothing);
    expect(find.text('No app on this device opens tg: links.'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(apps.opened, isEmpty);
  });

  testWidgets('calls, texts and WhatsApp open directly on a phone', (
    tester,
  ) async {
    final (view, apps) = await pumpHost(
      tester,
      apps: {'tel': '', 'sms': '', 'whatsapp': ''},
    );
    await request(tester, view, 'tel:+989121234567');
    await request(tester, view, 'sms:+989121234567?body=Hi');
    await request(tester, view, 'whatsapp://send?phone=989121234567');
    expect(find.byType(ExternalLinkPrompt), findsNothing);
    expect(apps.opened, [
      'tel:+989121234567',
      'sms:+989121234567?body=Hi',
      'whatsapp://send?phone=989121234567',
    ]);
  });

  testWidgets('a call link asks first on a computer', (tester) async {
    // Windows has no default app for tel: links and lets the user pick.
    final (view, apps) = await pumpHost(tester, apps: {'tel': ''});
    await request(tester, view, 'tel:+989121234567');
    expect(find.text('Open this link in another app?'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(apps.opened, ['tel:+989121234567']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('without WhatsApp, its intent link shows the web page', (
    tester,
  ) async {
    final (view, apps) = await pumpHost(
      tester,
      apps: {'intent': ''},
      opens: (_) => false,
    );
    await request(tester, view, _whatsAppIntent);
    expect(apps.opened, [_whatsAppIntent]);
    expect(view.url.value, 'https://www.whatsapp.com/download');
  });

  testWidgets('an intent link without a web page looks in the store', (
    tester,
  ) async {
    final (view, apps) = await pumpHost(
      tester,
      apps: {'intent': ''},
      opens: (url) => url.startsWith('market:'),
    );
    await request(
      tester,
      view,
      'intent://send/?phone=1#Intent;scheme=whatsapp;package=com.whatsapp;end',
    );
    expect(apps.opened.last, 'market://details?id=com.whatsapp');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('without a phone app, the number can be copied', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final (view, _) = await pumpHost(tester, apps: {'tel': null});
    await request(tester, view, 'tel:+989121234567');
    expect(
      find.text('No app on this device opens tel: links.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 500)); // slides in
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, '+989121234567');
  });

  testWidgets('dangerous schemes are ignored', (tester) async {
    final (view, apps) = await pumpHost(
      tester,
      apps: {'vbscript': 'Windows Script Host'},
    );
    await request(tester, view, 'vbscript:msgbox(1)');
    expect(find.byType(ExternalLinkPrompt), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(apps.opened, isEmpty);
  });
}
