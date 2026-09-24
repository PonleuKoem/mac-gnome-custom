import 'dart:io';

import 'package:flutter/material.dart';

import '../core/algorithms.dart';
import '../core/shell_controller.dart';
import '../surfaces/top_bar.dart';
import '../theme/shell_theme.dart';
import '../widgets/common.dart';

/// A miniature of the desktop as [theme] draws it: wallpaper, top bar, dock
/// (position, style, size, magnification room), all laid out at the real
/// screen size and scaled down as one picture, so proportions — and the
/// interface size — are exactly what the screen shows.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.theme, this.showWindow = true});

  final ShellTheme theme;

  /// Draw a sample app window, to show the space left for apps.
  final bool showWindow;

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.maybeOf(context);
    final main = ctrl?.surfaces.mainScreen;
    final screen = main == null ? const Size(1512, 982) : Size(main.frame.w, main.frame.h);
    final menuBar = main?.menuBarHeight ?? 37;
    return AspectRatio(
      aspectRatio: screen.width / screen.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox.fromSize(
            size: screen,
            child: _Desktop(theme: theme, screen: screen, menuBar: menuBar, showWindow: showWindow),
          ),
        ),
      ),
    );
  }
}

class _Desktop extends StatelessWidget {
  const _Desktop({required this.theme, required this.screen, required this.menuBar, required this.showWindow});

  final ShellTheme theme;
  final Size screen;
  final double menuBar;
  final bool showWindow;

