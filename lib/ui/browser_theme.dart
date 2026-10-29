import 'dart:io';

import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/themes/chrome_theme.dart';

/// Accent colors offered under Appearance: Apple's system colors.
const colorPalette = <(String, Color)>[
  ('Blue', Color(0xFF007AFF)),
  ('Indigo', Color(0xFF5856D6)),
  ('Purple', Color(0xFFAF52DE)),
  ('Pink', Color(0xFFFF2D55)),
  ('Red', Color(0xFFFF3B30)),
  ('Orange', Color(0xFFFF9500)),
  ('Yellow', Color(0xFFFFCC00)),
  ('Green', Color(0xFF34C759)),
  ('Mint', Color(0xFF00C7BE)),
  ('Teal', Color(0xFF30B0C7)),
  ('Cyan', Color(0xFF32ADE6)),
  ('Graphite', Color(0xFF8E8E93)),
];

const _defaultSeed = Color(0xFF007AFF);

/// Shared measurements of the interface, so every surface lines up.
abstract final class Ui {
  /// Corner radius of fields, buttons and tabs.
  static const radius = 8.0;

  /// Corner radius of menus, popovers and cards.
  static const radiusLarge = 12.0;

  /// Height of the address bar and other single-line fields in the toolbar.
  static const fieldHeight = 32.0;

  /// Snappy, Apple-like animation timing.
  static const fast = Duration(milliseconds: 140);
  static const curve = Curves.easeOutCubic;

  /// Soft shadow for raised surfaces (the selected tab, popovers).
  static List<BoxShadow> shadow(Brightness b, {double strength = 1}) => [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: (b == Brightness.light ? 0.08 : 0.35) * strength,
      ),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: Colors.black.withValues(
        alpha: (b == Brightness.light ? 0.06 : 0.25) * strength,
      ),
      blurRadius: 16 * strength,
      offset: Offset(0, 6 * strength),
    ),
  ];
}

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

  /// The built-in look: Apple's neutral greys, a light window frame with the
  /// selected tab and toolbar raised above it.
  factory BrowserColors.standard(Brightness b) => b == Brightness.light
      ? const BrowserColors(
          frame: Color(0xFFE8E8EB),
          toolbar: Color(0xFFF9F9FA),
          tabText: Color(0xFF1D1D1F),
          tabBackgroundText: Color(0xFF6E6E73),
          icon: Color(0xFF48484A),
          omnibox: Color(0xFFECECEF),
          omniboxText: Color(0xFF1D1D1F),
          separator: Color(0x1A000000),
          ntpBackground: Color(0xFFFFFFFF),
          ntpText: Color(0xFF1D1D1F),
        )
      : const BrowserColors(
          frame: Color(0xFF1C1C1E),
          toolbar: Color(0xFF2C2C2E),
          tabText: Color(0xFFF5F5F7),
          tabBackgroundText: Color(0xFF98989D),
          icon: Color(0xFFC7C7CC),
          omnibox: Color(0xFF3A3A3C),
          omniboxText: Color(0xFFF5F5F7),
          separator: Color(0x24FFFFFF),
          ntpBackground: Color(0xFF1E1E20),
          ntpText: Color(0xFFF5F5F7),
        );

  /// Private tabs always use a dark toolbar, whatever the theme.
  static const incognito = BrowserColors(
    frame: Color(0xFF161618),
    toolbar: Color(0xFF242426),
    tabText: Color(0xFFF5F5F7),
    tabBackgroundText: Color(0xFF98989D),
    icon: Color(0xFFC7C7CC),
    omnibox: Color(0xFF38383A),
    omniboxText: Color(0xFFF5F5F7),
    separator: Color(0x24FFFFFF),
    ntpBackground: Color(0xFF1A1A1C),
    ntpText: Color(0xFFF5F5F7),
  );

  /// A palette color: the neutral look with the frame faintly tinted, the
  /// way macOS lets the accent color through.
  factory BrowserColors.fromScheme(ColorScheme s) {
    final base = BrowserColors.standard(s.brightness);
    final tint = s.brightness == Brightness.light ? 0.07 : 0.08;
    return BrowserColors(
      frame: Color.alphaBlend(s.primary.withValues(alpha: tint), base.frame),
      toolbar: base.toolbar,
      tabText: base.tabText,
      tabBackgroundText: base.tabBackgroundText,
      icon: base.icon,
      omnibox: Color.alphaBlend(
        s.primary.withValues(alpha: tint / 2),
        base.omnibox,
      ),
      omniboxText: base.omniboxText,
      separator: base.separator,
      ntpBackground: base.ntpBackground,
      ntpText: base.ntpText,
    );
  }

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

