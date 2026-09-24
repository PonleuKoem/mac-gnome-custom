import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shellkit/shellkit.dart';

import '../core/algorithms.dart';
import '../core/shell_controller.dart';
import '../core/ui_state.dart';
import '../theme/shell_theme.dart';
import '../widgets/common.dart';

/// GNOME-style top bar covering the native menu bar (ADR-0004). Its content is
/// layout-as-data: `layout.topBar.left/center/right` list widget ids.
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.spec});

  final SurfaceSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = ShellThemeScope.of(context);
    final t = theme.tokens;
    final layout = theme.layout;
    // `spacer` must stay a direct Row child (it is an Expanded).
    Widget item(String id) => id == 'spacer'
        ? const Spacer()
        : DefaultTextStyle.merge(
            style: TextStyle(fontWeight: t.weightFor(id)),
            child: _TopBarItem(id: id, screenId: spec.screenId),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        // The bar is exactly as tall as the macOS menu bar (24 pt, or 37 pt
        // with a notch); text follows the interface size but always fits it.
        final h = constraints.maxHeight;
        final fontSize = h.isFinite ? math.min(t.barFontSize, math.max(9.0, (h - 4) * 0.62)) : t.barFontSize;
        return _bar(t, layout, item, fontSize);
      },
    );
  }

  Widget _bar(ShellTokens t, ShellLayout layout, Widget Function(String) item, double fontSize) {
    return DecoratedBox(
      // Optional hairline under the bar (`bar.border`, transparent by default).
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.barBorder)),
      ),
      child: ColoredBox(
        color: t.barBg,
        child: DefaultTextStyle(
          style: t.barText().copyWith(fontSize: fontSize),
          child: IconTheme(
            data: IconThemeData(color: t.barFg, size: fontSize + 2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Stack(
                children: [
                  Row(
                    children: [
                      for (final id in layout.left) item(id),
                      const Spacer(),
                      for (final id in layout.right) item(id),
                    ],
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final id in layout.center.where((id) => id != 'spacer')) item(id)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBarItem extends StatelessWidget {
  const _TopBarItem({required this.id, required this.screenId});

  final String id;
  final int screenId;

  @override
  Widget build(BuildContext context) {
    return switch (id) {
      'activities' => const _ActivitiesButton(),
      'appName' => const _ActiveAppName(),
      'clock' => _Clock(screenId: screenId),
      'indicators' => _Indicators(screenId: screenId),
      'appGrid' => const _AppGridButton(),
      'spacer' => const Spacer(),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Pill-shaped hover/active highlight used by every bar control.
class BarButton extends StatelessWidget {
  const BarButton({super.key, required this.child, required this.onTap, this.active = false});

  final Widget child;
  final void Function(Rect anchor) onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = ShellThemeScope.of(context).tokens;
    return Builder(
      builder: (context) {
        return Hover(
          onTap: () => onTap(rectOf(context)),
          builder: (context, hovered) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? t.barFg.withValues(alpha: 0.22)
                  : hovered
                  ? t.barFg.withValues(alpha: 0.12)
                  : null,
              borderRadius: BorderRadius.circular(t.radius('button')),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _ActivitiesButton extends StatelessWidget {
  const _ActivitiesButton();

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return ListenableBuilder(
      listenable: ctrl.ui,
      builder: (context, _) =>
          BarButton(active: ctrl.ui.overviewOpen, onTap: (_) => ctrl.toggleOverview(), child: const Text('Activities')),
    );
  }
}

class _AppGridButton extends StatelessWidget {
  const _AppGridButton();

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return BarButton(onTap: (_) => ctrl.toggleOverview(), child: const Icon(Icons.apps_rounded));
  }
}

/// Name of the frontmost app (public NSWorkspace data). Interface-only scope
/// (ADR-0012): no menus from other apps are read or pressed.
class _ActiveAppName extends StatelessWidget {
  const _ActiveAppName();

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return ListenableBuilder(
      listenable: ctrl.apps,
      builder: (context, _) {
        final bundle = ctrl.apps.activeBundle;
        if (bundle == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [AppIcon(bundle, size: 18), const SizedBox(width: 8), Text(ctrl.apps.nameFor(bundle))],
          ),
        );
      },
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock({required this.screenId});
  final int screenId;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;
  DateTime _now = shellNow();
  String _format = '';

  /// Ticks at the next second or minute boundary depending on the format, so
  /// an idle bar repaints once a minute (DESIGN.md §1.2 idle budget).
  /// Scheduled from didChangeDependencies (runs right after initState).
  void _schedule() {
    _timer?.cancel();
    final perSecond = _format.contains('ss');
    final now = shellNow();
    final wait = perSecond
        ? Duration(milliseconds: 1000 - now.millisecond)
        : Duration(seconds: 60 - now.second, milliseconds: -now.millisecond);
    _timer = Timer(wait, () {
      if (!mounted) return;
      setState(() => _now = shellNow());
      _schedule();
    });
    _now = shellNow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _format = ShellThemeScope.of(context).layout.clockFormat;
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final format = ShellThemeScope.of(context).layout.clockFormat;
    return ListenableBuilder(
      listenable: ctrl.ui,
      builder: (context, _) => BarButton(
        active: ctrl.ui.popover?.kind == PopoverKind.calendar,
        onTap: (anchor) =>
            ctrl.ui.openPopover(PopoverState(kind: PopoverKind.calendar, screenId: widget.screenId, anchor: anchor)),
        child: Text(formatClock(_now, format)),
      ),
    );
  }
}

class _Indicators extends StatelessWidget {
  const _Indicators({required this.screenId});
  final int screenId;

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl.system, ctrl.ui]),
      builder: (context, _) {
        final s = ctrl.system.value;
        return BarButton(
          active: ctrl.ui.popover?.kind == PopoverKind.quickSettings,
          onTap: (anchor) =>
              ctrl.ui.openPopover(PopoverState(kind: PopoverKind.quickSettings, screenId: screenId, anchor: anchor)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s != null) ...[
                Icon(wifiIcon(s)),
                const SizedBox(width: 10),
                Icon(volumeIcon(s)),
                if (s.batteryPercent >= 0) ...[const SizedBox(width: 10), Icon(batteryIcon(s))],
              ] else
                const Icon(Icons.tune_rounded),
            ],
          ),
        );
      },
    );
  }
}

IconData wifiIcon(SystemStatus s) {
  if (!s.wifiOn) return Icons.wifi_off_rounded;
  if (s.wifiRssi == 0) return Icons.wifi_rounded;
  if (s.wifiRssi > -60) return Icons.wifi_rounded;
  if (s.wifiRssi > -70) return Icons.wifi_2_bar_rounded;
  return Icons.wifi_1_bar_rounded;
}

IconData volumeIcon(SystemStatus s) {
  if (s.muted || s.volume <= 0.001) return Icons.volume_off_rounded;
  if (s.volume < 0.34) return Icons.volume_mute_rounded;
  if (s.volume < 0.67) return Icons.volume_down_rounded;
  return Icons.volume_up_rounded;
}

IconData batteryIcon(SystemStatus s) {
  if (s.charging) return Icons.battery_charging_full_rounded;
  final p = s.batteryPercent;
  if (p >= 95) return Icons.battery_full_rounded;
  if (p >= 80) return Icons.battery_6_bar_rounded;
  if (p >= 65) return Icons.battery_5_bar_rounded;
  if (p >= 50) return Icons.battery_4_bar_rounded;
  if (p >= 35) return Icons.battery_3_bar_rounded;
  if (p >= 20) return Icons.battery_2_bar_rounded;
  if (p >= 8) return Icons.battery_1_bar_rounded;
  return Icons.battery_alert_rounded;
}

/// Static rendering of a theme's top bar for the Customizer (any theme, not
/// just the active one). Laid out at a real bar width, then scaled to fit.
class TopBarPreview extends StatelessWidget {
  const TopBarPreview({super.key, required this.theme, this.barWidth = 1280, this.barHeight = 32});
  final ShellTheme theme;
  final double barWidth;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final t = theme.tokens;
    // As on the real bar: the interface size, but always fitting the bar.
    final fontSize = math.min(t.barFontSize, math.max(9.0, (barHeight - 4) * 0.62));
    Widget pill(String id) => switch (id) {
      'activities' => const _PreviewPill(child: Text('Activities')),
      'clock' => _PreviewPill(child: Text(formatClock(DateTime(2026, 9, 24, 9, 41), theme.layout.clockFormat))),
      'appName' => const _PreviewPill(child: Text('Finder')),
      'indicators' => const _PreviewPill(
        child: Row(
          children: [
            Icon(Icons.wifi_rounded),
            SizedBox(width: 10),
            Icon(Icons.volume_up_rounded),
            SizedBox(width: 10),
            Icon(Icons.battery_5_bar_rounded),
          ],
        ),
      ),
      'appGrid' => const _PreviewPill(child: Icon(Icons.apps_rounded)),
      _ => const SizedBox.shrink(),
    };
    Widget item(String id) => id == 'spacer'
        ? const Spacer()
        : DefaultTextStyle.merge(
            style: TextStyle(fontWeight: t.weightFor(id)),
            child: pill(id),
          );
    return FittedBox(
      fit: BoxFit.fitWidth,
      alignment: Alignment.topCenter,
      child: Container(
        width: barWidth,
        height: barHeight,
        decoration: BoxDecoration(
          color: t.barBg,
          border: Border(bottom: BorderSide(color: t.barBorder)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: DefaultTextStyle(
          style: t.barText().copyWith(fontSize: fontSize),
          child: IconTheme(
            data: IconThemeData(color: t.barFg, size: fontSize + 2),
            child: Stack(
              children: [
                Row(
                  children: [
                    for (final id in theme.layout.left) item(id),
                    const Spacer(),
                    for (final id in theme.layout.right) item(id),
                  ],
                ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [for (final id in theme.layout.center.where((id) => id != 'spacer')) item(id)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Center(child: child),
  );
}
