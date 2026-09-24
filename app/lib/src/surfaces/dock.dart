import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shellkit/shellkit.dart';

import '../core/algorithms.dart';
import '../core/shell_controller.dart';
import '../theme/shell_theme.dart';
import '../widgets/common.dart';

/// The dock panel (modes `always` / `intellihide`). In `overviewOnly` mode the
/// same [DockBar] is drawn inside the overview as GNOME's dash.
///
/// The dock sits against its screen edge; while the pointer is over it the
/// window grows away from the edge (see ShellController.dockRect) so
/// magnified icons have room, which is why everything here is edge-aligned.
class DockSurface extends StatefulWidget {
  const DockSurface({super.key});

  @override
  State<DockSurface> createState() => _DockSurfaceState();
}

class _DockSurfaceState extends State<DockSurface> {
  final _label = _DockLabelController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _label.ctrl = Shell.of(context);
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final theme = ShellThemeScope.of(context);
    final main = ctrl.surfaces.mainScreen;
    final strip = main == null ? null : ctrl.dockStrip(main);
    final panel = theme.layout.dockStyle == DockStyle.panel;
    final Widget content;
    if (strip != null && main != null) {
      content = _StripDock(strip: strip, screen: main);
    } else {
      final bar = DockBar(
        panel: panel,
        magnify: true,
        // Evaluated when a menu opens: the dock moves as apps launch and quit.
        surfaceOrigin: () {
          final main = ctrl.surfaces.mainScreen;
          return main == null ? Offset.zero : ctrl.dockRect(main).topLeft;
        },
        closeOverviewOnLaunch: false,
      );
      content = _edgeAligned(theme.layout.dockPosition, panel, bar);
    }
    return _DockLabelScope(
      controller: _label,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          Positioned(
            left: 0,
            top: 0,
            child: _DockLabel(controller: _label, edge: theme.layout.dockPosition),
          ),
        ],
      ),
    );
  }
}

/// The hover card over a dock icon: the app's name and one card per open
/// window. With window previews on (opt-in, ADR-0012) the cards are live
/// pictures — or titles, while only Accessibility is allowed — and clicking
/// one brings exactly that window forward. With previews off the shell only
/// counts windows (no permission), so the cards are placeholders plus a way
/// to turn previews on.
class _DockLabelController extends ChangeNotifier {
  final link = LayerLink();
  final cardKey = GlobalKey();
  ShellController? ctrl;

  /// App whose card is showing.
  String? target;

  /// Its on-screen window count (needs no permission).
  int? windows;

  /// Its windows, when previews are on (may include minimized ones).
  List<WindowSummary>? list;

  /// Previews are on but macOS hasn't granted access yet.
  bool needsAccess = false;
  bool _overLabel = false;
  Timer? _dwell;
  Timer? _hide;

  /// Pointer entered/left an icon. The first card waits a moment (so a
  /// pointer passing over the dock doesn't flash cards); once one shows,
  /// moving along the dock switches instantly, as on macOS.
  void iconHover(String bundleId, bool inside) {
    if (inside) {
      _hide?.cancel();
      if (target != null) {
        _show(bundleId);
      } else {
        _dwell?.cancel();
        _dwell = Timer(const Duration(milliseconds: 350), () => _show(bundleId));
      }
    } else {
      _dwell?.cancel();
      _scheduleHide();
    }
  }

  void labelHover(bool inside) {
    _overLabel = inside;
    if (inside) {
      _hide?.cancel();
    } else {
      _scheduleHide();
    }
  }

  void dismiss() {
    _dwell?.cancel();
    _hide?.cancel();
    _overLabel = false;
    if (target == null) return;
    target = null;
    notifyListeners();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 200), () {
      if (_overLabel || target == null) return;
      target = null;
      notifyListeners();
    });
  }

  Future<void> _show(String bundleId) async {
    if (target == bundleId) return;
    target = bundleId;
    windows = null;
    list = null;
    needsAccess = false;
    notifyListeners();
    final c = ctrl;
    if (c == null || c.apps.runningApp(bundleId) == null) return;
    try {
      final n = await c.bridge.apps.windowCount(bundleId);
      if (target != bundleId) return;
      windows = n;
      notifyListeners();
      if (!c.windowThumbnails) return;
      // 2× for Retina; natively empty unless the user opted in.
      final found = await c.bridge.apps.windows(bundleId, (_WindowCard.width * 2).round());
      if (target != bundleId) return;
      list = found;
      // Picking a window needs Accessibility; say so rather than letting a
      // click do nothing.
      final p = await c.bridge.diagnostics.thumbnailPermissions();
      needsAccess = !p.accessibility;
      if (target == bundleId) notifyListeners();
    } catch (_) {}
  }

  /// Tells the shell where the card is, so only it (not the dock window's
  /// empty room) takes clicks. Called after each layout of the card.
  void reportCard() {
    Rect? rect;
    final box = cardKey.currentContext?.findRenderObject();
    if (target != null && box is RenderBox && box.attached && box.hasSize) {
      // The dock's view is its whole window: global = window coordinates.
      // A little margin covers the card following a magnifying icon.
      rect = (box.localToGlobal(Offset.zero) & box.size).inflate(12);
    }
    ctrl?.setDockCardRect(rect);
  }

  @override
  void dispose() {
    _dwell?.cancel();
    _hide?.cancel();
    ctrl?.setDockCardRect(null);
    super.dispose();
  }
}

