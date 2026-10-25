import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Engine-agnostic handle to a single browsing surface (one tab).
///
/// Features depend only on this interface so the underlying backend
/// (webview_cef today, a custom CEF Chrome-runtime plugin later; see
/// docs/ENGINE.md) can be swapped without touching UI code.
abstract class BrowserView {
  /// Current page URL, updated as the page navigates.
  ValueListenable<String> get url;

  /// Current page title.
  ValueListenable<String> get title;

  /// True while a page is loading.
  ValueListenable<bool> get isLoading;

  /// True once the native surface is ready to be displayed.
  ValueListenable<bool> get isReady;

  /// Widget that renders the page.
  Widget get widget;

  /// True for private tabs: nothing is persisted to disk by the engine.
  bool get incognito;

  Future<void> load(String url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();

  /// Stops loading. Not supported by every backend; see [supportsStop].
  Future<void> stop();
  bool get supportsStop;

  /// Reloads, bypassing the cache (Ctrl+Shift+R / Shift+F5).
  Future<void> reloadIgnoringCache();

  Future<void> openDevTools();

  /// Page zoom as a factor (1.0 is 100%). Chromium keeps zoom per site, so
  /// it can also change when the tab navigates.
  ValueListenable<double> get zoom;

  /// Zooms out (-1), back to 100% (0) or in (1) using Chrome's zoom steps.
  Future<void> zoomStep(int direction);

  /// Find in page. Matches are highlighted by the engine and reported
  /// through [findResult]. [findNext] continues the current search.
  Future<void> find(String text, {bool forward = true, bool findNext = false});
  Future<void> stopFinding();
  ValueListenable<FindResult> get findResult;

  /// Opens the print dialog for the page.
  Future<void> printPage();

  /// False when the backend cannot zoom, find or print (the shortcuts are
  /// then ignored).
  bool get supportsPageTools;

  /// Right-click (context menu) requests from the page. The app draws the
  /// menu. Backends that show a native menu themselves never emit.
  Stream<PageContextMenu> get contextMenus;

  /// Runs an editing command on the focused frame.
  Future<void> editCommand(EditCommand command);

  /// Downloads [url] (Save link as / Save image as).
  Future<void> download(String url);

  /// Opens DevTools with the element at [pagePosition] selected.
  Future<void> inspectAt(Offset pagePosition);

  /// Runs [script] in the page's main frame (6browser's own page helpers,
  /// such as saving and filling passwords).
  Future<void> runScript(String script);

  /// JavaScript for a function that sends an object from the page to
  /// [scriptMessages]; null when this backend has no way back.
  String? get scriptPostFunction;

  /// What the page sent through [scriptPostFunction], as JSON text. Any
  /// frame can send, so the content is untrusted.
  Stream<String> get scriptMessages;

  Future<void> dispose();
}

enum EditCommand { undo, redo, cut, copy, paste, delete, selectAll }

/// Find-in-page progress: match [active] (1-based) of [count].
class FindResult {
  const FindResult({this.count = 0, this.active = 0});

  static const none = FindResult();

  final int count;
  final int active;
}

/// What was under the pointer when the page asked for a context menu.
class PageContextMenu {
  const PageContextMenu({
    required this.position,
    this.pagePosition = Offset.zero,
    this.pageUrl = '',
    this.linkUrl = '',
    this.imageUrl = '',
    this.selectionText = '',
    this.isEditable = false,
    this.canUndo = false,
    this.canRedo = false,
    this.canCut = false,
    this.canCopy = false,
    this.canPaste = false,
    this.canSelectAll = false,
    this.canGoBack = false,
    this.canGoForward = false,
  });

  /// Where to show the menu, in global logical pixels.
  final Offset position;

  /// The same point in page coordinates.
  final Offset pagePosition;
  final String pageUrl;

  /// Empty unless the pointer was over a link / an image.
  final String linkUrl;
  final String imageUrl;
  final String selectionText;
  final bool isEditable;
  final bool canUndo;
  final bool canRedo;
  final bool canCut;
  final bool canCopy;
  final bool canPaste;
  final bool canSelectAll;
  final bool canGoBack;
  final bool canGoForward;
}

/// Progress report for one download.
class DownloadEvent {
  const DownloadEvent({
    required this.id,
    required this.url,
    required this.path,
    required this.receivedBytes,
    required this.totalBytes,
    required this.state,
    this.incognito = false,
  });

  final int id;
  final String url;
  final String path;
  final int receivedBytes;

  /// -1 or 0 when the size is unknown.
  final int totalBytes;
  final DownloadState state;

  /// The download came from a private tab.
  final bool incognito;
}

enum DownloadState { inProgress, complete, canceled }

/// Process-wide engine lifecycle and factory for [BrowserView]s.
abstract class BrowserEngine {
  /// Download progress from any tab. Backends without download support
  /// return an empty stream.
  Stream<DownloadEvent> get downloads;

  Future<void> initialize();
  BrowserView createView({required String initialUrl, bool incognito = false});
  Future<void> shutdown();

  /// Chrome extensions, or null when this backend cannot run them.
  ExtensionHost? get extensions;
}

/// Loads Chrome extensions into a running engine. Extensions are not kept
/// by the engine between runs: the app loads its installed ones at start.
abstract class ExtensionHost {
  /// Loads the unpacked extension in the folder [path]. Returns the id the
  /// engine gave it (from the manifest's "key", or derived from the path).
  /// Throws when the extension is rejected, e.g. an invalid manifest.
  Future<String> load(String path);

  /// Removes extension [id] from the running engine, deleting the data it
  /// stored.
  Future<void> unload(String id);
}
