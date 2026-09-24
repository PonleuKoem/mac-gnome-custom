import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shellkit/shellkit.dart';

import '../core/shell_controller.dart';
import '../theme/shell_theme.dart';
import '../theme/theme_store.dart';

/// Rebuilds dependents whenever the theme changes.
class ShellThemeScope extends InheritedNotifier<ThemeStore> {
  const ShellThemeScope({super.key, required ThemeStore store, required super.child}) : super(notifier: store);

  static ShellTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellThemeScope>()!.notifier!.theme;

  static ThemeStore storeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellThemeScope>()!.notifier!;
}

bool isDark(Color c) => c.computeLuminance() < 0.4;

/// App icon from the icon cache (theme icon pack first, then the system icon).
class AppIcon extends StatefulWidget {
  const AppIcon(this.bundleIdOrPath, {super.key, required this.size});

  final String bundleIdOrPath;
  final double size;

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  ImageProvider? _image;
  String? _loadedKey;

  int get _px => (widget.size * MediaQuery.devicePixelRatioOf(context)).round().clamp(16, 512);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final icons = Shell.of(context).icons;
    // Depend on the theme so an icon-pack change reloads.
    ShellThemeScope.of(context);
    final peek = icons.peek(widget.bundleIdOrPath, _px);
    // peek() bumps the generation when the icon pack changed.
    final key = '${icons.generation}|${widget.bundleIdOrPath}@$_px';
    if (peek != null) {
      _image = peek;
      _loadedKey = key;
      return;
    }
    if (_loadedKey == key) return;
    _loadedKey = key;
    icons.get(widget.bundleIdOrPath, _px).then((img) {
      if (mounted && _loadedKey == key) setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final t = ShellThemeScope.of(context).tokens;
    // Themed plates only at dock/launcher sizes; small icons (menus, top bar)
    // stay native so they remain legible.
    final shape = widget.size >= 32 ? t.iconShape : IconShape.native;
    if (shape == IconShape.native) {
      return SizedBox.square(
        dimension: widget.size,
        child: image == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x33FFFFFF),
                  borderRadius: BorderRadius.circular(widget.size * 0.22),
                ),
              )
            : Image(image: image, width: widget.size, height: widget.size, filterQuality: FilterQuality.medium),
      );
    }
    final s = widget.size;
    final ShapeBorder border = switch (shape) {
      IconShape.circle => const CircleBorder(),
      IconShape.squircle => ContinuousRectangleBorder(borderRadius: BorderRadius.circular(s * 0.46)),
      _ => RoundedRectangleBorder(borderRadius: BorderRadius.circular(s * 0.2)),
    };
    // macOS icons carry ~10% transparent margin; inset so the artwork, not
    // the margin, fills the plate.
    final inner = s * (shape == IconShape.circle ? 0.86 : 0.9);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: t.iconPlate,
        shape: border,
        shadows: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: SizedBox.square(
        dimension: s,
        child: Center(
          child: image == null
              ? const SizedBox.shrink()
              : Image(image: image, width: inner, height: inner, filterQuality: FilterQuality.medium),
        ),
      ),
    );
  }
}

/// Hover-aware builder for bar buttons and tiles.
class Hover extends StatefulWidget {
  const Hover({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.onHoverChanged,
    this.cursor = SystemMouseCursors.basic,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHoverChanged;
  final MouseCursor cursor;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHoverChanged?.call(true);
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onHoverChanged?.call(false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        onLongPress: widget.onLongPress,
        child: widget.builder(context, _hovered),
      ),
    );
  }
}

/// Screen-relative rect of the widget owning [context], given the offset of the
/// surface it lives in.
Rect rectOf(BuildContext context, {Offset surfaceOrigin = Offset.zero}) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Rect.zero;
  return (box.localToGlobal(Offset.zero) & box.size).shift(surfaceOrigin);
}

/// Collects [BlurRegion]s in a surface and sends their shapes to native, where
/// an NSVisualEffectView behind the transparent Flutter view is masked to them
/// (DESIGN.md §4.1: Flutter's BackdropFilter can't see the desktop).
class SurfaceBlur extends StatefulWidget {
  const SurfaceBlur({super.key, required this.surfaceId, required this.child});

  final String surfaceId;
  final Widget child;

  static _SurfaceBlurState? _of(BuildContext context) => context.findAncestorStateOfType<_SurfaceBlurState>();

  @override
  State<SurfaceBlur> createState() => _SurfaceBlurState();
}

class _SurfaceBlurState extends State<SurfaceBlur> {
  final Map<Object, (Rect, double, bool)> _regions = {};
  bool _scheduled = false;
  String _lastSent = '';

  void report(Object key, Rect rect, double radius, bool dark) {
    if (_regions[key] == (rect, radius, dark)) return;
    _regions[key] = (rect, radius, dark);
    _schedule();
  }

