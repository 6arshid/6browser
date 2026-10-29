import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../engine/browser_engine.dart';
import '../features/bookmarks/bookmark_dialogs.dart';
import '../features/bookmarks/bookmarks_page.dart';
import '../features/downloads/downloads_page.dart';
import '../features/extensions/extension_install.dart';
import '../features/extensions/extension_toolbar.dart';
import '../features/extensions/extensions_page.dart';
import '../features/history/history_page.dart';
import '../features/import/import_page.dart';
import '../features/passwords/password_prompt.dart';
import '../features/profiles/profiles_page.dart';
import '../features/settings/app_settings.dart';
import '../features/settings/appearance_settings.dart';
import '../features/settings/settings_page.dart';
import '../features/tabs/tabs_controller.dart';
import '../features/tabs/url_input.dart';
import '../features/themes/theme_service.dart';
import 'browser_commands.dart';
import 'browser_theme.dart';
import 'favicon.dart';
import 'fullscreen.dart';
import 'shortcuts_page.dart';

/// Below this width the toolbar collapses secondary actions into a menu and
/// the tab strip becomes a tab-count button.
const compactBreakpoint = 720.0;

/// Widest the address field grows on large windows; it stays centered, as
/// in Safari.
const _maxFieldWidth = 860.0;

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
  const BrowserToolbar({super.key, required this.addressFocus, this.menuKey});

  final FocusNode addressFocus;

  /// Lets the shell open the main menu from the keyboard (Alt+F / F10).
  final GlobalKey<PopupMenuButtonState<String>>? menuKey;

  @override
  ConsumerState<BrowserToolbar> createState() => _BrowserToolbarState();
}

class _BrowserToolbarState extends ConsumerState<BrowserToolbar> {
  final _address = TextEditingController();
  final _suggestions = _SuggestionState();
  BrowserView? _bound;

  /// Set when the field has just gained focus, so the click that focused it
  /// selects the whole address and later clicks place the caret.
  bool _selectAllOnTap = false;

  /// The text the field showed when it gained focus.
  String _focusText = '';

  @override
  void initState() {
    super.initState();
    // Repaint the field when it gains or loses focus.
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
      _focusText = full;
      _selectAllOnTap = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _selectAllOnTap = false,
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
    _syncAddress();
  }

  /// The New Tab page shows an empty address bar.
  String _full(String url) => isNewTabUrl(url) ? '' : url;

  void _syncAddress() {
    if (widget.addressFocus.hasFocus) {
      // The page navigated (a New Tab tile, a bookmark) while the field was
      // focused but untouched: show the new address and give the page the
      // keyboard, as Chrome does.
      final view = _bound;
      if (view != null &&
          _address.text == _focusText &&
          _full(view.url.value) != _focusText) {
        widget.addressFocus.unfocus();
        view.focus();
      }
      return;
    }
    final full = _full(_bound?.url.value ?? '');
    if (_address.text == full) return;
    _address.value = TextEditingValue(
      text: full,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  void _onTap() {
    if (!_selectAllOnTap) return;
    _selectAllOnTap = false;
    _address.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _address.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabsProvider);
    final settings = ref.watch(appSettingsProvider);
    final view = state.active?.view;
    final compact = MediaQuery.sizeOf(context).width < compactBreakpoint;
    _bind(view);
    // On phones the address bar takes the whole row while editing.
    final editing = compact && widget.addressFocus.hasFocus;
    final colors = BrowserColors.of(context);

    void go(String text) {
      _suggestions.clear();
      if (text.trim().isEmpty) {
        // Nothing typed: leave the page as it is.
        widget.addressFocus.unfocus();
        return;
      }
      final keys = HardwareKeyboard.instance;
      final word = text.trim();
      if (keys.isControlPressed && RegExp(r'^[\w-]+$').hasMatch(word)) {
        text = 'www.$word.com';
      }
      final url = resolveInput(text, searchTemplate: settings.searchTemplate);
      if (keys.isAltPressed) {
        ref
            .read(tabsProvider.notifier)
            .newTab(url: url, incognito: view?.incognito ?? false);
      } else {
        view?.load(url);
      }
      widget.addressFocus.unfocus();
      // Like Chrome, the page then has the keyboard (Space scrolls it).
      view?.focus();
    }

    Widget button(String tooltip, IconData icon, VoidCallback? onPressed) =>
        _ToolbarButton(
          tooltip: tooltip,
          icon: icon,
          color: colors.icon,
          size: compact ? 21 : 19,
          onPressed: onPressed,
        );

    final field = _Omnibox(
      controller: _address,
      focus: widget.addressFocus,
      view: view,
      compact: compact,
      suggestions: _suggestions,
      onGo: go,
      onTap: _onTap,
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
      child: Padding(
        // Phones keep navigation in the bottom bar (MobileBottomBar), so the
        // address bar gets the whole top row.
        padding: compact
            ? const EdgeInsets.fromLTRB(10, 6, 6, 6)
            : const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            if (!compact) ...[
              button('Back', CupertinoIcons.chevron_left, view?.goBack),
              button('Forward', CupertinoIcons.chevron_right, view?.goForward),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: compact
                  ? field
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _maxFieldWidth,
                        ),
                        child: field,
                      ),
                    ),
            ),
            SizedBox(width: compact ? 4 : 10),
            if (editing)
              button(
                'Cancel',
                CupertinoIcons.xmark,
                widget.addressFocus.unfocus,
              ),
            if (view != null && !editing)
              ValueListenableBuilder<String>(
                valueListenable: view.url,
                builder: (_, url, _) => switch (webStoreItemId(url)) {
                  final id? => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(CupertinoIcons.add, size: 16),
                      label: Text(compact ? 'Add' : 'Add to 6browser'),
                      onPressed: () => runWebStoreInstall(context, ref, id),
                    ),
                  ),
                  null => const SizedBox.shrink(),
                },
              ),
            if (!compact) const ExtensionsToolbar(),
            if (!compact) const ProfileButton(),
            if (!compact) _MainMenu(menuKey: widget.menuKey, view: view),
            if (compact && !editing && view != null) _ReloadButton(view: view),
          ],
        ),
      ),
    );
  }
}

