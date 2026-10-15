import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'app_settings.dart';

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
    _home = TextEditingController(text: s.homeUrl);
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
    final preset = searchEngines
        .where((e) => e.template == s.searchTemplate)
        .map((e) => e.template)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Appearance', style: title),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => db.setSetting('themeMode', v.first.name),
          ),
          const SizedBox(height: 24),
          Text('Search engine', style: title),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: preset ?? _custom,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final e in searchEngines)
                DropdownMenuItem(value: e.template, child: Text(e.name)),
              const DropdownMenuItem(value: _custom, child: Text('Custom')),
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
              if (v.contains('%s')) db.setSetting('searchTemplate', v.trim());
            },
          ),
          const SizedBox(height: 24),
          Text('Home page', style: title),
          const SizedBox(height: 8),
          TextField(
            controller: _home,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onSubmitted: (v) => db.setSetting('homeUrl', v.trim()),
          ),
          const SizedBox(height: 24),
          Text('Privacy', style: title),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear browsing history'),
              onPressed: () async {
                await db.clearHistory();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('History cleared')),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('About', style: title),
          const SizedBox(height: 8),
          Row(
            children: [
              Image.asset('assets/logo.png', width: 40, height: 40),
              const SizedBox(width: 12),
              Text(
                '6browser',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '6browser · Flutter UI on CEF (Chromium 149)\n'
            'Chrome extensions are not supported yet (see docs/ENGINE.md).',
          ),
        ],
      ),
    );
  }
}
