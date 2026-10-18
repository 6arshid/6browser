import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'browser_engine.dart';

/// [BrowserEngine] backed by the platform WebView (Android System WebView /
/// Chromium) through the `webview_flutter` plugin. Used on Android, where CEF
/// is unavailable.
///
/// Downloads and DevTools are not surfaced by this backend, and "incognito" is
/// best-effort (storage is cleared, but tabs are not fully isolated) — see the
/// notes on [AndroidBrowserView].
class AndroidEngine implements BrowserEngine {
  @override
  Future<void> initialize() async {}

  // The platform WebView does not expose per-tab download events through
  // webview_flutter's high-level API yet.
  @override
  Stream<DownloadEvent> get downloads => const Stream.empty();

  @override
  BrowserView createView({
    required String initialUrl,
    bool incognito = false,
  }) => AndroidBrowserView(initialUrl, incognito: incognito);

  @override
  Future<void> shutdown() async {}
}

class AndroidBrowserView implements BrowserView {
  AndroidBrowserView(String initialUrl, {this.incognito = false}) {
    _url.value = initialUrl;
    _controller = WebViewController(onPermissionRequest: _onPermissionRequest)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (c) {
            if (c.url != null) _url.value = c.url!;
          },
          onPageStarted: (u) {
            _stopScreenShare();
            _url.value = u;
            _isLoading.value = true;
          },
          onPageFinished: (u) async {
            _url.value = u;
            _isLoading.value = false;
            final t = await _controller.getTitle();
            if (t != null && t.isNotEmpty) _title.value = t;
          },
          onProgress: (_) {},
        ),
      );
    // Best-effort private browsing: start from a clean slate.
    if (incognito) {
      _controller.clearCache();
      _controller.clearLocalStorage();
    }
    _initialize(initialUrl);
  }

  @override
  final bool incognito;

  static const _app = MethodChannel('6browser/app');

  int get _webViewId =>
      (_controller.platform as AndroidWebViewController).webViewIdentifier;

  Future<void> _initialize(String initialUrl) async {
    // Wait for native WebView creation before resolving it through the external
    // Android API on our app channel.
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    if (_disposed) return;
    try {
      // Install before navigation so sites see getDisplayMedia during startup.
      await _app.invokeMethod<void>('installScreenShare', {
        'webViewId': _webViewId,
      });
    } on PlatformException catch (error) {
      debugPrint('Screen sharing setup failed: ${error.message}');
    }
    if (_disposed) return;
    await _controller.loadRequest(Uri.parse(initialUrl));
    if (!_disposed) _isReady.value = true;
  }

  Future<void> _stopScreenShare() async {
    await _app.invokeMethod<void>('stopScreenShare', {'webViewId': _webViewId});
  }

  bool _disposed = false;

  // Android WebView denies getUserMedia unless the app grants the request.
  // The prompt and the runtime permissions live in MainActivity. The request
  // does not carry its origin, so the current page's origin is shown.
  Future<void> _onPermissionRequest(WebViewPermissionRequest request) async {
    final camera = request.types.contains(WebViewPermissionResourceType.camera);
    final microphone = request.types.contains(
      WebViewPermissionResourceType.microphone,
    );
    final onlyMedia = request.types.every(
      (t) =>
          t == WebViewPermissionResourceType.camera ||
          t == WebViewPermissionResourceType.microphone,
    );
    if (!onlyMedia || !(camera || microphone)) return request.deny();
    final uri = Uri.tryParse(_url.value);
    final origin = uri != null && uri.hasAuthority ? uri.origin : _url.value;
    bool allowed = false;
    try {
      allowed =
          await _app.invokeMethod<bool>('requestMediaAccess', {
            'origin': origin,
            'camera': camera,
            'microphone': microphone,
          }) ??
          false;
    } on PlatformException {
      allowed = false;
    }
    return allowed ? request.grant() : request.deny();
  }

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
  Widget get widget => WebViewWidget(controller: _controller);

  @override
  Future<void> load(String url) => _controller.loadRequest(Uri.parse(url));

  @override
  Future<void> goBack() async {
    if (await _controller.canGoBack()) await _controller.goBack();
  }

  @override
  Future<void> goForward() async {
    if (await _controller.canGoForward()) await _controller.goForward();
  }

  @override
  Future<void> reload() => _controller.reload();

  // webview_flutter's cross-platform API has no stop-loading call.
  @override
  bool get supportsStop => false;
  @override
  Future<void> stop() async {}

  // No DevTools on the Android WebView backend.
  @override
  Future<void> openDevTools() async {}

  // The Android WebView shows its own long-press text selection menu.
  @override
  Stream<PageContextMenu> get contextMenus => const Stream.empty();
  @override
  Future<void> editCommand(EditCommand command) async {}
  @override
  Future<void> download(String url) async {}
  @override
  Future<void> inspectAt(Offset pagePosition) async {}

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _stopScreenShare();
    if (incognito) {
      await _controller.clearCache();
      await _controller.clearLocalStorage();
    }
  }
}
