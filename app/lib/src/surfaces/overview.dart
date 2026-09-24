import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shellkit/shellkit.dart';

import '../core/algorithms.dart';
import '../core/shell_controller.dart';
import '../theme/shell_theme.dart';
import '../widgets/common.dart';
import 'dock.dart';

/// Activities launcher: search + app grid + dash, in one full-screen surface
/// below the top bar. Interface-only scope (ADR-0012): it shows apps, not other
/// apps' windows (no screen capture, no window control).
class OverviewSurface extends StatelessWidget {
  const OverviewSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return ListenableBuilder(
      listenable: ctrl.ui,
      builder: (context, _) {
        if (!ctrl.ui.overviewOpen) return const SizedBox.shrink();
        return const _Overview();
      },
    );
  }
}

class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  /// Flutter's FocusManager parks focus on the root scope whenever the app
  /// lifecycle changes away from `resumed`. The shell is an accessory app —
  /// almost never "active" — so opening the launcher (a key, non-activating
  /// panel) triggered that and the search field lost focus before the first
  /// keystroke. The FocusManager observes first, so re-focusing here wins.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted && !_focus.hasFocus) _focus.requestFocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _escape(ShellController ctrl) {
    if (_search.text.isNotEmpty) {
      _search.clear();
      ctrl.ui.setQuery('');
    } else {
      ctrl.ui.closeOverview();
    }
  }

  void _submit(ShellController ctrl) {
    final q = ctrl.ui.query;
    if (q.isEmpty) return;
    final apps = fuzzyFilter(q, ctrl.apps.installed, (a) => a.name);
    if (apps.isNotEmpty) {
      ctrl.ui.closeOverview();
      ctrl.activate(apps.first.bundleId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final theme = ShellThemeScope.of(context);
    final t = theme.tokens;
    final main = ctrl.surfaces.mainScreen;
    final surfaceOrigin = Offset(0, main?.menuBarHeight ?? 0);
    final reservedDock = main != null && ctrl.dockStrip(main) != null;
    // Focus sits around the whole overview (not just the search field), so
    // Escape / Enter / type-to-search keep working after clicks elsewhere.
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _escape(ctrl);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _submit(ctrl);
          return KeyEventResult.handled;
        }
        final ch = event.character;
        if (!_focus.hasFocus && ch != null && ch.trim().isNotEmpty && !HardwareKeyboard.instance.isMetaPressed) {
          _search.text += ch;
          _search.selection = TextSelection.collapsed(offset: _search.text.length);
          ctrl.ui.setQuery(_search.text);
          _focus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: t.overviewDuration,
        curve: t.curve,
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            ctrl.ui.closePopover();
            ctrl.ui.closeOverview();
          },
          child: ColoredBox(
            color: t.scrim,
            child: CustomPaint(
              painter: t.scrimTexture == ScrimTexture.none
                  ? null
                  : ScrimTexturePainter(t.scrimTexture, t.surfaceFg.withValues(alpha: t.textureStrength)),
              isComplex: t.scrimTexture != ScrimTexture.none,
              // Own layer for the content, so typing/scrolling never repaints the texture.
              child: RepaintBoundary(
                child: DefaultTextStyle(
                  style: t.body(),
                  child: Column(
                    children: [
                      const SizedBox(height: 18),
                      _SearchField(controller: _search, focusNode: _focus, onSubmit: () => _submit(ctrl)),
                      const SizedBox(height: 14),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: ctrl.ui,
                          builder: (context, _) {
                            if (ctrl.ui.query.isNotEmpty) return _SearchResults(query: ctrl.ui.query);
                            return const _AppGrid();
                          },
                        ),
                      ),
                      // No dash while the real dock stays up below the launcher.
                      if (theme.layout.dockMode != DockMode.off && !reservedDock) ...[
                        Center(
                          child: Builder(
                            builder: (context) {
                              // The dash sits at the bottom of the overview surface.
                              return _Dash(surfaceOrigin: () => surfaceOrigin);
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Print-style texture over the launcher backdrop (`tokens.texture`). Drawn
/// in a few batched point calls, beneath a RepaintBoundary, so typing and
/// scrolling in the launcher don't repaint it.
class ScrimTexturePainter extends CustomPainter {
  ScrimTexturePainter(this.texture, this.color);

  final ScrimTexture texture;
  final Color color;

  static double _hash(int x, int y) {
    var n = (x * 374761393 + y * 668265263) & 0xFFFFFFFF;
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF;
    return (n & 0xFFFF) / 65536.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;
    if (texture == ScrimTexture.grain) {
      final pts = <Offset>[];
      for (var y = 0; y < size.height; y += 3) {
        for (var x = 0; x < size.width; x += 3) {
          final h = _hash(x, y);
          if (h > 0.62) pts.add(Offset(x + h * 3, y + (1 - h) * 3));
        }
      }
      canvas.drawPoints(PointMode.points, pts, paint..strokeWidth = 1);
      return;
    }
    // Halftone: a 30°-rotated dot screen; dots grow towards the bottom, the
    // way a printed tint fades in. Bucketed by size so it's six draw calls.
    const pitch = 7.0;
    const levels = 6;
    final buckets = List.generate(levels, (_) => <Offset>[]);
    const cosA = 0.8660254, sinA = 0.5;
    final reach = size.width + size.height;
    for (var j = -reach / pitch; j < reach / pitch; j++) {
      for (var i = -reach / pitch; i < reach / pitch; i++) {
        final x = (i * cosA - j * sinA) * pitch;
        final y = (i * sinA + j * cosA) * pitch;
        if (x < 0 || y < 0 || x > size.width || y > size.height) continue;
        final level = ((y / size.height) * levels).floor().clamp(0, levels - 1);
        buckets[level].add(Offset(x, y));
      }
    }
    for (var l = 0; l < levels; l++) {
      canvas.drawPoints(PointMode.points, buckets[l], paint..strokeWidth = 0.8 + l * 0.55);
    }
  }

  @override
  bool shouldRepaint(ScrimTexturePainter old) => old.texture != texture || old.color != color;
}

class _Dash extends StatelessWidget {
  const _Dash({required this.surfaceOrigin});
  final Offset Function() surfaceOrigin;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {}, // don't close the overview when clicking the dash background
      child: DockBar(surfaceOrigin: surfaceOrigin, closeOverviewOnLaunch: true, horizontal: true),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode, required this.onSubmit});

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final t = ShellThemeScope.of(context).tokens;
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 380,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: t.surfaceFg.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: t.surfaceFg.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 18, color: t.surfaceFg.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: ctrl.ui.setQuery,
                onSubmitted: (_) => onSubmit(),
                // Keep typing in the search field after clicks elsewhere.
                onTapOutside: (_) {},
                cursorColor: t.accent,
                style: t.body(),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Type to search',
                  hintStyle: t.body(color: t.surfaceFg.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: Apps

class _AppGrid extends StatelessWidget {
  const _AppGrid();

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return ListenableBuilder(
      listenable: ctrl.apps,
      builder: (context, _) {
        final apps = ctrl.apps.installed;
        if (apps.isEmpty) return const Center(child: CircularProgressIndicator());
        return LauncherGrid(apps: apps);
      },
    );
  }
}

/// The launcher grid, sized by `layout.launcher` (icon size, labels), with
/// smooth wheel scrolling.
class LauncherGrid extends StatefulWidget {
  const LauncherGrid({super.key, required this.apps});
  final List<InstalledApp> apps;

  @override
  State<LauncherGrid> createState() => _LauncherGridState();
}

class _LauncherGridState extends State<LauncherGrid> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ShellThemeScope.of(context).layout;
    final icon = layout.launcherIconSize;
    final apps = widget.apps;
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 96, vertical: 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: icon + 68,
        mainAxisExtent: icon + (layout.launcherLabels ? 56 : 24),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: apps.length,
      itemBuilder: (context, i) => AppLauncherTile(app: apps[i]),
    );
  }
}

class AppLauncherTile extends StatelessWidget {
  const AppLauncherTile({super.key, required this.app});
  final InstalledApp app;

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final theme = ShellThemeScope.of(context);
    final t = theme.tokens;
    final layout = theme.layout;
    return Hover(
      onTap: () {
        ctrl.ui.closeOverview();
        ctrl.activate(app.bundleId);
      },
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: hovered ? t.surfaceFg.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(t.radius('tile')),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(app.path, size: layout.launcherIconSize),
            if (layout.launcherLabels) ...[
              const SizedBox(height: 8),
              Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: t.body(size: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final t = ShellThemeScope.of(context).tokens;
    final apps = fuzzyFilter(query, ctrl.apps.installed, (a) => a.name).take(24).toList();
    if (apps.isEmpty) {
      return Center(child: Text('No apps match “$query”', style: t.body(size: 16)));
    }
    return LauncherGrid(apps: apps);
  }
}
