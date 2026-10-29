import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../features/tabs/url_input.dart';
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

  @override
  ExtensionHost? get extensions => null;
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
            _clearHttpFallback();
            _url.value = u;
            _isLoading.value = false;
            final t = await _controller.getTitle();
            if (t != null && t.isNotEmpty) _title.value = t;
          },
          onProgress: (_) {},
          onWebResourceError: (error) {
            if (error.isForMainFrame != false && _isHttpsAttempt(error.url)) {
              _fallBackToHttp();
            }
          },
          onSslAuthError: (error) {
            // Never proceed past a bad certificate; for an upgraded load the
            // site simply has no working HTTPS, so use the address as typed.
            error.cancel();
            final platform = error.platform;
            if (platform is AndroidSslAuthError &&
                _isHttpsAttempt(platform.url)) {
              _fallBackToHttp();
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        _channel,
        onMessageReceived: (m) => _scriptMessages.add(m.message),
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
  static const _channel = 'sixbrowserPage';
  final _scriptMessages = StreamController<String>.broadcast();

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
    await load(initialUrl);
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

  // The WebView has no HTTPS Upgrades, so http:// addresses are tried over
  // HTTPS first and loaded as typed only if that fails (like Chrome).
  String? _httpsAttempt;
  String? _httpFallback;

  void _clearHttpFallback() => _httpsAttempt = _httpFallback = null;

  bool _isHttpsAttempt(String? url) {
    final attempt = _httpsAttempt;
    if (attempt == null || url == null) return false;
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == Uri.parse(attempt).host;
  }

  void _fallBackToHttp() {
    final url = _httpFallback;
    _clearHttpFallback();
    if (url != null && !_disposed) _controller.loadRequest(Uri.parse(url));
  }

  @override
  Future<void> load(String url) {
    final upgraded = httpsUpgradeOf(url);
    _httpsAttempt = upgraded;
    _httpFallback = upgraded == null ? null : url;
    return _controller.loadRequest(Uri.parse(upgraded ?? url));
  }

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

  @override
  Future<void> reloadIgnoringCache() => _controller.reload();

  // No DevTools on the Android WebView backend.
  @override
  Future<void> openDevTools() async {}

  // webview_flutter has no zoom, find or print API; pinch-zoom still works.
  @override
  bool get supportsPageTools => false;
  @override
  ValueListenable<double> get zoom => const _Fixed(1.0);
  @override
  Future<void> zoomStep(int direction) async {}
  @override
  Future<void> find(
    String text, {
    bool forward = true,
    bool findNext = false,
  }) async {}
  @override
  Future<void> stopFinding() async {}
  @override
  ValueListenable<FindResult> get findResult => const _Fixed(FindResult.none);
  @override
  Future<void> printPage() async {}

  // The Android WebView shows its own long-press text selection menu.
  @override
  Stream<PageContextMenu> get contextMenus => const Stream.empty();
  @override
  Stream<NewTabRequest> get newTabRequests => const Stream.empty();
  @override
  Stream<PageKey> get unhandledKeys => const Stream.empty();
  @override
  void focus() {}
  @override
  void setVisible(bool visible) {}
  @override
  Future<void> editCommand(EditCommand command) async {}
  @override
  Future<void> download(String url) async {}
  @override
  Future<void> inspectAt(Offset pagePosition) async {}

  @override
  Future<void> runScript(String script) async {
    try {
      await _controller.runJavaScript(script);
    } on PlatformException {
      // No page loaded yet.
    }
  }

  @override
  String get scriptPostFunction =>
      'function (m) { $_channel.postMessage(JSON.stringify(m)); }';

  @override
  Stream<String> get scriptMessages => _scriptMessages.stream;

  @override
  Future<void> dispose() async {
    _disposed = true;
    _scriptMessages.close();
    await _stopScreenShare();
    if (incognito) {
      await _controller.clearCache();
      await _controller.clearLocalStorage();
    }
  }
}

/// A listenable that never changes.
class _Fixed<T> implements ValueListenable<T> {
  const _Fixed(this.value);

  @override
  final T value;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