/// One window in the hover card: its picture (or, without one, the app's
/// icon) and its title. [onTap] null: a placeholder that can't pick a window.
class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.bundleId, required this.title, this.window, this.onTap});

  static const width = 150.0;
  final String bundleId;
  final String title;
  final WindowSummary? window;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShellThemeScope.of(context).tokens;
    final w = window;
    final png = w?.thumbnail;
    final aspect = w == null || w.width <= 0 ? 0.62 : (w.height / w.width).clamp(0.45, 0.8);
    final tap = onTap;
    return Hover(
      cursor: tap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onTap: tap,
      builder: (context, hovered) {
        final lit = hovered && tap != null;
        return Container(
          width: width + 12,
          padding: const EdgeInsets.all(5),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: lit ? t.accent.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: lit ? t.accent : const Color(0x00000000), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: width,
                height: width * aspect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: png != null
                      ? Image.memory(
                          png,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        )
                      : ColoredBox(
                          color: t.popoverFg.withValues(alpha: tap == null ? 0.05 : 0.1),
                          child: Center(
                            child: Opacity(
                              opacity: tap == null ? 0.45 : 0.9,
                              child: SizedBox.square(
                                dimension: 30,
                                child: FittedBox(child: AppIcon(bundleId, size: 31)),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.body(color: t.popoverFg.withValues(alpha: tap == null ? 0.6 : 1), size: 11),
              ),
              if (w?.minimized ?? false)
                Text('minimized', style: t.body(color: t.popoverFg.withValues(alpha: 0.55), size: 10)),
            ],
          ),
        );
      },
    );
  }
}

class _DockLabelScope extends InheritedNotifier<_DockLabelController> {
  const _DockLabelScope({required _DockLabelController controller, required super.child}) : super(notifier: controller);

  static _DockLabelController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DockLabelScope>()?.notifier;
}

class _DockLabel extends StatelessWidget {
  const _DockLabel({required this.controller, required this.edge});

  final _DockLabelController controller;
  final DockPosition edge;

