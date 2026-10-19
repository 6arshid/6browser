import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Everything the browser can do from the keyboard, with Chrome's shortcuts.
/// The shell runs the commands ([BrowserCommands.run]); the main menu and the
/// shortcuts page read their key labels from [browserShortcuts].
enum BrowserCommand {
  // Tabs and windows
  newTab('Open a new tab'),
  newWindow('New window (opens a new tab)'),
  newIncognitoTab('Open a new incognito tab'),
  reopenClosedTab('Reopen the last closed tab'),
  closeTab('Close the current tab'),
  closeWindow('Close the window'),
  nextTab('Go to the next tab'),
  previousTab('Go to the previous tab'),
  tab1('Go to tab 1'),
  tab2('Go to tab 2'),
  tab3('Go to tab 3'),
  tab4('Go to tab 4'),
  tab5('Go to tab 5'),
  tab6('Go to tab 6'),
  tab7('Go to tab 7'),
  tab8('Go to tab 8'),
  lastTab('Go to the last tab'),
  moveTabLeft('Move the tab left'),
  moveTabRight('Move the tab right'),
  fullscreen('Full screen'),

  // Navigation
  back('Back'),
  forward('Forward'),
  reload('Reload'),
  hardReload('Reload, ignoring cached content'),
  stop('Stop loading'),
  home('Open the home page'),

  // Address bar
  focusAddress('Jump to the address bar'),
  search('Search from the address bar'),

  // Page
  find('Find in page'),
  findNext('Find next match'),
  findPrevious('Find previous match'),
  zoomIn('Zoom in'),
  zoomOut('Zoom out'),
  zoomReset('Reset zoom (100%)'),
  print('Print'),
  savePage('Save page'),
  openFile('Open a file'),
  viewSource('View page source'),

  // Browser features
  bookmarkPage('Bookmark this page'),
  bookmarkAllTabs('Bookmark all open tabs'),
  toggleBookmarksBar('Show or hide the bookmarks bar'),
  bookmarks('Open bookmarks'),
  history('Open history'),
  downloads('Open downloads'),
  clearBrowsingData('Clear browsing data'),
  menu('Open the main menu'),
  devTools('Developer tools');

  const BrowserCommand(this.label);

  final String label;
}

/// Sections for the keyboard shortcuts page.
const browserCommandGroups = <(String, List<BrowserCommand>)>[
  (
    'Tabs and windows',
    [
      BrowserCommand.newTab,
      BrowserCommand.newWindow,
      BrowserCommand.newIncognitoTab,
      BrowserCommand.reopenClosedTab,
      BrowserCommand.closeTab,
      BrowserCommand.closeWindow,
      BrowserCommand.nextTab,
      BrowserCommand.previousTab,
      BrowserCommand.tab1,
      BrowserCommand.lastTab,
      BrowserCommand.moveTabLeft,
      BrowserCommand.moveTabRight,
      BrowserCommand.fullscreen,
    ],
  ),
  (
    'Navigation',
    [
      BrowserCommand.back,
      BrowserCommand.forward,
      BrowserCommand.reload,
      BrowserCommand.hardReload,
      BrowserCommand.stop,
      BrowserCommand.home,
      BrowserCommand.focusAddress,
      BrowserCommand.search,
    ],
  ),
  (
    'Page',
    [
      BrowserCommand.find,
      BrowserCommand.findNext,
      BrowserCommand.findPrevious,
      BrowserCommand.zoomIn,
      BrowserCommand.zoomOut,
      BrowserCommand.zoomReset,
      BrowserCommand.print,
      BrowserCommand.savePage,
      BrowserCommand.openFile,
      BrowserCommand.viewSource,
    ],
  ),
  (
    'Browser',
    [
      BrowserCommand.bookmarkPage,
      BrowserCommand.bookmarkAllTabs,
      BrowserCommand.toggleBookmarksBar,
      BrowserCommand.bookmarks,
      BrowserCommand.history,
      BrowserCommand.downloads,
      BrowserCommand.clearBrowsingData,
      BrowserCommand.menu,
      BrowserCommand.devTools,
    ],
  ),
];

bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

/// Ctrl on Windows/Linux, Cmd on macOS, as in Chrome.
SingleActivator _primary(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
}) => SingleActivator(
  key,
  control: !_isMac,
  meta: _isMac,
  shift: shift,
  alt: alt,
);

SingleActivator _key(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, shift: shift);

SingleActivator _alt(LogicalKeyboardKey key) => SingleActivator(key, alt: true);

