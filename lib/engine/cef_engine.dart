import 'dart:async';
import 'dart:math' show pow;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_cef/webview_cef.dart';

import 'browser_engine.dart';

/// [BrowserEngine] backed by CEF through the `webview_cef` plugin
/// (Alloy style, off-screen rendering). Extensions run, but the chrome.tabs
/// and chrome.windows APIs cannot see our tabs; see docs/ENGINE.md.
class CefEngine implements BrowserEngine {
  CefEngine({this.cachePath});

  /// The profile's folder for cookies, site data and cache; null for the
  /// plugin's default.
  final String? cachePath;

  @override
  Future<void> initialize() =>
      WebviewManager().initialize(cachePath: cachePath);

  @override
  Stream<DownloadEvent> get downloads => WebviewManager().downloadEvents.map(
    (m) => DownloadEvent(
      id: m['id'] as int,
      url: m['url'] as String,
      path: m['path'] as String,
      receivedBytes: m['received'] as int,
      totalBytes: m['total'] as int,
      incognito: (m['incognito'] as int?) == 1,
      state: switch (m['state'] as int) {
        1 => DownloadState.complete,
        2 => DownloadState.canceled,
        _ => DownloadState.inProgress,
      },
    ),
  );

  @override
  BrowserView createView({
    required String initialUrl,
    bool incognito = false,
  }) => CefBrowserView(initialUrl, incognito: incognito);

  @override
  Future<void> shutdown() => WebviewManager().quit();

  @override
  ExtensionHost? get extensions =>
      defaultTargetPlatform == TargetPlatform.windows ? _extensions : null;

  static final _extensions = _CefExtensionHost();
}

/// Loads extensions over the plugin's private DevTools pipe (the browser
/// target's Extensions domain).
class _CefExtensionHost implements ExtensionHost {
  @override
  Future<String> load(String path) async {
    final result = await WebviewManager().devTools('Extensions.loadUnpacked', {
      'path': path,
    });
    return result['id'] as String;
  }

  @override
  Future<void> unload(String id) =>
      WebviewManager().devTools('Extensions.uninstall', {'id': id});
}

class CefBrowserView implements BrowserView {
  CefBrowserView(String initialUrl, {this.incognito = false}) {
    _controller = WebviewManager().createWebView(
      loading: const Center(child: CircularProgressIndicator()),
    );
    _controller.setWebviewListener(
      WebviewEventsListener(
        onTitleChanged: (t) => _title.value = t,
        onUrlChanged: (u) => _url.value = u,
        onLoadStart: (_, _) => _isLoading.value = true,
        onLoadEnd: (_, _) => _isLoading.value = false,
        onContextMenu: (m) => _contextMenus.add(_toPageMenu(m)),
        onFindResult: (count, active, _) =>
            _findResult.value = FindResult(count: count, active: active),
        // Chromium zoom level: each step is a factor of 1.2.
        onZoomChanged: (level) => _zoom.value = pow(1.2, level).toDouble(),
        onNewWindow: (url, disposition) => _newTabs.add(
          NewTabRequest(url, background: disposition == cefNewBackgroundTab),
        ),
        onUnhandledKey: (code, flags) => _keys.add(
          PageKey(
            code,
            control: flags & eventFlagControlDown != 0,
            shift: flags & eventFlagShiftDown != 0,
            alt: flags & eventFlagAltDown != 0,
            meta: flags & eventFlagCommandDown != 0,
          ),
        ),
      ),
    );
    // The plugin's V8 extension defines external.JavaScriptChannel in every
    // frame; registering the name routes those messages here.
    _controller.javascriptChannels[_channel] = JavascriptChannel(
      name: _channel,
      onMessageReceived: (m) => _scriptMessages.add(m.message),
    );
    _url.value = initialUrl;
    _controller.initialize(initialUrl, incognito: incognito);
    _controller.addListener(() => _isReady.value = _controller.value);
  }

  static const _channel = 'sixbrowserPage';

  @override
  final bool incognito;

