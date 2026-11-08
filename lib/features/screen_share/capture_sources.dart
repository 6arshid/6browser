import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

enum CaptureKind { screen, window }

/// A screen or window the user can share.
class CaptureSource {
  const CaptureSource({
    required this.id,
    required this.kind,
    required this.title,
    this.thumbnail,
  });

  /// Chromium's desktop media id: `screen:<display index>:0` or
  /// `window:<window handle>:0`.
  final String id;
  final CaptureKind kind;
  final String title;

  /// A small picture of it (a BMP file); null when none could be taken,
  /// e.g. for a minimized window.
  final Uint8List? thumbnail;
}

/// The screens and windows that can be shared, windows in front-to-back
/// order, each with a thumbnail of at most [width] x [height] pixels.
/// Windows only; empty elsewhere.
Future<List<CaptureSource>> listCaptureSources({
  int width = 320,
  int height = 180,
}) async {
  if (!Platform.isWindows) return const [];
  try {
    return await Isolate.run(() => _listSources(width, height));
  } on Object {
    return const [];
  }
}

// ---- Windows ----

List<CaptureSource> _listSources(int width, int height) => [
  ..._screens(width, height),
  ..._windows(width, height),
];

const _displayDeviceActive = 0x1; // DISPLAY_DEVICE_ACTIVE
const _enumCurrentSettings = -1; // ENUM_CURRENT_SETTINGS
const _displayDeviceSize = 840; // sizeof(DISPLAY_DEVICEW)
const _devModeSize = 220; // sizeof(DEVMODEW)

/// Active displays, numbered as Chromium numbers them: by their index in
/// EnumDisplayDevices (webrtc's GetScreenList).
List<CaptureSource> _screens(int width, int height) {
  final device = calloc<Uint8>(_displayDeviceSize);
  final mode = calloc<Uint8>(_devModeSize);
  final found = <({int index, int x, int y, int w, int h})>[];
  try {
    for (var index = 0; ; index++) {
      device
          .asTypedList(_displayDeviceSize)
          .fillRange(0, _displayDeviceSize, 0);
      device.cast<Uint32>().value = _displayDeviceSize;
      if (_enumDisplayDevices(nullptr, index, device, 0) == 0) break;
      final flags = (device + 324).cast<Uint32>().value;
      if (flags & _displayDeviceActive == 0) continue;
      mode.asTypedList(_devModeSize).fillRange(0, _devModeSize, 0);
      (mode + 68).cast<Uint16>().value = _devModeSize; // dmSize
      final name = (device + 4).cast<Utf16>();
      if (_enumDisplaySettingsEx(name, _enumCurrentSettings, mode, 0) == 0) {
        continue;
      }
      found.add((
        index: index,
        x: (mode + 76).cast<Int32>().value,
        y: (mode + 80).cast<Int32>().value,
        w: (mode + 172).cast<Uint32>().value,
        h: (mode + 176).cast<Uint32>().value,
      ));
    }
  } finally {
    calloc
      ..free(device)
      ..free(mode);
  }
  final screen = _getDC(0);
  try {
    return [
      for (final (i, s) in found.indexed)
        CaptureSource(
          id: 'screen:${s.index}:0',
          kind: CaptureKind.screen,
          title: found.length == 1 ? 'Entire screen' : 'Screen ${i + 1}',
          thumbnail: _scaled(screen, s.x, s.y, s.w, s.h, width, height),
        ),
    ];
  } finally {
    _releaseDC(0, screen);
  }
}

final _foundWindows = <int>[];

int _collectWindow(int hwnd, int _) {
  _foundWindows.add(hwnd);
  return 1;
}

const _gwlExStyle = -20;
const _gwOwner = 4;
const _wsExToolWindow = 0x80;
const _wsExAppWindow = 0x40000;
const _dwmwaExtendedFrameBounds = 9;
const _dwmwaCloaked = 14;
const _pwRenderFullContent = 2;

