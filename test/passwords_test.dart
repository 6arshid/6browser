import 'dart:convert';
import 'dart:typed_data';

import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/features/import/import_models.dart';
import 'package:browser6/features/passwords/password_agent.dart';
import 'package:browser6/features/passwords/password_store.dart';
import 'package:browser6/features/passwords/passwords_page.dart';
import 'package:browser6/features/passwords/secret_box.dart';
import 'package:browser6/features/settings/app_settings.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/ui/browser_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_engine.dart';

/// Reversible but not plain text, so a missing seal/open shows up.
class FakeSecretBox implements SecretBox {
  @override
  bool get isAvailable => true;
  @override
  Future<Uint8List> seal(String secret) async =>
      Uint8List.fromList([for (final b in utf8.encode(secret)) b ^ 0x5A]);
  @override
  Future<String> open(Uint8List sealed) async =>
      utf8.decode([for (final b in sealed) b ^ 0x5A]);
}

class FakeVerifier implements UserVerifier {
  bool allow = true;
  int asked = 0;

  @override
  Future<bool> verify(String reason) async {
    asked++;
    return allow;
  }
}

/// The token and origin the agent put into its last injected script.
(String, String) lastInjection(FakeView view) {
  final m = RegExp(r'\}\)\("([0-9a-f]+)", "([^"]+)", function')
      .allMatches(view.scripts.join('\n'))
      .last;
  return (m.group(1)!, m.group(2)!);
}

void send(FakeView view, Map<String, Object?> message) =>
    view.scriptController.add(jsonEncode(message));

/// Loads [url] the way the engine reports it.
void navigate(FakeView view, String url) {
  view.isLoading.value = true;
  view.url.value = url;
  view.isLoading.value = false;
}

