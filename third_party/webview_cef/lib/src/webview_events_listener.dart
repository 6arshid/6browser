import 'dart:ui' show Offset;

import 'package:webview_cef/src/webview.dart';

typedef TitleChangeCb = void Function(String title);
typedef UrlChangeCb = void Function(String url);
/* Log severity levels. from CEF include/internal/cef_types.h
  0:default logging (currently info logging)
  1:verbose logging or debug logging
  2:info logging
  3:warning logging
  4:error logging
  5:fatal logging
  99:disable logging to file for all messages, and to stderr for messages with severity less than fatal
 */
typedef LoadStartCb = void Function(WebViewController controller, String url);
typedef LoadStopCb = void Function(WebViewController controller, String url);

typedef OnConsoleMessage = void Function(
    int level, String message, String source, int line);

/// 6browser patch: a page asked for a context menu (right click, menu key).
/// The native menu is suppressed; the host is expected to show its own.
class WebviewContextMenu {
  WebviewContextMenu({
    required this.position,
    required this.pagePosition,
    required this.typeFlags,
    required this.mediaType,
    required this.editFlags,
    required this.linkUrl,
    required this.srcUrl,
    required this.pageUrl,
    required this.selectionText,
    required this.canGoBack,
    required this.canGoForward,
  });

  /// Where to show the menu, in global (screen) logical pixels.
  final Offset position;

  /// The same point in page coordinates, for "Inspect".
  final Offset pagePosition;

  /// cef_context_menu_type_flags_t, cef_context_menu_media_type_t and
  /// cef_context_menu_edit_state_flags_t.
  final int typeFlags;
  final int mediaType;
  final int editFlags;
  final String linkUrl;
  final String srcUrl;
  final String pageUrl;
  final String selectionText;
  final bool canGoBack;
  final bool canGoForward;
}

typedef ContextMenuCb = void Function(WebviewContextMenu menu);

/// 6browser patch: find-in-page progress. [activeMatch] is 1-based.
typedef FindResultCb = void Function(int count, int activeMatch, bool finalUpdate);

/// 6browser patch: Chromium zoom level (0 is 100%, each step a factor 1.2).
typedef ZoomChangedCb = void Function(double level);

class WebviewEventsListener {
  TitleChangeCb? onTitleChanged;
  UrlChangeCb? onUrlChanged;
  OnConsoleMessage? onConsoleMessage;
  LoadStartCb? onLoadStart;
  LoadStopCb? onLoadEnd;
  ContextMenuCb? onContextMenu;
  FindResultCb? onFindResult;
  ZoomChangedCb? onZoomChanged;

  WebviewEventsListener({
    this.onTitleChanged,
    this.onUrlChanged,
    this.onConsoleMessage,
    this.onLoadStart,
    this.onLoadEnd,
    this.onContextMenu,
    this.onFindResult,
    this.onZoomChanged,
  });
}
