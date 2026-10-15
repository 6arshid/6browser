import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../engine/browser_engine.dart';
import '../features/bookmarks/bookmarks_page.dart';
import '../features/downloads/downloads_page.dart';
import '../features/history/history_page.dart';
import '../features/import/import_page.dart';
import '../features/settings/app_settings.dart';
import '../features/settings/settings_page.dart';
import '../features/tabs/tabs_controller.dart';
import '../features/tabs/url_input.dart';
import 'tab_strip.dart';

/// Below this width the toolbar collapses secondary actions into a menu and
/// the tab strip becomes a tab-count button.
const compactBreakpoint = 720.0;

/// Navigation buttons + address bar for the active tab.
class BrowserToolbar extends ConsumerStatefulWidget {
  const BrowserToolbar({super.key, required this.addressFocus});

  final FocusNode addressFocus;

  @override
  ConsumerState<BrowserToolbar> createState() => _BrowserToolbarState();
}

class _BrowserToolbarState extends ConsumerState<BrowserToolbar> {
  final _address = TextEditingController();
  BrowserView? _bound;

  @override
  void dispose() {
    _bound?.url.removeListener(_syncAddress);
    _address.dispose();
    super.dispose();
  }

  /// Follows the active tab's URL without clobbering what the user types.
  void _bind(BrowserView? view) {
    if (identical(view, _bound)) return;
    _bound?.url.removeListener(_syncAddress);
    _bound = view;
    view?.url.addListener(_syncAddress);
    _address.text = _shown(view?.url.value ?? '');
  }

  /// The New Tab page shows an empty address bar.
  String _shown(String url) => isNewTabUrl(url) ? '' : url;

  void _syncAddress() {
    if (!widget.addressFocus.hasFocus) {
      _address.text = _shown(_bound?.url.value ?? '');
    }
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabsProvider);
    final ctl = ref.read(tabsProvider.notifier);
    final settings = ref.watch(appSettingsProvider);
    final db = ref.read(databaseProvider);
    final view = state.active?.view;
    _bind(view);
    final compact = MediaQuery.sizeOf(context).width < compactBreakpoint;

    void go(String text) {
      view?.load(resolveInput(text, searchTemplate: settings.searchTemplate));
      widget.addressFocus.unfocus();
    }

    final back = IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back),
      onPressed: view?.goBack,
    );
    final forward = IconButton(
      tooltip: 'Forward',
      icon: const Icon(Icons.arrow_forward),
      onPressed: view?.goForward,
    );
    final reload = IconButton(
      tooltip: 'Reload',
      icon: const Icon(Icons.refresh),
      onPressed: view?.reload,
    );
    final home = IconButton(
      tooltip: 'Home',
      icon: const Icon(Icons.home_outlined),
      onPressed: view == null ? null : () => view.load(settings.homeUrl),
    );

    final field = Expanded(
      child: SizedBox(
        height: 40,
        child: RawAutocomplete<String>(
          textEditingController: _address,
          focusNode: widget.addressFocus,
          optionsBuilder: (value) async {
            if (!widget.addressFocus.hasFocus) return const [];
            return db.suggest(value.text);
          },
          onSelected: go,
          fieldViewBuilder: (context, controller, focus, _) => TextField(
            controller: controller,
            focusNode: focus,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              hintText: view?.incognito == true
                  ? 'Incognito: search or enter address'
                  : 'Search or enter address',
              prefixIcon: view == null
                  ? null
                  : ValueListenableBuilder<String>(
                      valueListenable: view.url,
                      builder: (_, url, _) => Icon(
                        isNewTabUrl(url)
                            ? Icons.search
                            : isSecureUrl(url)
                            ? Icons.lock_outline
                            : Icons.info_outline,
                        size: 18,
                      ),
                    ),
              suffixIcon: view == null ? null : _BookmarkStar(view: view),
            ),
            onTap: () => controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: controller.text.length,
            ),
            onSubmitted: go,
          ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 280,
                  maxWidth: 600,
                ),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.history, size: 18),
                        title: Text(
                          o,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onSelected(o),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          back,
          if (!compact) forward,
          reload,
          if (!compact) home,
          const SizedBox(width: 4),
          field,
          const SizedBox(width: 4),
          if (compact) _TabCountButton(count: state.tabs.length),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (v) {
              switch (v) {
                case 'new':
                  ctl.newTab();
                case 'incognito':
                  ctl.newIncognitoTab();
                case 'forward':
                  view?.goForward();
                case 'home':
                  view?.load(settings.homeUrl);
                case 'devtools':
                  view?.openDevTools();
                case 'bookmarks':
                  _open(const BookmarksPage());
                case 'history':
                  _open(const HistoryPage());
                case 'downloads':
                  _open(const DownloadsPage());
                case 'settings':
                  _open(const SettingsPage());
                case 'import':
                  _open(const ImportPage());
              }
            },
            itemBuilder: (_) => [
              if (compact) ...const [
                PopupMenuItem(value: 'new', child: Text('New tab')),
                PopupMenuItem(value: 'forward', child: Text('Forward')),
                PopupMenuItem(value: 'home', child: Text('Home')),
                PopupMenuDivider(),
              ],
              const PopupMenuItem(
                value: 'incognito',
                child: Text('New incognito tab (Ctrl+Shift+N)'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
              const PopupMenuItem(value: 'history', child: Text('History')),
              const PopupMenuItem(value: 'downloads', child: Text('Downloads')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuItem(
                value: 'import',
                child: Text('Import from browser…'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'devtools',
                child: Text('DevTools (F12)'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Star that shows and toggles whether the current page is bookmarked.
class _BookmarkStar extends ConsumerWidget {
  const _BookmarkStar({required this.view});

  final BrowserView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    return ValueListenableBuilder<String>(
      valueListenable: view.url,
      builder: (_, url, _) {
        if (!isBookmarkable(url)) return const SizedBox.shrink();
        final on = ref.watch(isBookmarkedProvider(url)).value ?? false;
        return IconButton(
          tooltip: on ? 'Remove bookmark' : 'Bookmark this page',
          icon: Icon(on ? Icons.star : Icons.star_border, size: 20),
          onPressed: () => on
              ? db.removeBookmarkByUrl(url)
              : db.addBookmark(url, view.title.value),
        );
      },
    );
  }
}

class _TabCountButton extends ConsumerWidget {
  const _TabCountButton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: 'Tabs',
    onPressed: () => showTabSheet(context, ref),
    icon: Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(
          width: 2,
          color: IconTheme.of(context).color ?? Colors.grey,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$count', style: const TextStyle(fontSize: 12)),
    ),
  );
}
