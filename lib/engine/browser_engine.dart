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

  Future<void> openDevTools();

  /// Right-click (context menu) requests from the page. The app draws the
  /// menu. Backends that show a native menu themselves never emit.
  Stream<PageContextMenu> get contextMenus;

  /// Runs an editing command on the focused frame.
  Future<void> editCommand(EditCommand command);

  /// Downloads [url] (Save link as / Save image as).
  Future<void> download(String url);

  /// Opens DevTools with the element at [pagePosition] selected.
  Future<void> inspectAt(Offset pagePosition);

  Future<void> dispose();
}

enum EditCommand { undo, redo, cut, copy, paste, delete, selectAll }

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
}
