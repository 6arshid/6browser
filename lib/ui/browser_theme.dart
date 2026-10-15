import 'dart:io';

import 'package:flutter/material.dart';

import '../features/themes/chrome_theme.dart';

/// Accent colors offered under Appearance, like Chrome's "Customize Chrome".
const colorPalette = <(String, Color)>[
  ('Blue', Color(0xFF1A73E8)),
  ('Aqua', Color(0xFF00838F)),
  ('Green', Color(0xFF1E8E3E)),
  ('Viridian', Color(0xFF00796B)),
  ('Citron', Color(0xFF9E9D24)),
  ('Orange', Color(0xFFE8710A)),
  ('Apricot', Color(0xFFD9822B)),
  ('Rose', Color(0xFFD93025)),
  ('Pink', Color(0xFFD01884)),
  ('Fuchsia', Color(0xFFA142F4)),
  ('Violet', Color(0xFF6741D9)),
  ('Grey', Color(0xFF5F6368)),
];

const _defaultSeed = Color(0xFF1A73E8);

/// Colors and images of the browser chrome (tab strip, toolbar, omnibox and
/// New Tab page). Comes from the default look, a palette color, or a Chrome
/// theme, and is read with `BrowserColors.of(context)`.
@immutable
class BrowserColors extends ThemeExtension<BrowserColors> {
  const BrowserColors({
    required this.frame,
    required this.toolbar,
    required this.tabText,
    required this.tabBackgroundText,
    required this.icon,
    required this.omnibox,
    required this.omniboxText,
    required this.separator,
    required this.ntpBackground,
    required this.ntpText,
    this.frameImage,
    this.toolbarImage,
    this.ntpImage,
    this.ntpAlignment = Alignment.center,
    this.ntpRepeat = ImageRepeat.noRepeat,
  });

  /// Behind the tabs (and the window title bar on Windows 11).
  final Color frame;

  /// Toolbar, bookmarks bar and the selected tab.
  final Color toolbar;

  /// Text on the selected tab and the toolbar.
  final Color tabText;

  /// Text on unselected tabs.
  final Color tabBackgroundText;
  final Color icon;
  final Color omnibox;
  final Color omniboxText;
  final Color separator;
  final Color ntpBackground;
  final Color ntpText;
  final ImageProvider? frameImage;
  final ImageProvider? toolbarImage;
  final ImageProvider? ntpImage;
  final Alignment ntpAlignment;
  final ImageRepeat ntpRepeat;

  static BrowserColors of(BuildContext context) =>
      Theme.of(context).extension<BrowserColors>() ??
      BrowserColors.fromScheme(Theme.of(context).colorScheme);

  Brightness get brightness => ThemeData.estimateBrightnessForColor(toolbar);

  /// The built-in look, close to Chrome's default.
  factory BrowserColors.standard(Brightness b) => b == Brightness.light
      ? const BrowserColors(
          frame: Color(0xFFDDE3EA),
          toolbar: Color(0xFFFFFFFF),
          tabText: Color(0xFF1F1F1F),
          tabBackgroundText: Color(0xFF474747),
          icon: Color(0xFF474747),
          omnibox: Color(0xFFEDF0F4),
          omniboxText: Color(0xFF1F1F1F),
          separator: Color(0x1F000000),
          ntpBackground: Color(0xFFFFFFFF),
          ntpText: Color(0xFF1F1F1F),
        )
      : const BrowserColors(
          frame: Color(0xFF1F1F1F),
          toolbar: Color(0xFF353638),
          tabText: Color(0xFFE3E3E3),
          tabBackgroundText: Color(0xFFC4C7C5),
          icon: Color(0xFFC4C7C5),
          omnibox: Color(0xFF282828),
          omniboxText: Color(0xFFE3E3E3),
          separator: Color(0x29FFFFFF),
          ntpBackground: Color(0xFF282828),
          ntpText: Color(0xFFE3E3E3),
        );

  /// Incognito tabs always use a dark toolbar, whatever the theme.
  static const incognito = BrowserColors(
    frame: Color(0xFF1F1F1F),
    toolbar: Color(0xFF3C3C3C),
    tabText: Color(0xFFE3E3E3),
    tabBackgroundText: Color(0xFFC4C7C5),
    icon: Color(0xFFC4C7C5),
    omnibox: Color(0xFF282828),
    omniboxText: Color(0xFFE3E3E3),
    separator: Color(0x29FFFFFF),
    ntpBackground: Color(0xFF282828),
    ntpText: Color(0xFFE3E3E3),
  );

  /// A palette color: a tinted frame around a neutral toolbar.
  factory BrowserColors.fromScheme(ColorScheme s) => BrowserColors(
    frame: Color.alphaBlend(
      s.primary.withValues(
        alpha: s.brightness == Brightness.light ? 0.16 : 0.12,
      ),
      s.surfaceContainer,
    ),
    toolbar: s.surface,
    tabText: s.onSurface,
    tabBackgroundText: s.onSurfaceVariant,
    icon: s.onSurfaceVariant,
    omnibox: s.surfaceContainerHigh,
    omniboxText: s.onSurface,
    separator: s.outlineVariant,
    ntpBackground: s.surface,
    ntpText: s.onSurface,
  );

