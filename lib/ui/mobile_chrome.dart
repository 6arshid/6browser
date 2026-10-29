import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../engine/browser_engine.dart';
import '../features/bookmarks/bookmarks_page.dart';
import '../features/downloads/downloads_page.dart';
import '../features/history/history_page.dart';
import '../features/import/import_page.dart';
import '../features/settings/app_settings.dart';
import '../features/settings/appearance_settings.dart';
import '../features/settings/settings_page.dart';
import '../features/tabs/tabs_controller.dart';
import '../features/tabs/tabs_state.dart';
import '../features/tabs/url_input.dart';
import 'browser_theme.dart';
import 'favicon.dart';
import 'tab_strip.dart' show tabTitle;
import 'toolbar.dart' show openPage;

/// Phone navigation bar below the page, like Chrome and Samsung Internet:
/// back, forward, home, tab switcher and the menu, all within thumb reach.
class MobileBottomBar extends ConsumerWidget {
  const MobileBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    final settings = ref.watch(appSettingsProvider);
    final view = state.active?.view;
    final colors = BrowserColors.of(context);

    Widget slot(String tooltip, Widget icon, VoidCallback? onPressed) =>
        Expanded(
          child: IconButton(
            tooltip: tooltip,
            iconSize: 24,
            color: colors.icon,
            disabledColor: colors.icon.withValues(alpha: 0.38),
            icon: icon,
            onPressed: onPressed,
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(top: BorderSide(color: colors.separator)),
      ),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            slot('Back', const Icon(CupertinoIcons.chevron_left), view?.goBack),
            slot(
              'Forward',
              const Icon(CupertinoIcons.chevron_right),
              view?.goForward,
            ),
            slot(
              'Home',
              const Icon(CupertinoIcons.house),
              view == null ? null : () => view.load(settings.homeUrl),
            ),
            slot(
              'Tabs',
              TabCountIcon(count: state.tabs.length, color: colors.icon),
              () => openTabSwitcher(context),
            ),
            slot(
              'Menu',
              const Icon(CupertinoIcons.ellipsis_circle),
              () => showMobileMenu(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded square with the number of open tabs.
class TabCountIcon extends StatelessWidget {
  const TabCountIcon({super.key, required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(width: 2, color: color),
      borderRadius: BorderRadius.circular(6),
    ),
    child: MediaQuery.withNoTextScaling(
      child: Text(
        count > 99 ? ':D' : '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ),
  );
}

/// The phone menu: the current page with quick actions on top, then a grid
/// of everything else.
Future<void> showMobileMenu(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _MobileMenu(),
);

class _MobileMenu extends ConsumerWidget {
  const _MobileMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(tabsProvider.notifier);
    final view = ref.watch(tabsProvider).active?.view;

    // Closes the sheet first so pages and dialogs open above the browser.
    void run(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    final shell = Navigator.of(context).context;
    final items = <(IconData, String, VoidCallback)>[
      (CupertinoIcons.plus_square, 'New tab', () => run(ctl.newTab)),
      (CupertinoIcons.eye_slash, 'Private tab', () => run(ctl.newIncognitoTab)),
      (
        CupertinoIcons.book,
        'Bookmarks',
        () => run(() => openPage(shell, const BookmarksPage())),
      ),
      (
        CupertinoIcons.clock,
        'History',
        () => run(() => openPage(shell, const HistoryPage())),
      ),
      (
        CupertinoIcons.arrow_down_circle,
        'Downloads',
        () => run(() => openPage(shell, const DownloadsPage())),
      ),
      (
        CupertinoIcons.paintbrush,
        'Appearance',
        () => run(() => showCustomizePanel(shell)),
      ),
      (
        CupertinoIcons.tray_arrow_down,
        'Import',
        () => run(() => openPage(shell, const ImportPage())),
      ),
      (
        CupertinoIcons.gear,
        'Settings',
        () => run(() => openPage(shell, const SettingsPage())),
      ),
    ];

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (view != null) _PageCard(view: view, onDone: run),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final perRow = box.maxWidth >= 480 ? 8 : 4;
                return Wrap(
                  runSpacing: 4,
                  children: [
                    for (final (icon, label, onTap) in items)
                      SizedBox(
                        width: box.maxWidth / perRow,
                        child: _MenuTile(
                          icon: icon,
                          label: label,
                          onTap: onTap,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The current page: icon, title and address, with bookmark, copy link and
/// reload buttons.
class _PageCard extends ConsumerWidget {
  const _PageCard({required this.view, required this.onDone});

  final BrowserView view;
  final void Function(VoidCallback) onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final db = ref.read(databaseProvider);
    final url = view.url.value;
    final web = isBookmarkable(url);
    final bookmarked =
        web && (ref.watch(isBookmarkedProvider(url)).value ?? false);

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Favicon(url: url, size: 22, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tabTitle(view),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  if (web)
                    Text(
                      displayHost(url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (web) ...[
              IconButton(
                tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark this page',
                color: bookmarked ? scheme.primary : scheme.onSurfaceVariant,
                icon: Icon(
                  bookmarked ? CupertinoIcons.star_fill : CupertinoIcons.star,
                ),
                onPressed: () => bookmarked
                    ? db.removeBookmarkByUrl(url)
                    : db.addBookmark(url, view.title.value),
              ),
              IconButton(
                tooltip: 'Copy link',
                color: scheme.onSurfaceVariant,
                icon: const Icon(CupertinoIcons.link),
                onPressed: () {
                  final messenger = ScaffoldMessenger.of(context);
                  onDone(() {
                    Clipboard.setData(ClipboardData(text: url));
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Link copied'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  });
                },
              ),
              IconButton(
                tooltip: 'Reload',
                color: scheme.onSurfaceVariant,
                icon: const Icon(CupertinoIcons.arrow_clockwise),
                onPressed: () => onDone(view.reload),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: scheme.onSecondaryContainer),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the full-screen tab switcher on the group of the active tab.
Future<void> openTabSwitcher(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  final private = container.read(tabsProvider).active?.view.incognito ?? false;
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => TabSwitcherPage(initialPrivate: private),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// Grid of tab cards, split into normal and private tabs.
class TabSwitcherPage extends ConsumerStatefulWidget {
  const TabSwitcherPage({super.key, this.initialPrivate = false});

  final bool initialPrivate;

  @override
  ConsumerState<TabSwitcherPage> createState() => _TabSwitcherPageState();
}

class _TabSwitcherPageState extends ConsumerState<TabSwitcherPage> {
  late bool _private = widget.initialPrivate;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabsProvider);
    final ctl = ref.read(tabsProvider.notifier);
    final normal = state.tabs.where((t) => !t.view.incognito).toList();
    final private = state.tabs.where((t) => t.view.incognito).toList();
    final shown = _private ? private : normal;

    void pick(BrowserTab t) {
      ctl.select(t.id);
      Navigator.pop(context);
    }

    final page = Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: scheme.surfaceContainer,
          appBar: AppBar(
            backgroundColor: scheme.surfaceContainer,
            centerTitle: true,
            title: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(CupertinoIcons.square_on_square, size: 18),
                  label: Text('${normal.length}'),
                  tooltip: 'Tabs',
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(CupertinoIcons.eye_slash, size: 18),
                  label: Text('${private.length}'),
                  tooltip: 'Private tabs',
                ),
              ],
              selected: {_private},
              onSelectionChanged: (s) => setState(() => _private = s.first),
            ),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (_) {
                  for (final t in shown) {
                    ctl.close(t.id);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'close',
                    enabled: shown.isNotEmpty,
                    child: Text(
                      _private ? 'Close private tabs' : 'Close all tabs',
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: shown.isEmpty
              ? _EmptyTabs(private: _private)
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 0.78,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final t = shown[i];
                    return Dismissible(
                      key: ValueKey(t.id),
                      onDismissed: (_) => ctl.close(t.id),
                      child: TabCard(
                        tab: t,
                        active: t.id == state.activeId,
                        onTap: () => pick(t),
                        onClose: () => ctl.close(t.id),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(CupertinoIcons.add),
            label: Text(_private ? 'Private tab' : 'New tab'),
            onPressed: () {
              _private ? ctl.newIncognitoTab() : ctl.newTab();
              Navigator.pop(context);
            },
          ),
        );
      },
    );

    return _private
        ? Theme(
            data: buildTheme(
              brightness: Brightness.dark,
              colors: BrowserColors.incognito,
            ),
            child: page,
          )
        : page;
  }
}

class _EmptyTabs extends StatelessWidget {
  const _EmptyTabs({required this.private});

  final bool private;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              private
                  ? CupertinoIcons.eye_slash
                  : CupertinoIcons.square_on_square,
              size: 56,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              private ? 'No private tabs' : 'No open tabs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              private
                  ? 'Private tabs leave no history, cookies or downloads.'
                  : 'Open a new tab to start browsing.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab in the switcher: title bar with a close button over a preview
/// of the site's icon and address.
class TabCard extends StatelessWidget {
  const TabCard({
    super.key,
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final BrowserTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final view = tab.view;
    return Material(
      color: scheme.surface,
      elevation: active ? 3 : 1,
      shadowColor: Colors.black26,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: active
            ? BorderSide(color: scheme.primary, width: 2.5)
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: ListenableBuilder(
          listenable: Listenable.merge([view.title, view.url]),
          builder: (context, _) {
            final url = view.url.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: active
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHigh,
                  padding: const EdgeInsetsDirectional.only(start: 10),
                  child: Row(
                    children: [
                      if (tab.pinned)
                        Icon(
                          CupertinoIcons.pin_fill,
                          size: 14,
                          color: scheme.primary,
                        )
                      else
                        Favicon(url: url, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tabTitle(view),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelLarge?.copyWith(
                            color: active
                                ? scheme.onPrimaryContainer
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close tab',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: const Icon(CupertinoIcons.xmark),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: view.incognito && isNewTabUrl(url)
                            ? Icon(
                                CupertinoIcons.eye_slash,
                                size: 32,
                                color: scheme.onSurfaceVariant,
                              )
                            : Favicon(
                                url: url,
                                size: 32,
                                color: scheme.onSurfaceVariant,
                              ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          isNewTabUrl(url) ? 'New tab' : displayHost(url),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
