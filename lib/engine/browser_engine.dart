import 'dart:async';

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

  /// Gives the page the keyboard focus.
  void focus();

  /// Background tabs are hidden: they stop rendering, as in Chrome.
  void setVisible(bool visible);
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

  /// Pages asking for a new tab: target=_blank links, window.open, Ctrl or
  /// middle clicks. Backends that open such links in place never emit.
  Stream<NewTabRequest> get newTabRequests;

  /// Links to other apps (mailto:, tg:, zoommtg:...) the page tried to open.
  /// The page stays as it was; the app asks the user and hands the link to
  /// the system. Backends that cannot catch such links never emit.
  Stream<ExternalLinkRequest> get externalLinks;

  /// Key presses the page did not handle, so browser shortcuts that pages
  /// may claim (Ctrl+F, Ctrl+K...) run only when the page leaves them.
  /// Backends whose keys never reach the page first never emit.
  Stream<PageKey> get unhandledKeys;

  /// Sites asking to use the camera, microphone, location... The app
  /// answers from the user's saved choice or asks. Backends that cannot ask
  /// never emit.
  Stream<PermissionRequest> get permissionRequests;

  /// The page wants to share the screen (getDisplayMedia); the app shows
  /// its screen and window picker. Backends with their own picker never
  /// emit.
  Stream<ScreenShareRequest> get screenShareRequests;

  /// alert(), confirm(), prompt() and "Leave site?" for the app to draw.
  /// Backends that show their own dialogs never emit.
  Stream<PageDialogRequest> get pageDialogs;

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

/// A key press the page left alone: a Windows virtual-key code and the
/// modifiers held.
class PageKey {
  const PageKey(
    this.keyCode, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final int keyCode;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;
}

/// A page asked to open [url] in a new tab; [background] for Ctrl and middle
/// clicks, which leave the current tab selected.
class NewTabRequest {
  const NewTabRequest(this.url, {this.background = false});

  final String url;
  final bool background;
}

/// A page asked to open [url], a link that belongs to another app.
/// [source] is the URL of that page; empty when the user typed the link.
class ExternalLinkRequest {
  const ExternalLinkRequest(this.url, {this.source = ''});

  final String url;
  final String source;
}

/// What a site can ask to use.
enum SitePermission {
  camera,
  microphone,

  /// Pan, tilt and zoom of the camera.
  cameraControl,
  location,
  clipboard,
  midi,
  windowManagement,
  localFonts,
  idleDetection,
  automaticDownloads,
  sensors,
  localNetwork,
}

/// The user's answer to a [PermissionRequest].
enum PermissionAnswer {
  /// Closed without answering: refused this time, asked again next time.
  dismiss,
  allow,
  block,
}

/// A request the engine waits on: answered once by the app, or withdrawn by
/// the engine first (the page navigated or the tab closed).
abstract class EngineRequest {
  final _withdrawn = Completer<void>();
  bool _answered = false;

  /// Neither answered nor withdrawn.
  bool get isOpen => !_answered && !_withdrawn.isCompleted;

  /// Completes when the engine no longer needs an answer.
  Future<void> get withdrawn => _withdrawn.future;

  /// Called by the engine.
  void withdraw() {
    if (isOpen) _withdrawn.complete();
  }

  /// Marks the request answered; false when it already was, or was
  /// withdrawn.
  @protected
  bool answer() {
    if (!isOpen) return false;
    _answered = true;
    return true;
  }
}

/// A site ([origin]) asks to use [permissions]. They are allowed or refused
/// together.
class PermissionRequest extends EngineRequest {
  PermissionRequest({
    required this.origin,
    required this.permissions,
    required this._onAnswer,
  });

  final String origin;
  final Set<SitePermission> permissions;
  final void Function(PermissionAnswer) _onAnswer;

  void respond(PermissionAnswer answer) {
    if (super.answer()) _onAnswer(answer);
  }
}

/// A page ([origin]) wants to share a screen or window. [audioOffered]: the
/// page asked for audio and the computer's sound can be shared.
class ScreenShareRequest extends EngineRequest {
  ScreenShareRequest({
    required this.origin,
    required this.audioOffered,
    required this._onAnswer,
  });

  final String origin;
  final bool audioOffered;
  final void Function(String? sourceId, bool audio) _onAnswer;

  /// Shares the screen or window [sourceId] (`screen:<index>:0` or
  /// `window:<handle>:0`); [audio] adds the computer's sound.
  void share(String sourceId, {bool audio = false}) {
    if (super.answer()) _onAnswer(sourceId, audio && audioOffered);
  }

  void cancel() {
    if (super.answer()) _onAnswer(null, false);
  }
}

enum PageDialogType { alert, confirm, prompt, leave }

/// alert(), confirm(), prompt() or "Leave site?" ([type] leave; [isReload]
/// when the page is reloading). The page waits for the answer.
class PageDialogRequest extends EngineRequest {
  PageDialogRequest({
    required this.type,
    required this.origin,
    required this.message,
    this.defaultText = '',
    this.isReload = false,
    required this._onAnswer,
  });

  final PageDialogType type;

  /// The page's scheme, host and port; empty when it has none.
  final String origin;
  final String message;

  /// The text prompt() starts with.
  final String defaultText;
  final bool isReload;
  final void Function(bool ok, String text) _onAnswer;

  void respond(bool ok, [String text = '']) {
    if (super.answer()) _onAnswer(ok, text);
  }
}

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

  /// Applies a site permission changed in the app's settings to the
  /// engine's own per-site state, if it keeps one. [allowed] null: ask
  /// again.
  Future<void> setSitePermission(
    String origin,
    Set<SitePermission> permissions,
    bool? allowed,
  );
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
