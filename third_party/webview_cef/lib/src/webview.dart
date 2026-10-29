import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'webview_manager.dart';
import 'webview_events_listener.dart';
import 'webview_javascript.dart';
import 'webview_textinput.dart';
import 'webview_tooltip.dart';

// CEF key event types
const int keyEventRawKeyDown = 0;
const int keyEventKeyDown = 1;
const int keyEventKeyUp = 2;
const int keyEventChar = 3;

// CEF event flags
const int eventFlagNone = 0;
const int eventFlagCapsLockOn = 1 << 0;
const int eventFlagShiftDown = 1 << 1;
const int eventFlagControlDown = 1 << 2;
const int eventFlagAltDown = 1 << 3;
const int eventFlagLeftMouseButton = 1 << 4;
const int eventFlagMiddleMouseButton = 1 << 5;
const int eventFlagRightMouseButton = 1 << 6;
const int eventFlagCommandDown = 1 << 7;
const int eventFlagNumLockOn = 1 << 8;
const int eventFlagIsKeyPad = 1 << 9;
const int eventFlagIsLeft = 1 << 10;
const int eventFlagIsRight = 1 << 11;

class WebViewController extends ValueNotifier<bool> {
  WebViewController(this._pluginChannel, this._index, {Widget? loading})
      : super(false) {
    _loadingWidget = loading;
  }
  final MethodChannel _pluginChannel;
  Widget? _loadingWidget;

  late WebView _webviewWidget;
  Widget get webviewWidget => _webviewWidget;
  Widget get loadingWidget => _loadingWidget ?? const Text("loading...");

  late Completer<void> _creatingCompleter;
  Future<void> get ready => _creatingCompleter.future;
  bool _isDisposed = false;
  bool _focusEditable = false;

  final int _index;
  late int _browserId;
  late int _textureId;
  final Map<String, JavascriptChannel> _javascriptChannels =
      <String, JavascriptChannel>{};
  Map<String, JavascriptChannel> get javascriptChannels => _javascriptChannels;
  WebviewEventsListener? _listener;
  WebviewEventsListener? get listener => _listener;

  get onJavascriptChannelMessage => (final String channelName,
          final String message, final String callbackId, final String frameId) {
        if (_javascriptChannels.containsKey(channelName)) {
          _javascriptChannels[channelName]!.onMessageReceived(
              JavascriptMessage(message, callbackId, frameId));
        } else {
          debugPrint('Channel "$channelName" is not exists');
        }
      };

  get onToolTip => _onToolTip;
  get onCursorChanged => _onCursorChanged;
  get onFocusedNodeChangeMessage => _onFocusedNodeChangeMessage;
  get onImeCompositionRangeChangedMessage =>
      _onImeCompositionRangeChangedMessage;

  /// Initializes the underlying platform view.
  Future<void> initialize(String url, {bool incognito = false}) async {
    if (_isDisposed) {
      return Future<void>.value();
    }
    _creatingCompleter = Completer<void>();
    try {
      await WebviewManager().ready;
      // 6browser patch: incognito browsers use an in-memory profile.
      List args = await _pluginChannel.invokeMethod(
          incognito ? 'createIncognito' : 'create', url);
      _browserId = args[0] as int;
      _textureId = args[1] as int;
      WebviewManager().onBrowserCreated(_index, _browserId);
      await Future.delayed(const Duration(milliseconds: 50));
      _webviewWidget = WebView(this);
      value = true;
      _creatingCompleter.complete();
    } on PlatformException catch (e) {
      _creatingCompleter.completeError(e);
    }
    return _creatingCompleter.future;
  }

  /// 6browser patch: calls made while the browser is still being created
  /// (a click on the New Tab page at startup) wait for it instead of failing.
  Future<bool> _whenReady() async {
    if (!value) {
      try {
        await ready;
      } catch (_) {
        return false;
      }
    }
    return !_isDisposed;
  }

  setWebviewListener(WebviewEventsListener listener) {
    _listener = listener;
  }

  @override
  Future<void> dispose() async {
    await _creatingCompleter.future;
    if (!_isDisposed) {
      _isDisposed = true;
      WebviewManager().removeWebView(_browserId);
      await _pluginChannel.invokeMethod('close', _browserId);
    }
    super.dispose();
  }

