import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'window_caption.dart';

/// Browser full screen (F11): the window covers its monitor without a frame
/// and the shell hides the tab strip and toolbar. Windows only for now;
/// elsewhere [toggle] does nothing.
class Fullscreen {
  Fullscreen._();

  static final active = ValueNotifier<bool>(false);

  static bool get supported => Platform.isWindows;

  static int _style = 0;
  static bool _wasMaximized = false;
  static final _saved = <int>[0, 0, 0, 0];

  static void toggle() => set(!active.value);

  static void set(bool on) {
    if (!supported || on == active.value) return;
    final hwnd = WindowCaption.findWindow();
    if (hwnd == 0) return;
    on ? _enter(hwnd) : _leave(hwnd);
    active.value = on;
  }

  static const _gwlStyle = -16;
  static const _wsOverlappedWindow = 0x00CF0000;
  static const _wmSysCommand = 0x0112;
  static const _scMaximize = 0xF030, _scRestore = 0xF120;
  static const _swpNoZOrder = 0x0004, _swpNoOwnerZOrder = 0x0200;
  static const _swpFrameChanged = 0x0020;

  static void _enter(int hwnd) {
    _wasMaximized = _isZoomed(hwnd) != 0;
    if (_wasMaximized) _sendMessage(hwnd, _wmSysCommand, _scRestore, 0);
    _style = _getLong(hwnd, _gwlStyle);
    final rect = calloc<Int32>(4);
    final info = calloc<Uint32>(10)..value = 40; // MONITORINFO.cbSize
    try {
      _getWindowRect(hwnd, rect);
      for (var i = 0; i < 4; i++) {
        _saved[i] = rect[i];
      }
      _getMonitorInfo(_monitorFromWindow(hwnd, 2), info);
      final m = info.cast<Int32>(); // rcMonitor at [1..4]
      _setLong(hwnd, _gwlStyle, _style & ~_wsOverlappedWindow);
      _setWindowPos(
        hwnd,
        0,
        m[1],
        m[2],
        m[3] - m[1],
        m[4] - m[2],
        _swpNoOwnerZOrder | _swpFrameChanged,
      );
    } finally {
      calloc.free(rect);
      calloc.free(info);
    }
  }

  static void _leave(int hwnd) {
    _setLong(hwnd, _gwlStyle, _style);
    _setWindowPos(
      hwnd,
      0,
      _saved[0],
      _saved[1],
      _saved[2] - _saved[0],
      _saved[3] - _saved[1],
      _swpNoZOrder | _swpNoOwnerZOrder | _swpFrameChanged,
    );
    if (_wasMaximized) _sendMessage(hwnd, _wmSysCommand, _scMaximize, 0);
  }

  static final _user32 = DynamicLibrary.open('user32.dll');

  static final _getLong = _user32
      .lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>(
        'GetWindowLongPtrW',
      );
  static final _setLong = _user32
      .lookupFunction<
        IntPtr Function(IntPtr, Int32, IntPtr),
        int Function(int, int, int)
      >('SetWindowLongPtrW');
  static final _isZoomed = _user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsZoomed');
  static final _sendMessage = _user32
      .lookupFunction<
        IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
        int Function(int, int, int, int)
      >('SendMessageW');
  static final _getWindowRect = _user32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Int32>),
        int Function(int, Pointer<Int32>)
      >('GetWindowRect');
  static final _monitorFromWindow = _user32
      .lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>(
        'MonitorFromWindow',
      );
  static final _getMonitorInfo = _user32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetMonitorInfoW');
  static final _setWindowPos = _user32
      .lookupFunction<
        Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
        int Function(int, int, int, int, int, int, int)
      >('SetWindowPos');
}