  static const _maxCards = 6;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => controller.reportCard());
        final bundleId = controller.target;
        final ctrl = controller.ctrl;
        if (bundleId == null || ctrl == null) return const SizedBox.shrink();
        final t = ShellThemeScope.of(context).tokens;
        final running = ctrl.apps.runningApp(bundleId) != null;
        final list = controller.list;
        final n = list != null && list.isNotEmpty ? list.length : controller.windows;
        final (target, follower, offset) = switch (edge) {
          DockPosition.bottom => (Alignment.topCenter, Alignment.bottomCenter, const Offset(0, -8)),
          DockPosition.left => (Alignment.centerRight, Alignment.centerLeft, const Offset(8, 0)),
          DockPosition.right => (Alignment.centerLeft, Alignment.centerRight, const Offset(-8, 0)),
        };
        final muted = t.body(color: t.popoverFg.withValues(alpha: 0.65), size: 12);

        // Cards: real windows when previews listed them; placeholders when
        // there are several windows but no way (yet) to tell them apart.
        final cards = <Widget>[];
        String? hint;
        String? action;
        VoidCallback? onAction;
        if (running && list != null && list.isNotEmpty) {
          if (controller.needsAccess) {
            hint = 'To switch to one window, allow Accessibility.';
            action = 'Set up…';
            onAction = () {
              controller.dismiss();
              ctrl.openCustomizer(page: 'windows');
            };
          }
          for (final w in list.take(_maxCards)) {
            cards.add(
              _WindowCard(
                bundleId: bundleId,
                title: w.title.isEmpty ? 'Untitled window' : w.title,
                window: w,
                onTap: () {
                  controller.dismiss();
                  ctrl.bridge.apps.focusWindow(bundleId, w.id);
                },
              ),
            );
          }
        } else if (running && (n ?? 0) >= 2) {
          for (var i = 0; i < math.min(n!, _maxCards); i++) {
            cards.add(_WindowCard(bundleId: bundleId, title: 'Window ${i + 1}'));
          }
          if (!ctrl.windowThumbnails) {
            hint = 'Turn on window previews to see each window and switch to it.';
            action = 'Turn on previews…';
            onAction = () {
              controller.dismiss();
              ctrl.enableWindowPreviews();
            };
          } else if (controller.needsAccess) {
            hint = 'Window previews need your permission in System Settings.';
            action = 'Set up…';
            onAction = () {
              controller.dismiss();
              ctrl.openCustomizer(page: 'windows');
            };
          }
        }
        final more = (n ?? 0) - cards.length;

        return CompositedTransformFollower(
          link: controller.link,
          showWhenUnlinked: false,
          targetAnchor: target,
          followerAnchor: follower,
          offset: offset,
          child: MouseRegion(
            onEnter: (_) => controller.labelHover(true),
            onExit: (_) => controller.labelHover(false),
            child: Container(
              key: controller.cardKey,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: cards.isEmpty ? 6 : 10),
              decoration: BoxDecoration(
                color: t.popoverBg,
                borderRadius: BorderRadius.circular(t.radius('popover').clamp(0, cards.isEmpty ? 10 : 14)),
                border: Border.all(color: t.popoverFg.withValues(alpha: 0.12)),
                boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ctrl.apps.nameFor(bundleId),
                        style: t.body(color: t.popoverFg, size: 13, weight: FontWeight.w600),
                      ),
                      if (running && n != null && (n != 1 || cards.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(switch (n) {
                            0 => 'no open windows',
                            1 => '1 window',
                            _ => '$n windows',
                          }, style: muted),
                        ),
                    ],
                  ),
                  if (cards.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...cards,
                          if (more > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 6, top: 30),
                              child: Text('+$more', style: muted),
                            ),
                        ],
                      ),
                    ),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(hint, style: muted),
                          const SizedBox(width: 10),
                          Hover(
                            cursor: SystemMouseCursors.click,
                            onTap: onAction!,
                            builder: (context, hovered) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: t.accent.withValues(alpha: hovered ? 1 : 0.85),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                action!,
                                style: t.body(color: const Color(0xFFFFFFFF), size: 12, weight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pins [bar] to the dock's screen edge; a panel also fills the edge.
Widget _edgeAligned(DockPosition position, bool panel, Widget bar, {EdgeInsets margin = EdgeInsets.zero}) {
  final vertical = position != DockPosition.bottom;
  final alignment = switch (position) {
    DockPosition.bottom => Alignment.bottomCenter,
    DockPosition.left => Alignment.centerLeft,
    DockPosition.right => Alignment.centerRight,
  };
  final child = panel
      ? SizedBox(width: vertical ? null : double.infinity, height: vertical ? double.infinity : null, child: bar)
      : bar;
  return Align(
    alignment: alignment,
    child: Padding(padding: margin, child: child),
  );
}

/// The dock while macOS reserves its strip (the native Dock sits underneath
/// as a spacer). The whole strip is painted — the theme's wallpaper, cropped
/// to exactly where it sits on screen, or an opaque dock colour — so nothing
/// of the native Dock shows, and a floating island keeps its look. While the
/// window is grown for magnification, only the strip itself is painted.
class _StripDock extends StatelessWidget {
  const _StripDock({required this.strip, required this.screen});

  final Rect strip;
  final ScreenInfo screen;

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final theme = ShellThemeScope.of(context);
    final t = theme.tokens;
    final layout = theme.layout;
    final panel = layout.dockStyle == DockStyle.panel;
    final dark = switch (theme.system.appearance) {
      Appearance.dark => true,
      Appearance.light => false,
      Appearance.untouched => ctrl.system.value?.darkMode ?? false,
    };
    final path = theme.system.wallpaperFor(dark: dark);
    final wallpaper = path != null && File(path).existsSync() ? path : null;
    final window = ctrl.dockRect(screen);
    final local = strip.shift(-window.topLeft);
    // Fit the icons to the strip macOS actually reserved (it follows the
    // native Dock's sizing, which is close to but not exactly ours).
    final vertical = layout.dockPosition != DockPosition.bottom;
    final stripDepth = vertical ? strip.width : strip.height;
    final depth = stripDepth - (panel ? 0 : 16);
    final maxIcon = (depth - 6) / 1.36;
    final size = layout.dockIconSize.clamp(16.0, maxIcon < 16 ? 16.0 : maxIcon);
    final thickness = dockSize(items: 1, iconSize: size, vertical: false).height;
    final inset = panel ? 0.0 : (stripDepth - thickness) / 2;
    final bar = DockBar(
      panel: panel,
      magnify: true,
      ownBackdrop: true,
      maxIconSize: maxIcon,
      backgroundThickness: panel ? stripDepth : null,
      surfaceOrigin: () => ctrl.dockRect(screen).topLeft,
      closeOverviewOnLaunch: false,
    );
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fromRect(
          rect: local,
          child: ClipRect(
            child: wallpaper != null
                ? Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned(
                        left: -strip.left,
                        top: -strip.top,
                        width: screen.frame.w,
                        height: screen.frame.h,
                        // macOS "Fill Screen": scale to cover, centred.
                        // Decoded at screen width (not full resolution) and kept on
                        // its own layer, so magnifying never repaints it.
                        child: RepaintBoundary(
                          child: Image.file(
                            File(wallpaper),
                            fit: BoxFit.cover,
                            cacheWidth: (screen.frame.w * screen.scale).round(),
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, _, _) => ColoredBox(color: t.dockBg.withValues(alpha: 1)),
                          ),
                        ),
                      ),
                    ],
                  )
                : ColoredBox(color: t.dockBg.withValues(alpha: 1)),
          ),
        ),
        _edgeAligned(
          layout.dockPosition,
          panel,
          bar,
          margin: switch (layout.dockPosition) {
            DockPosition.bottom => EdgeInsets.only(bottom: inset),
            DockPosition.left => EdgeInsets.only(left: inset),
            DockPosition.right => EdgeInsets.only(right: inset),
          },
        ),
      ],
    );
  }
}