  /// Loads the given [url].
  Future<void> loadUrl(String url) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('loadUrl', [_browserId, url]);
  }

  /// 6browser patch: runs an editing command on the focused frame:
  /// undo, redo, cut, copy, paste, delete or selectAll.
  Future<void> editCommand(String command) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('editCommand', [_browserId, command]);
  }

  /// 6browser patch: downloads [url] as if the user had clicked a download.
  Future<void> startDownload(String url) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('startDownload', [_browserId, url]);
  }

  /// 6browser patch: opens DevTools with the element at [pagePosition]
  /// selected.
  Future<void> inspectElementAt(Offset pagePosition) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('inspectElementAt',
        [_browserId, pagePosition.dx.round(), pagePosition.dy.round()]);
  }

  /// 6browser patch: browser shortcuts. These are no-ops until the browser
  /// exists, so a shortcut pressed while a tab is still starting is ignored.
  Future<void> _call(String method, Object arguments) async {
    if (_isDisposed || !value) return;
    return _pluginChannel.invokeMethod(method, arguments);
  }

  Future<void> stopLoad() => _call('stopLoad', _browserId);

  /// 6browser patch: a hidden (background) tab stops rendering and its
  /// timers slow down, as in Chrome. Applied once the browser exists.
  Future<void> setVisible(bool visible) async {
    if (_visible == visible) return;
    _visible = visible;
    if (!await _whenReady()) return;
    if (_visible != visible) return; // changed again meanwhile
    return _pluginChannel.invokeMethod('setVisible', [_browserId, visible]);
  }

  bool _visible = true;
  Future<void> reloadIgnoreCache() => _call('reloadIgnoreCache', _browserId);
  Future<void> printPage() => _call('print', _browserId);

  /// Zooms out (-1), resets (0) or zooms in (1) using Chrome's zoom steps.
  /// The new level arrives through [WebviewEventsListener.onZoomChanged].
  Future<void> zoom(int command) => _call('zoom', [_browserId, command]);

  /// Searches the page; results arrive through
  /// [WebviewEventsListener.onFindResult].
  Future<void> find(String text,
          {bool forward = true,
          bool matchCase = false,
          bool findNext = false}) =>
      _call('find', [_browserId, text, forward, matchCase, findNext]);
  Future<void> stopFinding({bool clearSelection = true}) =>
      _call('stopFinding', [_browserId, clearSelection]);

  /// Called by [WebviewManager] when the page asks for a context menu.
  void handleContextMenu(Map<String, dynamic> args) {
    final page =
        Offset((args['x'] as int).toDouble(), (args['y'] as int).toDouble());
    _listener?.onContextMenu?.call(WebviewContextMenu(
      position: _localToGlobal?.call(page) ?? page,
      pagePosition: page,
      typeFlags: args['typeFlags'] as int,
      mediaType: args['mediaType'] as int,
      editFlags: args['editFlags'] as int,
      linkUrl: args['linkUrl'] as String,
      srcUrl: args['srcUrl'] as String,
      pageUrl: args['pageUrl'] as String,
      selectionText: args['selectionText'] as String,
      canGoBack: args['canGoBack'] as bool,
      canGoForward: args['canGoForward'] as bool,
    ));
  }

  /// Set by [WebViewState]: maps page coordinates to global ones.
  Offset Function(Offset local)? _localToGlobal;

  /// 6browser patch: gives the page the keyboard focus (after a tab switch
  /// or navigating from the address bar).
  void requestFocus() => _requestFocus?.call();
  VoidCallback? _requestFocus;

  /// Reloads the current document.
  Future<void> reload() async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('reload', _browserId);
  }

  Future<void> goForward() async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('goForward', _browserId);
  }

  Future<void> goBack() async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('goBack', _browserId);
  }

  Future<void> openDevTools() async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('openDevTools', _browserId);
  }

  Future<void> imeSetComposition(String composingText) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel
        .invokeMethod('imeSetComposition', [_browserId, composingText]);
  }

  Future<void> imeCommitText(String composingText) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel
        .invokeMethod('imeCommitText', [_browserId, composingText]);
  }

  Future<void> setClientFocus(bool focus) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('setClientFocus', [_browserId, focus]);
  }

  /// Sends a key event to CEF. Used on platforms without native key support (eLinux).
  Future<void> sendKeyEvent(int type, int keyCode, int modifiers, int character,
      int unmodifiedCharacter) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('sendKeyEvent',
        [_browserId, type, keyCode, modifiers, character, unmodifiedCharacter]);
  }

  Future<void> setJavaScriptChannels(Set<JavascriptChannel> channels) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    _assertJavascriptChannelNamesAreUnique(channels);

    for (var channel in channels) {
      _javascriptChannels[channel.name] = channel;
    }

    return _pluginChannel.invokeMethod('setJavaScriptChannels',
        [_browserId, _extractJavascriptChannelNames(channels).toList()]);
  }

  Future<void> sendJavaScriptChannelCallBack(
      bool error, String result, String callbackId, String frameId) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('sendJavaScriptChannelCallBack',
        [error, result, callbackId, _browserId, frameId]);
  }

  Future<void> executeJavaScript(String code) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel.invokeMethod('executeJavaScript', [_browserId, code]);
  }

  Future<dynamic> evaluateJavascript(String code) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel
        .invokeMethod('evaluateJavascript', [_browserId, code]);
  }

  /// Moves the virtual cursor to [position].
  Future<void> _cursorMove(Offset position, [int modifiers = 0]) =>
      _cursor('cursorMove', position, 0, 1, modifiers);

  Future<void> _cursorDragging(Offset position, [int modifiers = 0]) =>
      _cursor('cursorDragging', position, 0, 1, modifiers);

  // 6browser patch: [button] is 0 left, 1 middle, 2 right; [clickCount] is 2
  // for a double-click; [modifiers] are CEF event flags.
  Future<void> _cursorClickDown(Offset position,
          [int button = 0, int clickCount = 1, int modifiers = 0]) =>
      _cursor('cursorClickDown', position, button, clickCount, modifiers);

  Future<void> _cursorClickUp(Offset position,
          [int button = 0, int clickCount = 1, int modifiers = 0]) =>
      _cursor('cursorClickUp', position, button, clickCount, modifiers);

  /// The pointer left the view.
  Future<void> _cursorLeave(Offset position) =>
      _cursor('cursorLeave', position, 0, 1, 0);

  Future<void> _cursor(String method, Offset position, int button,
      int clickCount, int modifiers) async {
    if (_isDisposed || !value) {
      return;
    }
    return _pluginChannel.invokeMethod(method, [
      _browserId,
      position.dx.round(),
      position.dy.round(),
      button,
      clickCount,
      modifiers,
    ]);
  }

  /// 6browser patch: scrolls by [delta] logical pixels (positive scrolls
  /// right/down) at [position]; [modifiers] are CEF event flags.
  Future<void> _scrollBy(Offset position, Offset delta, int modifiers) async {
    if (_isDisposed || !value || delta == Offset.zero) {
      return;
    }
    return _pluginChannel.invokeMethod('setScrollDelta', [
      _browserId,
      position.dx.round(),
      position.dy.round(),
      delta.dx,
      delta.dy,
      modifiers,
    ]);
  }

  /// 6browser patch: releases a press that Flutter cancelled (a route opened
  /// or the window lost the pointer), so the page is not left thinking a
  /// button is still down.
  Future<void> _cursorCancel(Offset position, int button) =>
      _cursor('cursorCancel', position, button, 1, 0);

  /// Sets the surface size to the provided [size].
  Future<void> _setSize(double dpi, Size size) async {
    if (_isDisposed) {
      return;
    }
    if (!await _whenReady()) return;
    return _pluginChannel
        .invokeMethod('setSize', [_browserId, dpi, size.width, size.height]);
  }

  Set<String> _extractJavascriptChannelNames(Set<JavascriptChannel> channels) {
    final Set<String> channelNames =
        channels.map((JavascriptChannel channel) => channel.name).toSet();
    return channelNames;
  }

  void _assertJavascriptChannelNamesAreUnique(
      final Set<JavascriptChannel>? channels) {
    if (channels == null || channels.isEmpty) {
      return;
    }
    assert(_extractJavascriptChannelNames(channels).length == channels.length);
  }

  Function(String)? _onToolTip;
  Function(int)? _onCursorChanged;
  Function(bool editable)? _onFocusedNodeChangeMessage;
  Function(int, int, int)? _onImeCompositionRangeChangedMessage;
}