  @override
  Widget build(BuildContext context) {
    final layout = theme.layout;
    final dock = layout.dockMode == DockMode.always ? _dockRect() : null;
    // Space apps get: below the bar, clear of an always-on dock that keeps
    // windows clear of it.
    var usable = Rect.fromLTRB(0, menuBar, screen.width, screen.height);
    if (dock != null && layout.reserveDockSpace) {
      usable = switch (layout.dockPosition) {
        DockPosition.bottom => Rect.fromLTRB(0, menuBar, screen.width, dock.top - 4),
        DockPosition.left => Rect.fromLTRB(dock.right + 4, menuBar, screen.width, screen.height),
        DockPosition.right => Rect.fromLTRB(0, menuBar, dock.left - 4, screen.height),
      };
    }
    return Stack(
      children: [
        Positioned.fill(child: _Wallpaper(theme: theme)),
        if (showWindow)
          Positioned.fromRect(
            rect: Rect.fromLTRB(
              usable.left + usable.width * 0.12,
              usable.top + usable.height * 0.1,
              usable.right - usable.width * 0.12,
              usable.bottom - usable.height * 0.08,
            ),
            child: const _SampleWindow(),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: menuBar,
          child: layout.topBarEnabled
              ? TopBarPreview(theme: theme, barWidth: screen.width, barHeight: menuBar)
              : const _MacMenuBar(),
        ),
        if (dock != null)
          Positioned.fromRect(
            rect: dock,
            child: _PreviewDock(theme: theme),
          ),
        if (layout.dockMode == DockMode.overviewOnly)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(40)),
                child: const Text(
                  'Dock appears in Activities',
                  style: TextStyle(color: Colors.white, fontSize: 26, decoration: TextDecoration.none),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Same geometry as ShellController.dockRestRect.
  Rect _dockRect() {
    final layout = theme.layout;
    final vertical = layout.dockPosition != DockPosition.bottom;
    final count = _items(theme).length + _buttons(theme).length;
    final dock = dockSize(items: count, iconSize: layout.dockIconSize, vertical: vertical);
    final depth = vertical ? dock.width : dock.height;
    final length = vertical ? dock.height : dock.width;
    if (layout.dockStyle == DockStyle.panel) {
      return switch (layout.dockPosition) {
        DockPosition.bottom => Rect.fromLTWH(0, screen.height - depth, screen.width, depth),
        DockPosition.left => Rect.fromLTWH(0, menuBar, depth, screen.height - menuBar),
        DockPosition.right => Rect.fromLTWH(screen.width - depth, menuBar, depth, screen.height - menuBar),
      };
    }
    final w = vertical ? depth : length.clamp(0.0, screen.width - 16);
    final h = vertical ? length.clamp(0.0, screen.height - menuBar - 16) : depth;
    return switch (layout.dockPosition) {
      DockPosition.bottom => Rect.fromLTWH((screen.width - w) / 2, screen.height - h - 8, w, h),
      DockPosition.left => Rect.fromLTWH(8, (screen.height - h) / 2, w, h),
      DockPosition.right => Rect.fromLTWH(screen.width - w - 8, (screen.height - h) / 2, w, h),
    };
  }
}

List<String> _items(ShellTheme theme) => theme.layout.pinned.take(8).toList();

List<IconData> _buttons(ShellTheme theme) => [
  if (theme.layout.showAppGridButton) Icons.apps_rounded,
  if (theme.layout.showCustomizerButton) Icons.tune_rounded,
];

class _PreviewDock extends StatelessWidget {
  const _PreviewDock({required this.theme});
  final ShellTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme.tokens;
    final layout = theme.layout;
    final panel = layout.dockStyle == DockStyle.panel;
    final vertical = layout.dockPosition != DockPosition.bottom;
    final size = layout.dockIconSize;
    final pad = size * 0.18;
    Widget slot(Widget child, {bool dot = false}) => Padding(
      padding: EdgeInsets.all(pad / 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(dimension: size, child: child),
          SizedBox(
            height: 6,
            child: dot && layout.showRunningDots
                ? Center(
                    child: Container(
                      width: 5,
                      height: 4,
                      decoration: BoxDecoration(color: t.dockFg, borderRadius: BorderRadius.circular(2)),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
    final items = _items(theme);
    final children = [
      for (final (i, b) in items.indexed)
        slot(
          _PlateIcon(theme: theme, bundleId: b, size: size),
          dot: i < 2,
        ),
      if (panel) const Spacer(),
      for (final g in _buttons(theme)) slot(Icon(g, size: size * 0.6, color: t.dockFg)),
    ];
    final flex = Flex(
      direction: vertical ? Axis.vertical : Axis.horizontal,
      mainAxisSize: panel ? MainAxisSize.max : MainAxisSize.min,
      children: children,
    );
    return Container(
      decoration: BoxDecoration(color: t.dockBg, borderRadius: BorderRadius.circular(panel ? 0 : t.radius('dock'))),
      padding: EdgeInsets.all(pad / 2),
      // A floating dock longer than the screen is squeezed, as on screen.
      child: panel ? flex : FittedBox(fit: BoxFit.scaleDown, child: flex),
    );
  }
}

/// The app's icon framed the way [theme] frames dock icons.
class _PlateIcon extends StatelessWidget {
  const _PlateIcon({required this.theme, required this.bundleId, required this.size});

  final ShellTheme theme;
  final String bundleId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = theme.tokens;
    // AppIcon below 32 pt is always the plain icon; scale it up here.
    final icon = FittedBox(child: AppIcon(bundleId, size: 31));
    if (t.iconShape == IconShape.native) return icon;
    final ShapeBorder shape = switch (t.iconShape) {
      IconShape.circle => const CircleBorder(),
      IconShape.squircle => ContinuousRectangleBorder(borderRadius: BorderRadius.circular(size * 0.6)),
      _ => RoundedRectangleBorder(borderRadius: BorderRadius.circular(size * 0.22)),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, color: t.iconPlate),
      child: Padding(padding: EdgeInsets.all(size * 0.16), child: icon),
    );
  }
}

class _Wallpaper extends StatelessWidget {
  const _Wallpaper({required this.theme});
  final ShellTheme theme;

  @override
  Widget build(BuildContext context) {
    final dark = switch (theme.system.appearance) {
      Appearance.dark => true,
      Appearance.light => false,
      Appearance.untouched => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final path = theme.system.wallpaperFor(dark: dark);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.tokens.surface, theme.tokens.accent.withValues(alpha: 0.7)],
        ),
      ),
    );
    if (path == null || !File(path).existsSync()) return fallback;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 640,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// A plain window, so the preview shows where apps go.
class _SampleWindow extends StatelessWidget {
  const _SampleWindow();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF2F6F6F6),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 10))],
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)])
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The macOS menu bar, for themes that keep it.
class _MacMenuBar extends StatelessWidget {
  const _MacMenuBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x66FFFFFF),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.centerLeft,
      child: const Icon(Icons.apple, size: 18, color: Color(0xFF1D1D1F)),
    );
  }
}