/// Top-level windows a person would recognize, as webrtc lists them:
/// visible, titled, not cloaked, not tool windows, not owned dialogs.
List<CaptureSource> _windows(int width, int height) {
  _foundWindows.clear();
  _enumWindows(Pointer.fromFunction<_EnumProc>(_collectWindow, 0), 0);
  final shell = _getShellWindow();
  final text = calloc<Uint16>(512).cast<Utf16>();
  final cloaked = calloc<Uint32>();
  final sources = <CaptureSource>[];
  try {
    for (final hwnd in _foundWindows) {
      if (hwnd == shell || _isWindowVisible(hwnd) == 0) continue;
      if (_getWindow(hwnd, _gwOwner) != 0) continue;
      final exStyle = _getWindowLongPtr(hwnd, _gwlExStyle);
      if (exStyle & _wsExToolWindow != 0 && exStyle & _wsExAppWindow == 0) {
        continue;
      }
      cloaked.value = 0;
      if (_dwmGetWindowAttribute(hwnd, _dwmwaCloaked, cloaked.cast(), 4) == 0 &&
          cloaked.value != 0) {
        continue;
      }
      if (_getClassName(hwnd, text, 256) > 0 &&
          const {
            'Progman',
            'WorkerW',
            'Shell_TrayWnd',
          }.contains(text.toDartString())) {
        continue;
      }
      final length = _getWindowText(hwnd, text, 256);
      if (length <= 0) continue;
      final title = text.toDartString(length: length).trim();
      if (title.isEmpty) continue;
      sources.add(
        CaptureSource(
          id: 'window:$hwnd:0',
          kind: CaptureKind.window,
          title: title,
          thumbnail: _windowThumbnail(hwnd, width, height),
        ),
      );
    }
  } finally {
    calloc
      ..free(text)
      ..free(cloaked);
  }
  return sources;
}

Uint8List? _windowThumbnail(int hwnd, int width, int height) {
  // A minimized window draws nothing; a hung one would never answer.
  if (_isIconic(hwnd) != 0 || _isHungAppWindow(hwnd) != 0) return null;
  final rect = calloc<Int32>(4);
  final frame = calloc<Int32>(4);
  try {
    if (_getWindowRect(hwnd, rect) == 0) return null;
    final left = rect[0], top = rect[1];
    final w = rect[2] - left, h = rect[3] - top;
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384) return null;
    // The window without its invisible resize borders.
    var (fx, fy, fw, fh) = (0, 0, w, h);
    if (_dwmGetWindowAttribute(
          hwnd,
          _dwmwaExtendedFrameBounds,
          frame.cast(),
          16,
        ) ==
        0) {
      final x0 = (frame[0] - left).clamp(0, w);
      final y0 = (frame[1] - top).clamp(0, h);
      final x1 = (frame[2] - left).clamp(0, w);
      final y1 = (frame[3] - top).clamp(0, h);
      if (x1 > x0 && y1 > y0) (fx, fy, fw, fh) = (x0, y0, x1 - x0, y1 - y0);
    }
    final screen = _getDC(0);
    final dc = _createCompatibleDC(screen);
    final bitmap = _createCompatibleBitmap(screen, w, h);
    final old = _selectObject(dc, bitmap);
    try {
      if (_printWindow(hwnd, dc, _pwRenderFullContent) == 0) return null;
      return _scaled(dc, fx, fy, fw, fh, width, height);
    } finally {
      _selectObject(dc, old);
      _deleteObject(bitmap);
      _deleteDC(dc);
      _releaseDC(0, screen);
    }
  } finally {
    calloc
      ..free(rect)
      ..free(frame);
  }
}

const _srcCopy = 0x00CC0020;
const _halftone = 4;

/// The [w] x [h] area at ([x], [y]) of [source], shrunk to fit [maxWidth] x
/// [maxHeight], as a BMP file.
Uint8List? _scaled(
  int source,
  int x,
  int y,
  int w,
  int h,
  int maxWidth,
  int maxHeight,
) {
  if (w <= 0 || h <= 0) return null;
  final scale = [
    maxWidth / w,
    maxHeight / h,
    1.0,
  ].reduce((a, b) => a < b ? a : b);
  final dw = (w * scale).round().clamp(1, maxWidth);
  final dh = (h * scale).round().clamp(1, maxHeight);
  final info = calloc<Uint8>(44); // BITMAPINFOHEADER + one color
  final bits = calloc<Pointer<Void>>();
  final dc = _createCompatibleDC(source);
  try {
    final header = info.cast<Int32>();
    header[0] = 40; // biSize
    header[1] = dw; // biWidth
    header[2] = -dh; // biHeight: top-down
    (info + 12).cast<Uint16>().value = 1; // biPlanes
    (info + 14).cast<Uint16>().value = 32; // biBitCount
    final dib = _createDIBSection(dc, info, 0, bits, 0, 0);
    if (dib == 0 || bits.value == nullptr) return null;
    final old = _selectObject(dc, dib);
    try {
      _setStretchBltMode(dc, _halftone);
      _setBrushOrgEx(dc, 0, 0, nullptr);
      if (_stretchBlt(dc, 0, 0, dw, dh, source, x, y, w, h, _srcCopy) == 0) {
        return null;
      }
      final pixels = bits.value.cast<Uint8>().asTypedList(dw * dh * 4);
      return _bmp(pixels, dw, dh);
    } finally {
      _selectObject(dc, old);
      _deleteObject(dib);
    }
  } finally {
    _deleteDC(dc);
    calloc
      ..free(info)
      ..free(bits);
  }
}