class WebView extends StatefulWidget {
  final WebViewController controller;

  const WebView(this.controller, {super.key});

  @override
  WebViewState createState() => WebViewState();
}

class WebViewState extends State<WebView> with WebeViewTextInput {
  final GlobalKey _key = GlobalKey();
  String _composingText = '';
  late final _focusNode = FocusNode();
  bool isPrimaryFocus = false;
  WebviewTooltip? _tooltip;
  MouseCursor _mouseType = SystemMouseCursors.basic;
  bool? _hasNativeKeySupport;

  WebViewController get _controller => widget.controller;

  // 6browser patch: the button of the press in progress, so the matching
  // release (whose `buttons` is already 0) goes to the same button.
  int _pressedButton = 0;

  // 6browser patch: double and triple clicks (select a word / a paragraph).
  int _clickCount = 1;
  Duration? _lastDownTime;
  Offset _lastDownPosition = Offset.zero;
  int _lastDownButton = -1;

  int _countClick(PointerDownEvent ev, int button) {
    final last = _lastDownTime;
    final repeat = last != null &&
        button == _lastDownButton &&
        ev.timeStamp - last <= const Duration(milliseconds: 500) &&
        (ev.localPosition - _lastDownPosition).distance <= 4;
    _clickCount = repeat ? _clickCount % 3 + 1 : 1;
    _lastDownTime = ev.timeStamp;
    _lastDownPosition = ev.localPosition;
    _lastDownButton = button;
    return _clickCount;
  }