void main() {
  test('passwordOrigin keeps scheme, host and port of web pages', () {
    expect(passwordOrigin('https://a.test/login?next=/'), 'https://a.test');
    expect(passwordOrigin('http://a.test:8080/x'), 'http://a.test:8080');
    expect(passwordOrigin('about:blank'), isNull);
    expect(passwordOrigin('file:///C:/x.html'), isNull);
    expect(passwordOrigin('android://hash@com.app/'), isNull);
  });

  group('PasswordStore', () {
    late AppDatabase db;
    late PasswordStore store;
    setUp(() {
      db = AppDatabase.inMemory();
      store = PasswordStore(db, FakeSecretBox());
    });
    tearDown(() => db.close());

    test('saves encrypted and offers only what is new', () async {
      await store.save('https://a.test', 'ann', 'pw1');
      final saved = (await store.forOrigin('https://a.test')).single;
      expect(utf8.decode(saved.password, allowMalformed: true), isNot('pw1'));
      expect(await store.reveal(saved), 'pw1');

      expect(await store.offerFor('https://a.test', 'ann', 'pw1'), isNull);
      final update = await store.offerFor('https://a.test', 'ann', 'pw2');
      expect(update!.replaces!.id, saved.id);
      final fresh = await store.offerFor('https://a.test', 'bob', 'pw3');
      expect(fresh!.replaces, isNull);

      await store.neverSave('https://b.test');
      expect(await store.offerFor('https://b.test', 'ann', 'x'), isNull);
    });

    test('imports web sign-ins by origin', () async {
      final n = await store.import(const [
        ImportedLogin(
          url: 'https://a.test/signin/v2',
          username: 'ann',
          password: 'pw',
        ),
        ImportedLogin(
          url: 'android://x@com.app/',
          username: 'a',
          password: 'p',
        ),
        ImportedLogin(url: 'https://b.test/', username: 'b', password: ''),
      ]);
      expect(n, 1);
      final saved = (await store.forOrigin('https://a.test')).single;
      expect(saved.username, 'ann');
      expect(await store.reveal(saved), 'pw');
    });
  });

  group('PasswordAgent', () {
    late AppDatabase db;
    late PasswordStore store;
    late FakeView view;
    var settings = AppSettings.defaults;
    late PasswordAgent agent;

    void start({bool incognito = false}) {
      view = FakeView('https://site.test/login', incognito: incognito);
      agent = PasswordAgent(view: view, store: store, settings: () => settings);
    }

    setUp(() {
      db = AppDatabase.inMemory();
      store = PasswordStore(db, FakeSecretBox());
      settings = AppSettings.defaults;
    });
    tearDown(() async {
      agent.dispose();
      await db.close();
    });

    testWidgets('offers to save after the sign-in page goes away', (
      tester,
    ) async {
      start();
      final (token, origin) = lastInjection(view);
      expect(origin, 'https://site.test');

      send(view, {
        't': token,
        'type': 'submit',
        'username': 'ann',
        'password': 'pw1',
      });
      navigate(view, 'https://site.test/home');
      await tester.pump(const Duration(milliseconds: 1300));
      final offer = agent.offer.value!;
      expect(
        (offer.origin, offer.username, offer.password),
        ('https://site.test', 'ann', 'pw1'),
      );

      await tester.runAsync(() => agent.save(username: 'ann', password: 'pw1'));
      expect(agent.offer.value, isNull);
      final saved = await tester.runAsync(
        () => store.forOrigin('https://site.test'),
      );
      expect(saved!.single.username, 'ann');
    });

    testWidgets('no offer when the sign-in form comes back', (tester) async {
      start();
      final (token, _) = lastInjection(view);
      send(view, {
        't': token,
        'type': 'submit',
        'username': 'ann',
        'password': 'wrong',
      });
      navigate(view, 'https://site.test/login?error=1');
      final (next, _) = lastInjection(view);
      send(view, {'t': next, 'type': 'form'});
      await tester.pump(const Duration(milliseconds: 1300));
      expect(agent.offer.value, isNull);
    });

    testWidgets('ignores forged messages, private tabs and the setting', (
      tester,
    ) async {
      start();
      final (token, _) = lastInjection(view);
      Future<void> trySubmit(String t) async {
        send(view, {
          't': t,
          'type': 'submit',
          'username': 'ann',
          'password': 'pw',
        });
        view.scriptController.add('not json');
        await tester.pump(const Duration(milliseconds: 1300));
      }

      await trySubmit('0000');
      expect(agent.offer.value, isNull, reason: 'unknown token');

      settings = const AppSettings(savePasswords: false);
      await trySubmit(token);
      expect(agent.offer.value, isNull, reason: 'saving turned off');

      agent.dispose();
      settings = AppSettings.defaults;
      start(incognito: true);
      await trySubmit(lastInjection(view).$1);
      expect(agent.offer.value, isNull, reason: 'private tab');
    });

    testWidgets('fills the saved sign-in when the page shows a form', (
      tester,
    ) async {
      await tester.runAsync(
        () => store.save('https://site.test', 'ann', 'pw1'),
      );
      start();
      final (token, _) = lastInjection(view);
      view.scripts.clear();
      send(view, {'t': token, 'type': 'form'});
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(agent.logins.value.single.username, 'ann');
      final fill = view.scripts.single;
      expect(fill, contains('location.origin !== "https://site.test"'));
      expect(fill, contains('api.fill("ann", "pw1", false)'));

      // With filling turned off, the key still lists the sign-in.
      settings = const AppSettings(fillPasswords: false);
      view.scripts.clear();
      send(view, {'t': token, 'type': 'form'});
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(view.scripts, isEmpty);
      expect(agent.logins.value, hasLength(1));
    });

    testWidgets('a changed password is offered as an update', (tester) async {
      await tester.runAsync(
        () => store.save('https://site.test', 'ann', 'old'),
      );
      start();
      final (token, _) = lastInjection(view);
      send(view, {
        't': token,
        'type': 'submit',
        'username': 'ann',
        'password': 'new',
      });
      navigate(view, 'https://site.test/home');
      await tester.pump(const Duration(milliseconds: 1300));
      expect(agent.offer.value?.replaces, isNotNull);
      await tester.runAsync(() => agent.save(username: 'ann', password: 'new'));
      final saved = await tester.runAsync(
        () => store.forOrigin('https://site.test'),
      );
      expect(saved, hasLength(1));
      expect(await tester.runAsync(() => store.reveal(saved!.single)), 'new');
    });
  });

  group('screens', () {
    late FakeVerifier verifier;

    Future<ProviderContainer> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      verifier = FakeVerifier();
      final container = ProviderContainer(
        overrides: [
          engineProvider.overrideWithValue(FakeEngine()),
          databaseProvider.overrideWithValue(AppDatabase.inMemory()),
          secretBoxProvider.overrideWithValue(FakeSecretBox()),
          userVerifierProvider.overrideWithValue(verifier),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 10));
        container.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: home),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('the tab prompts to save, then the key fills it in', (
      tester,
    ) async {
      final c = await pump(tester, const BrowserShell());
      await tester.pumpAndSettle();
      final view = c.read(tabsProvider).active!.view as FakeView;
      navigate(view, 'https://site.test/login');
      await tester.pump();
      final (token, _) = lastInjection(view);
      send(view, {
        't': token,
        'type': 'submit',
        'username': 'ann',
        'password': 'pw1',
      });
      navigate(view, 'https://site.test/home');
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();

      expect(find.text('Save password?'), findsOneWidget);
      expect(find.text('site.test'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save password?'), findsNothing);

      // The site now has a saved sign-in: the key fills it in on demand.
      await tester.tap(find.byTooltip('Saved passwords for this site'));
      await tester.pumpAndSettle();
      view.scripts.clear();
      await tester.tap(find.text('ann'));
      await tester.pumpAndSettle();
      expect(view.scripts.single, contains('api.fill("ann", "pw1", true)'));
    });

    testWidgets('the password page shows only after verifying the user', (
      tester,
    ) async {
      final c = await pump(tester, const PasswordsPage());
      final store = c.read(passwordStoreProvider);
      await tester.runAsync(() => store.save('https://a.test', 'ann', 'pw1'));
      await tester.pumpAndSettle();
      expect(find.text('a.test'), findsOneWidget);
      expect(find.textContaining('pw1'), findsNothing);

      verifier.allow = false;
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(find.textContaining('pw1'), findsNothing);

      verifier.allow = true;
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(find.textContaining('pw1'), findsOneWidget);
      expect(verifier.asked, 2);

      // Delete, then undo.
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('a.test'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('a.test'), findsOneWidget);
    });
  });
}
