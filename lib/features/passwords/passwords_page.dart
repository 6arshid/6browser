import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../ui/favicon.dart';
import 'password_store.dart';
import 'secret_box.dart';

final _neverSaveProvider = StreamProvider<List<String>>(
  (ref) => ref.watch(databaseProvider).watchNeverSavePasswords(),
);

/// The password manager: every saved sign-in of this profile. Showing,
/// copying, editing or exporting a password first asks Windows Hello (or
/// the phone's screen lock) to confirm it is the user.
class PasswordsPage extends ConsumerStatefulWidget {
  const PasswordsPage({super.key});

  @override
  ConsumerState<PasswordsPage> createState() => _PasswordsPageState();
}

class _PasswordsPageState extends ConsumerState<PasswordsPage> {
  final _search = TextEditingController();
  String _query = '';

  /// Passwords the user chose to show, by sign-in id.
  final _shown = <int, String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  PasswordStore get _store => ref.read(passwordStoreProvider);

  Future<bool> _verify(String reason) =>
      ref.read(userVerifierProvider).verify(reason);

  void _snack(String text, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text), action: action));

  Future<void> _toggle(Login login) async {
    if (_shown.containsKey(login.id)) {
      setState(() => _shown.remove(login.id));
      return;
    }
    if (!await _verify('6browser wants to show a saved password')) return;
    final password = await _store.reveal(login);
    if (mounted) setState(() => _shown[login.id] = password);
  }

  Future<void> _copy(Login login) async {
    if (!await _verify('6browser wants to copy a saved password')) return;
    await Clipboard.setData(ClipboardData(text: await _store.reveal(login)));
    if (mounted) _snack('Password copied');
  }

  Future<void> _edit(Login login) async {
    if (!await _verify('6browser wants to edit a saved password')) return;
    final password = await _store.reveal(login);
    if (!mounted) return;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _EditDialog(login: login, password: password),
    );
    if (result == null) return;
    try {
      await _store.edit(login, username: result.$1, password: result.$2);
      setState(() => _shown.remove(login.id));
    } on Object {
      _snack('A password for ${result.$1} on this site is already saved');
    }
  }

  Future<void> _delete(Login login) async {
    await _store.delete(login);
    setState(() => _shown.remove(login.id));
    _snack(
      'Password deleted',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _store.restore(login),
      ),
    );
  }

  Future<void> _export(List<Login> logins) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export passwords?'),
        content: const Text(
          'The passwords are saved to a CSV file that is not encrypted. '
          'Anyone who can open the file can read them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (ok != true || !await _verify('6browser wants to export passwords')) {
      return;
    }
    final dir =
        await getDownloadsDirectory() ?? await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, '6browser-passwords.csv'));
    final csv = StringBuffer('name,url,username,password\r\n');
    for (final l in logins) {
      csv.write(
        '${_csv(Uri.parse(l.origin).host)},${_csv(l.origin)},'
        '${_csv(l.username)},${_csv(await _store.reveal(l))}\r\n',
      );
    }
    await file.writeAsString(csv.toString());
    if (mounted) _snack('Exported ${logins.length} to ${file.path}');
  }

  static String _csv(String v) =>
      v.contains(RegExp('[,"\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(passwordStoreProvider);
    final saved = ref.watch(savedLoginsProvider).value ?? const <Login>[];
    final never = ref.watch(_neverSaveProvider).value ?? const <String>[];
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final l in saved)
        if (l.origin.toLowerCase().contains(query) ||
            l.username.toLowerCase().contains(query))
          l,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Passwords'),
        actions: [
          if (saved.isNotEmpty)
            IconButton(
              tooltip: 'Export passwords',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => _export(saved),
            ),
        ],
      ),
      body: !store.isAvailable
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Saving passwords is not available on this system yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search passwords',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          saved.isEmpty
                              ? 'No saved passwords yet. When you sign in to a '
                                    'site, 6browser offers to save the password.'
                              : 'No matching passwords.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted),
                        ),
                      ),
                    for (final l in shown)
                      ListTile(
                        key: ValueKey(l.id),
                        leading: Favicon(url: l.origin, size: 20, color: muted),
                        title: Text(Uri.parse(l.origin).host),
                        subtitle: Text(
                          '${l.username.isEmpty ? '(no username)' : l.username}'
                          '\n${_shown[l.id] ?? '••••••••'}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _shown.containsKey(l.id)
                                  ? 'Hide password'
                                  : 'Show password',
                              icon: Icon(
                                _shown.containsKey(l.id)
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () => _toggle(l),
                            ),
                            IconButton(
                              tooltip: 'Copy password',
                              icon: const Icon(Icons.copy_outlined),
                              onPressed: () => _copy(l),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'More actions',
                              onSelected: (v) =>
                                  v == 'edit' ? _edit(l) : _delete(l),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    if (never.isNotEmpty) ...[
                      const Divider(height: 32),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text(
                          'Never saved',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      for (final origin in never)
                        ListTile(
                          leading: Favicon(url: origin, size: 20, color: muted),
                          title: Text(Uri.parse(origin).host),
                          trailing: IconButton(
                            tooltip: 'Offer to save again',
                            icon: const Icon(Icons.close),
                            onPressed: () => store.allowSaving(origin),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.login, required this.password});

  final Login login;
  final String password;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _username = TextEditingController(text: widget.login.username);
  late final _password = TextEditingController(text: widget.password);

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit password'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Uri.parse(widget.login.origin).host),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('edit-username'),
            controller: _username,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('edit-password'),
            controller: _password,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => _password.text.isEmpty
            ? null
            : Navigator.pop(context, (_username.text.trim(), _password.text)),
        child: const Text('Save'),
      ),
    ],
  );
}
