import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../import/import_models.dart';
import 'secret_box.dart';

/// The scheme, host and port of [url] for http(s) pages; null otherwise.
/// Saved passwords are matched to pages by it.
String? passwordOrigin(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  if (!uri.isScheme('https') && !uri.isScheme('http')) return null;
  return uri.origin;
}

/// A sign-in the user may want to save, or an update of a saved one.
class SaveOffer {
  const SaveOffer({
    required this.origin,
    required this.username,
    required this.password,
    this.replaces,
  });

  final String origin;
  final String username;
  final String password;

  /// The saved sign-in with this user name, when the password changed.
  final Login? replaces;
}

/// Saved passwords: encrypted in the profile's database with [box].
class PasswordStore {
  PasswordStore(this.db, this.box);

  final AppDatabase db;
  final SecretBox box;

  bool get isAvailable => box.isAvailable;

  Future<List<Login>> forOrigin(String origin) => db.loginsFor(origin);

  Future<String> reveal(Login login) => box.open(login.password);

  Future<void> save(String origin, String username, String password) async =>
      db.saveLogin(origin, username, await box.seal(password));

  Future<void> edit(Login login, {String? username, String? password}) async =>
      db.updateLogin(
        login.id,
        username: username,
        password: password == null ? null : await box.seal(password),
      );

  Future<void> markUsed(Login login) => db.touchLogin(login.id);

  Future<void> delete(Login login) => db.deleteLogin(login.id);

  /// Puts back a sign-in deleted by mistake (Undo).
  Future<void> restore(Login login) => db.restoreLogin(login);

  Future<void> neverSave(String origin) => db.neverSavePasswordsFor(origin);

  Future<void> allowSaving(String origin) => db.allowSavingPasswordsFor(origin);

  /// What to offer after a sign-in on [origin]: saving it, updating the
  /// password saved for that user name, or nothing (already saved, or the
  /// user said never for this site).
  Future<SaveOffer?> offerFor(
    String origin,
    String username,
    String password,
  ) async {
    if (!isAvailable || await db.isNeverSavePasswords(origin)) return null;
    for (final login in await forOrigin(origin)) {
      if (login.username != username) continue;
      if (await reveal(login) == password) {
        await db.touchLogin(login.id);
        return null;
      }
      return SaveOffer(
        origin: origin,
        username: username,
        password: password,
        replaces: login,
      );
    }
    return SaveOffer(origin: origin, username: username, password: password);
  }

  /// Saves passwords read from another browser; returns how many. Sign-ins
  /// for apps rather than web pages are skipped.
  Future<int> import(List<ImportedLogin> logins) async {
    var saved = 0;
    for (final l in logins) {
      final origin = passwordOrigin(l.url);
      if (origin == null || l.password.isEmpty) continue;
      await save(origin, l.username, l.password);
      saved++;
    }
    return saved;
  }
}

final passwordStoreProvider = Provider<PasswordStore>(
  (ref) =>
      PasswordStore(ref.watch(databaseProvider), ref.watch(secretBoxProvider)),
);

/// Every saved sign-in (passwords still encrypted).
final savedLoginsProvider = StreamProvider<List<Login>>(
  (ref) => ref.watch(databaseProvider).watchLogins(),
);
