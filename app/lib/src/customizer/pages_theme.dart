import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shellkit/shellkit.dart';

import '../core/algorithms.dart';
import '../core/shell_controller.dart';
import '../theme/shell_theme.dart';
import '../theme/theme_parser.dart';
import '../theme/theme_store.dart';
import '../widgets/common.dart';
import 'customizer.dart';
import 'settings.dart';
import 'theme_preview.dart';

// MARK: Themes

class ThemesPage extends StatelessWidget {
  const ThemesPage({super.key});

  Future<void> _import(BuildContext context, ThemeStore store, {required bool folder}) async {
    final ctrl = Shell.of(context);
    final path = await ctrl.bridge.host.pickPath(folder, folder ? const [] : const ['mgctheme', 'zip']);
    if (path == null) return;
    try {
      final id = await store.import(path);
      store.setActive(id);
      if (context.mounted) toast(context, 'Imported "${store.theme.name}"');
    } catch (e) {
      if (context.mounted) toast(context, 'Import failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final active = store.theme;
    return CustomizerPage(
      title: 'Themes',
      subtitle:
          'Pick a look. Each theme has its own style, top bar, dock, launcher and desktop settings — '
          'changing one theme never touches another.',
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Import',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (v) => switch (v) {
            'import' => _import(context, store, folder: false),
            'importFolder' => _import(context, store, folder: true),
            'folder' => Process.run('open', [store.userThemesDir]),
            _ => null,
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'import', child: Text('Import .mgctheme…')),
            PopupMenuItem(value: 'importFolder', child: Text('Import theme folder…')),
            PopupMenuItem(value: 'folder', child: Text('Open themes folder')),
          ],
        ),
      ],
      children: [
        if (active.warnings.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"${active.name}" has ${active.warnings.length} problem(s); defaults were used:',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  for (final w in active.warnings.take(8)) Text('• $w'),
                ],
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 16.0;
            final columns = ((constraints.maxWidth + gap) / (250 + gap)).floor().clamp(1, 4);
            final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final e in store.repository.entries)
                  SizedBox(
                    width: width,
                    child: _ThemeCard(
                      theme: e.id == store.activeId ? active : store.repository.resolve(e.id),
                      builtIn: e.builtIn,
                      active: e.id == store.activeId,
                      changes: store.changeCount(e.id),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, required this.builtIn, required this.active, required this.changes});

  final ShellTheme theme;
  final bool builtIn;
  final bool active;
  final int changes;

  Future<void> _menu(BuildContext context, String action) async {
    final store = ShellThemeScope.storeOf(context);
    final ctrl = Shell.of(context);
    final go = CustomizerNav.of(context);
    switch (action) {
      case 'customize':
        store.setActive(theme.id);
        go('style');
      case 'reset':
        if (await confirm(
          context,
          'Reset ${theme.name}?',
          'Your $changes change${changes == 1 ? '' : 's'} to this theme will be undone.',
          action: 'Reset',
        )) {
          store.resetOverrides(theme.id);
        }
      case 'copy':
        store.setActive(theme.id);
        if (context.mounted) await saveThemeAsNew(context);
      case 'export':
        store.setActive(theme.id);
        final path = await ctrl.bridge.host.savePath('${theme.id}.mgctheme');
        if (path == null) return;
        try {
          await store.export(path);
          if (context.mounted) toast(context, 'Exported to $path');
        } catch (e) {
          if (context.mounted) toast(context, 'Export failed: $e');
        }
      case 'delete':
        if (await confirm(context, 'Delete "${theme.name}"?', 'The theme folder will be removed.', action: 'Delete')) {
          await store.delete(theme.id);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final store = ShellThemeScope.storeOf(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: active ? scheme.primary : scheme.outlineVariant, width: active ? 2.5 : 1),
      ),
      child: InkWell(
        onTap: () => store.setActive(theme.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: ThemePreview(theme: theme),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(theme.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (active) _Badge('Active', color: scheme.primary, fg: scheme.onPrimary),
                            _Badge(builtIn ? 'Built-in' : 'Custom'),
                            if (changes > 0) _Badge('$changes change${changes == 1 ? '' : 's'}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Theme options',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (v) => _menu(context, v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'customize', child: Text('Customize')),
                      const PopupMenuItem(value: 'copy', child: Text('Save a copy…')),
                      const PopupMenuItem(value: 'export', child: Text('Export…')),
                      if (changes > 0) const PopupMenuItem(value: 'reset', child: Text('Reset changes')),
                      if (!builtIn) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
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

class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.color, this.fg});
  final String label;
  final Color? color;
  final Color? fg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: fg ?? scheme.onSurfaceVariant)),
    );
  }
}