/// A plain toolbar glyph with a rounded hover highlight, as in Safari.
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.size = 19,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    iconSize: size,
    color: color,
    disabledColor: color.withValues(alpha: 0.3),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 34, height: 32),
    icon: Icon(icon),
    onPressed: onPressed,
  );
}

/// Reload, or Stop while the page loads.
class _ReloadButton extends StatelessWidget {
  const _ReloadButton({required this.view, this.inField = false});

  final BrowserView view;

  /// Smaller, inside the address field (desktop).
  final bool inField;

  @override
  Widget build(BuildContext context) {
    final colors = BrowserColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: view.isLoading,
      builder: (_, loading, _) {
        final stop = loading && view.supportsStop;
        return IconButton(
          tooltip: stop ? 'Stop loading' : 'Reload (F5)',
          iconSize: inField ? 14 : 19,
          color: inField ? colors.omniboxText : colors.icon,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(
            width: inField ? 28 : 34,
            height: inField ? 26 : 32,
          ),
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(inField ? 6 : Ui.radius),
            ),
          ),
          icon: Icon(
            stop ? CupertinoIcons.xmark : CupertinoIcons.arrow_clockwise,
          ),
          onPressed: stop ? view.stop : view.reload,
        );
      },
    );
  }
}

/// What the suggestions list shows, so Enter can tell an option the user
/// picked with the arrow keys from the text they typed.
class _SuggestionState {
  String query = '';
  List<String> options = const [];
  int highlighted = 0;

  void clear() {
    query = '';
    options = const [];
    highlighted = 0;
  }

  /// The option to open for [text]: the highlighted suggestion when the
  /// user moved to one, otherwise what they typed.
  String pick(String text) =>
      query == text && highlighted > 0 && highlighted < options.length
      ? options[highlighted]
      : text;
}

