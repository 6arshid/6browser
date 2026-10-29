import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Schemes never handed to the system, as in Chrome: they can run files or
/// scripts on the computer.
const _deniedSchemes = {
  'afp', 'data', 'disk', 'disks', 'file', 'hcp', 'ie.http', 'javascript', //
  'ms-help', 'nntp', 'res', 'shell', 'vbscript', 'view-source',
  'vnd.ms.radio',
};

/// Schemes that open without asking first: mail and news, as in Chrome.
const _trustedSchemes = {'mailto', 'news', 'snews'};

/// On phones also calls, texts and WhatsApp chats, as Chrome on Android
/// does: the app still asks before calling or sending anything.
const _trustedOnPhones = {'tel', 'sms', 'smsto', 'mms', 'mmsto', 'whatsapp'};

/// Links whose address part is worth copying when no app opens them.
const _copyableSchemes = {'tel', 'sms', 'smsto', 'mms', 'mmsto', 'mailto'};

final _validScheme = RegExp(r'^[a-z][a-z0-9+.-]*$');

/// A link that belongs to another app: mailto:, tel:, tg:, whatsapp:, or an
/// Android intent: link (intent://send#Intent;scheme=whatsapp;...;end).
class AppLink {
  const AppLink._(
    this.url,
    this.scheme,
    this.target, {
    this.fallbackUrl,
    this.package,
  });

  /// Null when [url] must not be handed to the system: schemes that can run
  /// files or scripts, or a Windows drive ("c:").
  static AppLink? parse(String url) {
    final scheme = _schemeOf(url);
    if (scheme == null) return null;
    if (scheme != 'intent') return AppLink._(url, scheme, scheme);
    final parts = _intentParts(url);
    final target = parts['scheme']?.toLowerCase() ?? scheme;
    if (!_validScheme.hasMatch(target) || _deniedSchemes.contains(target)) {
      return null;
    }
    final fallback = parts['S.browser_fallback_url'];
    return AppLink._(
      url,
      scheme,
      target,
      fallbackUrl: fallback != null && _isWebUrl(fallback) ? fallback : null,
      package: parts['package'],
    );
  }

  final String url;

  /// The link's own scheme ("intent" for intent: links).
  final String scheme;

  /// The scheme of what it opens: [scheme], or the one an intent: link
  /// carries ("whatsapp").
  final String target;

  /// Web page to show instead when no app opens the link.
  final String? fallbackUrl;

  /// The app an intent: link names, to find in the store when missing.
  final String? package;

  /// The phone number or email address in a tel:, sms: or mailto: link.
  String? get address {
    if (!_copyableSchemes.contains(scheme)) return null;
    var rest = url.substring(scheme.length + 1);
    if (rest.startsWith('//')) rest = rest.substring(2);
    final end = rest.indexOf(RegExp('[?;]'));
    if (end >= 0) rest = rest.substring(0, end);
    try {
      rest = Uri.decodeComponent(rest);
    } on ArgumentError {
      // Keep it as written.
    }
    return rest.isEmpty ? null : rest;
  }
}

String? _schemeOf(String url) {
  final colon = url.indexOf(':');
  if (colon < 2) return null;
  final scheme = url.substring(0, colon).toLowerCase();
  if (!_validScheme.hasMatch(scheme) || _deniedSchemes.contains(scheme)) {
    return null;
  }
  return scheme;
}

/// The `key=value` parts after `#Intent;` (values are URI-encoded).
Map<String, String> _intentParts(String url) {
  final start = url.indexOf('#Intent;');
  if (start < 0) return const {};
  final parts = <String, String>{};
  for (final part in url.substring(start + '#Intent;'.length).split(';')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final value = part.substring(eq + 1);
    try {
      parts[part.substring(0, eq)] = Uri.decodeComponent(value);
    } on ArgumentError {
      parts[part.substring(0, eq)] = value;
    }
  }
  return parts;
}

bool _isWebUrl(String url) =>
    url.startsWith('https://') || url.startsWith('http://');

/// True when [link] opens without asking first. [phone]: running on a
/// phone, where calls, texts and WhatsApp open directly too.
bool opensWithoutAsking(AppLink link, {required bool phone}) =>
    _trustedSchemes.contains(link.target) ||
    phone && _trustedOnPhones.contains(link.target);

/// Hands links such as mailto: or tg: to the app the system has for them.
class ExternalApps {
  const ExternalApps();

