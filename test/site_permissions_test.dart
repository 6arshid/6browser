import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/engine/browser_engine.dart';
import 'package:browser6/engine/cef_engine.dart';
import 'package:browser6/features/site_permissions/permission_prompt.dart';
import 'package:browser6/features/site_permissions/site_permissions.dart';
import 'package:browser6/features/site_permissions/site_permissions_page.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_engine.dart';

const _meet = 'https://meet.google.com';
const _media = {SitePermission.camera, SitePermission.microphone};

/// A request whose answers are recorded in [answers].
PermissionRequest _ask(
  List<PermissionAnswer> answers, {
  String origin = _meet,
  Set<SitePermission> permissions = _media,
}) => PermissionRequest(
  origin: origin,
  permissions: permissions,
  onAnswer: answers.add,
);

void main() {
  late AppDatabase db;
  late FakeEngine engine;

  Future<FakeView> pumpHost(
    WidgetTester tester, {
    bool incognito = false,
  }) async {
    db = AppDatabase.inMemory();
    engine = FakeEngine();
    final view = FakeView('$_meet/abc-defg-hij', incognito: incognito);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        engineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SitePermissionHost(
              view: view,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    return view;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('Allow is remembered: the site is not asked again', (
    tester,
  ) async {
    final view = await pumpHost(tester);
    final answers = <PermissionAnswer>[];
    view.permissionController.add(_ask(answers));
    await settle(tester);

    expect(find.text('meet.google.com wants to'), findsOneWidget);
    expect(find.text('Use your camera'), findsOneWidget);
    expect(find.text('Use your microphone'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await settle(tester);
    expect(answers, [PermissionAnswer.allow]);
    expect(find.byType(PermissionPrompt), findsNothing);

    // Chromium asks for the devices right after its own prompt.
    final again = <PermissionAnswer>[];
    view.permissionController.add(_ask(again));
    await settle(tester);
    expect(again, [PermissionAnswer.allow]);
    expect(find.byType(PermissionPrompt), findsNothing);
    // Saved: also after a restart.
    final rows = await db.sitePermissionsFor(_meet);
    expect(
      {for (final r in rows) r.permission: r.allowed},
      {'camera': true, 'microphone': true},
    );
  });

  testWidgets('Block is remembered, and blocks a request that includes it', (
    tester,
  ) async {
    final view = await pumpHost(tester);
    final answers = <PermissionAnswer>[];
    view.permissionController.add(
      _ask(answers, permissions: {SitePermission.microphone}),
    );
    await settle(tester);
    await tester.tap(find.text('Block'));
    await settle(tester);
    expect(answers, [PermissionAnswer.block]);

    final again = <PermissionAnswer>[];
    view.permissionController.add(_ask(again));
    await settle(tester);
    expect(again, [PermissionAnswer.block]);
    expect(find.byType(PermissionPrompt), findsNothing);
  });

  testWidgets('closing the prompt refuses this time only', (tester) async {
    final view = await pumpHost(tester);
    final answers = <PermissionAnswer>[];
    view.permissionController.add(_ask(answers));
    await settle(tester);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    expect(answers, [PermissionAnswer.dismiss]);
    expect(await db.sitePermissionsFor(_meet), isEmpty);

    view.permissionController.add(_ask(<PermissionAnswer>[]));
    await settle(tester);
    expect(find.byType(PermissionPrompt), findsOneWidget);
  });

  testWidgets('a request waiting behind another is answered with it', (
    tester,
  ) async {
    final view = await pumpHost(tester);
    final first = <PermissionAnswer>[];
    final second = <PermissionAnswer>[];
    view.permissionController.add(_ask(first));
    view.permissionController.add(
      _ask(second, permissions: {SitePermission.camera}),
    );
    await settle(tester);
    expect(find.byType(PermissionPrompt), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await settle(tester);
    expect(first, [PermissionAnswer.allow]);
    expect(second, [PermissionAnswer.allow]);
    expect(find.byType(PermissionPrompt), findsNothing);
  });

  testWidgets('the prompt goes away when the tab opens another site', (
    tester,
  ) async {
    final view = await pumpHost(tester);
    final answers = <PermissionAnswer>[];
    view.permissionController.add(_ask(answers));
    await settle(tester);
    // Same site: still asking.
    view.url.value = '$_meet/landing';
    await settle(tester);
    expect(find.byType(PermissionPrompt), findsOneWidget);

    view.url.value = 'https://example.com/';
    await settle(tester);
    expect(answers, [PermissionAnswer.dismiss]);
    expect(find.byType(PermissionPrompt), findsNothing);
  });

  testWidgets('a withdrawn request closes its prompt', (tester) async {
    final view = await pumpHost(tester);
    final request = _ask(<PermissionAnswer>[]);
    view.permissionController.add(request);
    await settle(tester);
    request.withdraw();
    await settle(tester);
    expect(find.byType(PermissionPrompt), findsNothing);
  });

  testWidgets('private tabs remember in memory only; saved blocks apply', (
    tester,
  ) async {
    final view = await pumpHost(tester, incognito: true);
    await db.setSitePermissions('https://blocked.example', ['camera'], false);

    final answers = <PermissionAnswer>[];
    view.permissionController.add(_ask(answers));
    await settle(tester);
    expect(find.textContaining('private window'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await settle(tester);
    expect(answers, [PermissionAnswer.allow]);
    expect(await db.sitePermissionsFor(_meet), isEmpty);

    final again = <PermissionAnswer>[];
    view.permissionController.add(_ask(again));
    await settle(tester);
    expect(again, [PermissionAnswer.allow]);

    final blocked = <PermissionAnswer>[];
    view.permissionController.add(
      _ask(
        blocked,
        origin: 'https://blocked.example',
        permissions: {SitePermission.camera},
      ),
    );
    await settle(tester);
    expect(blocked, [PermissionAnswer.block]);
  });

  testWidgets('settings change and forget a decision', (tester) async {
    db = AppDatabase.inMemory();
    engine = FakeEngine();
    await db.setSitePermissions(_meet, ['camera', 'microphone'], true);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        engineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SitePermissionsPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('meet.google.com'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Microphone'), findsOneWidget);

    // Camera: Allow -> Block.
    await tester.tap(find.text('Allow').first);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.text('Block').last);
    await tester.pump(const Duration(milliseconds: 10));
    final rows = await db.sitePermissionsFor(_meet);
    expect(
      {for (final r in rows) r.permission: r.allowed},
      {'camera': false, 'microphone': true},
    );
    expect(engine.sitePermissionChanges.single.allowed, isFalse);
    expect(engine.sitePermissionChanges.single.permissions, {
      SitePermission.camera,
    });

    await tester.tap(find.text('Reset'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(await db.sitePermissionsFor(_meet), isEmpty);
    expect(engine.sitePermissionChanges.last.allowed, isNull);
    expect(find.textContaining('appear here'), findsOneWidget);
  });

  test('CEF permission bits map to site permissions and back', () {
    // Camera and microphone, as the device request reports them.
    expect(sitePermissionsOf(1 << 2 | 1 << 12), _media);
    expect(cefPermissionBits(_media), 1 << 2 | 1 << 12);
    expect(sitePermissionsOf(1 << 26), {SitePermission.localNetwork});
    // Notifications cannot be shown by this engine: not offered.
    expect(sitePermissionsOf(1 << 15), isNull);
    expect(sitePermissionsOf(1 << 2 | 1 << 15), isNull);
    expect(sitePermissionsOf(0), isNull);
    for (final p in SitePermission.values) {
      expect(sitePermissionsOf(cefPermissionBits({p})), {p});
    }
  });

  test('site names leave out the scheme and default ports', () {
    expect(siteName('https://meet.google.com'), 'meet.google.com');
    expect(siteName('http://localhost:8080'), 'localhost:8080');
    expect(siteName('file:///C:/x.html'), 'file:///C:/x.html');
  });
}