  static int _cefButton(int buttons) => (buttons & kSecondaryMouseButton) != 0
      ? 2
      : (buttons & kMiddleMouseButton) != 0
          ? 1
          : 0;

  /// CEF flags for the modifier keys held now.
  static int _modifiers() {
    final keys = HardwareKeyboard.instance;
    return (keys.isShiftPressed ? eventFlagShiftDown : 0) |
        (keys.isControlPressed ? eventFlagControlDown : 0) |
        (keys.isAltPressed ? eventFlagAltDown : 0) |
        (keys.isMetaPressed ? eventFlagCommandDown : 0);
  }

  Offset _pageToGlobal(Offset local) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? local : box.localToGlobal(local);
  }

  @override
  updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    /// Handles IME composition only
    for (var d in textEditingDeltas) {
      if (d is TextEditingDeltaInsertion) {
        // composing text
        if (d.composing.isValid) {
          _composingText += d.textInserted;
          _controller.imeSetComposition(_composingText);
        } else {
          // Directly committed text (e.g. English typing, or a commit delivered
          // as a plain insertion). Must run on every platform, including Windows.
          _controller.imeCommitText(d.textInserted);
        }
      } else if (d is TextEditingDeltaDeletion) {
        if (d.composing.isValid) {
          if (_composingText == d.textDeleted) {
            _composingText = "";
          }
          _controller.imeSetComposition(_composingText);
        }
      } else if (d is TextEditingDeltaReplacement) {
        if (d.composing.isValid) {
          // Composition is still ongoing (preedit revised).
          _composingText = d.replacementText;
          _controller.imeSetComposition(_composingText);
        } else {
          // Composition finished (a candidate was selected): commit the final
          // text. Without this the selected text was dropped and never shown.
          _controller.imeCommitText(d.replacementText);
          _composingText = '';
        }
      } else if (d is TextEditingDeltaNonTextUpdate) {
        if (_composingText.isNotEmpty) {
          _controller.imeCommitText(_composingText);
          _composingText = '';
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _controller._requestFocus = _focusPage;
    _controller._onFocusedNodeChangeMessage = (editable) {
      _composingText = '';
      editable ? attachTextInputClient() : detachTextInputClient();
      _controller._focusEditable = editable;
    };

    _controller._onImeCompositionRangeChangedMessage = (x, y, height) {
      final box = _key.currentContext!.findRenderObject() as RenderBox;
      updateIMEComposionPosition(x.toDouble(), y.toDouble(), height.toDouble(),
          box.localToGlobal(Offset.zero));
    };

    _controller._onToolTip = (final String text) {
      _tooltip ??= WebviewTooltip(_key.currentContext!);
      _tooltip?.showToolTip(text);
    };

    _controller._onCursorChanged = (int type) {
      switch (type) {
        case 0:
          _mouseType = SystemMouseCursors.basic;
          break;
        case 1:
          _mouseType = SystemMouseCursors.precise;
          break;
        case 2:
          _mouseType = SystemMouseCursors.click;
          break;
        case 3:
          _mouseType = SystemMouseCursors.text;
          break;
        case 4:
          _mouseType = SystemMouseCursors.wait;
          break;
        default:
          _mouseType = SystemMouseCursors.basic;
          break;
      }
      setState(() {});
    };

    // Check if platform has native key support (e.g., GTK on desktop Linux)
    WebviewManager().hasNativeKeySupport.then((value) {
      _hasNativeKeySupport = value;
    });

    // Report initial surface size
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reportSurfaceSize(context));
  }

  void _focusPage() {
    if (mounted) _focusNode.requestFocus();
  }

  double? _pixelRatio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 6browser patch: moving to a monitor with another scale keeps the
    // logical size, so no size notification comes; the page must still
    // re-render at the new scale.
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (_pixelRatio != null && ratio != _pixelRatio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportSurfaceSize(context);
      });
    }
    _pixelRatio = ratio;
  }

  @override
  void dispose() {
    // 6browser patch: a tooltip shown over a closed tab stayed forever.
    _tooltip?.hide();
    if (_controller._requestFocus == _focusPage) {
      _controller._requestFocus = null;
    }
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // Only handle keys on platforms without native key support (eLinux)
    // Treat null as "don't handle yet" to prevent double-delivery during async gap
    if (_hasNativeKeySupport != false) {
      return KeyEventResult.ignored;
    }

    // Map Flutter key event to CEF key event
    final logicalKey = event.logicalKey;
    final character = event.character;

    // Convert logical key to Windows keycode
    int keyCode = _logicalKeyToWindowsKeyCode(logicalKey);

    // Build modifiers
    int modifiers = 0;
    if (HardwareKeyboard.instance.isShiftPressed) {
      modifiers |= eventFlagShiftDown;
    }
    if (HardwareKeyboard.instance.isControlPressed) {
      modifiers |= eventFlagControlDown;
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      modifiers |= eventFlagAltDown;
    }

    // Determine event type
    int type;
    if (event is KeyDownEvent) {
      type = keyEventRawKeyDown;
    } else if (event is KeyUpEvent) {
      type = keyEventKeyUp;
    } else {
      return KeyEventResult.ignored;
    }

    // Send key event to CEF
    _controller.sendKeyEvent(
      type,
      keyCode,
      modifiers,
      character?.codeUnitAt(0) ?? 0,
      character?.codeUnitAt(0) ?? 0,
    );

    // Send CHAR event after RAWKEYDOWN when character is present (required for text entry)
    if (event is KeyDownEvent && character != null) {
      _controller.sendKeyEvent(
        keyEventChar,
        keyCode,
        modifiers,
        character.codeUnitAt(0),
        character.codeUnitAt(0),
      );
    }
    return KeyEventResult.handled;
  }

  int _logicalKeyToWindowsKeyCode(LogicalKeyboardKey key) {
    // Map Flutter logical keys to Windows key codes
    // This is a simplified mapping - may need to be expanded
    if (key == LogicalKeyboardKey.f12) return 0x7B;
    if (key == LogicalKeyboardKey.f1) return 0x70;
    if (key == LogicalKeyboardKey.f2) return 0x71;
    if (key == LogicalKeyboardKey.f3) return 0x72;
    if (key == LogicalKeyboardKey.f4) return 0x73;
    if (key == LogicalKeyboardKey.f5) return 0x74;
    if (key == LogicalKeyboardKey.f6) return 0x75;
    if (key == LogicalKeyboardKey.f7) return 0x76;
    if (key == LogicalKeyboardKey.f8) return 0x77;
    if (key == LogicalKeyboardKey.f9) return 0x78;
    if (key == LogicalKeyboardKey.f10) return 0x79;
    if (key == LogicalKeyboardKey.f11) return 0x7A;
    if (key == LogicalKeyboardKey.enter) return 0x0D;
    if (key == LogicalKeyboardKey.escape) return 0x1B;
    if (key == LogicalKeyboardKey.tab) return 0x09;
    if (key == LogicalKeyboardKey.backspace) return 0x08;
    if (key == LogicalKeyboardKey.delete) return 0x2E;
    if (key == LogicalKeyboardKey.insert) return 0x2D;
    if (key == LogicalKeyboardKey.home) return 0x24;
    if (key == LogicalKeyboardKey.end) return 0x23;
    if (key == LogicalKeyboardKey.pageUp) return 0x21;
    if (key == LogicalKeyboardKey.pageDown) return 0x22;
    if (key == LogicalKeyboardKey.arrowUp) return 0x26;
    if (key == LogicalKeyboardKey.arrowDown) return 0x28;
    if (key == LogicalKeyboardKey.arrowLeft) return 0x25;
    if (key == LogicalKeyboardKey.arrowRight) return 0x27;

    // For alphanumeric keys, use the key label
    final keyLabel = key.keyLabel;
    if (keyLabel.length == 1) {
      final charCode = keyLabel.codeUnitAt(0);
      if (charCode >= 0x41 && charCode <= 0x5A) {
        // A-Z
        return charCode;
      }
      if (charCode >= 0x30 && charCode <= 0x39) {
        // 0-9
        return charCode;
      }
    }

    // Default fallback
    return 0;
  }

  // 6browser patch: keys the page itself uses. Without this, Flutter's
  // default shortcuts acted on them too while the page had focus: Tab and
  // the arrows moved focus out of the page (to the toolbar), PageUp/PageDown
  // scrolled an enclosing scrollable.
  static final _pageKeys = <ShortcutActivator, Intent>{
    for (final key in [
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ]) ...{
      SingleActivator(key): const DoNothingAndStopPropagationIntent(),
      SingleActivator(key, shift: true):
          const DoNothingAndStopPropagationIntent(),
    },
  };

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
        shortcuts: _pageKeys,
        child: Focus(
          autofocus: true,
          focusNode: _focusNode,
          canRequestFocus: true,
          debugLabel: "webview_cef",
          onFocusChange: (focused) {
            _composingText = '';
            if (focused) {
              _controller.setClientFocus(true);
              if (_controller._focusEditable) {
                attachTextInputClient();
              }
            } else {
              _controller.setClientFocus(false);
              if (_controller._focusEditable) {
                detachTextInputClient();
              }
            }
          },
          onKeyEvent: _onKeyEvent,
          child: SizedBox.expand(key: _key, child: _buildInner()),
        ));
  }

  Widget _buildInner() {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (notification) {
        _reportSurfaceSize(context);
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: Listener(
          onPointerHover: (ev) {
            _controller._cursorMove(ev.localPosition, _modifiers());
            _tooltip?.cursorOffset = ev.position;
          },
          onPointerDown: (ev) {
            if (!_focusNode.hasFocus) {
              _controller._onImeCompositionRangeChangedMessage?.call(0, 0, 0);
              _focusNode.requestFocus();
              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted && !_focusNode.hasFocus) {
                  _focusNode.requestFocus();
                }
              });
            }
            _pressedButton = _cefButton(ev.buttons);
            _controller._localToGlobal = _pageToGlobal;
            _controller._cursorClickDown(ev.localPosition, _pressedButton,
                _countClick(ev, _pressedButton), _modifiers());
          },
          onPointerUp: (ev) {
            _controller._cursorClickUp(
                ev.localPosition, _pressedButton, _clickCount, _modifiers());
            _pressedButton = 0;
          },
          onPointerCancel: (ev) {
            _controller._cursorCancel(ev.localPosition, _pressedButton);
            _pressedButton = 0;
          },
          onPointerMove: (ev) {
            // Only a left-button drag selects text or drags content.
            if (_pressedButton == 0) {
              _controller._cursorDragging(ev.localPosition, _modifiers());
            } else {
              _controller._cursorMove(ev.localPosition, _modifiers());
            }
          },
          onPointerSignal: (signal) {
            if (signal is! PointerScrollEvent) return;
            // Claim the wheel so no enclosing scrollable also moves.
            GestureBinding.instance.pointerSignalResolver.register(signal,
                (event) {
              final scroll = event as PointerScrollEvent;
              // Flutter divides the platform's wheel distance by the pixel
              // ratio; the page scrolls by the platform's distance, as in
              // Chrome.
              var delta =
                  scroll.scrollDelta * MediaQuery.devicePixelRatioOf(context);
              // Shift+wheel scrolls sideways (macOS swaps the axes itself).
              if (delta.dx == 0 &&
                  HardwareKeyboard.instance.isShiftPressed &&
                  defaultTargetPlatform != TargetPlatform.macOS) {
                delta = Offset(delta.dy, 0);
              }
              _controller._scrollBy(scroll.localPosition, delta, _modifiers());
            });
          },
          onPointerPanZoomUpdate: (event) {
            // Trackpad: the content follows the fingers.
            _controller._scrollBy(
                event.localPosition, -event.localPanDelta, _modifiers());
          },
          child: MouseRegion(
            cursor: _mouseType,
            // Ends hover effects and tooltips on the page, as in Chrome.
            onExit: (ev) {
              _controller._cursorLeave(ev.localPosition);
              _tooltip?.hide();
            },
            child: Texture(textureId: _controller._textureId),
          ),
        ),
      ),
    );
  }

  void _reportSurfaceSize(BuildContext context) async {
    double dpi = MediaQuery.of(context).devicePixelRatio;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      await _controller.ready;
      unawaited(
          _controller._setSize(dpi, Size(box.size.width, box.size.height)));
    }
  }
}
