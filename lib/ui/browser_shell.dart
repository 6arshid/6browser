import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../engine/browser_engine.dart';

import '../features/bookmarks/bookmarks_page.dart';
import '../features/downloads/downloads_page.dart';
import '../features/external_links/external_link_prompt.dart';
import '../features/history/history_page.dart';
import '../features/new_tab/new_tab_page.dart';
import '../features/passwords/password_prompt.dart';
import '../features/profiles/profiles.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/app_settings.dart';
import '../features/tabs/tabs_controller.dart';
import '../features/tabs/url_input.dart';
import '../features/themes/theme_service.dart';
import 'bookmarks_bar.dart';
import 'browser_commands.dart';
import 'browser_theme.dart';
import 'find_bar.dart';
import 'fullscreen.dart';
import 'mobile_chrome.dart';
import 'page_context_menu.dart';
import 'tab_strip.dart';
import 'toolbar.dart';
import 'window_caption.dart';

/// Main window: tab strip and toolbar on wide screens; on phones an address
/// bar on top and a navigation bar (MobileBottomBar) below the page.
class BrowserShell extends ConsumerStatefulWidget {
  const BrowserShell({super.key});

  @override
  ConsumerState<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends ConsumerState<BrowserShell> {
  final _addressFocus = FocusNode();
  final _menuKey = GlobalKey<PopupMenuButtonState<String>>();

  // Find in page (Ctrl+F). The bar belongs to one tab; switching tabs
  // closes it.
  final _findText = TextEditingController();
  final _findFocus = FocusNode();
  BrowserView? _findView;

  StreamSubscription<List<String>>? _handOvers;

  @override
  void initState() {
    super.initState();
    // Provider state may not be modified while the tree is building.
    Future.microtask(() => ref.read(tabsProvider.notifier).start());
    // The phone bottom bar hides while the address is being edited.
    _addressFocus.addListener(_onAddressFocus);
    // Launching 6browser again with this profile (e.g. a link clicked in
    // another app) opens a tab here.
    _handOvers = ref
        .read(activeProfileProvider)
        ?.instance
        ?.requests
        .listen(_onHandOver);
    // The keyboard follows the selected tab: the address bar on a New Tab
    // page (Ctrl+T, then type), the page otherwise.
    ref.listenManual(tabsProvider.select((s) => s.active?.view), (_, view) {
      if (view == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(ref.read(tabsProvider).active?.view, view)) {
          return;
        }
        // Not on phones, where it would open the on-screen keyboard.
        final desktop =
            MediaQuery.sizeOf(context).width >= compactBreakpoint &&
            defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS;
        if (!isNewTabUrl(view.url.value)) {
          view.focus();
        } else if (desktop) {
          _addressFocus.requestFocus();
        }
      });
    });
    // Only the selected tab renders; the others are hidden, as in Chrome.
    ref.listenManual(tabsProvider, (_, next) {
      for (final t in next.tabs) {
        t.view.setVisible(t.id == next.activeId);
      }
    }, fireImmediately: true);
    // With several profiles, the title tells the windows apart.
    ref.listenManual(profileListProvider, (_, next) {
      final list = next.value;
      final active = ref.read(activeProfileProvider);
      if (list == null || active == null) return;
      final me = list.byId(active.profile.id) ?? active.profile;
      WindowCaption.setTitle(
        list.profiles.length > 1 ? '${me.name} - 6browser' : '6browser',
      );
    }, fireImmediately: true);
  }

  void _onHandOver(List<String> args) {
    final launch = LaunchOptions.parse(args);
    ref
        .read(tabsProvider.notifier)
        .newTab(url: launch.url, incognito: launch.incognito);
    WindowCaption.bringToFront();
  }

  void _onAddressFocus() => setState(() {});

  @override
  void dispose() {
    _handOvers?.cancel();
    _addressFocus.removeListener(_onAddressFocus);
    _addressFocus.dispose();
    _findText.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  void _openFind(BrowserView view) {
    if (!view.supportsPageTools) return;
    if (!identical(_findView, view)) _closeFind();
    setState(() => _findView = view);
    _findFocus.requestFocus();
    _findText.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _findText.text.length,
    );
    if (_findText.text.isNotEmpty) view.find(_findText.text);
  }

  void _closeFind() {
    final view = _findView;
    if (view == null) return;
    view.stopFinding();
    setState(() => _findView = null);
    view.focus();
  }

  void _findStep(BrowserView view, {required bool forward}) {
    if (!identical(_findView, view) || _findText.text.isEmpty) {
      _openFind(view);
      return;
    }
    view.find(_findText.text, forward: forward, findNext: true);
  }

  /// True while a page (not the address bar or another field) has the
  /// keyboard focus.
  bool _pageHasFocus() {
    final view = ref.read(tabsProvider).active?.view;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (view == null || focused == null) return false;
    var inPage = identical(focused.widget, view.widget);
    if (inPage) return true;
    focused.visitAncestorElements((e) {
      inPage = identical(e.widget, view.widget);
      return !inPage;
    });
    return inPage;
  }

  /// A shortcut pressed in Flutter. While a page has focus it sees the key
  /// first and only the shortcuts it leaves alone run (see [_onPageKey]),
  /// as in Chrome; tab and window shortcuts always run.
  void _runKey(BrowserCommand command) {
    if (!reservedCommands.contains(command) && _pageHasFocus()) return;
    _run(command);
  }

  void _onPageKey(PageKey key) {
    final command = commandForPageKey(
      key.keyCode,
      control: key.control,
      shift: key.shift,
      alt: key.alt,
      meta: key.meta,
    );
    if (command != null && !reservedCommands.contains(command)) _run(command);
  }

  void _snack(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  /// Runs a keyboard shortcut or menu command, as Chrome does.
  void _run(BrowserCommand command) {
    final ctl = ref.read(tabsProvider.notifier);
    final state = ref.read(tabsProvider);
    final view = state.active?.view;
    final db = ref.read(databaseProvider);
    switch (command) {
      case BrowserCommand.newTab || BrowserCommand.newWindow:
        ctl.newTab();
      case BrowserCommand.newIncognitoTab:
        ctl.newIncognitoTab();
      case BrowserCommand.reopenClosedTab:
        ctl.reopenClosed();
      case BrowserCommand.closeTab:
        final a = state.active;
        if (a != null) ctl.close(a.id);
      case BrowserCommand.closeWindow:
        ServicesBinding.instance.exitApplication(AppExitType.cancelable);
      case BrowserCommand.nextTab:
        ctl.cycle();
      case BrowserCommand.previousTab:
        ctl.cycle(delta: -1);
      case BrowserCommand.tab1 ||
          BrowserCommand.tab2 ||
          BrowserCommand.tab3 ||
          BrowserCommand.tab4 ||
          BrowserCommand.tab5 ||
          BrowserCommand.tab6 ||
          BrowserCommand.tab7 ||
          BrowserCommand.tab8:
        ctl.selectIndex(command.index - BrowserCommand.tab1.index);
      case BrowserCommand.lastTab:
        ctl.selectLast();
      case BrowserCommand.moveTabLeft:
        ctl.moveActive(-1);
      case BrowserCommand.moveTabRight:
        ctl.moveActive(1);
      case BrowserCommand.fullscreen:
        Fullscreen.toggle();
      case BrowserCommand.back:
        view?.goBack();
      case BrowserCommand.forward:
        view?.goForward();
      case BrowserCommand.reload:
        view?.reload();
      case BrowserCommand.hardReload:
        view?.reloadIgnoringCache();
      case BrowserCommand.stop:
        // Esc leaves the address bar, find bar or full screen first.
        if (_addressFocus.hasFocus) {
          _addressFocus.unfocus();
        } else if (_findView != null) {
          _closeFind();
        } else if (Fullscreen.active.value) {
          Fullscreen.set(false);
        } else if (view != null && view.isLoading.value) {
          view.stop();
        }
      case BrowserCommand.home:
        view?.load(ref.read(appSettingsProvider).homeUrl);
      case BrowserCommand.focusAddress || BrowserCommand.search:
        Fullscreen.set(false);
        _addressFocus.requestFocus();
      case BrowserCommand.find:
        if (view != null) _openFind(view);
      case BrowserCommand.findNext:
        if (view != null) _findStep(view, forward: true);
      case BrowserCommand.findPrevious:
        if (view != null) _findStep(view, forward: false);
      case BrowserCommand.zoomIn:
        view?.zoomStep(1);
      case BrowserCommand.zoomOut:
        view?.zoomStep(-1);
      case BrowserCommand.zoomReset:
        view?.zoomStep(0);
      case BrowserCommand.print:
        view?.printPage();
      case BrowserCommand.savePage:
        final url = view?.url.value ?? '';
        if (view != null && isRecordableUrl(url)) view.download(url);
      case BrowserCommand.openFile:
        _openFile(view);
      case BrowserCommand.viewSource:
        final url = view?.url.value ?? '';
        if (view != null && isRecordableUrl(url)) {
          ctl.newTab(url: 'view-source:$url', incognito: view.incognito);
        }
      case BrowserCommand.bookmarkPage:
        final url = view?.url.value ?? '';
        if (view == null || !isBookmarkable(url)) return;
        db.addBookmark(url, view.title.value);
        _snack('Bookmark added');
      case BrowserCommand.bookmarkAllTabs:
        db
            .addBookmarks([
              for (final t in state.tabs)
                if (isBookmarkable(t.view.url.value))
                  (url: t.view.url.value, title: t.view.title.value),
            ])
            .then((n) => _snack('Bookmarks added: $n'));
      case BrowserCommand.toggleBookmarksBar:
        toggleBookmarksBar(ref);
      case BrowserCommand.bookmarks:
        openPage(context, const BookmarksPage());
      case BrowserCommand.history:
        openPage(context, const HistoryPage());
      case BrowserCommand.downloads:
        openPage(context, const DownloadsPage());
      case BrowserCommand.clearBrowsingData:
        openPage(context, const SettingsPage());
      case BrowserCommand.menu:
        _menuKey.currentState?.showButtonMenu();
      case BrowserCommand.devTools:
        view?.openDevTools();
    }
  }

  Future<void> _openFile(BrowserView? view) async {
    final file = await openFile();
    if (file == null || view == null) return;
    await view.load(Uri.file(file.path).toString());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabsProvider);
    final compact = MediaQuery.sizeOf(context).width < compactBreakpoint;
    final typing =
        _addressFocus.hasFocus || MediaQuery.viewInsetsOf(context).bottom > 0;
    final settings = ref.watch(appSettingsProvider);
    final view = state.active?.view;
    if (_findView != null && !identical(_findView, view)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _closeFind());
    }
    final private = view?.incognito == true;
    final colors = private
        ? BrowserColors.incognito
        : BrowserColors.of(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => WindowCaption.apply(colors.frame),
    );

    // A private tab makes the whole window dark, whatever the theme.
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
        for (final MapEntry(key: command, value: keys)
            in browserShortcuts.entries)
          for (final key in keys) key: () => _runKey(command),
      },
      child: BrowserCommands(
        run: _run,
        child: Focus(
          autofocus: true,
          child: ValueListenableBuilder<bool>(
            valueListenable: Fullscreen.active,
            builder: (context, fullscreen, _) => Scaffold(
              backgroundColor: colors.frame,
              body: SafeArea(
                child: Column(
                  children: [
                    if (!compact && !fullscreen) chrome(const TabStrip()),
                    if (!fullscreen)
                      chrome(
                        BrowserToolbar(
                          addressFocus: _addressFocus,
                          menuKey: _menuKey,
                        ),
                      ),
                    if (view != null && !fullscreen)
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
                    if (!fullscreen)
                      Container(height: 1, color: colors.separator),
                    Expanded(
                      child: state.tabs.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : Stack(
                              children: [
                                Positioned.fill(
                                  child: IndexedStack(
                                    index: state.activeIndex,
                                    children: [
                                      for (final t in state.tabs)
                                        KeyedSubtree(
                                          // IndexedStack wraps each child in
                                          // an unkeyed widget, so a plain
                                          // key rebuilt every tab after a
                                          // closed or inserted one.
                                          key: GlobalObjectKey(t.view),
                                          // Saves and fills passwords.
                                          child: PasswordHost(
                                            view: t.view,
                                            // Opens mailto:, tg:... in apps.
                                            child: ExternalLinkHost(
                                              view: t.view,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  ValueListenableBuilder<bool>(
                                                    valueListenable:
                                                        t.view.isReady,
                                                    builder: (_, ready, _) =>
                                                        ready
                                                        // Pages without a background
                                                        // draw on white, as in Chrome
                                                        // (the engine leaves them
                                                        // transparent).
                                                        ? ColoredBox(
                                                            color: Colors.white,
                                                            child: PageContextMenuHost(
                                                              view: t.view,
                                                              child: _PageKeys(
                                                                view: t.view,
                                                                onKey:
                                                                    _onPageKey,
                                                                child: t
                                                                    .view
                                                                    .widget,
                                                              ),
                                                            ),
                                                          )
                                                        : const Center(
                                                            child:
                                                                CircularProgressIndicator(),
                                                          ),
                                                  ),
                                                  // The New Tab page covers the engine's
                                                  // blank page; the view stays alive below.
                                                  ValueListenableBuilder<
                                                    String
                                                  >(
                                                    valueListenable: t.view.url,
                                                    builder: (_, url, _) =>
                                                        isNewTabUrl(url)
                                                        ? NewTabPage(
                                                            view: t.view,
                                                          )
                                                        : const SizedBox.shrink(),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (_findView case final findView?)
                                  Positioned(
                                    top: 0,
                                    right: 16,
                                    child: chrome(
                                      FindBar(
                                        view: findView,
                                        controller: _findText,
                                        focusNode: _findFocus,
                                        onClose: _closeFind,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    if (compact && !typing && !fullscreen)
                      chrome(const MobileBottomBar()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown on the Chrome Web Store. The store's own "Add to Chrome" button
/// cannot work here (its install API crashes this engine and is removed,
/// see docs/ENGINE.md), so it points to "Add to 6browser" instead.
class _WebStoreBar extends ConsumerWidget {
  const _WebStoreBar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final id = webStoreItemId(url);
    final extensions = ref.read(engineProvider).extensions != null;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              Icons.extension_outlined,
              size: 20,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(switch ((id, extensions)) {
                (null, true) =>
                  'Extensions and themes from this store work in '
                      '6browser: open one and use "Add to 6browser" next '
                      'to the address bar.',
                (null, false) =>
                  'Themes from this store work in 6browser: open one and '
                      'use "Add" next to the address bar. Extensions are '
                      'not supported on this system yet.',
                (_, _) =>
                  'Use "Add to 6browser" next to the address bar; the '
                      "store's \"Add to Chrome\" button does not work here.",
              }, style: TextStyle(color: scheme.onSecondaryContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs browser shortcuts for keys the page did not handle.
class _PageKeys extends StatefulWidget {
  const _PageKeys({
    required this.view,
    required this.onKey,
    required this.child,
  });

  final BrowserView view;
  final ValueChanged<PageKey> onKey;
  final Widget child;

  @override
  State<_PageKeys> createState() => _PageKeysState();
}

class _PageKeysState extends State<_PageKeys> {
  StreamSubscription<PageKey>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.view.unhandledKeys.listen((k) => widget.onKey(k));
  }

  @override
  void didUpdateWidget(_PageKeys old) {
    super.didUpdateWidget(old);
    if (!identical(old.view, widget.view)) {
      _sub?.cancel();
      _sub = widget.view.unhandledKeys.listen((k) => widget.onKey(k));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
