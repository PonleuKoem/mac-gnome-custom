import 'package:flutter/material.dart';
import 'package:shellkit/shellkit.dart';

import '../core/algorithms.dart';
import '../core/shell_controller.dart';
import '../core/ui_state.dart';
import '../widgets/common.dart';
import 'top_bar.dart';

/// One panel for every popover (calendar, quick settings, app menu, dock
/// menu). Content reports its preferred size so the panel fits it exactly.
class PopoverSurface extends StatelessWidget {
  const PopoverSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final t = ShellThemeScope.of(context).tokens;
    return ListenableBuilder(
      listenable: ctrl.ui,
      builder: (context, _) {
        final p = ctrl.ui.popover;
        if (p == null) return const SizedBox.shrink();
        final content = switch (p.kind) {
          PopoverKind.calendar => const _Calendar(),
          PopoverKind.quickSettings => const _QuickSettings(),
        };
        return ShellPanelBox(
          color: t.popoverBg,
          radius: t.radius('popover'),
          blur: t.blurOf('popover'),
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle(
            style: t.body(color: t.popoverFg),
            child: IconTheme(
              data: IconThemeData(color: t.popoverFg, size: 20),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

/// Asks the controller to resize the popover panel after this frame.
void _reportSize(BuildContext context, Size size) {
  final ui = Shell.of(context).ui;
  WidgetsBinding.instance.addPostFrameCallback((_) => ui.setPopoverSize(size));
}

// MARK: Calendar

class _Calendar extends StatefulWidget {
  const _Calendar();

  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  late DateTime _month = DateTime(shellNow().year, shellNow().month);

  @override
  Widget build(BuildContext context) {
    _reportSize(context, const Size(320, 356));
    final t = ShellThemeScope.of(context).tokens;
    final now = shellNow();
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday-first grid
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatClock(now, 'EEEE'), style: t.body(color: t.popoverFg.withValues(alpha: 0.7), size: 13)),
        Text(
          '${formatClock(now, 'MMMM d')} ${now.year}',
          style: t.body(color: t.popoverFg, size: 20, weight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '${formatClock(_month, 'MMMM')} ${_month.year}',
              style: t.body(color: t.popoverFg, weight: FontWeight.w600),
            ),
            const Spacer(),
            _IconButton(
              icon: Icons.chevron_left_rounded,
              onTap: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            ),
            _IconButton(
              icon: Icons.chevron_right_rounded,
              onTap: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final d in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(
                child: Center(
                  child: Text(d, style: t.body(size: 12, color: t.popoverFg.withValues(alpha: 0.6))),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.count(
            crossAxisCount: 7,
            childAspectRatio: 1.2,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < lead; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysInMonth; d++)
                () {
                  final today = now.year == _month.year && now.month == _month.month && now.day == d;
                  return Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: today ? BoxDecoration(color: t.accent, shape: BoxShape.circle) : null,
                      child: Text(
                        '$d',
                        style: t.body(size: 13, color: t.popoverFg, weight: today ? FontWeight.w700 : null),
                      ),
                    ),
                  );
                }(),
            ],
          ),
        ),
      ],
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShellThemeScope.of(context).tokens;
    return Hover(
      onTap: onTap,
      builder: (context, hovered) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: hovered ? t.popoverFg.withValues(alpha: 0.12) : null, shape: BoxShape.circle),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

// MARK: Quick settings

/// Read-only status plus the appearance toggle. Interface-only scope
/// (ADR-0012): the shell doesn't change volume, Wi-Fi or power state, lock
/// the screen or log out — those stay with macOS's own Control Center.
class _QuickSettings extends StatelessWidget {
  const _QuickSettings();

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final t = ShellThemeScope.of(context).tokens;
    _reportSize(context, const Size(360, 150));
    return ValueListenableBuilder<SystemStatus?>(
      valueListenable: ctrl.system,
      builder: (context, s, _) {
        if (s == null) return const SizedBox.shrink();
        final label = t.body(color: t.popoverFg, size: 13);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (s.batteryPercent >= 0) ...[
                  Icon(batteryIcon(s), size: 18),
                  const SizedBox(width: 6),
                  Text('${s.batteryPercent}%${s.charging ? ' · charging' : ''}', style: label),
                  const SizedBox(width: 14),
                ],
                Icon(volumeIcon(s), size: 18),
                const SizedBox(width: 6),
                Text(s.muted ? 'Muted' : '${(s.volume * 100).round()}%', style: label),
                const SizedBox(width: 14),
                Icon(wifiIcon(s), size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    s.wifiOn ? (s.wifiSsid ?? 'Wi-Fi on') : 'Wi-Fi off',
                    overflow: TextOverflow.ellipsis,
                    style: label,
                  ),
                ),
                const Spacer(),
                _RoundButton(
                  icon: Icons.tune_rounded,
                  tooltip: 'Customize',
                  onTap: () {
                    ctrl.ui.closePopover();
                    ctrl.openCustomizer();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Toggle(
              icon: Icons.dark_mode_rounded,
              label: 'Dark Style',
              subtitle: s.darkMode ? 'On' : 'Off',
              on: s.darkMode,
              onTap: () => ctrl.bridge.system.setDarkMode(!s.darkMode),
            ),
          ],
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShellThemeScope.of(context).tokens;
    return Semantics(
      label: tooltip,
      button: true,
      child: Hover(
        onTap: onTap,
        builder: (context, hovered) => Container(
          width: 38,
          height: 38,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: t.popoverFg.withValues(alpha: hovered ? 0.18 : 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.on,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShellThemeScope.of(context).tokens;
    final fg = on ? Colors.white : t.popoverFg;
    return Hover(
      onTap: onTap,
      builder: (context, hovered) => Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: on ? t.accent : t.popoverFg.withValues(alpha: hovered ? 0.16 : 0.1),
          borderRadius: BorderRadius.circular(27),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: t.body(color: fg, weight: FontWeight.w700, size: 13),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body(color: fg.withValues(alpha: 0.8), size: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