/// Chrome's shortcuts for each command, the first being the one shown in
/// menus. Commands without an entry have no shortcut.
final Map<BrowserCommand, List<SingleActivator>> browserShortcuts = {
  BrowserCommand.newTab: [_primary(LogicalKeyboardKey.keyT)],
  BrowserCommand.newWindow: [_primary(LogicalKeyboardKey.keyN)],
  BrowserCommand.newIncognitoTab: [
    _primary(LogicalKeyboardKey.keyN, shift: true),
  ],
  BrowserCommand.reopenClosedTab: [
    _primary(LogicalKeyboardKey.keyT, shift: true),
  ],
  BrowserCommand.closeTab: [
    _primary(LogicalKeyboardKey.keyW),
    _primary(LogicalKeyboardKey.f4),
  ],
  BrowserCommand.closeWindow: [_primary(LogicalKeyboardKey.keyW, shift: true)],
  BrowserCommand.nextTab: [
    const SingleActivator(LogicalKeyboardKey.tab, control: true),
    _primary(LogicalKeyboardKey.pageDown),
    if (_isMac) _primary(LogicalKeyboardKey.arrowRight, alt: true),
  ],
  BrowserCommand.previousTab: [
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true),
    _primary(LogicalKeyboardKey.pageUp),
    if (_isMac) _primary(LogicalKeyboardKey.arrowLeft, alt: true),
  ],
  for (final (i, cmd) in const [
    BrowserCommand.tab1,
    BrowserCommand.tab2,
    BrowserCommand.tab3,
    BrowserCommand.tab4,
    BrowserCommand.tab5,
    BrowserCommand.tab6,
    BrowserCommand.tab7,
    BrowserCommand.tab8,
    BrowserCommand.lastTab,
  ].indexed)
    cmd: [_primary(_digits[i]), _primary(_numpadDigits[i])],
  BrowserCommand.moveTabLeft: [
    _primary(LogicalKeyboardKey.pageUp, shift: true),
  ],
  BrowserCommand.moveTabRight: [
    _primary(LogicalKeyboardKey.pageDown, shift: true),
  ],
  BrowserCommand.fullscreen: [
    _key(LogicalKeyboardKey.f11),
    if (_isMac)
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true, control: true),
  ],
  BrowserCommand.back: [
    if (_isMac)
      _primary(LogicalKeyboardKey.bracketLeft)
    else
      _alt(LogicalKeyboardKey.arrowLeft),
    _key(LogicalKeyboardKey.browserBack),
  ],
  BrowserCommand.forward: [
    if (_isMac)
      _primary(LogicalKeyboardKey.bracketRight)
    else
      _alt(LogicalKeyboardKey.arrowRight),
    _key(LogicalKeyboardKey.browserForward),
  ],
  BrowserCommand.reload: [
    _key(LogicalKeyboardKey.f5),
    _primary(LogicalKeyboardKey.keyR),
    _key(LogicalKeyboardKey.browserRefresh),
  ],
  BrowserCommand.hardReload: [
    _primary(LogicalKeyboardKey.keyR, shift: true),
    _key(LogicalKeyboardKey.f5, shift: true),
    _primary(LogicalKeyboardKey.f5),
  ],
  BrowserCommand.stop: [
    _key(LogicalKeyboardKey.escape),
    _key(LogicalKeyboardKey.browserStop),
  ],
  BrowserCommand.home: [
    if (_isMac)
      _primary(LogicalKeyboardKey.keyH, shift: true)
    else
      _alt(LogicalKeyboardKey.home),
    _key(LogicalKeyboardKey.browserHome),
  ],
  BrowserCommand.focusAddress: [
    _primary(LogicalKeyboardKey.keyL),
    _alt(LogicalKeyboardKey.keyD),
    _key(LogicalKeyboardKey.f6),
  ],
  BrowserCommand.search: [
    _primary(LogicalKeyboardKey.keyK),
    _primary(LogicalKeyboardKey.keyE),
    _key(LogicalKeyboardKey.browserSearch),
  ],
  BrowserCommand.find: [_primary(LogicalKeyboardKey.keyF)],
  BrowserCommand.findNext: [
    _primary(LogicalKeyboardKey.keyG),
    _key(LogicalKeyboardKey.f3),
  ],
  BrowserCommand.findPrevious: [
    _primary(LogicalKeyboardKey.keyG, shift: true),
    _key(LogicalKeyboardKey.f3, shift: true),
  ],
  BrowserCommand.zoomIn: [
    _primary(LogicalKeyboardKey.equal),
    _primary(LogicalKeyboardKey.equal, shift: true), // Ctrl and "+"
    _primary(LogicalKeyboardKey.add),
    _primary(LogicalKeyboardKey.numpadAdd),
  ],
  BrowserCommand.zoomOut: [
    _primary(LogicalKeyboardKey.minus),
    _primary(LogicalKeyboardKey.numpadSubtract),
  ],
  BrowserCommand.zoomReset: [
    _primary(LogicalKeyboardKey.digit0),
    _primary(LogicalKeyboardKey.numpad0),
  ],
  BrowserCommand.print: [_primary(LogicalKeyboardKey.keyP)],
  BrowserCommand.savePage: [_primary(LogicalKeyboardKey.keyS)],
  BrowserCommand.openFile: [_primary(LogicalKeyboardKey.keyO)],
  BrowserCommand.viewSource: [
    if (_isMac)
      _primary(LogicalKeyboardKey.keyU, alt: true)
    else
      _primary(LogicalKeyboardKey.keyU),
  ],
  BrowserCommand.bookmarkPage: [_primary(LogicalKeyboardKey.keyD)],
  BrowserCommand.bookmarkAllTabs: [
    _primary(LogicalKeyboardKey.keyD, shift: true),
  ],
  BrowserCommand.toggleBookmarksBar: [
    _primary(LogicalKeyboardKey.keyB, shift: true),
  ],
  BrowserCommand.bookmarks: [
    _primary(LogicalKeyboardKey.keyO, shift: true),
    if (_isMac) _primary(LogicalKeyboardKey.keyB, alt: true),
  ],
  BrowserCommand.history: [
    if (_isMac)
      _primary(LogicalKeyboardKey.keyY)
    else
      _primary(LogicalKeyboardKey.keyH),
  ],
  BrowserCommand.downloads: [
    if (_isMac)
      _primary(LogicalKeyboardKey.keyJ, shift: true)
    else
      _primary(LogicalKeyboardKey.keyJ),
  ],
  BrowserCommand.clearBrowsingData: [
    _primary(LogicalKeyboardKey.delete, shift: true),
    if (_isMac) _primary(LogicalKeyboardKey.backspace, shift: true),
  ],
  BrowserCommand.menu: [
    _alt(LogicalKeyboardKey.keyF),
    _alt(LogicalKeyboardKey.keyE),
    _key(LogicalKeyboardKey.f10),
  ],
  BrowserCommand.devTools: [
    _key(LogicalKeyboardKey.f12),
    _primary(LogicalKeyboardKey.keyI, shift: true),
    _primary(LogicalKeyboardKey.keyJ, shift: true),
    _primary(LogicalKeyboardKey.keyC, shift: true),
    if (_isMac) _primary(LogicalKeyboardKey.keyI, alt: true),
  ],
};

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const _numpadDigits = [
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

/// "Ctrl+Shift+T" style label for an activator.
String shortcutLabel(SingleActivator a) {
  final parts = <String>[
    if (a.control) 'Ctrl',
    if (a.meta) 'Cmd',
    if (a.alt) _isMac ? 'Option' : 'Alt',
    if (a.shift) 'Shift',
    _keyName(a.trigger),
  ];
  return parts.join('+');
}

String _keyName(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.arrowLeft => '←',
  LogicalKeyboardKey.arrowRight => '→',
  LogicalKeyboardKey.equal => '=',
  LogicalKeyboardKey.add => '+',
  LogicalKeyboardKey.minus => '-',
  LogicalKeyboardKey.pageUp => 'PgUp',
  LogicalKeyboardKey.pageDown => 'PgDn',
  LogicalKeyboardKey.escape => 'Esc',
  LogicalKeyboardKey.delete => 'Delete',
  LogicalKeyboardKey.bracketLeft => '[',
  LogicalKeyboardKey.bracketRight => ']',
  _ => key.keyLabel,
};

/// The menu label for [command]'s main shortcut, or null.
String? shortcutFor(BrowserCommand command) {
  final list = browserShortcuts[command];
  return list == null || list.isEmpty ? null : shortcutLabel(list.first);
}

/// Lets widgets below the shell run commands (menus, buttons).
class BrowserCommands extends InheritedWidget {
  const BrowserCommands({super.key, required this.run, required super.child});

  final void Function(BrowserCommand command) run;

  static BrowserCommands? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BrowserCommands>();

  @override
  bool updateShouldNotify(BrowserCommands oldWidget) => run != oldWidget.run;
}