/// Saves the active theme plus its changes as a new user theme.
Future<void> saveThemeAsNew(BuildContext context) async {
  final store = ShellThemeScope.storeOf(context);
  final name = await askText(context, 'Save as new theme', 'Theme name', '${store.theme.name} (custom)');
  if (name == null || name.trim().isEmpty) return;
  await store.saveAsNew(name.trim());
  if (context.mounted) toast(context, 'Saved "$name"');
}

// MARK: Style

const _interfaceSizes = [(0.85, 'Small'), (1.0, 'Default'), (1.15, 'Large'), (1.3, 'Larger')];

/// Theme colours, grouped by where they show, with names people use.
const _colorGroups = <(String, List<(String, String)>)>[
  ('Accent', [('accent', 'Accent'), ('tile.selected', 'Selection'), ('danger', 'Warning')]),
  ('Top bar', [('bar.bg', 'Background'), ('bar.fg', 'Text & icons'), ('bar.border', 'Bottom line')]),
  ('Dock', [('dock.bg', 'Background'), ('dock.fg', 'Dots & buttons'), ('icon.plate', 'Icon plates')]),
  ('Menus & popovers', [('popover.bg', 'Background'), ('popover.fg', 'Text')]),
  ('Launcher', [('overview.scrim', 'Backdrop'), ('tile.bg', 'Tiles'), ('surface', 'Surface'), ('surface.fg', 'Text')]),
];

const _weights = [(300, 'Light'), (400, 'Regular'), (500, 'Medium'), (600, 'Semibold'), (700, 'Bold'), (800, 'Heavy')];

const _fonts = [
  ('.AppleSystemUIFont', 'System (SF Pro)'),
  ('Helvetica Neue', 'Helvetica Neue'),
  ('Avenir Next', 'Avenir Next'),
  ('Futura', 'Futura'),
  ('Cantarell', 'Cantarell'),
  ('Inter', 'Inter'),
  ('Roboto', 'Roboto'),
  ('Ubuntu', 'Ubuntu'),
  ('Segoe UI Variable', 'Segoe UI'),
  ('Menlo', 'Menlo'),
];

class StylePage extends StatelessWidget {
  const StylePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final t = store.theme.tokens;
    int weightAt(String path) {
      final v = store.valueAt(path);
      return v is num ? (v / 100).round() * 100 : t.barFontWeight.value;
    }

