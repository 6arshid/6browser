import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../engine/browser_engine.dart';
import 'password_agent.dart';
import 'password_store.dart';
import 'passwords_page.dart';

/// Keeps the tab's [PasswordAgent] running and shows its "Save password?"
/// prompt over the page.
class PasswordHost extends ConsumerWidget {
  const PasswordHost({super.key, required this.view, required this.child});

  final BrowserView view;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agent = ref.watch(passwordAgentProvider(view));
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        PositionedDirectional(
          top: 8,
          end: 16,
          child: ValueListenableBuilder<SaveOffer?>(
            valueListenable: agent.offer,
            builder: (_, offer, _) => offer == null
                ? const SizedBox.shrink()
                : SavePasswordPrompt(
                    key: ObjectKey(offer),
                    agent: agent,
                    offer: offer,
                  ),
          ),
        ),
      ],
    );
  }
}

/// "Save password?" / "Update password?" with the user name and password,
/// both editable before saving.
class SavePasswordPrompt extends StatefulWidget {
  const SavePasswordPrompt({
    super.key,
    required this.agent,
    required this.offer,
  });

  final PasswordAgent agent;
  final SaveOffer offer;

  @override
  State<SavePasswordPrompt> createState() => _SavePasswordPromptState();
}

class _SavePasswordPromptState extends State<SavePasswordPrompt> {
  late final _username = TextEditingController(text: widget.offer.username);
  late final _password = TextEditingController(text: widget.offer.password);
  bool _show = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final update = offer.replaces != null;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        // Fits phones too.
        width: min(360, MediaQuery.sizeOf(context).width - 32),
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.key_outlined, color: muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    update ? 'Update password?' : 'Save password?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: widget.agent.dismiss,
                ),
              ],
            ),
            Text(Uri.parse(offer.origin).host, style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('save-username'),
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('save-password'),
                    controller: _password,
                    obscureText: !_show,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: _show ? 'Hide password' : 'Show password',
                        icon: Icon(
                          _show ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!update)
                    TextButton(
                      onPressed: widget.agent.never,
                      child: const Text('Never'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _password.text.isEmpty
                        ? null
                        : () => widget.agent.save(
                            username: _username.text.trim(),
                            password: _password.text,
                          ),
                    child: Text(update ? 'Update' : 'Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Key in the address bar when the site has saved passwords: pick one to
/// fill in, or open the password manager.
class PasswordKeyButton extends ConsumerWidget {
  const PasswordKeyButton({super.key, required this.view, this.color});

  final BrowserView view;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agent = ref.watch(passwordAgentProvider(view));
    return ValueListenableBuilder<List<Login>>(
      valueListenable: agent.logins,
      builder: (context, logins, _) {
        if (logins.isEmpty) return const SizedBox.shrink();
        return IconButton(
          tooltip: 'Saved passwords for this site',
          iconSize: 18,
          color: color,
          icon: const Icon(Icons.key_outlined),
          onPressed: () async {
            final box = context.findRenderObject()! as RenderBox;
            final at = box.localToGlobal(box.size.bottomLeft(Offset.zero));
            final choice = await showMenu<Object>(
              context: context,
              position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
              items: [
                for (final l in logins)
                  PopupMenuItem(
                    value: l,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(
                        l.username.isEmpty ? '(no username)' : l.username,
                      ),
                      subtitle: const Text('Fill in'),
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'manage',
                  child: Text('Manage passwords'),
                ),
              ],
            );
            if (!context.mounted) return;
            switch (choice) {
              case final Login login:
                await agent.fill(login, force: true);
              case 'manage':
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PasswordsPage(),
                  ),
                );
            }
          },
        );
      },
    );
  }
}
