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

  Future<void> load(String url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();

  /// Stops loading. Not supported by every backend; see [supportsStop].
  Future<void> stop();
  bool get supportsStop;

  Future<void> openDevTools();
  Future<void> dispose();
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
  });

  final int id;
  final String url;
  final String path;
  final int receivedBytes;

  /// -1 or 0 when the size is unknown.
  final int totalBytes;
  final DownloadState state;
}

enum DownloadState { inProgress, complete, canceled }

/// Process-wide engine lifecycle and factory for [BrowserView]s.
abstract class BrowserEngine {
  /// Download progress from any tab. Backends without download support
  /// return an empty stream.
  Stream<DownloadEvent> get downloads;

  Future<void> initialize();
  BrowserView createView({required String initialUrl});
  Future<void> shutdown();
}