  static const _app = MethodChannel('6browser/app');

  /// The app that opens [scheme] links: its name, '' when the system does
  /// not say which app it is, or null when no app opens them.
  Future<String?> appFor(String scheme) async {
    if (!Platform.isWindows) return '';
    try {
      return await Isolate.run(() => _windowsAppFor(scheme));
    } on Object {
      return '';
    }
  }

  /// Opens [url] in its app. False when that failed.
  Future<bool> open(String url) async {
    try {
      if (Platform.isWindows) return await Isolate.run(() => _windowsOpen(url));
      if (Platform.isAndroid) {
        return await _app.invokeMethod<bool>('openExternal', url) ?? false;
      }
      final opener = Platform.isMacOS ? 'open' : 'xdg-open';
      return (await Process.run(opener, [url])).exitCode == 0;
    } on Object {
      return false;
    }
  }
}

final externalAppsProvider = Provider<ExternalApps>(
  (ref) => const ExternalApps(),
);

// ---- Windows ----

const _assocIsProtocol = 0x1000; // ASSOCF_IS_PROTOCOL
const _assocExecutable = 2; // ASSOCSTR_EXECUTABLE
const _assocFriendlyAppName = 4; // ASSOCSTR_FRIENDLYAPPNAME
const _swShowNormal = 1;
const _comApartment = 0x2 | 0x4; // COINIT_APARTMENTTHREADED | DISABLE_OLE1DDE

String? _windowsAppFor(String scheme) => _withCom(() {
  final assoc = scheme.toNativeUtf16(allocator: calloc);
  final out = calloc<Uint16>(1024).cast<Utf16>();
  final size = calloc<Uint32>();
  try {
    String? query(int what) {
      size.value = 1024;
      final result = _assocQueryString(
        _assocIsProtocol,
        what,
        assoc,
        nullptr,
        out,
        size,
      );
      return result == 0 ? out.toDartString() : null;
    }

    final exe = query(_assocExecutable);
    // Registered without a default app (tel: and sms: on most PCs):
    // Windows asks which app to use ("Pick an application").
    if (exe != null &&
        p.windows.basename(exe).toLowerCase() == 'openwith.exe') {
      return '';
    }
    final name = query(_assocFriendlyAppName);
    if (name != null && name.isNotEmpty) return name;
    return exe == null ? null : p.windows.basenameWithoutExtension(exe);
  } finally {
    calloc
      ..free(assoc)
      ..free(out)
      ..free(size);
  }
});

bool _windowsOpen(String url) {
  // Quoted so the app cannot read part of the link as extra command-line
  // arguments, and kept under the length ShellExecute handles (as Chrome
  // does, platform_util_win.cc).
  if (url.length > 2048 ||
      url.contains('"') ||
      url.codeUnits.any((c) => c < 0x20)) {
    return false;
  }
  return _withCom(() {
    final verb = 'open'.toNativeUtf16(allocator: calloc);
    final file = '"$url"'.toNativeUtf16(allocator: calloc);
    try {
      return _shellExecute(0, verb, file, nullptr, nullptr, _swShowNormal) > 32;
    } finally {
      calloc
        ..free(verb)
        ..free(file);
    }
  });
}

/// Shell handlers may be COM objects, so the calling thread needs COM.
T _withCom<T>(T Function() body) {
  final initialized = _coInitializeEx(nullptr, _comApartment) >= 0;
  try {
    return body();
  } finally {
    if (initialized) _coUninitialize();
  }
}

final _shlwapi = DynamicLibrary.open('shlwapi.dll');
final _shell32 = DynamicLibrary.open('shell32.dll');
final _ole32 = DynamicLibrary.open('ole32.dll');

final _assocQueryString = _shlwapi
    .lookupFunction<
      Int32 Function(
        Uint32,
        Uint32,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Uint32>,
      ),
      int Function(
        int,
        int,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Uint32>,
      )
    >('AssocQueryStringW');

final _shellExecute = _shell32
    .lookupFunction<
      IntPtr Function(
        IntPtr,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Int32,
      ),
      int Function(
        int,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
      )
    >('ShellExecuteW');

final _coInitializeEx = _ole32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)
    >('CoInitializeEx');

final _coUninitialize = _ole32.lookupFunction<Void Function(), void Function()>(
  'CoUninitialize',
);
