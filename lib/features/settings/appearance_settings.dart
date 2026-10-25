import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/browser_theme.dart';
import '../tabs/tabs_controller.dart';
import '../themes/chrome_theme.dart';
import '../themes/theme_service.dart';
import 'app_settings.dart';

/// Themes category of the Chrome Web Store.
const webStoreThemesUrl = 'https://chromewebstore.google.com/category/themes';

/// Runs a theme install with progress and result messages, offering Undo.
Future<void> runThemeInstall(
  BuildContext context,
  WidgetRef ref,
  Future<ChromeTheme> Function(ThemeService) install,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final db = ref.read(databaseProvider);
  final before = ref.read(appSettingsProvider);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Installing theme…'),
          ],
        ),
        duration: Duration(minutes: 1),
      ),
    );
  try {
    final theme = await install(ref.read(themeServiceProvider));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Theme "${theme.name}" installed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await db.setSetting('chromeTheme', before.chromeTheme);
              await db.setSetting(
                'colorSeed',
                before.colorSeed?.toARGB32().toString() ?? '',
              );
            },
          ),
        ),
      );
  } on FormatException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            e.message == 'This item is not a Chrome theme'
                ? 'This item is an extension, not a theme. Add it from '
                      'Extensions in the menu.'
                : 'Could not install the theme: ${e.message}',
          ),
        ),
      );
  } on Object catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Could not install the theme: $e')),
      );
  }
}

/// Chrome-style "Customize" side panel with the appearance options.
Future<void> showCustomizePanel(BuildContext context) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: Colors.black26,
  transitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, _, _) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: Material(
      elevation: 8,
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width.clamp(0, 380).toDouble(),
        height: double.infinity,
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: Text(
                  'Customize',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                trailing: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const Divider(height: 1),
              const Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: AppearanceSettings(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
  transitionBuilder: (_, animation, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  ),
);

/// Theme mode, accent color, Chrome theme and bookmarks bar options.
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final db = ref.read(databaseProvider);
    final chrome = ref.watch(chromeThemeProvider).value;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    Future<void> pickColor(Color? seed) async {
      await ref.read(themeServiceProvider).reset();
      await db.setSetting('colorSeed', seed?.toARGB32().toString() ?? '');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Chrome theme', style: text.titleSmall),
        const SizedBox(height: 8),
        _ThemeCard(theme: chrome),
        const SizedBox(height: 24),
        Text('Mode', style: text.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('Dark'),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined),
              label: Text('Device'),
            ),
          ],
          selected: {s.themeMode},
          onSelectionChanged: chrome != null
              ? null
              : (v) => db.setSetting('themeMode', v.first.name),
        ),
        if (chrome != null) ...[
          const SizedBox(height: 6),
          Text(
            'Set by the theme. Remove the theme to choose light or dark.',
            style: text.bodySmall?.copyWith(color: muted),
          ),
        ],
        const SizedBox(height: 24),
        Text('Color', style: text.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Swatch(
              label: 'Default',
              color: null,
              selected: chrome == null && s.colorSeed == null,
              onTap: () => pickColor(null),
            ),
            for (final (name, color) in colorPalette)
              _Swatch(
                label: name,
                color: color,
                selected:
                    chrome == null &&
                    s.colorSeed?.toARGB32() == color.toARGB32(),
                onTap: () => pickColor(color),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show bookmarks bar'),
          subtitle: const Text('Always shown on the New Tab page'),
          value: s.showBookmarksBar,
          onChanged: (v) => db.setSetting('bookmarksBar', '$v'),
        ),
      ],
    );
  }
}

/// The installed theme with a preview, or the ways to get one.
class _ThemeCard extends ConsumerWidget {
  const _ThemeCard({required this.theme});

  final ChromeTheme? theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = this.theme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    Future<void> loadFile() async {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Chrome theme', extensions: ['crx', 'zip']),
        ],
      );
      if (file == null || !context.mounted) return;
      await runThemeInstall(context, ref, (s) => s.installFromPath(file.path));
    }

    Future<void> loadFolder() async {
      final dir = await getDirectoryPath(confirmButtonText: 'Load theme');
      if (dir == null || !context.mounted) return;
      await runThemeInstall(context, ref, (s) => s.installFromPath(dir));
    }

    void browse() {
      ref.read(tabsProvider.notifier).newTab(url: webStoreThemesUrl);
      Navigator.of(context).popUntil((r) => r.isFirst);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (theme != null) ...[
              _ThemePreview(colors: BrowserColors.fromChromeTheme(theme)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      theme.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset to default'),
                    onPressed: () => ref.read(themeServiceProvider).reset(),
                  ),
                ],
              ),
            ] else
              Text(
                'Install any theme from the Chrome Web Store: open a theme '
                'and press "Install theme" in the bar above the page.',
                style: TextStyle(color: muted),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text('Get themes'),
                  onPressed: browse,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('Load .crx file'),
                  onPressed: loadFile,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Load unpacked'),
                  onPressed: loadFolder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A miniature browser window in the theme's colors.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.colors});

  final BrowserColors colors;

  @override
  Widget build(BuildContext context) {
    DecorationImage? img(ImageProvider? p, {BoxFit fit = BoxFit.none}) =>
        p == null
        ? null
        : DecorationImage(image: p, fit: fit, alignment: Alignment.topLeft);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 96,
        child: Column(
          children: [
            Container(
              height: 22,
              decoration: BoxDecoration(
                color: colors.frame,
                image: img(colors.frameImage),
              ),
              padding: const EdgeInsets.only(left: 10, top: 6),
              alignment: Alignment.bottomLeft,
              child: Container(
                width: 70,
                decoration: BoxDecoration(
                  color: colors.toolbar,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(5),
                  ),
                ),
              ),
            ),
            Container(
              height: 18,
              color: colors.toolbar,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.omnibox,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colors.ntpBackground,
                  image: img(colors.ntpImage, fit: BoxFit.cover),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// Null draws the default look (half light, half dark).
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = this.color;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                width: 2,
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
                gradient: color == null
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        stops: [0.5, 0.5],
                        colors: [Color(0xFFFFFFFF), Color(0xFF3C3C3C)],
                      )
                    : null,
                color: color,
              ),
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 18,
                      color: color == null
                          ? scheme.primary
                          : (ThemeData.estimateBrightnessForColor(color) ==
                                    Brightness.dark
                                ? Colors.white
                                : Colors.black),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
