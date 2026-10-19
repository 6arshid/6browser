import 'package:flutter/material.dart';

import 'browser_commands.dart';

/// Lists every keyboard shortcut, grouped as on Chrome's help page.
class ShortcutsPage extends StatelessWidget {
  const ShortcutsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Keyboard shortcuts')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final (title, commands) in browserCommandGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            for (final c in commands)
              ListTile(
                dense: true,
                title: Text(
                  c == BrowserCommand.tab1 ? 'Go to tab 1 to 8' : c.label,
                ),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    for (final label in _labels(c))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                  ],
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Address bar',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const ListTile(
            dense: true,
            title: Text('Add www. and .com to a name and open it'),
            trailing: Text('Ctrl+Enter'),
          ),
          const ListTile(
            dense: true,
            title: Text('Open the address in a new tab'),
            trailing: Text('Alt+Enter'),
          ),
        ],
      ),
    );
  }

  /// Distinct labels; the numpad duplicates of digit shortcuts are skipped.
  static List<String> _labels(BrowserCommand c) {
    final keys = browserShortcuts[c] ?? const [];
    final labels = <String>[];
    for (final k in keys) {
      final label = shortcutLabel(k);
      if (label.contains('Numpad')) continue;
      if (!labels.contains(label)) labels.add(label);
    }
    if (c == BrowserCommand.tab1) {
      return [labels.first.replaceFirst('1', '1…8')];
    }
    return labels;
  }
}