    return CustomizerPage(
      title: 'Style',
      subtitle: 'Size, colours, text and shapes.',
      themed: true,
      children: [
        const SettingsGroup(
          title: 'Interface size',
          description:
              'Makes text, icons and corners bigger or smaller together, so the theme keeps its proportions. '
              'The top bar always fits the macOS menu bar.',
          children: [_InterfaceSizeRow()],
        ),
        SettingsGroup(
          title: 'Colours',
          children: [
            for (final (group, keys) in _colorGroups)
              SettingRow(
                title: group,
                below: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final (key, label) in keys)
                      ColorTile(label: label, path: 'tokens.color.$key', color: t.color(key)),
                  ],
                ),
              ),
          ],
        ),
        SettingsGroup(
          title: 'Text',
          children: [
            SettingRow(
              title: 'Font',
              subtitle: 'Any installed font works; pick "Other…" to type its name.',
              paths: const ['tokens.font.family'],
              control: _FontPicker(family: t.fontFamily),
            ),
            const ThemeSliderRow(title: 'Top bar text', path: 'tokens.font.size.bar', min: 10, max: 20, format: _pt),
            const ThemeSliderRow(
              title: 'Menu & launcher text',
              path: 'tokens.font.size.body',
              min: 10,
              max: 20,
              format: _pt,
            ),
            SettingRow(
              title: 'Top bar weight',
              paths: const ['tokens.font.weight.bar'],
              controlWidth: 360,
              control: ChoiceControl<int>(
                segmentWidth: 84,
                options: _weights,
                value: weightAt('tokens.font.weight.bar'),
                onChanged: (v) => store.setOverride('tokens.font.weight.bar', v),
              ),
            ),
            for (final (w, name) in [
              ('activities', 'Activities weight'),
              ('clock', 'Clock weight'),
              ('appName', 'App name weight'),
            ])
              SettingRow(
                title: name,
                paths: ['tokens.font.weight.$w'],
                controlWidth: 160,
                control: DropdownButton<int>(
                  value: _weights.any((e) => e.$1 == t.weightFor(w).value) ? t.weightFor(w).value : null,
                  isDense: true,
                  items: [for (final (v, l) in _weights) DropdownMenuItem(value: v, child: Text(l))],
                  onChanged: (v) => store.setOverride('tokens.font.weight.$w', v),
                ),
              ),
          ],
        ),
        SettingsGroup(
          title: 'Shape',
          children: [
            SettingRow(
              title: 'App icons',
              subtitle: 'Frame icons in the dock and launcher.',
              paths: const ['tokens.icon.shape'],
              controlWidth: 380,
              control: ChoiceControl<IconShape>(
                options: const [
                  (IconShape.native, 'As is'),
                  (IconShape.circle, 'Circle'),
                  (IconShape.squircle, 'Squircle'),
                  (IconShape.rounded, 'Rounded'),
                ],
                value: t.iconShape,
                onChanged: (v) => store.setOverride('tokens.icon.shape', v.name),
              ),
            ),
            const ThemeSliderRow(title: 'Dock corners', path: 'tokens.radius.dock', min: 0, max: 40),
            const ThemeSliderRow(title: 'Menu & popover corners', path: 'tokens.radius.popover', min: 0, max: 40),
            const ThemeSliderRow(title: 'Tile corners', path: 'tokens.radius.tile', min: 0, max: 40),
            SettingRow(
              title: 'Pill-shaped top bar buttons',
              paths: const ['tokens.radius.button'],
              controlWidth: 60,
              control: Switch(
                value: t.radius('button') >= 99,
                onChanged: (v) => store.setOverride('tokens.radius.button', v ? 999 : 6),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Effects',
          children: [
            const ThemeSliderRow(title: 'Dock blur', path: 'tokens.blur.dock', min: 0, max: 60),
            const ThemeSliderRow(title: 'Menu blur', path: 'tokens.blur.popover', min: 0, max: 60),
            const ThemeSliderRow(
              title: 'Animation length',
              subtitle: 'Opening and closing Activities.',
              path: 'tokens.motion.overview.ms',
              min: 0,
              max: 800,
              step: 10,
              format: _ms,
            ),
            SettingRow(
              title: 'Animation curve',
              paths: const ['tokens.motion.curve'],
              controlWidth: 200,
              control: DropdownButton<String>(
                value: switch (store.valueAt('tokens.motion.curve')) {
                  final String c when curveNames.contains(c) => c,
                  _ => 'easeOutCubic',
                },
                isDense: true,
                items: [for (final c in curveNames) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => store.setOverride('tokens.motion.curve', v),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _pt(double v) => '${v.round()} pt';
String _ms(double v) => '${v.round()} ms';
String _percent(double v) => '${(v * 100).round()}%';

class _InterfaceSizeRow extends StatelessWidget {
  const _InterfaceSizeRow();

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final scale = store.theme.tokens.scale;
    final preset = _interfaceSizes.where((s) => (s.$1 - scale).abs() < 0.005).firstOrNull?.$1;
    return SettingRow(
      title: 'Size',
      paths: const ['tokens.scale'],
      controlWidth: 400,
      control: ChoiceControl<double>(
        options: _interfaceSizes,
        value: preset,
        onChanged: (v) => store.setOverride('tokens.scale', v),
      ),
      below: Row(
        children: [
          const Icon(Icons.text_decrease_rounded, size: 18),
          Expanded(
            child: Slider(
              value: scale,
              min: minInterfaceScale,
              max: maxInterfaceScale,
              divisions: ((maxInterfaceScale - minInterfaceScale) / 0.05).round(),
              label: _percent(scale),
              onChanged: (v) => store.setOverride('tokens.scale', double.parse(v.toStringAsFixed(2))),
            ),
          ),
          const Icon(Icons.text_increase_rounded, size: 22),
          SizedBox(width: 52, child: Text(_percent(scale), textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _FontPicker extends StatelessWidget {
  const _FontPicker({required this.family});
  final String family;

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final known = _fonts.any((f) => f.$1 == family);
    return DropdownButton<String>(
      value: family,
      isDense: true,
      items: [
        for (final (f, label) in [..._fonts, if (!known) (family, family)])
          DropdownMenuItem(
            value: f,
            child: Text(
              label,
              style: TextStyle(fontFamily: f, fontFamilyFallback: ShellTokens.fontFallback),
            ),
          ),
        const DropdownMenuItem(value: '\u0000other', child: Text('Other…')),
      ],
      onChanged: (v) async {
        if (v == null) return;
        if (v == '\u0000other') {
          final name = await askText(context, 'Font', 'Installed font name', family);
          if (name != null && name.trim().isNotEmpty) store.setOverride('tokens.font.family', name.trim());
        } else {
          store.setOverride('tokens.font.family', v);
        }
      },
    );
  }
}

// MARK: Top bar

const _clockPresets = ['EEE MMM d  HH:mm', 'EEE d MMM  h:mm a', 'EEEE  ·  HH:mm', 'MMM d  HH:mm', 'HH:mm', 'h:mm a'];

class TopBarPage extends StatelessWidget {
  const TopBarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final layout = store.theme.layout;
    final on = layout.topBarEnabled;
    return CustomizerPage(
      title: 'Top bar',
      subtitle: 'The bar across the top of the screen, in place of the macOS menu bar.',
      themed: true,
      children: [
        const SettingsGroup(
          children: [
            ThemeSwitchRow(
              title: 'Show the top bar',
              subtitle: 'Covers the macOS menu bar. Turn off to keep the macOS menu bar.',
              path: 'layout.topBar.enabled',
            ),
          ],
        ),
        SettingsGroup(
          title: 'Items',
          description: 'What sits on the left, in the centre and on the right. Click the dots on an item to move it.',
          children: [
            SettingRow(
              title: 'Layout',
              paths: const ['layout.topBar.left', 'layout.topBar.center', 'layout.topBar.right'],
              enabled: on,
              below: _ZonesEditor(layout: layout),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Clock',
          children: [
            SettingRow(
              title: 'Format',
              paths: const ['layout.topBar.clockFormat'],
              enabled: on,
              below: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in _clockPresets)
                        ChoiceChip(
                          label: Text(formatClock(shellNow(), f)),
                          selected: layout.clockFormat == f,
                          onSelected: (_) => store.setOverride('layout.topBar.clockFormat', f),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 420,
                    child: TextFormField(
                      key: ValueKey('clock-${store.activeId}-${layout.clockFormat}'),
                      initialValue: layout.clockFormat,
                      decoration: const InputDecoration(
                        labelText: 'Custom',
                        isDense: true,
                        helperMaxLines: 2,
                        helperText: 'EEE/EEEE day · MMM/MMMM month · d day · HH/H 24 h · hh/h 12 h · mm · ss · a',
                      ),
                      onFieldSubmitted: (v) => store.setOverride('layout.topBar.clockFormat', v),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ZonesEditor extends StatelessWidget {
  const _ZonesEditor({required this.layout});
  final ShellLayout layout;

  static const _zones = [('left', 'Left'), ('center', 'Centre'), ('right', 'Right')];

  List<String> _items(String zone) => switch (zone) {
    'left' => layout.left,
    'center' => layout.center,
    _ => layout.right,
  };

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    void set(String zone, List<String> items) => store.setOverride('layout.topBar.$zone', items);
    void move(String from, int i, String to) {
      final src = [..._items(from)];
      final id = src.removeAt(i);
      set(from, src);
      set(to, [..._items(to), id]);
    }

    Widget zone(String id, String label) {
      final items = _items(id);
      final scheme = Theme.of(context).colorScheme;
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text('Empty', style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            for (final (i, item) in items.indexed)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Expanded(child: Text(topBarWidgets[item] ?? item, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    PopupMenuButton<String>(
                      tooltip: 'Move or remove',
                      icon: const Icon(Icons.more_horiz_rounded, size: 18),
                      onSelected: (a) {
                        final list = [...items];
                        switch (a) {
                          case 'up':
                            list.insert(i - 1, list.removeAt(i));
                            set(id, list);
                          case 'down':
                            list.insert(i + 1, list.removeAt(i));
                            set(id, list);
                          case 'remove':
                            list.removeAt(i);
                            set(id, list);
                          default:
                            move(id, i, a);
                        }
                      },
                      itemBuilder: (_) => [
                        if (i > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
                        if (i < items.length - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
                        for (final (z, l) in _zones)
                          if (z != id) PopupMenuItem(value: z, child: Text('Move to ${l.toLowerCase()}')),
                        const PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                    ),
                  ],
                ),
              ),
            PopupMenuButton<String>(
              tooltip: 'Add to ${label.toLowerCase()}',
              onSelected: (w) => set(id, [...items, w]),
              itemBuilder: (_) => [
                for (final e in topBarWidgets.entries)
                  if (e.key == 'spacer' || ![...layout.left, ...layout.center, ...layout.right].contains(e.key))
                    PopupMenuItem(value: e.key, child: Text(e.value)),
              ],
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text('Add', style: TextStyle(color: scheme.primary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final zones = [for (final (id, label) in _zones) zone(id, label)];
        if (constraints.maxWidth < 560) {
          return Column(
            children: [for (final z in zones) Padding(padding: const EdgeInsets.only(bottom: 8), child: z)],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, z) in zones.indexed) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: z)],
          ],
        );
      },
    );
  }
}

// MARK: Dock

class DockPage extends StatelessWidget {
  const DockPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final ctrl = Shell.of(context);
    final layout = store.theme.layout;
    final shown = layout.dockMode != DockMode.off;
    final always = layout.dockMode == DockMode.always;
    final magnify = layout.dockMagnification > 1.001;
    return CustomizerPage(
      title: 'Dock',
      subtitle: 'Where the dock sits, how big it is and what it holds.',
      themed: true,
      children: [
        SettingsGroup(
          title: 'Placement',
          children: [
            SettingRow(
              title: 'Show the dock',
              subtitle: '"In Activities" shows it only in the launcher, like GNOME.',
              paths: const ['layout.dock.mode'],
              controlWidth: 340,
              control: ChoiceControl<DockMode>(
                segmentWidth: 110,
                options: const [
                  (DockMode.always, 'Always'),
                  (DockMode.overviewOnly, 'In Activities'),
                  (DockMode.off, 'Off'),
                ],
                value: layout.dockMode,
                onChanged: (v) => store.setOverride('layout.dock.mode', v.name),
              ),
            ),
            SettingRow(
              title: 'Style',
              paths: const ['layout.dock.style'],
              enabled: shown,
              controlWidth: 300,
              control: ChoiceControl<DockStyle>(
                segmentWidth: 130,
                options: const [(DockStyle.floating, 'Floating'), (DockStyle.panel, 'Full-width panel')],
                value: layout.dockStyle,
                onChanged: (v) => store.setOverride('layout.dock.style', v.name),
              ),
            ),
            SettingRow(
              title: 'Position on screen',
              paths: const ['layout.dock.position'],
              enabled: always,
              controlWidth: 300,
              control: ChoiceControl<DockPosition>(
                options: const [
                  (DockPosition.left, 'Left'),
                  (DockPosition.bottom, 'Bottom'),
                  (DockPosition.right, 'Right'),
                ],
                value: layout.dockPosition,
                onChanged: (v) => store.setOverride('layout.dock.position', v.name),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Size',
          children: [
            ThemeSliderRow(
              title: 'Icon size',
              subtitle: 'Before the interface size (Style) is applied.',
              path: 'layout.dock.iconSize',
              min: 24,
              max: 96,
              format: _pt,
              enabled: shown,
            ),
            SettingRow(
              title: 'Magnify icons on hover',
              paths: const ['layout.dock.magnification'],
              enabled: always,
              controlWidth: 60,
              control: Switch(
                value: magnify,
                onChanged: (v) => store.setOverride('layout.dock.magnification', v ? 1.5 : 1.0),
              ),
            ),
            if (magnify)
              ThemeSliderRow(
                title: 'Magnification',
                path: 'layout.dock.magnification',
                min: 1.1,
                max: 2,
                step: 0.05,
                format: _percent,
                enabled: always,
              ),
          ],
        ),
        SettingsGroup(
          title: 'Contents',
          children: [
            ThemeSwitchRow(title: 'Dots under open apps', path: 'layout.dock.showRunningDots', enabled: shown),
            ThemeSwitchRow(title: '"Show Applications" button', path: 'layout.dock.showAppGridButton', enabled: shown),
            ThemeSwitchRow(
              title: '"Customize" button',
              subtitle: 'Opens this window from the dock.',
              path: 'layout.dock.showCustomizerButton',
              enabled: shown,
            ),
            SettingRow(
              title: 'Pinned apps',
              subtitle: 'Drag to reorder.',
              paths: const ['layout.dock.pinned'],
              controlWidth: 160,
              control: TextButton.icon(
                onPressed: () => _pinApp(context, ctrl, layout.pinned),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Pin an app…'),
              ),
              below: _PinnedEditor(pinned: layout.pinned, ctrl: ctrl),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Windows',
          children: [
            ThemeSwitchRow(
              title: 'Keep windows clear of the dock',
              subtitle:
                  'Maximized and tiled windows stop at the dock, like the macOS Dock. Only when the dock is '
                  'always shown; the macOS Dock stays underneath as an invisible spacer until you quit.',
              path: 'layout.dock.reserveSpace',
              enabled: always,
            ),
            SettingRow(
              title: 'Hide the macOS Dock',
              subtitle: 'Uses the Dock\'s own settings and puts them back when you quit.',
              paths: const ['system.nativeDock'],
              controlWidth: 60,
              control: Switch(
                value: store.theme.system.hideNativeDock,
                onChanged: (v) => store.setOverride('system.nativeDock', v ? 'hidden' : 'visible'),
              ),
            ),
            const _WindowPreviewsLink(),
          ],
        ),
      ],
    );
  }
}

Future<void> _pinApp(BuildContext context, ShellController ctrl, List<String> pinned) async {
  await ctrl.refreshInstalledApps();
  if (!context.mounted) return;
  final chosen = await showDialog<String>(
    context: context,
    builder: (context) =>
        _AppPickerDialog(apps: ctrl.apps.installed.where((a) => !pinned.contains(a.bundleId)).toList()),
  );
  if (chosen != null) ctrl.setPinned(chosen, true);
}

/// Window previews are app-wide (a permission, not a look); link to them.
class _WindowPreviewsLink extends StatelessWidget {
  const _WindowPreviewsLink();

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return ValueListenableBuilder(
      valueListenable: ctrl.flags,
      builder: (context, _, _) => SettingRow(
        title: 'Window previews on hover',
        subtitle: ctrl.windowThumbnails
            ? 'On: hover an app to see each of its windows, click one to switch to it.'
            : 'Off: hovering shows how many windows an app has. Turn on to see and pick them.',
        controlWidth: 140,
        control: OutlinedButton(
          onPressed: () => CustomizerNav.of(context)('windows'),
          child: Text(ctrl.windowThumbnails ? 'Settings…' : 'Set up…'),
        ),
      ),
    );
  }
}

class _PinnedEditor extends StatelessWidget {
  const _PinnedEditor({required this.pinned, required this.ctrl});

  final List<String> pinned;
  final ShellController ctrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (pinned.isEmpty) {
      return Text('Nothing pinned: the dock shows only open apps.', style: TextStyle(color: scheme.onSurfaceVariant));
    }
    return ReorderableListView(
      shrinkWrap: true,
      buildDefaultDragHandles: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorder: (from, to) {
        final list = [...pinned];
        final x = list.removeAt(from);
        list.insert(to > from ? to - 1 : to, x);
        ctrl.themes.setOverride('layout.dock.pinned', list);
      },
      children: [
        for (final b in pinned)
          ListTile(
            key: ValueKey(b),
            dense: true,
            contentPadding: const EdgeInsets.only(left: 4, right: 40),
            leading: AppIcon(b, size: 28),
            title: Text(ctrl.apps.nameFor(b)),
            trailing: IconButton(
              tooltip: 'Unpin',
              onPressed: () => ctrl.setPinned(b, false),
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
            ),
          ),
      ],
    );
  }
}

class _AppPickerDialog extends StatefulWidget {
  const _AppPickerDialog({required this.apps});
  final List<InstalledApp> apps;

  @override
  State<_AppPickerDialog> createState() => _AppPickerDialogState();
}

class _AppPickerDialogState extends State<_AppPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = fuzzyFilter(_q, widget.apps, (a) => a.name).take(60).toList();
    return AlertDialog(
      title: const Text('Pin an app'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search apps'),
              onChanged: (v) => setState(() => _q = v),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final a in list)
                    ListTile(
                      leading: AppIcon(a.path, size: 28),
                      title: Text(a.name),
                      onTap: () => Navigator.pop(context, a.bundleId),
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

// MARK: Launcher

class LauncherPage extends StatelessWidget {
  const LauncherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final t = store.theme.tokens;
    return CustomizerPage(
      title: 'Launcher',
      subtitle: 'Activities: the full-screen app grid with search.',
      themed: true,
      children: [
        const SettingsGroup(
          title: 'App grid',
          children: [
            ThemeSliderRow(
              title: 'Icon size',
              subtitle: 'Before the interface size (Style) is applied.',
              path: 'layout.launcher.iconSize',
              min: 48,
              max: 112,
              format: _pt,
            ),
            ThemeSwitchRow(title: 'App names under icons', path: 'layout.launcher.labels'),
          ],
        ),
        SettingsGroup(
          title: 'Backdrop',
          children: [
            SettingRow(
              title: 'Colour',
              paths: const ['tokens.color.overview.scrim'],
              below: Align(
                alignment: Alignment.centerLeft,
                child: ColorTile(label: 'Backdrop', path: 'tokens.color.overview.scrim', color: t.scrim),
              ),
            ),
            SettingRow(
              title: 'Texture',
              subtitle: 'A printed pattern over the backdrop.',
              paths: const ['tokens.texture.scrim'],
              controlWidth: 300,
              control: ChoiceControl<ScrimTexture>(
                options: const [
                  (ScrimTexture.none, 'None'),
                  (ScrimTexture.halftone, 'Halftone'),
                  (ScrimTexture.grain, 'Grain'),
                ],
                value: t.scrimTexture,
                onChanged: (v) => store.setOverride('tokens.texture.scrim', v.name),
              ),
            ),
            ThemeSliderRow(
              title: 'Texture strength',
              path: 'tokens.texture.strength',
              min: 0,
              max: 1,
              step: 0.05,
              format: _percent,
              enabled: t.scrimTexture != ScrimTexture.none,
            ),
          ],
        ),
      ],
    );
  }
}

// MARK: Desktop

/// macOS accent swatches (approximate system colours).
const _accentSwatches = <String, Color>{
  'multicolor': Color(0xFF007AFF),
  'blue': Color(0xFF007AFF),
  'purple': Color(0xFFA550A7),
  'pink': Color(0xFFF74F9E),
  'red': Color(0xFFFF5257),
  'orange': Color(0xFFF7821B),
  'yellow': Color(0xFFFFC600),
  'green': Color(0xFF62BA46),
  'graphite': Color(0xFF8C8C8C),
};

class DesktopPage extends StatelessWidget {
  const DesktopPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final store = ShellThemeScope.storeOf(context);
    final s = store.theme.system;
    Future<void> pickWallpaper(String variant) async {
      final path = await ctrl.bridge.host.pickPath(false, const ['jpg', 'jpeg', 'png', 'heic']);
      if (path == null) return;
      // Always write both variants: a single-string wallpaper (e.g. Windows 11)
      // must not be lost when only one variant is picked.
      store.setOverride('system.wallpaper', {
        'light': variant == 'light' ? path : s.wallpaperLight,
        'dark': variant == 'dark' ? path : s.wallpaperDark,
      });
    }

    return CustomizerPage(
      title: 'Desktop',
      subtitle:
          'macOS settings this theme sets while it\'s active. They\'re saved before the first change and put back '
          'from the Safety page.',
      themed: true,
      actions: [
        FilledButton.tonalIcon(
          onPressed: ctrl.applySystemNow,
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Apply now'),
        ),
      ],
      children: [
        SettingsGroup(
          title: 'Wallpaper',
          children: [
            SettingRow(
              title: 'Pictures',
              subtitle: 'The dark one is used while macOS is in dark mode.',
              paths: const ['system.wallpaper'],
              below: Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  for (final (variant, path) in [('Light', s.wallpaperLight), ('Dark', s.wallpaperDark)])
                    _WallpaperTile(label: variant, path: path, onPick: () => pickWallpaper(variant.toLowerCase())),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Appearance',
          children: [
            SettingRow(
              title: 'Light or dark',
              paths: const ['system.darkMode'],
              controlWidth: 330,
              control: ChoiceControl<Appearance>(
                segmentWidth: 106,
                options: const [
                  (Appearance.untouched, "Don't change"),
                  (Appearance.light, 'Light'),
                  (Appearance.dark, 'Dark'),
                ],
                value: s.appearance,
                onChanged: (v) => store.setOverride('system.darkMode', v.name),
              ),
            ),
            SettingRow(
              title: 'Accent colour',
              subtitle: 'Buttons and selections in every app.',
              paths: const ['system.accent'],
              below: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text("Don't change"),
                    selected: s.accent == null,
                    onSelected: (_) => store.setOverride('system.accent', null),
                  ),
                  for (final e in accentNames.entries)
                    Tooltip(
                      message: e.key,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => store.setOverride('system.accent', e.key),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _accentSwatches[e.key],
                            gradient: e.key == 'multicolor'
                                ? const SweepGradient(
                                    colors: [
                                      Color(0xFFFF5257),
                                      Color(0xFFF7821B),
                                      Color(0xFFFFC600),
                                      Color(0xFF62BA46),
                                      Color(0xFF007AFF),
                                      Color(0xFFA550A7),
                                      Color(0xFFFF5257),
                                    ],
                                  )
                                : null,
                            border: Border.all(
                              color: s.accent == e.value ? Theme.of(context).colorScheme.onSurface : Colors.black12,
                              width: s.accent == e.value ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({required this.label, required this.path, required this.onPick});
  final String label;
  final String? path;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final file = path == null ? null : File(path!);
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPick,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: file != null && file.existsSync()
                    ? Image.file(file, fit: BoxFit.cover, cacheWidth: 440)
                    : ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Center(
                          child: Text('None', style: TextStyle(color: scheme.onSurfaceVariant)),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
              TextButton(onPressed: onPick, child: const Text('Choose…')),
            ],
          ),
        ],
      ),
    );
  }
}

Future<String?> askText(BuildContext context, String title, String label, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
      ],
    ),
  ).whenComplete(controller.dispose);
}
