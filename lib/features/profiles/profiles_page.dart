import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/anchored_popup.dart';
import 'profiles.dart';

/// Round avatar with the profile's color and initial.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.radius = 12});

  final Profile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final name = profile.name.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(profile.color),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.95,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// This window's profile, as saved now (another window may have renamed
/// it); null where there are no profiles.
Profile? currentProfile(WidgetRef ref) {
  final active = ref.watch(activeProfileProvider);
  if (active == null) return null;
  return ref.watch(profileListProvider).value?.byId(active.profile.id) ??
      active.profile;
}

/// Toolbar button showing this window's profile; opens the profile menu.
class ProfileButton extends ConsumerWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = currentProfile(ref);
    if (me == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: me.name,
      icon: ProfileAvatar(profile: me, radius: 11),
      onPressed: () => showProfileMenu(context, ref),
    );
  }
}

/// The profile menu: this profile, the others (each opens in its own
/// window), Add profile and Manage profiles.
Future<void> showProfileMenu(BuildContext anchor, WidgetRef ref) async {
  // Pick up profiles added or renamed in other windows.
  ref.invalidate(profileListProvider);
  final choice = await showAnchoredPopup<Object>(
    anchor,
    width: 300,
    builder: (_) => const _ProfileMenu(),
  );
  if (!anchor.mounted) return;
  switch (choice) {
    case final Profile other:
      await ref.read(openProfileWindowProvider)(other);
    case 'add':
      await addProfile(anchor, ref);
    case 'manage':
      await Navigator.of(anchor)
          .push(MaterialPageRoute<void>(builder: (_) => const ProfilesPage()));
  }
}

class _ProfileMenu extends ConsumerWidget {
  const _ProfileMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = currentProfile(ref)!;
    final list = ref.watch(profileListProvider).value;
    final others = [
      for (final p in list?.profiles ?? const <Profile>[])
        if (p.id != me.id) p,
    ];
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Column(
            children: [
              ProfileAvatar(profile: me, radius: 28),
              const SizedBox(height: 10),
              Text(me.name, style: Theme.of(context).textTheme.titleMedium),
              Text('This window', style: TextStyle(color: muted)),
            ],
          ),
        ),
        const Divider(height: 1),
        if (others.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Other profiles', style: TextStyle(color: muted)),
          ),
          for (final p in others)
            ListTile(
              dense: true,
              leading: ProfileAvatar(profile: p),
              title: Text(p.name),
              onTap: () => Navigator.pop(context, p),
            ),
          const Divider(height: 1),
        ],
        ListTile(
          dense: true,
          leading: const Icon(Icons.person_add_alt_1_outlined),
          title: const Text('Add profile'),
          onTap: () => Navigator.pop(context, 'add'),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.manage_accounts_outlined),
          title: const Text('Manage profiles'),
          onTap: () => Navigator.pop(context, 'manage'),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// Asks for a name and color, creates the profile and opens its window.
Future<void> addProfile(BuildContext context, WidgetRef ref) async {
  final active = ref.read(activeProfileProvider);
  if (active == null) return;
  final count = ref.read(profileListProvider).value?.profiles.length ?? 1;
  final result = await showDialog<(String, int)>(
    context: context,
    builder: (_) => _ProfileDialog(
      title: 'Add profile',
      action: 'Add',
      name: 'Person ${count + 1}',
      color: profileColors[count % profileColors.length],
    ),
  );
  if (result == null) return;
  final profile = await active.store.create(result.$1, result.$2);
  ref.invalidate(profileListProvider);
  await ref.read(openProfileWindowProvider)(profile);
}

Future<void> _editProfile(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final result = await showDialog<(String, int)>(
    context: context,
    builder: (_) => _ProfileDialog(
      title: 'Edit profile',
      action: 'Save',
      name: profile.name,
      color: profile.color,
    ),
  );
  if (result == null) return;
  await ref
      .read(activeProfileProvider)!
      .store
      .update(profile.copyWith(name: result.$1, color: result.$2));
  ref.invalidate(profileListProvider);
}

Future<void> _deleteProfile(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete "${profile.name}"?'),
      content: const Text(
        "This profile's bookmarks, history, passwords, settings and site data "
        'on this computer will be deleted. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(activeProfileProvider)!.store.delete(profile.id);
  } on StateError {
    messenger.showSnackBar(
      SnackBar(content: Text('Close the "${profile.name}" window first.')),
    );
  } on Object catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not delete the profile: $e')),
    );
  }
  ref.invalidate(profileListProvider);
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({
    required this.title,
    required this.action,
    required this.name,
    required this.color,
  });

  final String title;
  final String action;
  final String name;
  final int color;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final _name = TextEditingController(
    text: widget.name,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.name.length);
  late int _color = widget.color;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name, _color));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('profile-name'),
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in profileColors)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c),
                    child: c == _color
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}

/// Lists the profiles: open one in its window, rename it, change its
/// color, delete it, or add another.
class ProfilesPage extends ConsumerWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = currentProfile(ref);
    final list = ref.watch(profileListProvider).value;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      floatingActionButton: me == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add profile'),
              onPressed: () => addProfile(context, ref),
            ),
      body: me == null || list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Each profile has its own bookmarks, history, passwords, '
                    'settings and signed-in sites, and opens in its own '
                    'window.',
                    style: TextStyle(color: muted),
                  ),
                ),
                for (final p in list.profiles)
                  ListTile(
                    leading: ProfileAvatar(profile: p, radius: 18),
                    title: Text(p.name),
                    subtitle: Text(
                      [
                        if (p.id == me.id) 'This window',
                        if (p.isDefault) 'Default profile',
                      ].join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (p.id != me.id)
                          TextButton(
                            onPressed: () =>
                                ref.read(openProfileWindowProvider)(p),
                            child: const Text('Open'),
                          ),
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editProfile(context, ref, p),
                        ),
                        if (!p.isDefault && p.id != me.id)
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteProfile(context, ref, p),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
