import 'package:flutter/widgets.dart';

/// A fully resolved theme (ADR-0009): defaults → extends chain → theme file →
/// user overrides. Immutable; every surface reads from it and nothing else.
@immutable
class ShellTheme {
  const ShellTheme({
    required this.id,
    required this.name,
    required this.tokens,
    required this.layout,
    required this.system,
    required this.keybindings,
    required this.iconPackDir,
    required this.sourceDir,
    required this.raw,
    this.warnings = const [],
    this.degraded = false,
  });

  final String id;
  final String name;
  final ShellTokens tokens;
  final ShellLayout layout;
  final SystemBlock system;

  /// action → chord ("superTap", "cmd+tab", …).
  final Map<String, String> keybindings;

  /// Absolute directory holding `<bundleId>.png` overrides, if any.
  final String? iconPackDir;

  /// Directory the theme was loaded from (null for asset presets).
  final String? sourceDir;

  /// The merged JSON this theme was built from (for export / editing).
  final Map<String, dynamic> raw;
  final List<String> warnings;

  /// True when the requested theme could not be loaded and defaults stand in.
  /// A degraded theme is shown, but its `system` block is never applied.
  final bool degraded;

  ShellTheme copyWith({String? iconPackDir, String? sourceDir, List<String>? warnings, bool? degraded}) => ShellTheme(
    id: id,
    name: name,
    tokens: tokens,
    layout: layout,
    system: system,
    keybindings: keybindings,
    iconPackDir: iconPackDir ?? this.iconPackDir,
    sourceDir: sourceDir ?? this.sourceDir,
    raw: raw,
    warnings: warnings ?? this.warnings,
    degraded: degraded ?? this.degraded,
  );
}

@immutable
class ShellTokens {
  const ShellTokens({
    required this.colors,
    required this.fontFamily,
    required this.barFontSize,
    required this.barFontWeight,
    required this.bodyFontSize,
    required this.radii,
    required this.blur,
    required this.overviewDuration,
    required this.curve,
    this.iconShape = IconShape.native,
    this.widgetWeights = const {},
    this.scrimTexture = ScrimTexture.none,
    this.textureStrength = 0.1,
    this.scale = 1,
  });

  final Map<String, Color> colors;
  final String fontFamily;
  final double barFontSize;
  final FontWeight barFontWeight;
  final double bodyFontSize;
  final Map<String, double> radii;
  final Map<String, double> blur;
  final Duration overviewDuration;
  final Curve curve;

  /// How app icons are framed in the dock and launcher (`tokens.icon.shape`).
  final IconShape iconShape;

  /// Per-widget top-bar font weight (`tokens.font.weight.clock`, …); widgets
  /// not listed use `weight.bar`.
  final Map<String, FontWeight> widgetWeights;

  /// Printed texture over the launcher backdrop (`tokens.texture`).
  final ScrimTexture scrimTexture;
  final double textureStrength;

  /// Interface size (`tokens.scale`), already applied to font sizes, radii
  /// and icon sizes; surfaces use it for their own fixed dimensions.
  final double scale;

  /// [v] at this theme's interface size.
  double px(double v) => v * scale;

  Color color(String key) => colors[key] ?? const Color(0xFFFF00FF);
  double radius(String key) => radii[key] ?? 8;
  double blurOf(String key) => blur[key] ?? 0;

  Color get barBg => color('bar.bg');
  Color get barFg => color('bar.fg');
  Color get accent => color('accent');
  Color get surface => color('surface');
  Color get surfaceFg => color('surface.fg');
  Color get scrim => color('overview.scrim');
  Color get dockBg => color('dock.bg');
  Color get popoverBg => color('popover.bg');
  Color get popoverFg => color('popover.fg');
  Color get tileBg => color('tile.bg');
  Color get selection => color('tile.selected');
  Color get iconPlate => color('icon.plate');

  /// Hairline under the top bar (transparent by default).
  Color get barBorder => color('bar.border');

  /// Dock foreground: running dots and the app-grid glyph. Defaults to
  /// surface.fg when a theme doesn't set it (see ThemeParser).
  Color get dockFg => color('dock.fg');

  FontWeight weightFor(String widget) => widgetWeights[widget] ?? barFontWeight;