/// A 24-bit BMP file of top-down BGRA [pixels].
Uint8List _bmp(Uint8List pixels, int width, int height) {
  final row = (width * 3 + 3) & ~3;
  final size = 54 + row * height;
  final out = Uint8List(size);
  final data = ByteData.sublistView(out);
  out[0] = 0x42; // 'B'
  out[1] = 0x4D; // 'M'
  data.setUint32(2, size, Endian.little);
  data.setUint32(10, 54, Endian.little);
  data.setUint32(14, 40, Endian.little);
  data.setInt32(18, width, Endian.little);
  data.setInt32(22, height, Endian.little); // bottom-up
  data.setUint16(26, 1, Endian.little);
  data.setUint16(28, 24, Endian.little);
  data.setUint32(34, row * height, Endian.little);
  for (var y = 0; y < height; y++) {
    var to = 54 + (height - 1 - y) * row;
    var from = y * width * 4;
    for (var x = 0; x < width; x++, from += 4, to += 3) {
      out[to] = pixels[from];
      out[to + 1] = pixels[from + 1];
      out[to + 2] = pixels[from + 2];
    }
  }
  return out;
}

typedef _EnumProc = Int32 Function(IntPtr, IntPtr);

final _user32 = DynamicLibrary.open('user32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');
final _dwmapi = DynamicLibrary.open('dwmapi.dll');

final _enumWindows = _user32
    .lookupFunction<
      Int32 Function(Pointer<NativeFunction<_EnumProc>>, IntPtr),
      int Function(Pointer<NativeFunction<_EnumProc>>, int)
    >('EnumWindows');
final _isWindowVisible = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'IsWindowVisible',
    );
final _isIconic = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');
final _isHungAppWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'IsHungAppWindow',
    );
final _getWindowText = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Int32),
      int Function(int, Pointer<Utf16>, int)
    >('GetWindowTextW');
final _getClassName = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Int32),
      int Function(int, Pointer<Utf16>, int)
    >('GetClassNameW');
final _getWindowLongPtr = _user32
    .lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>(
      'GetWindowLongPtrW',
    );
final _getWindow = _user32
    .lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>(
      'GetWindow',
    );
final _getShellWindow = _user32
    .lookupFunction<IntPtr Function(), int Function()>('GetShellWindow');
final _getWindowRect = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Int32>),
      int Function(int, Pointer<Int32>)
    >('GetWindowRect');
final _printWindow = _user32
    .lookupFunction<
      Int32 Function(IntPtr, IntPtr, Uint32),
      int Function(int, int, int)
    >('PrintWindow');
final _getDC = _user32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
final _releaseDC = _user32
    .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
      'ReleaseDC',
    );
final _enumDisplayDevices = _user32
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Pointer<Uint8>, Uint32),
      int Function(Pointer<Utf16>, int, Pointer<Uint8>, int)
    >('EnumDisplayDevicesW');
final _enumDisplaySettingsEx = _user32
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Pointer<Uint8>, Uint32),
      int Function(Pointer<Utf16>, int, Pointer<Uint8>, int)
    >('EnumDisplaySettingsExW');

final _createCompatibleDC = _gdi32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
      'CreateCompatibleDC',
    );
final _deleteDC = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');
final _createCompatibleBitmap = _gdi32
    .lookupFunction<
      IntPtr Function(IntPtr, Int32, Int32),
      int Function(int, int, int)
    >('CreateCompatibleBitmap');
final _createDIBSection = _gdi32
    .lookupFunction<
      IntPtr Function(
        IntPtr,
        Pointer<Uint8>,
        Uint32,
        Pointer<Pointer<Void>>,
        IntPtr,
        Uint32,
      ),
      int Function(int, Pointer<Uint8>, int, Pointer<Pointer<Void>>, int, int)
    >('CreateDIBSection');
final _selectObject = _gdi32
    .lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>(
      'SelectObject',
    );
final _deleteObject = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');
final _setStretchBltMode = _gdi32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
      'SetStretchBltMode',
    );
final _setBrushOrgEx = _gdi32
    .lookupFunction<
      Int32 Function(IntPtr, Int32, Int32, Pointer<Void>),
      int Function(int, int, int, Pointer<Void>)
    >('SetBrushOrgEx');
final _stretchBlt = _gdi32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Int32,
        Int32,
        Int32,
        Int32,
        IntPtr,
        Int32,
        Int32,
        Int32,
        Int32,
        Uint32,
      ),
      int Function(int, int, int, int, int, int, int, int, int, int, int)
    >('StretchBlt');

final _dwmGetWindowAttribute = _dwmapi
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
      int Function(int, int, Pointer<Void>, int)
    >('DwmGetWindowAttribute');
