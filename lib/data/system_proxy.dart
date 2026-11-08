import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// A [HttpClient.findProxy] that follows the system proxy. Dart's
/// HttpClient only reads the proxy environment variables, but on Windows
/// the proxy is a setting (Settings > Network & internet > Proxy), which
/// is also what VPN apps change. PAC scripts and SOCKS proxies are not
/// supported: those connect directly.
String Function(Uri) systemProxyFinder() {
  if (Platform.isWindows) {
    try {
      final proxy = WindowsProxy.read();
      if (proxy != null) return proxy.proxyFor;
    } on Object {
      // No registry access: fall back to the environment.
    }
  }
  return (uri) => HttpClient.findProxyFromEnvironment(uri);
}

/// Windows' manual proxy setting.
class WindowsProxy {
  const WindowsProxy(this.server, {this.bypass = ''});

  /// "host:port", or per scheme: "http=host:port;https=host:port".
  final String server;

  /// Hosts that skip the proxy: `localhost;*.lan;<local>`.
  final String bypass;

  static const _key =
      r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  /// The current setting, or null when no proxy is turned on.
  static WindowsProxy? read() {
    if (_readDword(_key, 'ProxyEnable') != 1) return null;
    final server = _readString(_key, 'ProxyServer')?.trim() ?? '';
    if (server.isEmpty) return null;
    return WindowsProxy(
      server,
      bypass: _readString(_key, 'ProxyOverride') ?? '',
    );
  }

  /// A [HttpClient.findProxy] answer for [uri].
  String proxyFor(Uri uri) {
    if (_bypassed(uri.host.toLowerCase())) return 'DIRECT';
    final address = _addressFor(uri.scheme);
    return address == null ? 'DIRECT' : 'PROXY $address; DIRECT';
  }

  String? _addressFor(String scheme) {
    String clean(String s) =>
        s.trim().replaceFirst(RegExp(r'^[a-z]+://', caseSensitive: false), '');
    if (!server.contains('=')) return clean(server);
    final byScheme = <String, String>{};
    for (final part in server.split(';')) {
      final i = part.indexOf('=');
      if (i > 0) {
        byScheme[part.substring(0, i).trim().toLowerCase()] = clean(
          part.substring(i + 1),
        );
      }
    }
    final address = scheme == 'https'
        ? byScheme['https'] ?? byScheme['http']
        : byScheme['http'];
    return address == null || address.isEmpty ? null : address;
  }

  bool _bypassed(String host) {
    for (final raw in bypass.split(';')) {
      final rule = raw.trim().toLowerCase();
      if (rule.isEmpty) continue;
      if (rule == '<local>') {
        if (!host.contains('.')) return true;
        continue;
      }
      final pattern = RegExp(
        '^${RegExp.escape(rule).replaceAll(r'\*', '.*')}\$',
      );
      if (pattern.hasMatch(host)) return true;
    }
    return false;
  }
}

// HKEY_CURRENT_USER is (HKEY)(LONG)0x80000001, sign-extended on 64-bit.
const _currentUser = -0x7FFFFFFF;
const _rrfRegSz = 0x2;
const _rrfRegDword = 0x10;

typedef _RegGetValueNative =
    Int32 Function(
      IntPtr key,
      Pointer<Utf16> subKey,
      Pointer<Utf16> value,
      Uint32 flags,
      Pointer<Uint32> type,
      Pointer<Void> data,
      Pointer<Uint32> size,
    );
typedef _RegGetValueDart =
    int Function(
      int key,
      Pointer<Utf16> subKey,
      Pointer<Utf16> value,
      int flags,
      Pointer<Uint32> type,
      Pointer<Void> data,
      Pointer<Uint32> size,
    );

final _regGetValue = DynamicLibrary.open(
  'advapi32.dll',
).lookupFunction<_RegGetValueNative, _RegGetValueDart>('RegGetValueW');

int? _readDword(String key, String name) => using((arena) {
  final data = arena<Uint32>();
  final size = arena<Uint32>()..value = 4;
  final status = _regGetValue(
    _currentUser,
    key.toNativeUtf16(allocator: arena),
    name.toNativeUtf16(allocator: arena),
    _rrfRegDword,
    nullptr,
    data.cast(),
    size,
  );
  return status == 0 ? data.value : null;
});

String? _readString(String key, String name) => using((arena) {
  final subKey = key.toNativeUtf16(allocator: arena);
  final value = name.toNativeUtf16(allocator: arena);
  final size = arena<Uint32>();
  if (_regGetValue(
        _currentUser,
        subKey,
        value,
        _rrfRegSz,
        nullptr,
        nullptr,
        size,
      ) !=
      0) {
    return null;
  }
  final data = arena<Uint8>(size.value + 2).cast<Utf16>();
  if (_regGetValue(
        _currentUser,
        subKey,
        value,
        _rrfRegSz,
        nullptr,
        data.cast(),
        size,
      ) !=
      0) {
    return null;
  }
  return data.toDartString();
});
