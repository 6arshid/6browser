import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart';

/// Paints the native Windows title bar in the theme's frame color, so it
/// joins the tab strip as in Chrome. Needs Windows 11; elsewhere it does
/// nothing.
class WindowCaption {
  WindowCaption._();

  static int? _hwnd;
  static Color? _last;

  static void apply(Color frame) {
    if (!Platform.isWindows || frame == _last) return;
    try {
      final hwnd = _hwnd ??= _findWindow();
      if (hwnd == 0) return;
      _last = frame;
      final dark = frame.computeLuminance() < 0.4;
      _set(hwnd, 20, dark ? 1 : 0); // DWMWA_USE_IMMERSIVE_DARK_MODE
      _set(hwnd, 35, _colorRef(frame)); // DWMWA_CAPTION_COLOR
      _set(hwnd, 34, _colorRef(frame)); // DWMWA_BORDER_COLOR
      _set(
        hwnd,
        36, // DWMWA_TEXT_COLOR
        _colorRef(dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000)),
      );
    } on Object {
      // Older Windows or no dwmapi: keep the system title bar.
    }
  }

  /// COLORREF is 0x00BBGGRR.
  static int _colorRef(Color c) {
    int ch(double v) => (v * 255).round() & 0xFF;
    return ch(c.r) | (ch(c.g) << 8) | (ch(c.b) << 16);
  }

  static final _dwm = DynamicLibrary.open('dwmapi.dll');
  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _setAttribute = _dwm
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)
      >('DwmSetWindowAttribute');

  static void _set(int hwnd, int attribute, int value) {
    final p = calloc<Uint32>()..value = value;
    try {
      _setAttribute(hwnd, attribute, p.cast(), sizeOf<Uint32>());
    } finally {
      calloc.free(p);
    }
  }

  /// The runner's top-level window in this process.
  static int findWindow() => _hwnd ??= _findWindow();

  static int _findWindow() {
    final findWindowEx = _user32
        .lookupFunction<
          IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
          int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)
        >('FindWindowExW');
    final getPid = _user32
        .lookupFunction<
          Uint32 Function(IntPtr, Pointer<Uint32>),
          int Function(int, Pointer<Uint32>)
        >('GetWindowThreadProcessId');
    final currentPid = _kernel32
        .lookupFunction<Uint32 Function(), int Function()>(
          'GetCurrentProcessId',
        )();
    final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final pid = calloc<Uint32>();
    try {
      var hwnd = 0;
      while ((hwnd = findWindowEx(0, hwnd, cls, nullptr)) != 0) {
        getPid(hwnd, pid);
        if (pid.value == currentPid) return hwnd;
      }
      return 0;
    } finally {
      calloc.free(cls);
      calloc.free(pid);
    }
  }
}