class DockBar extends StatefulWidget {
  const DockBar({
    super.key,
    required this.surfaceOrigin,
    required this.closeOverviewOnLaunch,
    this.panel = false,
    this.horizontal = false,
    this.ownBackdrop = false,
    this.magnify = false,
    this.maxIconSize,
    this.backgroundThickness,
  });

  /// See [ShellPanelBox.ownBackdrop].
  final bool ownBackdrop;

  /// macOS-style magnification on hover (`layout.dock.magnification`). Off
  /// for the dash inside the launcher.
  final bool magnify;

  /// Cap on the icon size so the dock fits a given depth (icon + 36% padding
  /// + 6 pt indicator row, as in [dockSize]).
  final double? maxIconSize;

  /// Depth of the background bar, when it must match a reserved strip.
  final double? backgroundThickness;

  /// Always lay out in a row, whatever the dock position: the dash at the
  /// bottom of the launcher.
  final bool horizontal;

  /// Fill the whole surface (a `panel` dock): square edges, icons from the
  /// start, the app-grid button pushed to the far end. The dash inside the
  /// launcher is always a floating island.
  final bool panel;

  /// Where the hosting surface sits on screen, to anchor context menus.
  final Offset Function() surfaceOrigin;
  final bool closeOverviewOnLaunch;

  @override
  State<DockBar> createState() => _DockBarState();
}

class _DockBarState extends State<DockBar> with SingleTickerProviderStateMixin {
  /// How far magnification is "in" (0 → 1 on enter, back to 0 on exit), so
  /// icons ease up and settle down like the macOS Dock.
  late final AnimationController _strength;

  @override
  void initState() {
    super.initState();
    _strength = AnimationController(vsync: this, duration: const Duration(milliseconds: 140))
      ..addListener(() => setState(() {}));
  }

  /// Pointer along the main axis, relative to the first slot.
  double? _cursor;

  @override
  void dispose() {
    _strength.dispose();
    super.dispose();
  }

  void _enter() {
    if (!widget.magnify) return;
    Shell.of(context).setDockPointerInside(true);
    _strength.duration = const Duration(milliseconds: 140);
    _strength.forward();
  }