  /// Maps a Chrome theme's colors, falling back the way Chrome does: missing
  /// colors come from the default look, tinted by the theme's tints.
  factory BrowserColors.fromChromeTheme(ChromeTheme t) {
    final c = t.colors;
    final base = BrowserColors.standard(Brightness.light);
    final frame =
        c['frame'] ?? t.tints['frame']?.apply(base.frame) ?? base.frame;
    final toolbar = c['toolbar'] ?? base.toolbar;
    final onToolbar = _contrast(toolbar);
    final onFrame = _contrast(frame);
    final tabText = c['tab_text'] ?? c['bookmark_text'] ?? onToolbar;
    final toolbarDark =
        ThemeData.estimateBrightnessForColor(toolbar) == Brightness.dark;
    final ntpBackground = c['ntp_background'] ?? toolbar;
    return BrowserColors(
      frame: frame,
      toolbar: toolbar,
      tabText: tabText,
      tabBackgroundText: c['tab_background_text'] ?? onFrame,
      icon:
          c['toolbar_button_icon'] ??
          t.tints['buttons']?.apply(const Color(0xFF5F6368)) ??
          tabText.withValues(alpha: 0.8),
      omnibox:
          c['omnibox_background'] ??
          Color.alphaBlend(
            (toolbarDark ? Colors.black : const Color(0xFF0B57D0)).withValues(
              alpha: toolbarDark ? 0.25 : 0.06,
            ),
            toolbar,
          ),
      omniboxText: c['omnibox_text'] ?? onToolbar,
      separator: onFrame.withValues(alpha: 0.2),
      ntpBackground: ntpBackground,
      ntpText: c['ntp_text'] ?? _contrast(ntpBackground),
      frameImage: _file(t.frameImage),
      toolbarImage: _file(t.toolbarImage),
      ntpImage: _file(t.ntpImage),
      ntpAlignment: t.ntpAlignment,
      ntpRepeat: t.ntpRepeat,
    );
  }

  static ImageProvider? _file(File? f) => f == null ? null : FileImage(f);

  static Color _contrast(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark
      ? const Color(0xFFF1F3F4)
      : const Color(0xFF1F1F1F);

  @override
  BrowserColors copyWith({Color? frame, Color? toolbar}) => BrowserColors(
    frame: frame ?? this.frame,
    toolbar: toolbar ?? this.toolbar,
    tabText: tabText,
    tabBackgroundText: tabBackgroundText,
    icon: icon,
    omnibox: omnibox,
    omniboxText: omniboxText,
    separator: separator,
    ntpBackground: ntpBackground,
    ntpText: ntpText,
    frameImage: frameImage,
    toolbarImage: toolbarImage,
    ntpImage: ntpImage,
    ntpAlignment: ntpAlignment,
    ntpRepeat: ntpRepeat,
  );

  @override
  BrowserColors lerp(BrowserColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    final o = t < 0.5 ? this : other;
    return BrowserColors(
      frame: l(frame, other.frame),
      toolbar: l(toolbar, other.toolbar),
      tabText: l(tabText, other.tabText),
      tabBackgroundText: l(tabBackgroundText, other.tabBackgroundText),
      icon: l(icon, other.icon),
      omnibox: l(omnibox, other.omnibox),
      omniboxText: l(omniboxText, other.omniboxText),
      separator: l(separator, other.separator),
      ntpBackground: l(ntpBackground, other.ntpBackground),
      ntpText: l(ntpText, other.ntpText),
      frameImage: o.frameImage,
      toolbarImage: o.toolbarImage,
      ntpImage: o.ntpImage,
      ntpAlignment: o.ntpAlignment,
      ntpRepeat: o.ntpRepeat,
    );
  }
}

/// App theme for one brightness: Material 3 seeded from the accent, with
/// [BrowserColors] attached.
ThemeData buildTheme({
  required Brightness brightness,
  Color? seed,
  BrowserColors? colors,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed ?? _defaultSeed,
    brightness: brightness,
  );
  final browser =
      colors ??
      (seed == null
          ? BrowserColors.standard(brightness)
          : BrowserColors.fromScheme(scheme));
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    extensions: [browser],
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Theme used for a Chrome theme: its brightness follows the toolbar color,
/// whatever the light/dark setting says, as in Chrome.
ThemeData buildChromeTheme(ChromeTheme theme) {
  final colors = BrowserColors.fromChromeTheme(theme);
  final seed = theme.colors['frame'] ?? colors.frame;
  return buildTheme(brightness: colors.brightness, seed: seed, colors: colors);
}
