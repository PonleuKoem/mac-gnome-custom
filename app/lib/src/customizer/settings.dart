import 'package:flutter/material.dart';

import '../theme/json_util.dart';
import '../widgets/common.dart';

/// Building blocks shared by every Customizer page: grouped cards of rows,
/// each row a label on the left and its control on the right (stacked when
/// the window is narrow). Rows bound to a theme setting show a reset button
/// once the user has changed it, so it's always clear what differs from how
/// the theme ships.

/// A titled card of setting rows.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, this.description, this.trailing, required this.children});

  final String? title;
  final String? description;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rows = <Widget>[];
    for (final (i, c) in children.indexed) {
      if (i > 0) {
        rows.add(Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outlineVariant.withValues(alpha: 0.5)));
      }
      rows.add(c);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        if (description != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(description!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
          ),
        ],
      ),
    );
  }
}

/// One setting: label (+ help) and a control. [paths] are the theme settings
/// it edits; when any is changed from the theme's own value a reset button
/// appears.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.control,
    this.paths = const [],
    this.below,
    this.controlWidth = 300,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? control;
  final List<String> paths;

  /// Full-width content under the label (lists, editors).
  final Widget? below;

  /// Room for [control] when side by side (sliders want width).
  final double controlWidth;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final store = ShellThemeScope.storeOf(context);
    final changed = paths.where(store.isOverridden).toList();
    final reset = changed.isEmpty
        ? null
        : IconButton(
            tooltip: 'Reset to the theme\'s value',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: Icon(Icons.undo_rounded, color: scheme.primary),
            onPressed: () {
              for (final p in changed) {
                store.clearOverride(p);
              }
            },
          );
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: Text(title, style: text.bodyLarge)),
            if (changed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Tooltip(
                  message: 'Changed from the theme',
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  ),
                ),
              ),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < controlWidth + 220;
              final Widget head;
              if (control == null) {
                head = Row(
                  children: [
                    Expanded(child: label),
                    ?reset,
                  ],
                );
              } else if (narrow) {
                head = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: label),
                        ?reset,
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: control),
                  ],
                );
              } else {
                head = Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 16),
                    ?reset,
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: controlWidth),
                      child: Align(alignment: Alignment.centerRight, child: control),
                    ),
                  ],
                );
              }
              if (below == null) return head;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [head, const SizedBox(height: 10), below!],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A switch bound to a boolean theme setting.
class ThemeSwitchRow extends StatelessWidget {
  const ThemeSwitchRow({super.key, required this.title, this.subtitle, required this.path, this.enabled = true});

  final String title;
  final String? subtitle;
  final String path;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    return SettingRow(
      title: title,
      subtitle: subtitle,
      paths: [path],
      enabled: enabled,
      controlWidth: 60,
      control: Switch(value: store.valueAt(path) == true, onChanged: (v) => store.setOverride(path, v)),
    );
  }
}

/// A slider bound to a numeric theme setting. Shows the theme's own number
/// (before the interface size is applied).
class ThemeSliderRow extends StatelessWidget {
  const ThemeSliderRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.path,
    required this.min,
    required this.max,
    this.step = 1,
    this.format,
    this.fallback,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final String path;
  final double min;
  final double max;
  final double step;
  final String Function(double)? format;

  /// Used when the theme has no value at [path].
  final double? fallback;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final raw = store.valueAt(path);
    final value = (raw is num ? raw.toDouble() : fallback ?? min).clamp(min, max);
    final divisions = ((max - min) / step).round();
    return SettingRow(
      title: title,
      subtitle: subtitle,
      paths: [path],
      enabled: enabled,
      control: SliderControl(
        value: value,
        min: min,
        max: max,
        divisions: divisions > 0 && divisions <= 200 ? divisions : null,
        label: (format ?? _plain)(value),
        onChanged: (v) {
          final snapped = (v / step).round() * step;
          store.setOverride(path, step >= 1 ? snapped.round() : double.parse(snapped.toStringAsFixed(2)));
        },
      ),
    );
  }

  static String _plain(double v) => v.round().toString();
}

