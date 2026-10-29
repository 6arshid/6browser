import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_cef/src/webview_inject_user_script.dart';

import 'webview.dart';

class WebviewManager extends ValueNotifier<bool> {
  static final WebviewManager _instance = WebviewManager._internal();

  factory WebviewManager() => _instance;

  late Completer<void> _creatingCompleter;

  final MethodChannel pluginChannel = const MethodChannel("webview_cef");

  final _webViews = <int, WebViewController>{};
  final _injectUserScripts = <int, InjectUserScripts?>{};

  final _tempWebViews = <int, WebViewController>{};
  final _tempInjectUserScripts = <int, InjectUserScripts?>{};

  int nextIndex = 1;

  bool? _hasNativeKeySupport;

  get ready => _creatingCompleter.future;

  /// Returns true if the platform has native key event handling (e.g., GTK on desktop Linux).
  /// When false, Dart-side key handling should be used (e.g., eLinux).
  Future<bool> get hasNativeKeySupport async {
    _hasNativeKeySupport ??=
        await pluginChannel.invokeMethod<bool>('hasNativeKeySupport') ?? false;
    return _hasNativeKeySupport!;
  }

  WebViewController createWebView({
    Widget? loading,
    InjectUserScripts? injectUserScripts,
  }) {
    int browserIndex = nextIndex++;
    final controller =
        WebViewController(pluginChannel, browserIndex, loading: loading);
    _tempWebViews[browserIndex] = controller;
    _tempInjectUserScripts[browserIndex] = injectUserScripts;

    return controller;
  }

  void removeWebView(int browserId) {
    if (browserId > 0) {
      _webViews.remove(browserId);
    }
  }

  WebviewManager._internal() : super(false);

  final _downloadEvents = StreamController<Map<String, dynamic>>.broadcast();

  /// 6browser patch: download progress events (id, url, path, received,
  /// total, state: 0 in progress / 1 complete / 2 canceled).
  Stream<Map<String, dynamic>> get downloadEvents => _downloadEvents.stream;

  /// [cachePath] (6browser patch) is the folder for cookies, site data and
  /// cache. Only one process may use a folder at a time.
  Future<void> initialize({String? userAgent, String? cachePath}) async {
    _creatingCompleter = Completer<void>();
    try {
      if (cachePath != null && cachePath.isNotEmpty) {
        await pluginChannel.invokeMethod('setCachePath', cachePath);
      }
      if (userAgent != null && userAgent.isNotEmpty) {
        await pluginChannel.invokeMethod('init', userAgent);
      } else {
        await pluginChannel.invokeMethod('init');
      }
      pluginChannel.setMethodCallHandler(methodCallhandler);
      // Wait for the platform to complete initialization.
      await Future.delayed(const Duration(milliseconds: 300));
      _creatingCompleter.complete();
      value = true;
    } on PlatformException catch (e) {
      _creatingCompleter.completeError(e);
    }
    return _creatingCompleter.future;
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    pluginChannel.setMethodCallHandler(null);
    _webViews.clear();
  }

  void onBrowserCreated(int browserIndex, int browserId) {
    _webViews[browserId] = _tempWebViews[browserIndex]!;
    _injectUserScripts[browserId] = _tempInjectUserScripts[browserIndex];

    _tempWebViews.remove(browserIndex);
    _tempInjectUserScripts.remove(browserIndex);
  }

  Future<void> methodCallhandler(MethodCall call) async {
    switch (call.method) {
      case "urlChanged":
        int browserId = call.arguments["browserId"] as int;
        _webViews[browserId]
            ?.listener
            ?.onUrlChanged
            ?.call(call.arguments["url"] as String);
        return;
      case "downloadUpdated":
        // 6browser patch: forwarded download progress from the native handler.
        _downloadEvents.add(Map<String, dynamic>.from(call.arguments as Map));
        return;
      case "titleChanged":
        int browserId = call.arguments["browserId"] as int;
        _webViews[browserId]
            ?.listener
            ?.onTitleChanged
            ?.call(call.arguments["title"] as String);
        return;
      case "onConsoleMessage":
        int browserId = call.arguments["browserId"] as int;
        _webViews[browserId]?.listener?.onConsoleMessage?.call(
            call.arguments["level"] as int,
            call.arguments["message"] as String,
            call.arguments["source"] as String,
            call.arguments["line"] as int);
        return;
      case 'javascriptChannelMessage':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.onJavascriptChannelMessage?.call(
            call.arguments['channel'] as String,
            call.arguments['message'] as String,
            call.arguments['callbackId'] as String,
            call.arguments['frameId'] as String);
        return;
      case 'onTooltip':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.onToolTip?.call(call.arguments['text'] as String);
        return;
      case 'onCursorChanged':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]
            ?.onCursorChanged
            ?.call(call.arguments['type'] as int);
        return;
      case 'onFocusedNodeChangeMessage':
        int browserId = call.arguments['browserId'] as int;
        bool editable = call.arguments['editable'] as bool;
        _webViews[browserId]?.onFocusedNodeChangeMessage(editable);
        return;
      case 'onImeCompositionRangeChangedMessage':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.onImeCompositionRangeChangedMessage?.call(
            call.arguments['x'] as int,
            call.arguments['y'] as int,
            call.arguments['height'] as int);
        return;
      case 'onContextMenu':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.handleContextMenu(
            Map<String, dynamic>.from(call.arguments as Map));
        return;
      case 'onFindResult':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.listener?.onFindResult?.call(
            call.arguments['count'] as int,
            call.arguments['activeMatch'] as int,
            call.arguments['finalUpdate'] as bool);
        return;
      case 'onUnhandledKey':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.listener?.onUnhandledKey?.call(
            call.arguments['keyCode'] as int,
            call.arguments['modifiers'] as int);
        return;
      case 'onNewWindow':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.listener?.onNewWindow?.call(
            call.arguments['url'] as String,
            call.arguments['disposition'] as int);
        return;
      case 'onExternalLink':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.listener?.onExternalLink?.call(
            call.arguments['url'] as String,
            call.arguments['source'] as String);
        return;
      case 'onZoomChanged':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]
            ?.listener
            ?.onZoomChanged
            ?.call((call.arguments['level'] as num).toDouble());
        return;
      case 'devToolsMessage':
        _onDevToolsMessage(call.arguments as String);
        return;
      case 'onLoadStart':
        int browserId = call.arguments["browserId"] as int;
        String urlId = call.arguments["urlId"] as String;