  late final WebViewController _controller;
  final _scriptMessages = StreamController<String>.broadcast();
  final _url = ValueNotifier<String>('');
  final _title = ValueNotifier<String>('');
  final _isLoading = ValueNotifier<bool>(false);
  final _isReady = ValueNotifier<bool>(false);
  final _contextMenus = StreamController<PageContextMenu>.broadcast();
  final _newTabs = StreamController<NewTabRequest>.broadcast();
  final _keys = StreamController<PageKey>.broadcast();
  final _zoom = ValueNotifier<double>(1);
  final _findResult = ValueNotifier<FindResult>(FindResult.none);

  @override
  ValueListenable<String> get url => _url;
  @override
  ValueListenable<String> get title => _title;
  @override
  ValueListenable<bool> get isLoading => _isLoading;
  @override
  ValueListenable<bool> get isReady => _isReady;

  @override
  Widget get widget => _controller.webviewWidget;

  @override
  Future<void> load(String url) => _controller.loadUrl(url);
  @override
  void focus() => _controller.requestFocus();
  @override
  void setVisible(bool visible) => _controller.setVisible(visible);
  @override
  Future<void> goBack() => _controller.goBack();
  @override
  Future<void> goForward() => _controller.goForward();
  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<void> reloadIgnoringCache() => _controller.reloadIgnoreCache();

  @override
  bool get supportsStop => true;
  @override
  Future<void> stop() => _controller.stopLoad();

  @override
  Future<void> openDevTools() => _controller.openDevTools();

  @override
  bool get supportsPageTools => true;
  @override
  ValueListenable<double> get zoom => _zoom;
  @override
  Future<void> zoomStep(int direction) => _controller.zoom(direction.sign);
  @override
  Future<void> find(String text, {bool forward = true, bool findNext = false}) {
    if (text.isEmpty) return stopFinding();
    return _controller.find(text, forward: forward, findNext: findNext);
  }

  @override
  Future<void> stopFinding() {
    _findResult.value = FindResult.none;
    return _controller.stopFinding();
  }

  @override
  ValueListenable<FindResult> get findResult => _findResult;
  @override
  Future<void> printPage() => _controller.printPage();

  @override
  Stream<PageContextMenu> get contextMenus => _contextMenus.stream;
  @override
  Stream<NewTabRequest> get newTabRequests => _newTabs.stream;
  @override
  Stream<PageKey> get unhandledKeys => _keys.stream;
  @override
  Future<void> editCommand(EditCommand command) =>
      _controller.editCommand(command.name);
  @override
  Future<void> download(String url) => _controller.startDownload(url);
  @override
  Future<void> inspectAt(Offset pagePosition) =>
      _controller.inspectElementAt(pagePosition);

  @override
  Future<void> runScript(String script) async {
    // The browser may not have been created yet.
    if (_controller.value) await _controller.executeJavaScript(script);
  }

  @override
  String get scriptPostFunction =>
      "function (m) { external.JavaScriptChannel('$_channel', m); }";

  @override
  Stream<String> get scriptMessages => _scriptMessages.stream;

  @override
  Future<void> dispose() {
    _contextMenus.close();
    _newTabs.close();
    _keys.close();
    _scriptMessages.close();
    return _controller.dispose();
  }
}

// CEF flag values (include/internal/cef_types.h).
const _typeEditable = 1 << 5; // CM_TYPEFLAG_EDITABLE
const _mediaImage = 1; // CM_MEDIATYPE_IMAGE
const _editUndo = 1 << 0, _editRedo = 1 << 1, _editCut = 1 << 2;
const _editCopy = 1 << 3, _editPaste = 1 << 4, _editSelectAll = 1 << 6;

PageContextMenu _toPageMenu(WebviewContextMenu m) {
  bool edit(int flag) => m.editFlags & flag != 0;
  return PageContextMenu(
    position: m.position,
    pagePosition: m.pagePosition,
    pageUrl: m.pageUrl,
    linkUrl: m.linkUrl,
    imageUrl: m.mediaType == _mediaImage ? m.srcUrl : '',
    selectionText: m.selectionText,
    isEditable: m.typeFlags & _typeEditable != 0,
    canUndo: edit(_editUndo),
    canRedo: edit(_editRedo),
    canCut: edit(_editCut),
    canCopy: edit(_editCopy),
    canPaste: edit(_editPaste),
    canSelectAll: edit(_editSelectAll),
    canGoBack: m.canGoBack,
    canGoForward: m.canGoForward,
  );
}