/// Slider with its value printed at the end.
class SliderControl extends StatelessWidget {
  const SliderControl({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    this.divisions,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Row(
        children: [
          Expanded(
            child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
          ),
          SizedBox(
            width: 52,
            child: Text(
              label,
              textAlign: TextAlign.end,
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mutually exclusive options: segmented buttons when they fit, else a
/// dropdown.
class ChoiceControl<T> extends StatelessWidget {
  const ChoiceControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.segmentWidth = 96,
  });

  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final double segmentWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits = !constraints.hasBoundedWidth || constraints.maxWidth >= options.length * segmentWidth;
        if (fits) {
          return SegmentedButton<T>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [for (final (v, label) in options) ButtonSegment(value: v, label: Text(label, maxLines: 1))],
            selected: {?value},
            onSelectionChanged: (s) {
              if (s.isNotEmpty) onChanged(s.first);
            },
          );
        }
        return DropdownButton<T>(
          value: options.any((o) => o.$1 == value) ? value : null,
          isDense: true,
          borderRadius: BorderRadius.circular(10),
          items: [for (final (v, label) in options) DropdownMenuItem(value: v, child: Text(label))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        );
      },
    );
  }
}

/// A theme colour: swatch, human name and hex; tap to edit.
class ColorTile extends StatelessWidget {
  const ColorTile({super.key, required this.label, required this.path, required this.color});

  final String label;
  final String path;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final scheme = Theme.of(context).colorScheme;
    final changed = store.isOverridden(path);
    return SizedBox(
      width: 196,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final picked = await showDialog<Color>(
            context: context,
            builder: (_) => _ColorDialog(label: label, color: color),
          );
          if (picked != null) store.setOverride(path, colorToHex(picked));
        },
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              _Swatch(color: color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      colorToHex(color),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (changed)
                IconButton(
                  tooltip: 'Reset to the theme\'s colour',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: Icon(Icons.undo_rounded, color: scheme.primary),
                  onPressed: () => store.clearOverride(path),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swatch with a checkerboard behind, so transparency is visible.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
        gradient: const SweepGradient(
          colors: [Colors.white, Color(0xFFCCCCCC), Colors.white, Color(0xFFCCCCCC), Colors.white],
          stops: [0, 0.25, 0.5, 0.75, 1],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late Color _color = widget.color;
  late final _hex = TextEditingController(text: colorToHex(widget.color));
  String? _error;

  static const _palette = [
    '#3584e4',
    '#2190a4',
    '#3a944a',
    '#c88800',
    '#ed5b00',
    '#e62d42',
    '#d56199',
    '#9141ac',
    '#6f8396',
    '#000000',
    '#1e1e1e',
    '#242424',
    '#303030',
    '#5e5c64',
    '#deddda',
    '#f6f5f4',
    '#fafafa',
    '#ffffff',
  ];

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(Color c) => setState(() {
    _color = c;
    _hex.text = colorToHex(c);
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Swatch(color: _color, size: 48),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: InputDecoration(
                      labelText: 'Hex',
                      errorText: _error,
                      helperText: '#rrggbb or #rrggbbaa',
                    ),
                    onSubmitted: (v) {
                      final c = parseColor(v.trim());
                      if (c == null) {
                        setState(() => _error = 'Not a colour');
                      } else {
                        _set(c);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in _palette)
                  InkWell(
                    customBorder: const CircleBorder(),
                    // Keep the current opacity when picking a solid colour.
                    onTap: () => _set(parseColor(hex)!.withValues(alpha: _color.a)),
                    child: _Swatch(color: parseColor(hex)!, size: 28),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Opacity'),
                Expanded(
                  child: Slider(
                    value: _color.a,
                    onChanged: (a) => _set(_color.withValues(alpha: (a * 100).round() / 100)),
                  ),
                ),
                SizedBox(width: 44, child: Text('${(_color.a * 100).round()}%', textAlign: TextAlign.end)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('Use colour')),
      ],
    );
  }
}