        await _injectUserScriptIfNeeds(
            browserId,
            _injectUserScripts[browserId]?.retrieveLoadStartInjectScripts() ??
                []);

        // 6browser patch: events can arrive after the tab was closed.
        final controller = _webViews[browserId];
        if (controller == null) return;
        controller.listener?.onLoadStart?.call(controller, urlId);
        return;
      case 'onLoadEnd':
        int browserId = call.arguments["browserId"] as int;
        String urlId = call.arguments["urlId"] as String;

        await _injectUserScriptIfNeeds(
            browserId,
            _injectUserScripts[browserId]?.retrieveLoadEndInjectScripts() ??
                []);

        // 6browser patch: events can arrive after the tab was closed.
        final controller = _webViews[browserId];
        if (controller == null) return;
        controller.listener?.onLoadEnd?.call(controller, urlId);
        return;
      default:
    }
  }

  Future<void> _injectUserScriptIfNeeds(
      int browserId, List<UserScript> scripts) async {
    if (scripts.isEmpty) return;

    await _webViews[browserId]?.ready;

    for (final script in scripts) {
      await _webViews[browserId]?.executeJavaScript(script.script);
    }
  }

  Future<void> setCookie(String domain, String key, String val) async {
    assert(value);
    return pluginChannel.invokeMethod('setCookie', [domain, key, val]);
  }

  Future<void> deleteCookie(String domain, String key) async {
    assert(value);
    return pluginChannel.invokeMethod('deleteCookie', [domain, key]);
  }

  Future<dynamic> visitAllCookies() async {
    assert(value);
    return pluginChannel.invokeMethod('visitAllCookies');
  }

  Future<dynamic> visitUrlCookies(String domain, bool isHttpOnly) async {
    assert(value);
    return pluginChannel.invokeMethod('visitUrlCookies', [domain, isHttpOnly]);
  }

  int _devToolsId = 0;
  final _devToolsCalls = <int, Completer<Map<String, dynamic>>>{};

  /// 6browser patch: sends a DevTools protocol command to the browser target
  /// over the app's private pipe (Windows only) and returns its result.
  /// Throws [DevToolsException] when the command fails, and
  /// [MissingPluginException] where the pipe is not available.
  Future<Map<String, dynamic>> devTools(String method,
      [Map<String, dynamic> params = const {}]) async {
    await ready;
    final id = ++_devToolsId;
    final call = Completer<Map<String, dynamic>>();
    _devToolsCalls[id] = call;
    try {
      await pluginChannel.invokeMethod('devToolsSend',
          jsonEncode({'id': id, 'method': method, 'params': params}));
    } on PlatformException {
      _devToolsCalls.remove(id);
      throw DevToolsException('$method could not be sent');
    } catch (_) {
      _devToolsCalls.remove(id);
      rethrow;
    }
    return call.future.timeout(const Duration(seconds: 30), onTimeout: () {
      _devToolsCalls.remove(id);
      throw DevToolsException('$method timed out');
    });
  }

  void _onDevToolsMessage(String text) {
    final message = jsonDecode(text);
    if (message is! Map<String, dynamic>) return;
    final call = _devToolsCalls.remove(message['id']);
    if (call == null) return; // an event; none are subscribed to
    final error = message['error'];
    if (error is Map) {
      call.completeError(DevToolsException('${error['message']}'));
    } else {
      call.complete(
          Map<String, dynamic>.from(message['result'] as Map? ?? const {}));
    }
  }

  Future<void> quit() async {
    //only call this method when you want to quit the app
    assert(value);
    return pluginChannel.invokeMethod('quit');
  }
}

/// 6browser patch: a DevTools protocol command failed.
class DevToolsException implements Exception {
  DevToolsException(this.message);

  final String message;

  @override
  String toString() => message;
}
