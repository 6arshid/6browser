import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// What 6browser reads from an extension's manifest.json.
class ExtensionManifest {
  ExtensionManifest._(this.json, this._messages);

  /// Parses [manifestText]; [readMessages] returns the text of
  /// `_locales/<locale>/messages.json`, or null when there is none.
  factory ExtensionManifest.parse(
    String manifestText, {
    String? Function(String locale)? readMessages,
  }) {
    final json = decodeManifest(manifestText);
    final messages = <String, String>{};
    final locale = json['default_locale'];
    if (locale is String && readMessages != null) {
      for (final l in {'en', locale}) {
        final text = readMessages(l);
        if (text == null) continue;
        try {
          final decoded = decodeManifest(text);
          for (final MapEntry(:key, :value) in decoded.entries) {
            if (value is Map && value['message'] is String) {
              messages[key.toLowerCase()] = value['message'] as String;
            }
          }
        } on FormatException {
          // Untranslated names are shown as they are.
        }
      }
    }
    return ExtensionManifest._(json, messages);
  }

  /// Reads the manifest of the unpacked extension in [dir].
  static ExtensionManifest load(Directory dir) {
    final text = File(p.join(dir.path, 'manifest.json')).readAsStringSync();
    return ExtensionManifest.parse(
      text,
      readMessages: (locale) {
        final f = File(p.join(dir.path, '_locales', locale, 'messages.json'));
        return f.existsSync() ? f.readAsStringSync() : null;
      },
    );
  }

  final Map<String, dynamic> json;
  final Map<String, String> _messages;

  /// A Chrome theme rather than an extension.
  bool get isTheme => json['theme'] is Map;

  int get manifestVersion => (json['manifest_version'] as num?)?.toInt() ?? 0;

  String get name => _text(json['name']) ?? 'Unnamed extension';
  String get version => _text(json['version']) ?? '';
  String get description => _text(json['description']) ?? '';

  /// Relative path of the toolbar popup page, if any.
  String? get popup =>
      _nonEmpty((json['action'] ?? json['browser_action']), 'default_popup');

  /// Relative path of the options page, if any.
  String? get optionsPage =>
      _nonEmpty(json['options_ui'], 'page') ??
      (json['options_page'] is String ? json['options_page'] as String : null);

  /// Relative path of the icon closest to [size] pixels (larger preferred).
  String? icon([int size = 32]) {
    final sets = [
      json['icons'],
      (json['action'] ?? json['browser_action']) is Map
          ? (json['action'] ?? json['browser_action'])['default_icon']
          : null,
    ];
    final icons = <int, String>{};
    for (final set in sets) {
      if (set is String) icons.putIfAbsent(16, () => set);
      if (set is Map) {
        for (final MapEntry(:key, :value) in set.entries) {
          final px = int.tryParse('$key');
          if (px != null && value is String) icons.putIfAbsent(px, () => value);
        }
      }
    }
    if (icons.isEmpty) return null;
    final sizes = icons.keys.toList()..sort();
    final best = sizes.firstWhere((s) => s >= size, orElse: () => sizes.last);
    return icons[best];
  }

  /// What the extension may do, phrased like Chrome's install dialog.
  List<String> get warnings {
    // Optional permissions are asked for later, not at install.
    final permissions = <String>{
      if (json['permissions'] is List)
        for (final v in json['permissions'] as List)
          if (v is String) v,
    };
    final hosts = <String>{
      if (json['host_permissions'] is List)
        for (final v in json['host_permissions'] as List)
          if (v is String) v,
      // Manifest V2 listed hosts among the permissions.
      for (final v in permissions)
        if (v.contains('://') || v == '<all_urls>') v,
      if (json['content_scripts'] is List)
        for (final script in json['content_scripts'] as List)
          if (script is Map && script['matches'] is List)
            for (final v in script['matches'] as List)
              if (v is String) v,
    };
    final out = <String>[];
    final allSites = hosts.any(
      (h) =>
          h == '<all_urls>' ||
          RegExp(r'^(\*|https?|wss?|file)://\*/').hasMatch(h),
    );
    if (allSites ||
        permissions.contains('debugger') ||
        permissions.contains('proxy')) {
      out.add('Read and change all your data on all websites');
    } else if (hosts.isNotEmpty) {
      final names = hosts
          .map((h) => RegExp(r'^[^:]+://(?:\*\.)?([^/]+)').firstMatch(h))
          .nonNulls
          .map((m) => m.group(1)!)
          .toSet()
          .toList();
      if (names.isNotEmpty) {
        out.add(
          names.length <= 3
              ? 'Read and change your data on ${names.join(', ')}'
              : 'Read and change your data on ${names.take(2).join(', ')} '
                    'and ${names.length - 2} other sites',
        );
      }
    }
    for (final MapEntry(:key, :value) in _permissionWarnings.entries) {
      if (permissions.contains(key) && !out.contains(value)) out.add(value);
    }
    return out;
  }

  String? _text(Object? value) {
    if (value is! String) return null;
    final m = RegExp(r'^__MSG_(\w+)__$').firstMatch(value);
    if (m == null) return value;
    return _messages[m.group(1)!.toLowerCase()] ?? value;
  }

  static String? _nonEmpty(Object? map, String key) {
    if (map is! Map) return null;
    final v = map[key];
    return v is String && v.isNotEmpty ? v : null;
  }
}

/// Chrome's warning text for permissions that have one.
const _permissionWarnings = {
  'tabs': 'Read your browsing history',
  'webNavigation': 'Read your browsing history',
  'history': 'Read and change your browsing history',
  'topSites': 'Read a list of your most frequently visited websites',
  'bookmarks': 'Read and change your bookmarks',
  'downloads': 'Manage your downloads',
  'clipboardRead': 'Read data you copy and paste',
  'clipboardWrite': 'Modify data you copy and paste',
  'nativeMessaging': 'Communicate with cooperating native applications',
  'geolocation': 'Detect your physical location',
  'notifications': 'Display notifications',
  'management': 'Manage your apps, extensions, and themes',
  'privacy': 'Change your privacy-related settings',
  'contentSettings':
      'Change your settings that control websites\' access to features '
      'such as cookies, JavaScript, location, microphone and camera',
  'declarativeNetRequest': 'Block content on any page',
  'desktopCapture': 'Capture content of your screen',
};

/// Decodes manifest.json text. Chrome tolerates a byte order mark and
/// comments, so they are removed first.
Map<String, dynamic> decodeManifest(String text) {
  var s = text.startsWith('﻿') ? text.substring(1) : text;
  try {
    return jsonDecode(s) as Map<String, dynamic>;
  } on FormatException {
    s = _stripComments(s);
  }
  final decoded = jsonDecode(s);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('manifest.json is not an object');
  }
  return decoded;
}

/// Removes // and /* */ comments outside of strings.
String _stripComments(String s) {
  final out = StringBuffer();
  var i = 0;
  var inString = false;
  while (i < s.length) {
    final c = s[i];
    if (inString) {
      out.write(c);
      if (c == r'\' && i + 1 < s.length) {
        out.write(s[++i]);
      } else if (c == '"') {
        inString = false;
      }
      i++;
    } else if (c == '"') {
      inString = true;
      out.write(c);
      i++;
    } else if (s.startsWith('//', i)) {
      while (i < s.length && s[i] != '\n') {
        i++;
      }
    } else if (s.startsWith('/*', i)) {
      final end = s.indexOf('*/', i + 2);
      i = end < 0 ? s.length : end + 2;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}
