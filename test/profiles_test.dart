import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:browser6/data/database.dart';
import 'package:browser6/data/providers.dart';
import 'package:browser6/features/profiles/profile_instance.dart';
import 'package:browser6/features/profiles/profiles.dart';
import 'package:browser6/features/profiles/profiles_page.dart';
import 'package:browser6/features/tabs/tabs_controller.dart';
import 'package:browser6/ui/browser_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/fake_engine.dart';

/// Keeps profiles in memory, so widget tests need no file system.
class FakeProfileStore implements ProfileStore {
  FakeProfileStore(this.profiles);

  List<Profile> profiles;

  @override
  Directory get root => Directory('unused');
  @override
  Directory dataDir(String id) => Directory(p.join('unused', id));
  @override
  Future<ProfileList> load() async =>
      ProfileList(List.of(profiles), Profile.defaultId);
  @override
  Future<Profile> create(String name, int color) async {
    final profile = Profile(
      id: 'p${profiles.length}',
      name: name,
      color: color,
    );
    profiles = [...profiles, profile];
    return profile;
  }

  @override
  Future<void> update(Profile profile) async =>
      profiles = [for (final x in profiles) x.id == profile.id ? profile : x];
  @override
  Future<void> setLastUsed(String id) async {}
  @override
  Future<void> delete(String id) async =>
      profiles = [...profiles.where((x) => x.id != id)];
}

const _default = Profile(
  id: Profile.defaultId,
  name: 'Default',
  color: 0xFF1A73E8,
);
const _work = Profile(id: 'w', name: 'Work', color: 0xFF188038);

void main() {
  group('ProfileStore', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('6b_prof_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('starts with the default profile in the old data folder', () async {
      final store = ProfileStore(root);
      final list = await store.load();
      expect(list.profiles.single.id, Profile.defaultId);
      expect(list.lastUsed, Profile.defaultId);
      expect(store.dataDir(Profile.defaultId).path, root.path);
    });

    test('creates, renames, remembers and deletes profiles', () async {
      final store = ProfileStore(root);
      final work = await store.create('Work', profileColors[1]);
      expect(
        store.dataDir(work.id).path,
        p.join(root.path, 'profiles', work.id),
      );
      await store.update(work.copyWith(name: 'Job'));
      await store.setLastUsed(work.id);
      var list = await store.load();
      expect(list.profiles.map((x) => x.name), ['Default', 'Job']);
      expect(list.lastUsed, work.id);

      await store.dataDir(work.id).create(recursive: true);
      await store.delete(work.id);
      list = await store.load();
      expect(list.profiles.map((x) => x.id), [Profile.defaultId]);
      expect(list.lastUsed, Profile.defaultId);
      expect(store.dataDir(work.id).existsSync(), isFalse);
      await expectLater(store.delete(Profile.defaultId), throwsStateError);
    });

    test(
      'a profile open in a window is not deleted',
      () async {
        final store = ProfileStore(root);
        final work = await store.create('Work', profileColors[1]);
        final instance = await ProfileInstance.acquire(store.dataDir(work.id));
        addTearDown(() => instance!.close());
        await expectLater(store.delete(work.id), throwsStateError);
        expect((await store.load()).byId(work.id), isNotNull);
      },
      // POSIX file locks belong to the process, so it cannot lock itself out.
      skip: !Platform.isWindows,
    );
  });

  group('ProfileInstance', () {
    late Directory dir;
    late ProfileInstance first;
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('6b_inst_');
      first = (await ProfileInstance.acquire(dir))!;
    });
    tearDown(() async {
      await first.close();
      dir.deleteSync(recursive: true);
    });

    test('a second launch hands its command line to the first', () async {
      if (Platform.isWindows) {
        expect(await ProfileInstance.acquire(dir), isNull);
        expect(await ProfileInstance.isRunning(dir), isTrue);
      }
      final received = first.requests.first;
      expect(
        await ProfileInstance.handOver(dir, ['--incognito', 'https://x.test']),
        isTrue,
      );
      expect(await received, ['--incognito', 'https://x.test']);
    });

    test('messages without the token are ignored', () async {
      final events = <List<String>>[];
      final got = Completer<void>();
      final sub = first.requests.listen((e) {
        events.add(e);
        if (!got.isCompleted) got.complete();
      });
      addTearDown(sub.cancel);
      final info = jsonDecode(
        File(p.join(dir.path, 'instance.json')).readAsStringSync(),
      ) as Map;
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        info['port'] as int,
      );
      socket.writeln(
        jsonEncode({
          'token': 'wrong',
          'args': ['https://evil.test'],
        }),
      );
      await socket.flush();
      await socket.close();
      await ProfileInstance.handOver(dir, ['https://ok.test']);
      await got.future.timeout(const Duration(seconds: 5));
      expect(events, [
        ['https://ok.test'],
      ]);
    });
  });

  test('LaunchOptions reads the profile', () {
    final o = LaunchOptions.parse(['--profile=abc', 'https://x.test']);
    expect(o.profile, 'abc');
    expect(o.url, 'https://x.test');
    expect(LaunchOptions.parse(const []).profile, isNull);
  });

  testWidgets('the avatar menu opens other profiles and adds new ones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = FakeProfileStore([_default, _work]);
    final opened = <String>[];
    final container = ProviderContainer(
      overrides: [
        engineProvider.overrideWithValue(FakeEngine()),
        databaseProvider.overrideWithValue(AppDatabase.inMemory()),
        activeProfileProvider.overrideWithValue(
          ActiveProfile(profile: _default, store: store),
        ),
        openProfileWindowProvider.overrideWithValue(
          (profile) async => opened.add(profile.id),
        ),
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
        child: const MaterialApp(home: BrowserShell()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Default'));
    await tester.pumpAndSettle();
    expect(find.text('This window'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(opened, ['w']);

    await tester.tap(find.byTooltip('Default'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Kids');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(store.profiles.map((x) => x.name), ['Default', 'Work', 'Kids']);
    expect(opened, ['w', 'p2']);
  });

  testWidgets('the profiles page renames and deletes profiles', (tester) async {
    final store = FakeProfileStore([_default, _work]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeProfileProvider.overrideWithValue(
            ActiveProfile(profile: _default, store: store),
          ),
        ],
        child: const MaterialApp(home: ProfilesPage()),
      ),
    );
    await tester.pumpAndSettle();
    // Neither this window's profile nor the default one can be deleted.
    expect(find.byTooltip('Delete'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Job');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Job'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.profiles.map((x) => x.name), ['Default']);
    expect(find.text('Job'), findsNothing);
  });
}
