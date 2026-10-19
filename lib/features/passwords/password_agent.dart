import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../engine/browser_engine.dart';
import '../settings/app_settings.dart';
import 'password_script.dart';
import 'password_store.dart';

/// Watches one tab for sign-in forms: fills saved passwords in, and offers
/// to save the ones the user signs in with.
class PasswordAgent {
  PasswordAgent({
    required this.view,
    required this.store,
    required this.settings,
  }) {
    _origin = passwordOrigin(view.url.value);
    view.url.addListener(_onUrl);
    view.isLoading.addListener(_onLoading);
    _messages = view.scriptMessages.listen(_onMessage);
    if (!view.isLoading.value) _inject();
  }

  final BrowserView view;
  final PasswordStore store;
  final AppSettings Function() settings;

  /// A sign-in to offer saving; the tab shows a prompt while it is set.
  final offer = ValueNotifier<SaveOffer?>(null);

  /// Saved sign-ins for the page's site, once it shows a password field.
  final logins = ValueNotifier<List<Login>>(const []);

  /// Tokens of the scripts injected lately, and the origin of each page.
  final _tokens = <String, String>{};
  late final StreamSubscription<String> _messages;
  String? _origin;

  /// A sign-in the page reported, offered once the next page shows no
  /// sign-in form (otherwise the password was probably wrong).
  ({String origin, String username, String password})? _pending;
  Timer? _promote;

  static final _random = Random.secure();

  void _onUrl() {
    final origin = passwordOrigin(view.url.value);
    if (origin != _origin) logins.value = const [];
    _origin = origin;
  }

  void _onLoading() {
    if (view.isLoading.value) return;
    _inject();
    if (_pending != null) _schedule();
  }

  Future<void> _inject() async {
    final origin = _origin;
    final post = view.scriptPostFunction;
    if (origin == null || post == null || !store.isAvailable) return;
    final token = List.generate(
      24,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    _tokens[token] = origin;
    if (_tokens.length > 16) _tokens.remove(_tokens.keys.first);
    await view.runScript(
      passwordScript(token: token, origin: origin, post: post),
    );
  }

  void _onMessage(String raw) {
    final Map<Object?, Object?> message;
    try {
      message = jsonDecode(raw) as Map;
    } on Object {
      return;
    }
    // Only our script knows a token, and each token belongs to one page.
    final origin = _tokens[message['t']];
    if (origin == null) return;
    switch (message['type']) {
      case 'form':
        _onForm(origin);
      case 'submit':
        _onSubmit(origin, message['username'], message['password']);
    }
  }

  Future<void> _onForm(String origin) async {
    if (_pending?.origin == origin) {
      // The sign-in form is back: the sign-in failed.
      _pending = null;
      _promote?.cancel();
    }
    final saved = await store.forOrigin(origin);
    if (origin != _origin) return;
    logins.value = saved;
    if (saved.isNotEmpty && settings().fillPasswords) await fill(saved.first);
  }

  void _onSubmit(String origin, Object? username, Object? password) {
    // Nothing from a private tab is kept.
    if (view.incognito || !settings().savePasswords) return;
    if (password is! String || password.isEmpty || password.length > 512) {
      return;
    }
    final user = username is String ? username.trim() : '';
    if (user.length > 256) return;
    _pending = (origin: origin, username: user, password: password);
    _schedule();
  }

  void _schedule() {
    _promote?.cancel();
    // While a page loads, wait for it (see _onLoading).
    if (view.isLoading.value) return;
    _promote = Timer(const Duration(milliseconds: 1200), _offer);
  }

  Future<void> _offer() async {
    final p = _pending;
    _pending = null;
    if (p == null) return;
    final next = await store.offerFor(p.origin, p.username, p.password);
    if (next != null) offer.value = next;
  }

  /// Saves the offered sign-in with the user's corrections.
  Future<void> save({
    required String username,
    required String password,
  }) async {
    final o = offer.value;
    if (o == null) return;
    offer.value = null;
    final old = o.replaces;
    if (old != null && old.username == username) {
      await store.edit(old, password: password);
    } else {
      await store.save(o.origin, username, password);
    }
    if (o.origin == _origin) logins.value = await store.forOrigin(o.origin);
  }

  /// Never offers to save passwords on the offered site again.
  Future<void> never() async {
    final o = offer.value;
    if (o == null) return;
    offer.value = null;
    await store.neverSave(o.origin);
  }

  void dismiss() => offer.value = null;

  /// Fills [login] into the page's sign-in form. With [force] (the user
  /// picked it), it replaces what was typed.
  Future<void> fill(Login login, {bool force = false}) async {
    final origin = _origin;
    if (origin == null || login.origin != origin) return;
    final password = await store.reveal(login);
    await view.runScript(
      passwordFillScript(
        origin: origin,
        username: login.username,
        password: password,
        force: force,
      ),
    );
    await store.markUsed(login);
  }

  void dispose() {
    view.url.removeListener(_onUrl);
    view.isLoading.removeListener(_onLoading);
    _messages.cancel();
    _promote?.cancel();
    offer.dispose();
    logins.dispose();
  }
}

/// The agent of each tab, alive while something shows the tab.
final passwordAgentProvider = Provider.autoDispose
    .family<PasswordAgent, BrowserView>((ref, view) {
      final agent = PasswordAgent(
        view: view,
        store: ref.watch(passwordStoreProvider),
        settings: () => ref.read(appSettingsProvider),
      );
      ref.onDispose(agent.dispose);
      return agent;
    });