/// Neutral surfaces of the app (menus, pages, dialogs) in Apple's greys,
/// with [accent] used as is for controls.
ColorScheme _neutralScheme(Color accent, Brightness brightness) {
  final light = brightness == Brightness.light;
  final base = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  // The accent as Apple draws it: the exact color, a touch lighter in dark.
  final primary = light ? accent : Color.lerp(accent, Colors.white, 0.12)!;
  final onPrimary =
      ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
      ? Colors.white
      : const Color(0xFF1D1D1F);
  final container = Color.alphaBlend(
    primary.withValues(alpha: light ? 0.12 : 0.22),
    light ? Colors.white : const Color(0xFF1C1C1E),
  );
  final onContainer = light
      ? Color.lerp(primary, Colors.black, 0.35)!
      : Color.lerp(primary, Colors.white, 0.45)!;
  return base.copyWith(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: container,
    onPrimaryContainer: onContainer,
    secondary: primary,
    onSecondary: onPrimary,
    secondaryContainer: container,
    onSecondaryContainer: onContainer,
    tertiary: primary,
    error: light ? const Color(0xFFFF3B30) : const Color(0xFFFF453A),
    onError: Colors.white,
    surface: light ? Colors.white : const Color(0xFF1C1C1E),
    onSurface: light ? const Color(0xFF1D1D1F) : const Color(0xFFF5F5F7),
    onSurfaceVariant: light ? const Color(0xFF6E6E73) : const Color(0xFF98989D),
    surfaceContainerLowest: light ? Colors.white : const Color(0xFF161618),
    surfaceContainerLow: light
        ? const Color(0xFFF9F9FA)
        : const Color(0xFF202022),
    surfaceContainer: light ? const Color(0xFFF5F5F7) : const Color(0xFF262628),
    surfaceContainerHigh: light
        ? const Color(0xFFEFEFF2)
        : const Color(0xFF2C2C2E),
    surfaceContainerHighest: light
        ? const Color(0xFFE8E8ED)
        : const Color(0xFF3A3A3C),
    surfaceTint: Colors.transparent,
    outline: light ? const Color(0xFFC7C7CC) : const Color(0xFF545458),
    outlineVariant: light ? const Color(0xFFE5E5EA) : const Color(0xFF38383A),
    inverseSurface: light ? const Color(0xFF1D1D1F) : const Color(0xFFF5F5F7),
    onInverseSurface: light ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F),
    inversePrimary: light ? Color.lerp(accent, Colors.white, 0.3) : accent,
  );
}

/// System font: SF Pro on Apple platforms (Flutter's default there), Segoe
/// UI Variable on Windows 11 with Segoe UI (which also covers Persian) as
/// the fallback.
String? get _fontFamily => defaultTargetPlatform == TargetPlatform.windows
    ? 'Segoe UI Variable Text'
    : null;

const _fontFallback = ['Segoe UI', 'Tahoma', 'Arial'];

/// Apple's type: tighter tracking on large text, none on body text.
TextTheme _textTheme(TextTheme base, Color text) {
  TextStyle? t(TextStyle? s, {double? size, FontWeight? w, double ls = 0}) =>
      s?.copyWith(
        fontSize: size,
        fontWeight: w,
        letterSpacing: ls,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      );
  return base
      .copyWith(
        displayLarge: t(base.displayLarge, w: FontWeight.w600, ls: -1.2),
        displayMedium: t(base.displayMedium, w: FontWeight.w600, ls: -1),
        displaySmall: t(base.displaySmall, w: FontWeight.w600, ls: -0.8),
        headlineLarge: t(base.headlineLarge, w: FontWeight.w600, ls: -0.6),
        headlineMedium: t(base.headlineMedium, w: FontWeight.w600, ls: -0.5),
        headlineSmall: t(base.headlineSmall, w: FontWeight.w600, ls: -0.4),
        titleLarge: t(base.titleLarge, size: 20, w: FontWeight.w600, ls: -0.3),
        titleMedium: t(base.titleMedium, size: 15, w: FontWeight.w600),
        titleSmall: t(base.titleSmall, size: 13, w: FontWeight.w600),
        bodyLarge: t(base.bodyLarge, size: 14.5),
        bodyMedium: t(base.bodyMedium, size: 13.5),
        bodySmall: t(base.bodySmall, size: 12),
        labelLarge: t(base.labelLarge, size: 13.5, w: FontWeight.w500),
        labelMedium: t(base.labelMedium, size: 12, w: FontWeight.w500),
        labelSmall: t(base.labelSmall, size: 11, w: FontWeight.w500),
      )
      .apply(bodyColor: text, displayColor: text);
}

/// Pages fade in softly instead of Material's zoom.
const _pageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
  },
);

