import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'profile_instance.dart';

/// A browser profile. Each one has its own bookmarks, history, settings,
/// passwords, cookies and site data, and opens in its own window.
class Profile {
  const Profile({required this.id, required this.name, required this.color});

  factory Profile.fromJson(Map<String, Object?> json) => Profile(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as int,
  );

  static const defaultId = 'default';

  final String id;
  final String name;

  /// Avatar color, 0xAARRGGBB.
  final int color;

  bool get isDefault => id == defaultId;

  Map<String, Object> toJson() => {'id': id, 'name': name, 'color': color};

  Profile copyWith({String? name, int? color}) =>
      Profile(id: id, name: name ?? this.name, color: color ?? this.color);
}

/// Avatar colors to pick from.
const profileColors = [
  0xFF1A73E8,
  0xFF188038,
  0xFFD93025,
  0xFFE37400,
  0xFF9334E6,
  0xFF00897B,
  0xFFD01884,
  0xFF5F6368,
];

const _defaultProfile = Profile(
  id: Profile.defaultId,
  name: 'Default',
  color: 0xFF1A73E8,
);

/// The saved profiles, the default one first, and the one opened last.
class ProfileList {
  const ProfileList(this.profiles, this.lastUsed);

  final List<Profile> profiles;
  final String lastUsed;

  Profile? byId(String id) => profiles.where((x) => x.id == id).firstOrNull;
}

/// Keeps the profile list in `profiles.json` in [root], the app data folder.
/// Every window reads it again when it needs it, so a profile added in one
/// window shows up in the others.
class ProfileStore {
  ProfileStore(this.root);

  final Directory root;

  File get _file => File(p.join(root.path, 'profiles.json'));

  /// Where a profile's data lives. The default profile keeps the folder the
  /// browser used before profiles existed.
  Directory dataDir(String id) => id == Profile.defaultId
      ? root
      : Directory(p.join(root.path, 'profiles', id));

  Future<ProfileList> load() async {
    try {
      final json = jsonDecode(await _file.readAsString()) as Map;
      final saved = [
        for (final e in json['profiles'] as List)
          Profile.fromJson((e as Map).cast()),
      ];
      final profiles = [
        saved.where((x) => x.isDefault).firstOrNull ?? _defaultProfile,
        ...saved.where((x) => !x.isDefault),
      ];
      final last = json['lastUsed'] as String? ?? Profile.defaultId;
      return ProfileList(
        profiles,
        profiles.any((x) => x.id == last) ? last : Profile.defaultId,
      );
    } on Object {
      // No file yet (or a damaged one): just the default profile.
      return const ProfileList([_defaultProfile], Profile.defaultId);
    }
  }

  Future<void> _save(ProfileList list) async {
    await root.create(recursive: true);
    // Write a temporary file and rename it, so a crash never leaves half a
    // file behind.
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'profiles': [for (final x in list.profiles) x.toJson()],
        'lastUsed': list.lastUsed,
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  Future<Profile> create(String name, int color) async {
    final list = await load();
    final random = Random.secure();
    final id = List.generate(
      8,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final profile = Profile(id: id, name: name, color: color);
    await _save(ProfileList([...list.profiles, profile], list.lastUsed));
    return profile;
  }

  Future<void> update(Profile profile) async {
    final list = await load();
    await _save(
      ProfileList([
        for (final x in list.profiles) x.id == profile.id ? profile : x,
      ], list.lastUsed),
    );
  }

  Future<void> setLastUsed(String id) async {
    final list = await load();
    if (list.lastUsed != id) await _save(ProfileList(list.profiles, id));
  }

  /// Removes a profile and deletes its data. The default profile and a
  /// profile that is open in a window cannot be deleted.
  Future<void> delete(String id) async {
    if (id == Profile.defaultId) throw StateError('The default profile stays');
    final dir = dataDir(id);
    if (await ProfileInstance.isRunning(dir)) {
      throw StateError('The profile is open in a window');
    }
    final list = await load();
    await _save(
      ProfileList([
        for (final x in list.profiles)
          if (x.id != id) x,
      ], list.lastUsed == id ? Profile.defaultId : list.lastUsed),
    );
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// The profile this window runs, with where its data lives.
class ActiveProfile {
  const ActiveProfile({
    required this.profile,
    required this.store,
    this.instance,
  });

  final Profile profile;
  final ProfileStore store;

  /// This window's claim on the profile; null where windows are not
  /// separate processes (tests).
  final ProfileInstance? instance;

  Directory get dataDir => store.dataDir(profile.id);

  /// CEF's folder for cookies, site data and cache.
  String get cachePath => p.join(dataDir.path, 'cef_profile');
}

/// Set in main() on desktop. Null on phones, where there is one profile, and
/// in tests.
final activeProfileProvider = Provider<ActiveProfile?>((ref) => null);

/// All profiles, read fresh from disk; invalidate it to see changes made by
/// other windows.
final profileListProvider = FutureProvider<ProfileList?>((ref) async {
  final active = ref.watch(activeProfileProvider);
  return active?.store.load();
});

/// Opens [profile] in a new window. Overridden in tests.
final openProfileWindowProvider = Provider<Future<void> Function(Profile)>(
  (ref) =>
      (profile) => Process.start(Platform.resolvedExecutable, [
        '--profile=${profile.id}',
      ], mode: ProcessStartMode.detached),
);