/// The address field. Unfocused it shows the site's name centered with its
/// security state, like Safari; focused it shows and edits the full URL.
class _Omnibox extends ConsumerWidget {
  const _Omnibox({
    required this.controller,
    required this.focus,
    required this.view,
    required this.compact,
    required this.suggestions,
    required this.onGo,
    required this.onTap,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final BrowserView? view;
  final bool compact;
  final _SuggestionState suggestions;
  final ValueChanged<String> onGo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final colors = BrowserColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final focused = focus.hasFocus;
    final view = this.view;
    final height = compact ? 40.0 : Ui.fieldHeight;
    final fontSize = compact ? 15.0 : 13.5;
    final radius = BorderRadius.circular(compact ? 12 : 9);
    final light = colors.brightness == Brightness.light;

    final placeholder = view?.incognito == true
        ? 'Search privately or enter website name'
        : 'Search or enter website name';

    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        height: height,
        child: RawAutocomplete<String>(
          textEditingController: controller,
          focusNode: focus,
          optionsBuilder: (value) async {
            final text = value.text;
            if (!focus.hasFocus || text.trim().isEmpty) return const [];
            final found = await db.suggest(text);
            // The typed text comes first, so Enter opens what was typed
            // unless an arrow key moved to a suggestion.
            return [text, ...found.where((s) => s != text)];
          },
          onSelected: onGo,
          // A large system font size must not overflow the fixed-height bar.
          fieldViewBuilder: (context, controller, focus, _) =>
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: AnimatedContainer(
                  duration: Ui.fast,
                  curve: Ui.curve,
                  decoration: BoxDecoration(
                    color: focused
                        ? (light ? Colors.white : colors.omnibox)
                        : colors.omnibox,
                    borderRadius: radius,
                    // Apple's focus ring: a soft halo in the accent color.
                    boxShadow: focused
                        ? [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.45),
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Stack(
                      children: [
                        TextField(
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
                            // Unfocused, the centered summary below shows
                            // instead.
                            color: focused
                                ? colors.omniboxText
                                : Colors.transparent,
                          ),
                          cursorColor: scheme.primary,
                          cursorWidth: 1.5,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            constraints: BoxConstraints.tightFor(
                              height: height,
                            ),
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: focused ? placeholder : null,
                            hintStyle: TextStyle(
                              fontSize: fontSize,
                              color: colors.omniboxText.withValues(alpha: 0.5),
                            ),
                            prefixIconConstraints: BoxConstraints(
                              minWidth: compact ? 38 : 32,
                              minHeight: height,
                            ),
                            prefixIcon: Icon(
                              CupertinoIcons.search,
                              size: compact ? 17 : 14,
                              color: focused
                                  ? colors.omniboxText.withValues(alpha: 0.55)
                                  : Colors.transparent,
                            ),
                            suffixIcon: view == null || compact
                                ? null
                                : Padding(
                                    padding: const EdgeInsets.only(right: 3),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        PasswordKeyButton(
                                          view: view,
                                          color: colors.omniboxText,
                                        ),
                                        _ZoomChip(view: view),
                                        _BookmarkStar(view: view),
                                        _ReloadButton(
                                          view: view,
                                          inField: true,
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          onTap: onTap,
                          onSubmitted: (text) => onGo(suggestions.pick(text)),
                        ),
                        if (!focused)
                          Positioned.fill(
                            right: compact ? 0 : 110,
                            left: compact ? 0 : 110,
                            child: IgnorePointer(
                              child: view == null
                                  ? const SizedBox.shrink()
                                  : ValueListenableBuilder<String>(
                                      valueListenable: view.url,
                                      builder: (_, url, _) => _AddressSummary(
                                        url: url,
                                        placeholder: placeholder,
                                        color: colors.omniboxText,
                                        fontSize: fontSize,
                                      ),
                                    ),
                            ),
                          ),
                        if (view != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 2,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: view.isLoading,
                              builder: (_, loading, _) => loading
                                  ? const LinearProgressIndicator(minHeight: 2)
                                  : const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          optionsViewBuilder: (context, onSelected, options) {
            suggestions
              ..query = controller.text
              ..options = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Material(
                  elevation: 12,
                  shadowColor: Colors.black.withValues(alpha: 0.3),
                  color: Theme.of(context).popupMenuTheme.color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Ui.radiusLarge),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 360,
                      maxWidth: box.maxWidth,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(5),
                      shrinkWrap: true,
                      children: [
                        for (final (i, o) in options.indexed)
                          _Suggestion(
                            index: i,
                            text: o,
                            suggestions: suggestions,
                            onTap: () => onSelected(o),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The unfocused address: lock and site name centered, or the placeholder
/// on the New Tab page.
class _AddressSummary extends StatelessWidget {
  const _AddressSummary({
    required this.url,
    required this.placeholder,
    required this.color,
    required this.fontSize,
  });

  final String url;
  final String placeholder;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final muted = color.withValues(alpha: 0.5);
    final List<Widget> parts;
    if (isNewTabUrl(url)) {
      parts = [
        Icon(CupertinoIcons.search, size: fontSize, color: muted),
        const SizedBox(width: 6),
        Flexible(child: _text(placeholder, muted)),
      ];
    } else if (isSecureUrl(url)) {
      parts = [
        Tooltip(
          message: 'Connection is secure',
          child: Icon(
            CupertinoIcons.lock_fill,
            size: fontSize - 2,
            color: color.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(child: _text(displayHost(url), color)),
      ];
    } else if (url.startsWith('http://')) {
      final warn = Theme.of(context).colorScheme.error;
      parts = [
        Icon(
          CupertinoIcons.exclamationmark_triangle_fill,
          size: fontSize - 1,
          color: warn,
        ),
        const SizedBox(width: 6),
        _text('Not Secure', warn),
        _text(' — ', muted),
        Flexible(child: _text(displayHost(url), color)),
      ];
    } else {
      parts = [Flexible(child: _text(url, color))];
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: parts);
  }

  Widget _text(String text, Color color) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textDirection: TextDirection.ltr,
    style: TextStyle(fontSize: fontSize, height: 1.2, color: color),
  );
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.index,
    required this.text,
    required this.suggestions,
    required this.onTap,
  });

  final int index;
  final String text;
  final _SuggestionState suggestions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final highlighted = AutocompleteHighlightedOption.of(context);
    if (index == highlighted) suggestions.highlighted = highlighted;
    final scheme = Theme.of(context).colorScheme;
    final isUrl = isBookmarkable(text);
    final selected = index == highlighted;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    final muted = selected
        ? scheme.onPrimary.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    return Material(
      color: selected ? scheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              index == 0
                  ? Icon(CupertinoIcons.search, size: 15, color: muted)
                  : isUrl
                  ? Favicon(url: text, color: muted)
                  : Icon(CupertinoIcons.clock, size: 15, color: muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the page zoom when it is not 100%; clicking resets it (Ctrl+0).
class _ZoomChip extends StatelessWidget {
  const _ZoomChip({required this.view});

  final BrowserView view;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: view.zoom,
    builder: (_, zoom, _) {
      final percent = (zoom * 100).round();
      if (percent == 100) return const SizedBox.shrink();
      return TextButton(
        key: const ValueKey('zoom-chip'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(0, 24),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: BrowserColors.of(context).omniboxText,
          textStyle: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        onPressed: () => view.zoomStep(0),
        child: Text('$percent%'),
      );
    },
  );
}

/// Star that shows whether the current page is bookmarked. Clicking it
/// bookmarks the page and opens the editor (name, folder, remove).
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
        return Builder(
          builder: (context) => IconButton(
            tooltip: on ? 'Edit bookmark for this tab' : 'Bookmark this tab',
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 26),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            color: on
                ? Theme.of(context).colorScheme.primary
                : colors.omniboxText,
            icon: Icon(on ? CupertinoIcons.star_fill : CupertinoIcons.star),
            onPressed: () async {
              final id = on
                  ? (await db.bookmarkForUrl(url))?.id
                  : await db.addBookmark(url, view.title.value);
              if (id != null && context.mounted) {
                await showBookmarkEditor(context, id: id, added: !on);
              }
            },
          ),
        );
      },
    );
  }
}

/// The "…" menu, with icons and keyboard shortcuts.
class _MainMenu extends ConsumerWidget {
  const _MainMenu({required this.view, this.menuKey});

  final BrowserView? view;
  final GlobalKey<PopupMenuButtonState<String>>? menuKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(tabsProvider.notifier);
    final settings = ref.watch(appSettingsProvider);
    final colors = BrowserColors.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final commands = BrowserCommands.maybeOf(context);
    final pageTools = view?.supportsPageTools ?? false;

    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      String? shortcut,
      bool checked = false,
    }) => PopupMenuItem(
      value: value,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 16, color: muted),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          if (checked)
            Icon(CupertinoIcons.checkmark_alt, size: 16, color: muted),
          if (shortcut != null)
            Text(shortcut, style: TextStyle(fontSize: 12, color: muted)),
        ],
      ),
    );

    return PopupMenuButton<String>(
      key: menuKey,
      tooltip: 'Menu',
      icon: Icon(CupertinoIcons.ellipsis_circle, color: colors.icon, size: 19),
      style: IconButton.styleFrom(
        minimumSize: const Size(34, 32),
        padding: EdgeInsets.zero,
      ),
      constraints: const BoxConstraints(minWidth: 280),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      onSelected: (v) {
        if (commands != null) {
          for (final c in BrowserCommand.values) {
            if (c.name == v) return commands.run(c);
          }
        }
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
          case 'extensions':
            openPage(context, const ExtensionsPage());
          case 'import':
            openPage(context, const ImportPage());
          case 'shortcuts':
            openPage(context, const ShortcutsPage());
        }
      },
      itemBuilder: (_) => [
        item('new', CupertinoIcons.plus_square, 'New tab', shortcut: 'Ctrl+T'),
        item(
          'incognito',
          CupertinoIcons.eye_slash,
          'New private tab',
          shortcut: 'Ctrl+Shift+N',
        ),
        item(
          BrowserCommand.reopenClosedTab.name,
          CupertinoIcons.arrow_counterclockwise,
          'Reopen closed tab',
          shortcut: shortcutFor(BrowserCommand.reopenClosedTab),
        ),
        const PopupMenuDivider(),
        item('history', CupertinoIcons.clock, 'History', shortcut: 'Ctrl+H'),
        item(
          'downloads',
          CupertinoIcons.arrow_down_circle,
          'Downloads',
          shortcut: 'Ctrl+J',
        ),
        item(
          'bookmarks',
          CupertinoIcons.book,
          'Bookmarks',
          shortcut: 'Ctrl+Shift+O',
        ),
        item(
          'bar',
          CupertinoIcons.bookmark,
          'Show bookmarks bar',
          checked: settings.showBookmarksBar,
        ),
        const PopupMenuDivider(),
        if (pageTools) ...[
          _ZoomMenuEntry(view: view!, color: muted),
          item(
            BrowserCommand.find.name,
            CupertinoIcons.doc_text_search,
            'Find…',
            shortcut: shortcutFor(BrowserCommand.find),
          ),
          item(
            BrowserCommand.print.name,
            CupertinoIcons.printer,
            'Print…',
            shortcut: shortcutFor(BrowserCommand.print),
          ),
          item(
            BrowserCommand.savePage.name,
            CupertinoIcons.arrow_down_doc,
            'Save page as…',
            shortcut: shortcutFor(BrowserCommand.savePage),
          ),
          item(
            BrowserCommand.viewSource.name,
            CupertinoIcons.chevron_left_slash_chevron_right,
            'View page source',
            shortcut: shortcutFor(BrowserCommand.viewSource),
          ),
          const PopupMenuDivider(),
        ],
        item('extensions', CupertinoIcons.cube, 'Extensions'),
        item('customize', CupertinoIcons.paintbrush, 'Customize appearance'),
        item('import', CupertinoIcons.tray_arrow_down, 'Import from browser…'),
        item('settings', CupertinoIcons.gear, 'Settings'),
        const PopupMenuDivider(),
        item(
          'devtools',
          CupertinoIcons.hammer,
          'Developer tools',
          shortcut: 'F12',
        ),
        item('shortcuts', CupertinoIcons.keyboard, 'Keyboard shortcuts'),
      ],
    );
  }
}

/// "Zoom  –  100%  +  ⛶" menu row. It stays open while zooming.
class _ZoomMenuEntry extends PopupMenuEntry<String> {
  const _ZoomMenuEntry({required this.view, required this.color});

  final BrowserView view;
  final Color color;

  @override
  double get height => 36;

  @override
  bool represents(String? value) => false;

  @override
  State<_ZoomMenuEntry> createState() => _ZoomMenuEntryState();
}

class _ZoomMenuEntryState extends State<_ZoomMenuEntry> {
  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final color = widget.color;
    final text = Theme.of(context).textTheme.bodyMedium;
    Widget small(String tooltip, IconData icon, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip,
          iconSize: 15,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 30, height: 28),
          icon: Icon(icon),
          onPressed: onPressed,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(CupertinoIcons.zoom_in, size: 16, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text('Zoom', style: text)),
          small(
            'Zoom out (${shortcutFor(BrowserCommand.zoomOut)})',
            CupertinoIcons.minus,
            () => view.zoomStep(-1),
          ),
          ValueListenableBuilder<double>(
            valueListenable: view.zoom,
            builder: (_, zoom, _) => SizedBox(
              width: 46,
              child: Text(
                '${(zoom * 100).round()}%',
                textAlign: TextAlign.center,
                style: text,
              ),
            ),
          ),
          small(
            'Zoom in (${shortcutFor(BrowserCommand.zoomIn)})',
            CupertinoIcons.plus,
            () => view.zoomStep(1),
          ),
          if (Fullscreen.supported)
            small('Full screen (F11)', CupertinoIcons.fullscreen, () {
              Navigator.of(context).pop();
              Fullscreen.toggle();
            }),
        ],
      ),
    );
  }
}