/// App theme for one brightness: Apple-style neutral surfaces, the accent
/// from [seed] on controls, no ink ripples, and [BrowserColors] attached.
ThemeData buildTheme({
  required Brightness brightness,
  Color? seed,
  BrowserColors? colors,
}) {
  final light = brightness == Brightness.light;
  final scheme = _neutralScheme(seed ?? _defaultSeed, brightness);
  final browser =
      colors ??
      (seed == null
          ? BrowserColors.standard(brightness)
          : BrowserColors.fromScheme(scheme));
  final hairline = scheme.outlineVariant;
  final menuSurface = light ? Colors.white : const Color(0xFF2C2C2E);
  final menuShadow = Colors.black.withValues(alpha: light ? 0.30 : 0.6);
  final small = BorderRadius.circular(Ui.radius);
  final large = BorderRadius.circular(Ui.radiusLarge);
  final typography = Typography.material2021(platform: defaultTargetPlatform);
  final textTheme = _textTheme(
    light ? typography.black : typography.white,
    scheme.onSurface,
  );
  final buttonText = textTheme.labelLarge?.copyWith(
    fontWeight: FontWeight.w600,
  );
  final buttonShape = WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: small),
  );
  const buttonPadding = WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  );
  WidgetStateProperty<Color?> overlay(Color base) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return base.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return base.withValues(alpha: 0.06);
        }
        return null;
      });

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: brightness,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    textTheme: textTheme,
    extensions: [browser],
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    // No Material ink ripples: Apple controls just highlight.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: scheme.onSurface.withValues(alpha: light ? 0.08 : 0.12),
    hoverColor: scheme.onSurface.withValues(alpha: light ? 0.045 : 0.07),
    focusColor: scheme.primary.withValues(alpha: 0.12),
    dividerColor: hairline,
    pageTransitionsTheme: _pageTransitions,
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: light
          ? const Color(0xFFF9F9FA)
          : const Color(0xFF242426),
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 52,
      titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 17),
      shape: Border(bottom: BorderSide(color: hairline)),
    ),
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(CupertinoIcons.chevron_left),
      closeButtonIconBuilder: (_) => const Icon(CupertinoIcons.xmark),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        overlayColor: overlay(scheme.onSurface),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 600),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      textStyle: TextStyle(
        fontSize: 12,
        color: light ? Colors.white : const Color(0xFF1D1D1F),
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
      decoration: BoxDecoration(
        color: light ? const Color(0xF21D1D1F) : const Color(0xF2F5F5F7),
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(menuSurface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        shadowColor: WidgetStatePropertyAll(menuShadow),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: large,
            side: BorderSide(color: hairline),
          ),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: menuSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shadowColor: menuShadow,
      menuPadding: const EdgeInsets.symmetric(vertical: 5),
      textStyle: textTheme.bodyMedium,
      labelTextStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
      shape: RoundedRectangleBorder(
        borderRadius: large,
        side: BorderSide(color: hairline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: menuSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 17),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: menuSurface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.outline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: light
          ? const Color(0xF21D1D1F)
          : const Color(0xFF3A3A3C),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      actionTextColor: light ? const Color(0xFF64A8FF) : scheme.primary,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: large),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: light ? Colors.white : const Color(0xFF242426),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: large,
        side: BorderSide(color: hairline),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: small),
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: textTheme.bodyLarge,
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      selectedColor: scheme.primary,
      selectedTileColor: scheme.primary.withValues(alpha: 0.10),
      minLeadingWidth: 24,
    ),
    switchTheme: SwitchThemeData(
      // iOS style: a white knob on the accent (or grey) track, no outline.
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : (light ? const Color(0xFFE5E5EA) : const Color(0xFF39393D)),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: scheme.outline, width: 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: WidgetStatePropertyAll(buttonText),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: WidgetStatePropertyAll(buttonText),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: WidgetStatePropertyAll(buttonText),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        textStyle: WidgetStatePropertyAll(buttonText),
        overlayColor: overlay(scheme.primary),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        side: WidgetStatePropertyAll(BorderSide(color: hairline)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: small),
      side: BorderSide(color: hairline),
      backgroundColor: scheme.surfaceContainerLow,
      labelStyle: textTheme.labelLarge,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? const Color(0xFFF2F2F5) : const Color(0xFF2C2C2E),
      hoverColor: Colors.transparent,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: small,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: small,
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: small,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: small,
        borderSide: BorderSide(color: scheme.error),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: Colors.transparent,
      circularTrackColor: Colors.transparent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(7),
      thumbColor: WidgetStatePropertyAll(
        scheme.onSurface.withValues(alpha: light ? 0.28 : 0.35),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: menuSurface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
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
