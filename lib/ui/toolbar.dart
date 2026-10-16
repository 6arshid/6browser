import 'package:flutter/material.dart';
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
import '../features/tabs/url_input.dart';
import '../features/themes/theme_service.dart';
import 'browser_theme.dart';
import 'favicon.dart';

/// Below this width the toolbar collapses secondary actions into a menu and
/// the tab strip becomes a tab-count button.
const compactBreakpoint = 720.0;

/// Opens a full-window page (history, settings, ...) above the browser.
void openPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// Shows or hides the bookmarks bar on every page.
void toggleBookmarksBar(WidgetRef ref) => ref
    .read(databaseProvider)
    .setSetting(
      'bookmarksBar',
      '${!ref.read(appSettingsProvider).showBookmarksBar}',
    );

/// Navigation buttons, address bar and the main menu for the active tab.
class BrowserToolbar extends ConsumerStatefulWidget {
  const BrowserToolbar({super.key, required this.addressFocus});

  final FocusNode addressFocus;

  @override
  ConsumerState<BrowserToolbar> createState() => _BrowserToolbarState();
}

class _BrowserToolbarState extends ConsumerState<BrowserToolbar> {
  final _address = TextEditingController();
  BrowserView? _bound;

  /// Small-screen layout; the unfocused address bar then shows only the host.
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    // Repaint the omnibox outline when it gains or loses focus.
    widget.addressFocus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.addressFocus.removeListener(_onFocus);
    _bound?.url.removeListener(_syncAddress);
    _address.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (widget.addressFocus.hasFocus) {
      // Editing always starts from the full URL, all selected.
      final full = _full(_bound?.url.value ?? '');
      _address.value = TextEditingValue(
        text: full,
        selection: TextSelection(baseOffset: 0, extentOffset: full.length),
      );
    } else {
      _syncAddress();
    }
    setState(() {});
  }

  /// Follows the active tab's URL without clobbering what the user types.
  void _bind(BrowserView? view) {
    if (identical(view, _bound)) return;
    _bound?.url.removeListener(_syncAddress);
    _bound = view;
    view?.url.addListener(_syncAddress);
    _setShown();
  }

  /// The New Tab page shows an empty address bar.
  String _full(String url) => isNewTabUrl(url) ? '' : url;

  void _syncAddress() {
    if (!widget.addressFocus.hasFocus) _setShown();
  }

  /// Unfocused text, with the caret at the start so the beginning of the
  /// address is visible rather than its tail.
  void _setShown() {
    final full = _full(_bound?.url.value ?? '');
    final text = _compact ? displayHost(full) : full;
    if (_address.text == text) return;
    _address.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabsProvider);
    final settings = ref.watch(appSettingsProvider);
    final view = state.active?.view;
    final compact = MediaQuery.sizeOf(context).width < compactBreakpoint;
    if (compact != _compact) {
      _compact = compact;
      _syncAddress();
    }
    _bind(view);
    // On phones the address bar takes the whole row while editing.
    final editing = compact && widget.addressFocus.hasFocus;
    final colors = BrowserColors.of(context);

    void go(String text) {
      view?.load(resolveInput(text, searchTemplate: settings.searchTemplate));
      widget.addressFocus.unfocus();
    }

    Widget button(String tooltip, IconData icon, VoidCallback? onPressed) =>
        IconButton(
          tooltip: tooltip,
          iconSize: compact ? 22 : 20,
          color: colors.icon,
          disabledColor: colors.icon.withValues(alpha: 0.38),
          icon: Icon(icon),
          onPressed: onPressed,
        );

    final reload = view == null
        ? button('Reload', Icons.refresh, null)
        : ValueListenableBuilder<bool>(
            valueListenable: view.isLoading,
            builder: (_, loading, _) => loading && view.supportsStop
                ? button('Stop loading', Icons.close, view.stop)
                : button('Reload (F5)', Icons.refresh, view.reload),
          );

    return Container(
      decoration: BoxDecoration(
        color: colors.toolbar,
        image: colors.toolbarImage == null
            ? null
            : DecorationImage(
                image: colors.toolbarImage!,
                alignment: Alignment.topLeft,
                repeat: ImageRepeat.repeat,
                fit: BoxFit.none,
              ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            // Phones keep navigation in the bottom bar (MobileBottomBar), so
            // the address bar gets the whole top row.
            padding: compact
                ? const EdgeInsets.fromLTRB(10, 6, 4, 6)
                : const EdgeInsets.fromLTRB(6, 5, 6, 5),
            child: Row(
              children: [
                if (!compact) ...[
                  button('Back', Icons.arrow_back, view?.goBack),
                  button('Forward', Icons.arrow_forward, view?.goForward),
                  reload,
                  button(
                    'Home',
                    Icons.home_outlined,
                    view == null ? null : () => view.load(settings.homeUrl),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: _Omnibox(
                    controller: _address,
                    focus: widget.addressFocus,
                    view: view,
                    compact: compact,
                    onGo: go,
                  ),
                ),
                SizedBox(width: compact ? 2 : 6),
                if (editing)
                  button('Cancel', Icons.close, widget.addressFocus.unfocus),
                if (view != null && !editing)
                  ValueListenableBuilder<String>(
                    valueListenable: view.url,
                    builder: (_, url, _) => switch (webStoreItemId(url)) {
                      final id? => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.palette_outlined, size: 18),
                          label: Text(compact ? 'Install' : 'Install theme'),
                          onPressed: () => runThemeInstall(
                            context,
                            ref,
                            (s) => s.installFromWebStore(id),
                          ),
                        ),
                      ),
                      null => const SizedBox.shrink(),
                    },
                  ),
                if (!compact) _MainMenu(view: view),
                if (compact && !editing && view != null) reload,
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: view == null
                ? null
                : ValueListenableBuilder<bool>(
                    valueListenable: view.isLoading,
                    builder: (_, loading, _) => loading
                        ? LinearProgressIndicator(
                            minHeight: 2,
                            backgroundColor: Colors.transparent,
                          )
                        : ColoredBox(color: colors.separator),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The address bar: site security chip, input, suggestions and the star.
class _Omnibox extends ConsumerWidget {
  const _Omnibox({
    required this.controller,
    required this.focus,
    required this.view,
    required this.compact,
    required this.onGo,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final BrowserView? view;
  final bool compact;
  final ValueChanged<String> onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final colors = BrowserColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final focused = focus.hasFocus;
    final view = this.view;
    final height = compact ? 44.0 : 36.0;
    final fontSize = compact ? 15.0 : 14.0;
    final radius = BorderRadius.circular(height / 2);

    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        height: height,
        child: RawAutocomplete<String>(
          textEditingController: controller,
          focusNode: focus,
          optionsBuilder: (value) async {
            if (!focus.hasFocus || value.text.trim().isEmpty) return const [];
            return db.suggest(value.text);
          },
          onSelected: onGo,
          // A large system font size must not overflow the fixed-height bar.
          fieldViewBuilder: (context, controller, focus, _) =>
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  // URLs read left to right even in an RTL UI.
                  textDirection: TextDirection.ltr,
                  textAlignVertical: TextAlignVertical.center,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1.2,
                    color: colors.omniboxText,
                  ),
                  cursorColor: scheme.primary,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: focused ? colors.toolbar : colors.omnibox,
                    hoverColor: colors.omniboxText.withValues(alpha: 0.04),
                    constraints: BoxConstraints.tightFor(height: height),
                    contentPadding: EdgeInsets.zero,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: radius,
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: radius,
                      borderSide: BorderSide(color: scheme.primary, width: 2),
                    ),
                    hintText: view?.incognito == true
                        ? 'Search privately or type a URL'
                        : 'Search Google or type a URL',
                    hintStyle: TextStyle(
                      fontSize: fontSize,
                      color: colors.omniboxText.withValues(alpha: 0.6),
                    ),
                    // The fill only covers the tallest child; on phones
                    // there is no star, so the chip sets the full height.
                    prefixIconConstraints: BoxConstraints(
                      minWidth: compact ? 44 : 40,
                      minHeight: height,
                    ),
                    prefixIcon: view == null
                        ? null
                        : ValueListenableBuilder<String>(
                            valueListenable: view.url,
                            builder: (_, url, _) =>
                                _SiteChip(url: url, color: colors.omniboxText),
                          ),
                    suffixIcon: view == null || compact
                        ? null
                        : _BookmarkStar(view: view),
                  ),
                  onTap: () => controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: controller.text.length,
                  ),
                  onSubmitted: onGo,
                ),
              ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 320,
                    maxWidth: box.maxWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    children: [
                      for (final (i, o) in options.indexed)
                        _Suggestion(
                          index: i,
                          text: o,
                          onTap: () => onSelected(o),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.index,
    required this.text,
    required this.onTap,
  });

  final int index;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final highlighted = AutocompleteHighlightedOption.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isUrl = isBookmarkable(text);
    return Material(
      color: index == highlighted
          ? scheme.onSurface.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              isUrl
                  ? Favicon(url: text, color: scheme.onSurfaceVariant)
                  : Icon(
                      Icons.history,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lock for HTTPS, a "Not secure" label for HTTP, a search icon on New Tab.
class _SiteChip extends StatelessWidget {
  const _SiteChip({required this.url, required this.color});

  final String url;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (isNewTabUrl(url)) {
      return Icon(Icons.search, size: 18, color: color.withValues(alpha: 0.7));
    }
    if (isSecureUrl(url)) {
      return Tooltip(
        message: 'Connection is secure',
        child: Icon(Icons.lock_outline, size: 16, color: color),
      );
    }
    if (url.startsWith('http://')) {
      final error = Theme.of(context).colorScheme.error;
      return Tooltip(
        message: 'Your connection to this site is not secure',
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: error),
              const SizedBox(width: 4),
              Text(
                'Not secure',
                style: TextStyle(fontSize: 12.5, color: error),
              ),
              const SizedBox(width: 6),
              Container(
                width: 1,
                height: 16,
                color: color.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      );
    }
    return Icon(Icons.info_outline, size: 16, color: color);
  }
}

/// Star that shows and toggles whether the current page is bookmarked.
class _BookmarkStar extends ConsumerWidget {
  const _BookmarkStar({required this.view});

  final BrowserView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final colors = BrowserColors.of(context);
    return ValueListenableBuilder<String>(
      valueListenable: view.url,
      builder: (_, url, _) {
        if (!isBookmarkable(url)) return const SizedBox.shrink();
        final on = ref.watch(isBookmarkedProvider(url)).value ?? false;
        return IconButton(
          tooltip: on ? 'Remove bookmark' : 'Bookmark this tab',
          iconSize: 18,
          color: on
              ? Theme.of(context).colorScheme.primary
              : colors.omniboxText,
          icon: Icon(on ? Icons.star : Icons.star_border),
          onPressed: () => on
              ? db.removeBookmarkByUrl(url)
              : db.addBookmark(url, view.title.value),
        );
      },
    );
  }
}

/// The "⋮" menu, with icons and keyboard shortcuts like Chrome's.
class _MainMenu extends ConsumerWidget {
  const _MainMenu({required this.view});

  final BrowserView? view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(tabsProvider.notifier);
    final settings = ref.watch(appSettingsProvider);
    final colors = BrowserColors.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      String? shortcut,
      bool checked = false,
    }) => PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 14),
          Expanded(child: Text(label)),
          if (checked) Icon(Icons.check, size: 18, color: muted),
          if (shortcut != null)
            Text(shortcut, style: TextStyle(fontSize: 12, color: muted)),
        ],
      ),
    );

    return PopupMenuButton<String>(
      tooltip: 'Menu',
      icon: Icon(Icons.more_vert, color: colors.icon, size: 20),
      constraints: const BoxConstraints(minWidth: 300),
      position: PopupMenuPosition.under,
      onSelected: (v) {
        switch (v) {
          case 'new':
            ctl.newTab();
          case 'incognito':
            ctl.newIncognitoTab();
          case 'devtools':
            view?.openDevTools();
          case 'bookmarks':
            openPage(context, const BookmarksPage());
          case 'bar':
            toggleBookmarksBar(ref);
          case 'history':
            openPage(context, const HistoryPage());
          case 'downloads':
            openPage(context, const DownloadsPage());
          case 'customize':
            showCustomizePanel(context);
          case 'settings':
            openPage(context, const SettingsPage());
          case 'import':
            openPage(context, const ImportPage());
        }
      },
      itemBuilder: (_) => [
        item('new', Icons.add, 'New tab', shortcut: 'Ctrl+T'),
        item(
          'incognito',
          Icons.visibility_off_outlined,
          'New incognito tab',
          shortcut: 'Ctrl+Shift+N',
        ),
        const PopupMenuDivider(),
        item('history', Icons.history, 'History', shortcut: 'Ctrl+H'),
        item(
          'downloads',
          Icons.download_outlined,
          'Downloads',
          shortcut: 'Ctrl+J',
        ),
        item(
          'bookmarks',
          Icons.bookmarks_outlined,
          'Bookmarks',
          shortcut: 'Ctrl+Shift+O',
        ),
        item(
          'bar',
          Icons.bookmark_border,
          'Show bookmarks bar',
          checked: settings.showBookmarksBar,
        ),
        const PopupMenuDivider(),
        item('customize', Icons.palette_outlined, 'Customize appearance'),
        item('import', Icons.move_to_inbox_outlined, 'Import from browser…'),
        item('settings', Icons.settings_outlined, 'Settings'),
        const PopupMenuDivider(),
        item('devtools', Icons.code, 'Developer tools', shortcut: 'F12'),
      ],
    );
  }
}
