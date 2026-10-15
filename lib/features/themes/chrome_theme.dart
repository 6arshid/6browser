import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

/// A Chrome theme (the `theme` key of an extension manifest), read from an
/// unpacked theme folder. See
/// https://developer.chrome.com/docs/extensions/reference/manifest/theme
///
/// Only colors, tints, the frame/toolbar/New Tab images and the New Tab
/// image placement are used; everything else in the manifest is ignored.
class ChromeTheme {
  const ChromeTheme({
    required this.name,
    this.colors = const {},
    this.tints = const {},
    this.frameImage,
    this.toolbarImage,
    this.ntpImage,
    this.ntpAlignment = Alignment.center,
    this.ntpRepeat = ImageRepeat.noRepeat,
  });

  final String name;

  /// Manifest color keys (`frame`, `toolbar`, `tab_text`, ...).
  final Map<String, Color> colors;

  /// Manifest tint keys (`buttons`, `frame`, ...) as HSL shifts.
  final Map<String, HslTint> tints;

  final File? frameImage;
  final File? toolbarImage;
  final File? ntpImage;
  final Alignment ntpAlignment;
  final ImageRepeat ntpRepeat;

  /// Reads `manifest.json` in [dir]. Throws [FormatException] when the
  /// folder is not a theme (for example a normal extension).
  static ChromeTheme load(Directory dir) {
    final file = File(p.join(dir.path, 'manifest.json'));
    if (!file.existsSync()) {
      throw const FormatException('No manifest.json found');
    }
    final manifest = _decodeJson(file.readAsBytesSync());
    return parse(manifest, dir: dir, messages: _messages(dir, manifest));
  }

  /// Parses a decoded manifest. Image paths are resolved against [dir] and
  /// dropped when the file is missing.
  static ChromeTheme parse(
    Object? manifest, {
    Directory? dir,
    Map<String, String> messages = const {},
  }) {
    if (manifest is! Map || manifest['theme'] is! Map) {
      throw const FormatException('This item is not a Chrome theme');
    }
    final theme = manifest['theme'] as Map;

    final colors = <String, Color>{};
    final rawColors = theme['colors'];
    if (rawColors is Map) {
      for (final e in rawColors.entries) {
        final c = _color(e.value);
        if (c != null) colors[e.key.toString()] = c;
      }
    }

    final tints = <String, HslTint>{};
    final rawTints = theme['tints'];
    if (rawTints is Map) {
      for (final e in rawTints.entries) {
        final t = HslTint.tryParse(e.value);
        if (t != null) tints[e.key.toString()] = t;
      }
    }

    final images = theme['images'] is Map ? theme['images'] as Map : const {};
    File? image(String key) {
      final rel = images[key];
      if (dir == null || rel is! String || rel.isEmpty) return null;
      final f = File(p.normalize(p.join(dir.path, rel)));
      // Never follow a path that points outside the theme folder.
      if (!p.isWithin(dir.path, f.path) || !f.existsSync()) return null;
      return f;
    }

    final props = theme['properties'] is Map
        ? theme['properties'] as Map
        : const {};

    var name = manifest['name']?.toString() ?? 'Theme';
    final msg = RegExp(r'^__MSG_(\w+)__$').firstMatch(name);
    if (msg != null) name = messages[msg[1]!.toLowerCase()] ?? 'Theme';

    return ChromeTheme(
      name: name,
      colors: colors,
      tints: tints,
      frameImage: image('theme_frame'),
      toolbarImage: image('theme_toolbar'),
      ntpImage: image('theme_ntp_background'),
      ntpAlignment: parseAlignment(props['ntp_background_alignment']),
      ntpRepeat: parseRepeat(props['ntp_background_repeat']),
    );
  }

  static Object? _decodeJson(List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    return jsonDecode(text);
  }

  /// Localized strings for `__MSG_name__`, from the default locale.
  static Map<String, String> _messages(Directory dir, Object? manifest) {
    final locales = <String>[
      if (manifest is Map && manifest['default_locale'] is String)
        manifest['default_locale'] as String,
      'en',
      'en_US',
    ];
    for (final l in locales) {
      final f = File(p.join(dir.path, '_locales', l, 'messages.json'));
      if (!f.existsSync()) continue;
      try {
        final json = _decodeJson(f.readAsBytesSync());
        if (json is! Map) continue;
        return {
          for (final e in json.entries)
            if (e.value is Map && (e.value as Map)['message'] is String)
              e.key.toString().toLowerCase(): (e.value as Map)['message'],
        };
      } on FormatException {
        continue;
      }
    }
    return const {};
  }

  /// `[r, g, b]` or `[r, g, b, alpha]` (alpha 0..1).
  static Color? _color(Object? v) {
    if (v is! List || v.length < 3 || v.take(3).any((x) => x is! num)) {
      return null;
    }
    int ch(Object x) => (x as num).round().clamp(0, 255);
    final a = v.length > 3 && v[3] is num
        ? ((v[3] as num).toDouble().clamp(0.0, 1.0) * 255).round()
        : 255;
    return Color.fromARGB(a, ch(v[0]), ch(v[1]), ch(v[2]));
  }
}

/// Chrome's `ntp_background_alignment`, e.g. "top", "bottom right".
Alignment parseAlignment(Object? v) {
  final words = v is String ? v.toLowerCase().split(RegExp(r'\s+')) : const [];
  final x = words.contains('left')
      ? -1.0
      : words.contains('right')
      ? 1.0
      : 0.0;
  final y = words.contains('top')
      ? -1.0
      : words.contains('bottom')
      ? 1.0
      : 0.0;
  return Alignment(x, y);
}

/// Chrome's `ntp_background_repeat`.
ImageRepeat parseRepeat(Object? v) => switch (v) {
  'repeat' => ImageRepeat.repeat,
  'repeat-x' => ImageRepeat.repeatX,
  'repeat-y' => ImageRepeat.repeatY,
  _ => ImageRepeat.noRepeat,
};

/// A Chrome tint: `[h, s, l]`, each 0..1 or -1 for "keep".
///
/// Hue replaces the hue; saturation and lightness shift the value, with
/// 0.5 meaning no change (Chrome's `color_utils::HSLShift`).
class HslTint {
  const HslTint(this.h, this.s, this.l);

  final double h;
  final double s;
  final double l;

  static HslTint? tryParse(Object? v) {
    if (v is! List || v.length < 3 || v.take(3).any((x) => x is! num)) {
      return null;
    }
    return HslTint(
      (v[0] as num).toDouble(),
      (v[1] as num).toDouble(),
      (v[2] as num).toDouble(),
    );
  }

  Color apply(Color c) {
    var hsl = HSLColor.fromColor(c);
    if (h >= 0) hsl = hsl.withHue((h.clamp(0, 1) * 360) % 360);
    if (s >= 0) {
      final sat = hsl.saturation;
      hsl = hsl.withSaturation(
        s <= 0.5 ? sat * s * 2 : sat + (1 - sat) * ((s - 0.5) * 2),
      );
    }
    if (l >= 0) {
      final lum = hsl.lightness;
      hsl = hsl.withLightness(
        l <= 0.5 ? lum * l * 2 : lum + (1 - lum) * ((l - 0.5) * 2),
      );
    }
    return hsl.toColor().withValues(alpha: c.a);
  }
}