  void _exit() {
    if (!widget.magnify) return;
    Shell.of(context).setDockPointerInside(false);
    _strength.duration = const Duration(milliseconds: 220);
    _strength.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final theme = ShellThemeScope.of(context);
    final layout = theme.layout;
    final t = theme.tokens;
    final vertical = !widget.horizontal && layout.dockPosition != DockPosition.bottom;
    final cap = widget.maxIconSize;
    final size = cap == null ? layout.dockIconSize : layout.dockIconSize.clamp(16.0, cap < 16 ? 16.0 : cap);
    final pad = size * 0.18;
    // Main-axis extent of one item at rest (vertical items also stack their
    // 6 pt indicator row, as in [dockSize]).
    final slot = size + pad + (vertical ? 6 : 0);
    final thickness = widget.backgroundThickness ?? size + pad * 2 + 6;
    final maxScale = widget.magnify ? layout.dockMagnification : 1.0;
    final edge = widget.horizontal ? DockPosition.bottom : layout.dockPosition;
    // Hover labels only on the dock itself (not the launcher's dash).
    final label = widget.magnify ? _DockLabelScope.maybeOf(context) : null;
    return ListenableBuilder(
      listenable: ctrl.apps,
      builder: (context, _) {
        final items = ctrl.dockItems();
        final buttons = <(IconData, String, VoidCallback)>[
          if (layout.showAppGridButton) (Icons.apps_rounded, 'Show Applications', ctrl.toggleOverview),
          // The shell's own entry point: it draws this dock, so it never
          // appears among the running apps.
          if (layout.showCustomizerButton)
            (
              Icons.tune_rounded,
              'Customize',
              () {
                ctrl.openCustomizer();
              },
            ),
        ];
        final count = items.length + buttons.length;
        final hasGap = widget.panel && buttons.isNotEmpty;
        return LayoutBuilder(
          builder: (context, constraints) {
            final length = (vertical ? constraints.maxHeight : constraints.maxWidth) - pad;
            final gapBase = hasGap && length.isFinite ? math.max(0.0, length - count * slot) : 0.0;
            final cursor = _cursor;
            final scales = cursor == null || maxScale <= 1
                ? List.filled(count, 1.0)
                : dockMagnify(
                    count: count,
                    slot: slot,
                    cursor: cursor,
                    maxScale: maxScale,
                    strength: _strength.value,
                    gapIndex: hasGap ? items.length : null,
                    gapBase: gapBase,
                    length: hasGap && length.isFinite ? length : null,
                  );
            final plain = maxScale <= 1;
            final children = <Widget>[
              for (final (i, item) in items.indexed)
                _DockIcon(
                  key: ValueKey(item.bundleId),
                  item: item,
                  size: size,
                  pad: pad,
                  scale: scales[i],
                  maxScale: maxScale,
                  slot: slot,
                  vertical: vertical,
                  highlight: plain,
                  focused: ctrl.apps.activeBundle == item.bundleId,
                  showDot: layout.showRunningDots,
                  labelLink: label?.target == item.bundleId ? label?.link : null,
                  onHoverChanged: label == null ? null : (inside) => label.iconHover(item.bundleId, inside),
                  onTap: () {
                    label?.dismiss();
                    if (widget.closeOverviewOnLaunch) ctrl.ui.closeOverview();
                    ctrl.activate(item.bundleId);
                  },
                  onMenu: (anchor) {
                    label?.dismiss();
                    ctrl.showDockMenu(item.bundleId, anchor.shift(widget.surfaceOrigin()), edge);
                  },
                ),
              if (hasGap) const Spacer(),
              for (final (i, (icon, tip, onTap)) in buttons.indexed)
                _GlyphButton(
                  icon: icon,
                  tooltip: tip,
                  size: size,
                  pad: pad,
                  scale: scales[items.length + i],
                  slot: slot,
                  vertical: vertical,
                  highlight: plain,
                  onTap: onTap,
                ),
            ];
            final background = ShellPanelBox(
              ownBackdrop: widget.ownBackdrop,
              color: t.dockBg,
              radius: widget.panel ? 0 : t.radius('dock'),
              blur: t.blurOf('dock'),
              child: const SizedBox.expand(),
            );
            final flex = Padding(
              padding: EdgeInsets.all(pad / 2),
              child: Flex(
                direction: vertical ? Axis.vertical : Axis.horizontal,
                mainAxisSize: widget.panel ? MainAxisSize.max : MainAxisSize.min,
                // Items grow away from the screen edge.
                crossAxisAlignment: edge == DockPosition.left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: children,
              ),
            );
            return MouseRegion(
              // The whole bar (including the room above shorter icons) counts,
              // so magnification doesn't flicker between icons.
              hitTestBehavior: HitTestBehavior.opaque,
              onEnter: (_) => _enter(),
              onExit: (_) => _exit(),
              onHover: (e) {
                final p = vertical ? e.localPosition.dy : e.localPosition.dx;
                setState(() => _cursor = p - pad / 2);
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The bar keeps its resting depth at the screen edge; icons
                  // magnify out of it, as on macOS.
                  switch (edge) {
                    DockPosition.bottom => Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: thickness,
                      child: background,
                    ),
                    DockPosition.left => Positioned(top: 0, bottom: 0, left: 0, width: thickness, child: background),
                    DockPosition.right => Positioned(top: 0, bottom: 0, right: 0, width: thickness, child: background),
                  },
                  flex,
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    super.key,
    required this.item,
    required this.size,
    required this.pad,
    required this.scale,
    required this.maxScale,
    required this.slot,
    required this.vertical,
    required this.highlight,
    required this.focused,
    required this.showDot,
    required this.onTap,
    required this.onMenu,
    this.labelLink,
    this.onHoverChanged,
  });

  /// Set on the icon whose hover label is showing: the label follows it.
  final LayerLink? labelLink;
  final ValueChanged<bool>? onHoverChanged;

  final DockItem item;
  final double size;
  final double pad;

  /// Current magnification of this icon (1 at rest).
  final double scale;
  final double maxScale;
  final double slot;
  final bool vertical;

  /// Hover highlight + nudge; used when magnification is off.
  final bool highlight;
  final bool focused;
  final bool showDot;
  final VoidCallback onTap;
  final void Function(Rect anchor) onMenu;

  @override
  Widget build(BuildContext context) {
    final t = ShellThemeScope.of(context).tokens;
    final icon = size * scale;
    return Builder(
      builder: (context) {
        return Hover(
          onTap: onTap,
          onSecondaryTap: () => onMenu(rectOf(context)),
          // Click and hold opens the menu too, as in the Dock.
          onLongPress: () => onMenu(rectOf(context)),
          onHoverChanged: onHoverChanged,
          builder: (context, hovered) => Container(
            // Exactly `slot × scale` along the dock, so the magnification
            // math and the layout agree.
            // Vertical docks are 6 pt deeper (the indicator row stacks below
            // the icon), so fill that depth to stay centred at rest.
            width: vertical ? (size + pad) * scale + 6 : slot * scale,
            height: vertical ? slot * scale : null,
            alignment: vertical ? Alignment.center : null,
            padding: EdgeInsets.all(pad * scale / 2),
            decoration: BoxDecoration(
              color: highlight && hovered ? t.surfaceFg.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(t.radius('tile') * 0.8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: highlight && hovered ? 1.06 : 1,
                  duration: const Duration(milliseconds: 120),
                  // Rendered once at the largest size and scaled down, so the
                  // icon cache isn't asked for a new bitmap every frame.
                  child: _maybeTarget(
                    labelLink,
                    SizedBox.square(
                      dimension: icon,
                      child: FittedBox(child: AppIcon(item.bundleId, size: size * maxScale)),
                    ),
                  ),
                ),
                SizedBox(
                  height: 6,
                  child: showDot && item.running
                      ? Center(
                          child: Container(
                            width: focused ? 12 : 5,
                            height: 4,
                            decoration: BoxDecoration(
                              color: focused ? t.accent : t.dockFg.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A glyph tile at the end of the dock (Show Applications, Customize).
class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.pad,
    required this.scale,
    required this.slot,
    required this.vertical,
    required this.highlight,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final double pad;
  final double scale;
  final double slot;
  final bool vertical;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShellThemeScope.of(context).tokens;
    final s = size * scale;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: Hover(
        onTap: onTap,
        builder: (context, hovered) => Container(
          width: vertical ? (size + pad) * scale + 6 : slot * scale,
          height: vertical ? slot * scale : null,
          alignment: vertical ? Alignment.center : null,
          padding: EdgeInsets.fromLTRB(pad * scale / 2, pad * scale / 2, pad * scale / 2, pad * scale / 2 + 6),
          decoration: BoxDecoration(
            color: highlight && hovered ? t.surfaceFg.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(t.radius('tile') * 0.8),
          ),
          child: SizedBox.square(
            dimension: s,
            child: Icon(icon, size: s * 0.6, color: t.dockFg),
          ),
        ),
      ),
    );
  }
}

Widget _maybeTarget(LayerLink? link, Widget child) =>
    link == null ? child : CompositedTransformTarget(link: link, child: child);
