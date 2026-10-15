import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_cef/webview_cef.dart';

import 'browser_engine.dart';

/// [BrowserEngine] backed by CEF through the `webview_cef` plugin
/// (Alloy runtime, off-screen rendering). Chrome extensions are NOT supported
/// by this backend; see docs/ENGINE.md.
class CefEngine implements BrowserEngine {
  @override
  Future<void> initialize() => WebviewManager().initialize();

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
      ),
    );
    _url.value = initialUrl;
    _controller.initialize(initialUrl, incognito: incognito);
    _controller.addListener(() => _isReady.value = _controller.value);
  }

  @override
  final bool incognito;

  late final WebViewController _controller;
  final _url = ValueNotifier<String>('');
  final _title = ValueNotifier<String>('');
  final _isLoading = ValueNotifier<bool>(false);
  final _isReady = ValueNotifier<bool>(false);

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
  Future<void> goBack() => _controller.goBack();
  @override
  Future<void> goForward() => _controller.goForward();
  @override
  Future<void> reload() => _controller.reload();

  // webview_cef 0.6.2 exposes no stop-loading call.
  @override
  bool get supportsStop => false;
  @override
  Future<void> stop() async {}

  @override
  Future<void> openDevTools() => _controller.openDevTools();

  @override
  Future<void> dispose() => _controller.dispose();
}
