import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/bookmarks/bookmarks_page.dart';
import '../features/downloads/downloads_page.dart';
import '../features/history/history_page.dart';
import '../features/new_tab/new_tab_page.dart';
import '../features/settings/app_settings.dart';
import '../features/tabs/tabs_controller.dart';
import '../features/tabs/url_input.dart';
import '../features/themes/theme_service.dart';
import 'bookmarks_bar.dart';
import 'browser_theme.dart';
import 'tab_strip.dart';
import 'toolbar.dart';
import 'window_caption.dart';

/// Main window: tab strip (wide) or tab button (narrow), toolbar, page area.
class BrowserShell extends ConsumerStatefulWidget {
  const BrowserShell({super.key});

  @override
  ConsumerState<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends ConsumerState<BrowserShell> {
  final _addressFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Provider state may not be modified while the tree is building.
    Future.microtask(() => ref.read(tabsProvider.notifier).start());
  }

  @override
  void dispose() {
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabsProvider);
    final ctl = ref.read(tabsProvider.notifier);
    final compact = MediaQuery.sizeOf(context).width < compactBreakpoint;
    final settings = ref.watch(appSettingsProvider);
    final view = state.active?.view;
    final colors = BrowserColors.of(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => WindowCaption.apply(colors.frame),
    );

    // A private tab gets a dark toolbar, whatever the theme.
    Widget chrome(Widget child) => view?.incognito == true
        ? Theme(
            data: buildTheme(
              brightness: Brightness.dark,
              colors: BrowserColors.incognito,
            ),
            child: child,
          )
        : child;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyT, control: true):
            ctl.newTab,
        const SingleActivator(
          LogicalKeyboardKey.keyN,
          control: true,
          shift: true,
        ): ctl.newIncognitoTab,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
          final a = state.active;
          if (a != null) ctl.close(a.id);
        },
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            _addressFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.tab, control: true): ctl.cycle,
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () =>
            ctl.cycle(delta: -1),
        const SingleActivator(LogicalKeyboardKey.f12): () =>
            view?.openDevTools(),
        const SingleActivator(LogicalKeyboardKey.f5): () => view?.reload(),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
            view?.reload(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            view?.goBack(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            view?.goForward(),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            openPage(context, const HistoryPage()),
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () =>
            openPage(context, const DownloadsPage()),
        const SingleActivator(
          LogicalKeyboardKey.keyO,
          control: true,
          shift: true,
        ): () =>
            openPage(context, const BookmarksPage()),
        const SingleActivator(
          LogicalKeyboardKey.keyB,
          control: true,
          shift: true,
        ): () =>
            toggleBookmarksBar(ref),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.frame,
          body: SafeArea(
            child: Column(
              children: [
                if (!compact) const TabStrip(),
                chrome(BrowserToolbar(addressFocus: _addressFocus)),
                if (view != null)
                  ValueListenableBuilder<String>(
                    valueListenable: view.url,
                    builder: (_, url, _) => Column(
                      children: [
                        if (settings.showBookmarksBar || isNewTabUrl(url))
                          chrome(const BookmarksBar()),
                        if (isWebStoreUrl(url)) _WebStoreBar(url: url),
                      ],
                    ),
                  ),
                Expanded(
                  child: state.tabs.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : IndexedStack(
                          index: state.activeIndex,
                          children: [
                            for (final t in state.tabs)
                              KeyedSubtree(
                                key: ValueKey(t.id),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ValueListenableBuilder<bool>(
                                      valueListenable: t.view.isReady,
                                      builder: (_, ready, _) => ready
                                          ? t.view.widget
                                          : const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                    ),
                                    // The New Tab page covers the engine's
                                    // blank page; the view stays alive below.
                                    ValueListenableBuilder<String>(
                                      valueListenable: t.view.url,
                                      builder: (_, url, _) => isNewTabUrl(url)
                                          ? NewTabPage(view: t.view)
                                          : const SizedBox.shrink(),
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
      ),
    );
  }
}

/// Shown on the Chrome Web Store: themes can be installed from a theme's
/// page; extensions cannot be installed by the current engine, so "Add to
/// Chrome" deliberately does nothing (see docs/ENGINE.md).
class _WebStoreBar extends ConsumerWidget {
  const _WebStoreBar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final id = webStoreItemId(url);
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              id == null ? Icons.palette_outlined : Icons.extension_off,
              size: 20,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                id == null
                    ? 'Chrome themes from this store work in 6browser: open a '
                          'theme to install it. Extensions are not supported yet.'
                    : '"Add to Chrome" does not work in 6browser. For a theme, '
                          'use "Install theme" next to the address bar. '
                          'Extensions are not supported yet.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
