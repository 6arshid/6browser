import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'app_settings.dart';
import 'appearance_settings.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static const _custom = 'custom';
  late final TextEditingController _home;
  late final TextEditingController _template;

  @override
  void initState() {
    super.initState();
    final s = ref.read(appSettingsProvider);
    _home = TextEditingController(
      text: s.homeUrl == defaultHomeUrl ? '' : s.homeUrl,
    );
    _template = TextEditingController(text: s.searchTemplate);
  }

  @override
  void dispose() {
    _home.dispose();
    _template.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appSettingsProvider);
    final db = ref.read(databaseProvider);
    final title = Theme.of(context).textTheme.titleMedium;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final preset = searchEngines
        .where((e) => e.template == s.searchTemplate)
        .map((e) => e.template)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const _Section(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                child: AppearanceSettings(),
              ),
              _Section(
                icon: Icons.search,
                title: 'Search engine',
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: preset ?? _custom,
                      decoration: const InputDecoration(
                        labelText: 'Used in the address bar',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final e in searchEngines)
                          DropdownMenuItem(
                            value: e.template,
                            child: Text(e.name),
                          ),
                        const DropdownMenuItem(
                          value: _custom,
                          child: Text('Custom'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null || v == _custom) return;
                        _template.text = v;
                        db.setSetting('searchTemplate', v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _template,
                      decoration: const InputDecoration(
                        labelText: 'Search URL (use %s for the query)',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (v) {
                        if (v.contains('%s')) {
                          db.setSetting('searchTemplate', v.trim());
                        }
                      },
                    ),
                  ],
                ),
              ),
              _Section(
                icon: Icons.home_outlined,
                title: 'On startup and Home',
                child: TextField(
                  controller: _home,
                  decoration: const InputDecoration(
                    labelText: 'Home page',
                    border: OutlineInputBorder(),
                    hintText: 'Empty: New Tab page',
                  ),
                  onSubmitted: (v) => db.setSetting('homeUrl', v.trim()),
                ),
              ),
              _Section(
                icon: Icons.shield_outlined,
                title: 'Privacy',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Clear browsing history'),
                  subtitle: const Text('Removes every visited page'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await db.clearHistory();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('History cleared')),
                      );
                    }
                  },
                ),
              ),
              _Section(
                icon: Icons.info_outline,
                title: 'About 6browser',
                child: Row(
                  children: [
                    Image.asset('assets/logo.png', width: 48, height: 48),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('6browser', style: title),
                          const SizedBox(height: 4),
                          Text(
                            'Flutter UI on CEF (Chromium 149). Chrome themes '
                            'are supported; Chrome extensions are not yet '
                            '(see docs/ENGINE.md).',
                            style: TextStyle(color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled card on the settings page.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    ),
  );
}