  void remove(Object key) {
    if (_regions.remove(key) != null) _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // A microtask, not a post-frame callback: reports arrive from paint, and a
    // post-frame callback registered then would wait for some future frame.
    scheduleMicrotask(() {
      _scheduled = false;
      if (!mounted) return;
      final regions = _regions.values
          .map(
            (r) => RRectD(
              rect: RectD(x: r.$1.left, y: r.$1.top, w: r.$1.width, h: r.$1.height),
              radius: r.$2,
            ),
          )
          .toList();
      final dark = _regions.values.any((r) => r.$3);
      final signature = '${_regions.values.toList()}';
      if (signature == _lastSent) return;
      _lastSent = signature;
      Shell.of(context).bridge.host.setBlurRegions(widget.surfaceId, regions, dark);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Marks its child's shape as frosted glass. The rect is reported from the
/// render object at paint time, so it follows every relayout — including the
/// one after native resizes the panel.
class BlurRegion extends StatefulWidget {
  const BlurRegion({super.key, required this.enabled, required this.radius, required this.dark, required this.child});

  final bool enabled;
  final double radius;
  final bool dark;
  final Widget child;

  @override
  State<BlurRegion> createState() => _BlurRegionState();
}

class _BlurRegionState extends State<BlurRegion> {
  final _key = Object();
  _SurfaceBlurState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = SurfaceBlur._of(context);
  }

  @override
  void didUpdateWidget(BlurRegion old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) _scope?.remove(_key);
  }

  @override
  void dispose() {
    _scope?.remove(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return _BlurReporter(
      onRect: (r) => _scope?.report(_key, r, widget.radius.clamp(0, r.shortestSide / 2), widget.dark),
      child: widget.child,
    );
  }
}

class _BlurReporter extends SingleChildRenderObjectWidget {
  const _BlurReporter({required this.onRect, super.child});
  final void Function(Rect) onRect;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBlurReporter(onRect);

  @override
  void updateRenderObject(BuildContext context, _RenderBlurReporter renderObject) => renderObject.onRect = onRect;
}

class _RenderBlurReporter extends RenderProxyBox {
  _RenderBlurReporter(this.onRect);
  void Function(Rect) onRect;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (hasSize && !size.isEmpty) {
      final rect = localToGlobal(Offset.zero) & size;
      // Report after the frame; never mutate state during paint.
      scheduleMicrotask(() => onRect(rect));
    }
  }
}

/// Rounded panel background used by the dock, popovers and switcher.
class ShellPanelBox extends StatelessWidget {
  const ShellPanelBox({
    super.key,
    required this.color,
    required this.radius,
    required this.blur,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.ownBackdrop = false,
  });

  final Color color;
  final double radius;
  final double blur;
  final Widget child;
  final EdgeInsets padding;

  /// The surface paints its own backdrop (the dock over the native spacer
  /// Dock): blur that in Flutter instead of the desktop behind the window,
  /// which would show the native Dock.
  final bool ownBackdrop;

  @override
  Widget build(BuildContext context) {
    if (ownBackdrop) {
      final box = DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Padding(padding: padding, child: child),
      );
      if (blur <= 0) return box;
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
          child: box,
        ),
      );
    }
    return BlurRegion(
      enabled: blur > 0,
      radius: radius,
      dark: isDark(color.withValues(alpha: 1)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Smooth scrolling for mouse wheels. Flutter jumps straight to the new
/// offset for each wheel notch; this glides there instead (ease-out, with
/// notches in quick succession adding to the target), like native macOS
/// views. Trackpads and Magic Mouse arrive as pan gestures and keep
/// Flutter's own momentum, untouched.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({this.duration = const Duration(milliseconds: 220)});

  final Duration duration;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) =>
      _SmoothScrollPosition(
        physics: physics,
        context: context,
        oldPosition: oldPosition,
        duration: duration,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        debugLabel: debugLabel,
      );
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    required this.duration,
    super.oldPosition,
    super.initialPixels,
    super.keepScrollOffset,
    super.debugLabel,
  });

  final Duration duration;
  double? _target;

  @override
  void pointerScroll(double delta) {
    if (delta == 0) return super.pointerScroll(delta);
    // Keep adding to where we're heading, so fast wheel spins accelerate.
    final from = _target ?? pixels;
    final to = (from + delta).clamp(minScrollExtent, maxScrollExtent);
    if (to == pixels && _target == null) return;
    _target = to;
    animateTo(to, duration: duration, curve: Curves.easeOutCubic).whenComplete(() {
      if (_target == to) _target = null;
    });
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // Any other scrolling (drag, trackpad, keyboard) takes over the target.
    if (newActivity is! DrivenScrollActivity) _target = null;
    super.beginActivity(newActivity);
  }
}

/// Owns a [SmoothScrollController] for a stateless scrollable.
class SmoothScroll extends StatefulWidget {
  const SmoothScroll({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController controller) builder;

  @override
  State<SmoothScroll> createState() => _SmoothScrollState();
}

class _SmoothScrollState extends State<SmoothScroll> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
