import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'site_permissions.dart';

/// Every site's saved decisions, with each permission changeable.
final sitePermissionsProvider = StreamProvider<List<SitePermissionEntry>>(
  (ref) => ref.watch(sitePermissionStoreProvider).watchAll(),
);

/// Settings > Site permissions: what each site may use. "Ask" forgets the
/// decision, so the site asks again.
class SitePermissionsPage extends ConsumerWidget {
  const SitePermissionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(sitePermissionsProvider).value;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final sites = <String, List<SitePermissionEntry>>{};
    for (final entry in entries ?? const <SitePermissionEntry>[]) {
      sites.putIfAbsent(entry.origin, () => []).add(entry);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Site permissions')),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : sites.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Sites you allow or block (camera, microphone, location...) '
                  'appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    for (final MapEntry(key: origin, value: list)
                        in sites.entries)
                      _SiteCard(origin: origin, entries: list),
                  ],
                ),
              ),
            ),
    );
  }
}

enum _Choice { allow, block, ask }

class _SiteCard extends ConsumerWidget {
  const _SiteCard({required this.origin, required this.entries});

  final String origin;
  final List<SitePermissionEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(sitePermissionStoreProvider);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    siteName(origin),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => store.forgetSite(origin, {
                    for (final e in entries) e.permission,
                  }),
                  child: const Text('Reset'),
                ),
              ],
            ),
            for (final entry in entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(entry.permission.icon),
                title: Text(entry.permission.label),
                trailing: DropdownButton<_Choice>(
                  value: entry.allowed ? _Choice.allow : _Choice.block,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: _Choice.allow,
                      child: Text('Allow'),
                    ),
                    DropdownMenuItem(
                      value: _Choice.block,
                      child: Text('Block'),
                    ),
                    DropdownMenuItem(value: _Choice.ask, child: Text('Ask')),
                  ],
                  onChanged: (choice) => store.change(
                    origin,
                    entry.permission,
                    allowed: switch (choice) {
                      _Choice.allow => true,
                      _Choice.block => false,
                      _ => null,
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The Settings row that opens [SitePermissionsPage].
class SitePermissionsSettings extends ConsumerWidget {
  const SitePermissionsSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(sitePermissionsProvider).value ?? const [];
    final count = {for (final e in entries) e.origin}.length;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.videocam_outlined),
      title: const Text('Camera, microphone, location...'),
      subtitle: Text(switch (count) {
        0 => 'No saved choices yet',
        1 => '1 site',
        _ => '$count sites',
      }),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SitePermissionsPage()),
      ),
    );
  }
}