  static const fontFallback = ['.AppleSystemUIFont', 'Helvetica Neue', 'Arial'];

  TextStyle barText() => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: barFontSize,
    fontWeight: barFontWeight,
    color: barFg,
    decoration: TextDecoration.none,
  );

  TextStyle body({Color? color, double? size, FontWeight? weight}) => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: size ?? bodyFontSize,
    fontWeight: weight ?? FontWeight.w400,
    color: color ?? surfaceFg,
    decoration: TextDecoration.none,
  );
}

/// `native` shows the app's own icon; the others draw a plate in `icon.plate`
/// with the icon inset on it (Android-style circles, iOS-style squircles…).
enum IconShape { native, circle, squircle, rounded }

/// `halftone`: a print-style dot screen, denser towards the bottom.
/// `grain`: fine paper/film noise.
enum ScrimTexture { none, halftone, grain }

enum DockMode { off, overviewOnly, always }

/// `floating`: a rounded island sized to its icons. `panel`: spans the whole
/// screen edge (Ubuntu-style), icons from the start, app grid at the end.
enum DockStyle { floating, panel }

enum DockPosition { bottom, left, right }

@immutable
class ShellLayout {
  const ShellLayout({
    required this.topBarEnabled,
    required this.left,
    required this.center,
    required this.right,
    required this.clockFormat,
    required this.dockMode,
    required this.dockPosition,
    required this.dockIconSize,
    required this.showRunningDots,
    required this.pinned,
    required this.showAppGridButton,
    this.showCustomizerButton = true,
    this.reserveDockSpace = true,
    this.dockMagnification = 1.5,
    this.dockStyle = DockStyle.floating,
    this.launcherIconSize = 72,
    this.launcherLabels = true,
  });

  final bool topBarEnabled;
  final List<String> left;
  final List<String> center;
  final List<String> right;
  final String clockFormat;
  final DockMode dockMode;
  final DockPosition dockPosition;
  final double dockIconSize;
  final bool showRunningDots;
  final List<String> pinned;
  final bool showAppGridButton;

  /// ⚙ tile at the end of the dock that opens the Customizer.
  final bool showCustomizerButton;

  /// Keep windows clear of an always-visible dock (maximize, tiling, zoom),
  /// like the macOS Dock. Uses the native Dock as a hidden spacer.
  final bool reserveDockSpace;

  /// macOS-style zoom of the icon under the pointer (1 = off, 2 = double).
  final double dockMagnification;
  final DockStyle dockStyle;

  /// Launcher (Activities) grid: icon size and whether names show under icons.
  final double launcherIconSize;
  final bool launcherLabels;
}

enum Appearance { light, dark, untouched }

@immutable
class SystemBlock {
  const SystemBlock({
    required this.appearance,
    required this.accent,
    required this.wallpaperLight,
    required this.wallpaperDark,
    required this.hideNativeDock,
  });

  final Appearance appearance;

  /// macOS accent index (-1 graphite … 6 pink), 99 = multicolor, null = untouched.
  final int? accent;

  /// Absolute paths (resolved against the theme folder).
  final String? wallpaperLight;
  final String? wallpaperDark;
  final bool hideNativeDock;

  String? wallpaperFor({required bool dark}) =>
      dark ? (wallpaperDark ?? wallpaperLight) : (wallpaperLight ?? wallpaperDark);
}

/// macOS accent names ↔ `AppleAccentColor` values.
const accentNames = <String, int>{
  'graphite': -1,
  'red': 0,
  'orange': 1,
  'yellow': 2,
  'green': 3,
  'blue': 4,
  'purple': 5,
  'pink': 6,
  'multicolor': 99,
};

/// Every action a keybinding can trigger, with a label for the Customizer.
/// Interface-only scope (ADR-0012): shortcuts open shell surfaces; none of
/// them control other apps' windows.
const keybindingActions = <String, String>{'overview': 'Activities (launcher)', 'appGrid': 'Show applications'};

/// Widgets the top bar can host (layout-as-data, DESIGN.md §4.5).
const topBarWidgets = <String, String>{
  'activities': 'Activities button',
  'appName': 'Name of the active app',
  'clock': 'Clock & calendar',
  'indicators': 'Status icons & quick settings',
  'appGrid': 'Show applications button',
  'spacer': 'Flexible space',
};
