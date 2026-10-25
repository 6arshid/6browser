import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tabs/tabs_controller.dart';
import 'extension_install.dart';
import 'extension_service.dart';

/// Chrome Web Store home page.
const webStoreUrl = 'https://chromewebstore.google.com/';

/// Lists installed extensions: turn on/off, pin, options, remove, and add
/// more from the Web Store, a `.crx` file or an unpacked folder.
class ExtensionsPage extends ConsumerWidget {
  const ExtensionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(extensionsProvider.notifier);
    final items = ref.watch(extensionsProvider);
    final theme = Theme.of(context);

    void openTab(String url) {
      ref.read(tabsProvider.notifier).newTab(url: url);
      Navigator.of(context).maybePop();
    }

    Future<void> installFile() async {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Chrome extension', extensions: ['crx', 'zip']),
        ],
      );
      if (file == null || !context.mounted) return;
      await runFileInstall(context, ref, file.path);
    }

    Future<void> loadUnpacked() async {
      final dir = await getDirectoryPath(confirmButtonText: 'Load extension');
      if (dir == null || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        final x = await controller.loadUnpacked(dir);
        messenger.showSnackBar(SnackBar(content: Text('"${x.name}" loaded')));
      } on Object catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not load the extension: $e')),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        actions: [
          if (controller.supported)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => switch (v) {
                'file' => installFile(),
                'unpacked' => loadUnpacked(),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'file',
                  child: Text('Install from .crx or .zip file…'),
                ),
                PopupMenuItem(
                  value: 'unpacked',
                  child: Text('Load unpacked (developer)…'),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!controller.supported)
                    const _Notice(
                      icon: Icons.extension_off_outlined,
                      text:
                          'Extensions run in 6browser on Windows. This system '
                          'is not supported yet.',
                    )
                  else ...[
                    _Notice(
                      icon: Icons.storefront_outlined,
                      text:
                          'Open an extension on the Chrome Web Store and use '
                          '"Add to 6browser" next to the address bar. '
                          '$extensionLimitsNote',
                      action: FilledButton.tonal(
                        onPressed: () => openTab(webStoreUrl),
                        child: const Text('Open Chrome Web Store'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No extensions yet',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    for (final x in items)
                      _ExtensionCard(
                        x: x,
                        onOptions: x.optionsUrl == null
                            ? null
                            : () => openTab(x.optionsUrl!),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          ],
        ),
      ),
    );
  }
}

/// Icon of an installed extension, or a puzzle piece.
class ExtensionIcon extends StatelessWidget {
  const ExtensionIcon(this.x, {super.key, this.size = 20});

  final InstalledExtension x;
  final double size;

  @override
  Widget build(BuildContext context) {
    final file = x.icon((size * 2).round());
    final fallback = Icon(Icons.extension_outlined, size: size);
    if (file == null) return fallback;
    return Image.file(
      file,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _ExtensionCard extends ConsumerWidget {
  const _ExtensionCard({required this.x, this.onOptions});

  final InstalledExtension x;
  final VoidCallback? onOptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(extensionsProvider.notifier);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final description = x.manifest.description;

    Future<void> remove() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove "${x.name}"?'),
          content: const Text('Its settings and data are deleted too.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok == true) await controller.remove(x.id);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: ExtensionIcon(x, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${x.name}  ${x.manifest.version}',
                        style: theme.textTheme.titleSmall,
                      ),
                      if (description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SelectableText(
                          x.copied ? 'ID: ${x.id}' : 'ID: ${x.id} · ${x.path}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ),
                      if (x.error case final error?)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Could not load: $error',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      if (x.pendingRestart)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Turns off when 6browser restarts.',
                            style: TextStyle(color: theme.colorScheme.primary),
                          ),
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: x.enabled,
                  onChanged: (v) => controller.setEnabled(x.id, v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                if (onOptions != null)
                  TextButton(
                    onPressed: onOptions,
                    child: const Text('Options'),
                  ),
                TextButton(
                  onPressed: () => controller.setPinned(x.id, !x.pinned),
                  child: Text(
                    x.pinned ? 'Unpin from toolbar' : 'Pin to toolbar',
                  ),
                ),
                TextButton(onPressed: remove, child: const Text('Remove')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
