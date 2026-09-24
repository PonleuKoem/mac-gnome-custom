import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shellkit/shellkit.dart';

import '../core/shell_controller.dart';
import '../theme/shell_theme.dart';
import '../widgets/common.dart';
import 'customizer.dart';
import 'settings.dart';

// MARK: Onboarding

/// First run: nothing on the system changes until the user presses Start
/// (DESIGN.md §4.8 — the snapshot is taken right before the first change).
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _launchAtLogin = true;

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final store = ShellThemeScope.storeOf(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(40),
            shrinkWrap: true,
            children: [
              Text('Welcome to mac-gnome-custom', style: text.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'A themable shell for macOS: top bar, dock, app launcher and themes. '
                'Nothing on your Mac changes until you press Start, and everything can be undone from the '
                'Safety page or by quitting.',
                style: text.bodyLarge,
              ),
              const SectionTitle('1 · Privacy'),
              const PrivacySummary(),
              const SectionTitle('2 · Choose a look'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in store.repository.entries)
                    ChoiceChip(
                      label: Text(e.name),
                      selected: store.activeId == e.id,
                      onSelected: (_) => store.setActive(e.id),
                    ),
                ],
              ),
              const SectionTitle('3 · Startup'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _launchAtLogin,
                onChanged: (v) => setState(() => _launchAtLogin = v ?? false),
                title: const Text('Start mac-gnome-custom when I log in'),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      if (_launchAtLogin) {
                        try {
                          await ctrl.bridge.host.setLaunchAtLogin(true);
                        } catch (_) {
                          // Unsigned dev builds can't register login items; not fatal.
                        }
                      }
                      store.setOnboarded(true);
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start'),
                  ),
                  const SizedBox(width: 16),
                  Text('Tip: ⌥Space opens Activities.', style: text.bodyMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// MARK: Privacy

/// Window previews (the one opt-in permission) and what the shell can and
/// cannot access (interface-only scope, ADR-0012).
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomizerPage(
      title: 'Windows & privacy',
      subtitle:
          'mac-gnome-custom only customizes the interface. It needs no special permissions unless you turn '
          'on window previews.',
      children: [
        WindowThumbnailsSection(),
        SettingsGroup(
          title: 'What the app can access',
          children: [Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 12), child: PrivacySummary())],
        ),
      ],
    );
  }
}

class PrivacySummary extends StatelessWidget {
  const PrivacySummary({super.key});

  static const _never = [
    'Read your keystrokes (shortcuts use macOS\'s hotkey API, which only reports the chords you set)',
    'Change volume, Wi-Fi or power, lock the screen, or log you out',
    'Connect to the internet',
  ];

  /// Depends on the opt-in window thumbnails.
  static const _windowsOff = [
    'See or record the screen or other apps\' windows (it only counts how many an app has open)',
    'Move, close or click anything inside other apps',
  ];
  static const _windowsOn = [
    'Window thumbnails (you turned them on): takes small pictures of an app\'s windows while you hover its '
        'dock icon — kept in memory for that moment only, never saved or sent',
    'Brings the one window you click to the front (Accessibility); nothing else inside other apps',
  ];

  static const _does = [
    'Draws its own top bar, dock and launcher',
    'Opens apps the way the Dock does',
    'Changes appearance settings you choose: Dock visibility, wallpaper, dark mode, accent colour '
        '(snapshotted first, every change journaled and reversible)',
    'Reads status for the top bar: battery, volume level, Wi-Fi on/off, running apps',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(IconData icon, Color color, String text) => ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(text),
    );
    final ctrl = Shell.maybeOf(context);
    if (ctrl == null) return _build(context, false, row, scheme);
    return ValueListenableBuilder(
      valueListenable: ctrl.flags,
      builder: (context, _, _) => _build(context, ctrl.windowThumbnails, row, scheme),
    );
  }

  Widget _build(BuildContext context, bool thumbs, Widget Function(IconData, Color, String) row, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Never', style: Theme.of(context).textTheme.titleSmall),
        for (final t in _never) row(Icons.block_rounded, scheme.error, t),
        if (!thumbs)
          for (final t in _windowsOff) row(Icons.block_rounded, scheme.error, t),
        const SizedBox(height: 8),
        Text('Does', style: Theme.of(context).textTheme.titleSmall),
        for (final t in _does) row(Icons.check_circle_rounded, Colors.green, t),
        if (thumbs)
          for (final t in _windowsOn) row(Icons.photo_library_outlined, Colors.orange, t),
        const SizedBox(height: 8),
        const Text('macOS may ask once for Automation (System Events) the first time a theme switches dark mode.'),
      ],
    );
  }
}

/// The one opt-in exception to the interface-only scope (ADR-0012).
class WindowThumbnailsSection extends StatefulWidget {
  const WindowThumbnailsSection({super.key});

  @override
  State<WindowThumbnailsSection> createState() => _WindowThumbnailsSectionState();
}

class _WindowThumbnailsSectionState extends State<WindowThumbnailsSection> {
  ThumbnailPermissions? _perms;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // macOS grants these in System Settings; follow along while this is open.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && Shell.of(context).windowThumbnails) _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final p = await Shell.of(context).bridge.diagnostics.thumbnailPermissions();
      if (mounted) setState(() => _perms = p);
    } catch (_) {}
  }

  Future<void> _toggle(bool on) async {
    final ctrl = Shell.of(context);
    await ctrl.setFlag('windowThumbnails', on);
    if (on) await ctrl.bridge.diagnostics.requestThumbnailPermissions();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return ValueListenableBuilder(
      valueListenable: ctrl.flags,
      builder: (context, _, _) {
        final on = ctrl.windowThumbnails;
        final p = _perms;
        Widget status(String label, String purpose, bool? granted, String pane) => SettingRow(
          title: '$label: ${granted == true ? 'allowed' : 'not allowed yet'}',
          subtitle: purpose,
          controlWidth: 200,
          control: granted == true
              ? const Icon(Icons.check_circle_rounded, color: Colors.green)
              : OutlinedButton(
                  onPressed: () => ctrl.bridge.diagnostics.openPrivacySettings(pane),
                  child: const Text('Open System Settings'),
                ),
        );
        return SettingsGroup(
          title: 'Window previews',
          description:
              'Hover an app in the dock to see a small picture of each of its windows, then click one to '
              'switch to exactly that window.',
          children: [
            SettingRow(
              title: 'Show window previews in the dock',
              subtitle:
                  'Off: the dock only counts an app\'s windows. On: needs two macOS permissions, below. '
                  'Pictures are taken only while you hover, kept in memory for that moment, never saved or sent.',
              controlWidth: 60,
              control: Switch(value: on, onChanged: _toggle),
            ),
            if (on) ...[
              status(
                'Accessibility',
                'Needed to switch to the window you click (and to list windows by title).',
                p?.accessibility,
                'Accessibility',
              ),
              status(
                'Screen Recording',
                'Needed for the pictures. Without it, windows show by title only.',
                p?.screenRecording,
                'ScreenCapture',
              ),
              if (p != null && !p.screenRecording)
                const SettingRow(
                  title: 'After allowing Screen Recording',
                  subtitle: 'macOS may ask you to quit and reopen mac-gnome-custom before pictures appear.',
                ),
            ],
          ],
        );
      },
    );
  }
}

// MARK: Keybindings

class ShortcutsPage extends StatelessWidget {
  const ShortcutsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final bindings = store.theme.keybindings;
    return CustomizerPage(
      title: 'Shortcuts',
      subtitle:
          'The shell only ever receives these exact key combinations (macOS\'s public hotkey API). '
          'Combinations macOS reserves, like ⌘Tab and ⌘Space, can\'t be used.',
      themed: true,
      children: [
        SettingsGroup(
          children: [
            for (final e in keybindingActions.entries)
              _BindingRow(
                action: e.key,
                label: e.value,
                chord: bindings[e.key],
                sharedWith: [
                  for (final o in bindings.entries)
                    if (o.key != e.key && o.value.isNotEmpty && o.value == bindings[e.key])
                      keybindingActions[o.key] ?? o.key,
                ],
                onChanged: (chord) => store.setOverride('keybindings.${e.key}', chord ?? ''),
              ),
          ],
        ),
      ],
    );
  }
}

class _BindingRow extends StatelessWidget {
  const _BindingRow({
    required this.action,
    required this.label,
    required this.chord,
    required this.sharedWith,
    required this.onChanged,
  });

  final String action;
  final String label;
  final String? chord;

  /// Other actions bound to the same chord (only one of them can win).
  final List<String> sharedWith;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return SettingRow(
      title: label,
      paths: ['keybindings.$action'],
      controlWidth: 200,
      below: chord == null || chord!.isEmpty
          ? null
          : FutureBuilder<List<String>>(
              future: ctrl.bridge.hotkeys.conflicts(chord!),
              builder: (context, snap) {
                final c = [...sharedWith.map((a) => 'also bound to "$a"'), ...?snap.data];
                if (c.isEmpty) return const SizedBox.shrink();
                return Text(
                  'Conflicts with: ${c.join('; ')}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                );
              },
            ),
      control: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(label: Text(prettyChord(chord))),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () async {
              final recorded = await showDialog<String>(
                context: context,
                builder: (_) => _RecordDialog(ctrl: ctrl),
              );
              if (recorded != null) onChanged(recorded.isEmpty ? null : recorded);
            },
            child: const Text('Change…'),
          ),
        ],
      ),
    );
  }
}

String prettyChord(String? chord) {
  if (chord == null || chord.isEmpty) return 'Unset';
  const glyphs = {
    'cmd': '⌘',
    'ctrl': '⌃',
    'alt': '⌥',
    'shift': '⇧',
    'left': '←',
    'right': '→',
    'up': '↑',
    'down': '↓',
    'grave': '`',
    'tab': '⇥',
    'escape': 'Esc',
    'return': '↩',
    'space': 'Space',
  };
  return chord.split('+').map((p) => glyphs[p] ?? p.toUpperCase()).join();
}

/// Captures the next key combination pressed in the Customizer window (a
/// normal key window — no system-wide keyboard access). The shell's own
/// hotkeys are unregistered meanwhile so the chord reaches this dialog; native
/// re-registers them if the Customizer closes with the dialog open.
class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.ctrl});
  final ShellController ctrl;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final _focus = FocusNode();
  String? _chord;

  @override
  void initState() {
    super.initState();
    widget.ctrl.bridge.hotkeys.setSuspended(true);
  }

  @override
  void dispose() {
    widget.ctrl.bridge.hotkeys.setSuspended(false);
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    final name = physicalKeyNames[e.physicalKey];
    if (name == null) return KeyEventResult.handled; // a bare modifier
    final hw = HardwareKeyboard.instance;
    final parts = [
      if (hw.isControlPressed) 'ctrl',
      if (hw.isAltPressed) 'alt',
      if (hw.isShiftPressed) 'shift',
      if (hw.isMetaPressed) 'cmd',
      name,
    ];
    setState(() => _chord = parts.join('+'));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Press a shortcut'),
      content: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SizedBox(
          width: 360,
          height: 90,
          child: Center(child: Text(prettyChord(_chord), style: Theme.of(context).textTheme.headlineSmall)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Clear')),
        FilledButton(onPressed: _chord == null ? null : () => Navigator.pop(context, _chord), child: const Text('Use')),
      ],
    );
  }
}

/// Physical (layout-independent) keys → chord names understood by ShellKit.
final physicalKeyNames = <PhysicalKeyboardKey, String>{
  for (var i = 0; i < 26; i++) _letters[i]: String.fromCharCode(97 + i),
  PhysicalKeyboardKey.digit0: '0',
  PhysicalKeyboardKey.digit1: '1',
  PhysicalKeyboardKey.digit2: '2',
  PhysicalKeyboardKey.digit3: '3',
  PhysicalKeyboardKey.digit4: '4',
  PhysicalKeyboardKey.digit5: '5',
  PhysicalKeyboardKey.digit6: '6',
  PhysicalKeyboardKey.digit7: '7',
  PhysicalKeyboardKey.digit8: '8',
  PhysicalKeyboardKey.digit9: '9',
  PhysicalKeyboardKey.arrowLeft: 'left',
  PhysicalKeyboardKey.arrowRight: 'right',
  PhysicalKeyboardKey.arrowUp: 'up',
  PhysicalKeyboardKey.arrowDown: 'down',
  PhysicalKeyboardKey.tab: 'tab',
  PhysicalKeyboardKey.space: 'space',
  PhysicalKeyboardKey.enter: 'return',
  PhysicalKeyboardKey.escape: 'escape',
  PhysicalKeyboardKey.backquote: 'grave',
  PhysicalKeyboardKey.minus: 'minus',
  PhysicalKeyboardKey.equal: 'equal',
  PhysicalKeyboardKey.comma: 'comma',
  PhysicalKeyboardKey.period: 'period',
  PhysicalKeyboardKey.slash: 'slash',
  PhysicalKeyboardKey.backslash: 'backslash',
  PhysicalKeyboardKey.semicolon: 'semicolon',
  PhysicalKeyboardKey.quote: 'quote',
  PhysicalKeyboardKey.bracketLeft: 'leftbracket',
  PhysicalKeyboardKey.bracketRight: 'rightbracket',
  PhysicalKeyboardKey.backspace: 'delete',
  PhysicalKeyboardKey.f1: 'f1',
  PhysicalKeyboardKey.f2: 'f2',
  PhysicalKeyboardKey.f3: 'f3',
  PhysicalKeyboardKey.f4: 'f4',
  PhysicalKeyboardKey.f5: 'f5',
  PhysicalKeyboardKey.f6: 'f6',
  PhysicalKeyboardKey.f7: 'f7',
  PhysicalKeyboardKey.f8: 'f8',
  PhysicalKeyboardKey.f9: 'f9',
  PhysicalKeyboardKey.f10: 'f10',
  PhysicalKeyboardKey.f11: 'f11',
  PhysicalKeyboardKey.f12: 'f12',
};

const _letters = [
  PhysicalKeyboardKey.keyA,
  PhysicalKeyboardKey.keyB,
  PhysicalKeyboardKey.keyC,
  PhysicalKeyboardKey.keyD,
  PhysicalKeyboardKey.keyE,
  PhysicalKeyboardKey.keyF,
  PhysicalKeyboardKey.keyG,
  PhysicalKeyboardKey.keyH,
  PhysicalKeyboardKey.keyI,
  PhysicalKeyboardKey.keyJ,
  PhysicalKeyboardKey.keyK,
  PhysicalKeyboardKey.keyL,
  PhysicalKeyboardKey.keyM,
  PhysicalKeyboardKey.keyN,
  PhysicalKeyboardKey.keyO,
  PhysicalKeyboardKey.keyP,
  PhysicalKeyboardKey.keyQ,
  PhysicalKeyboardKey.keyR,
  PhysicalKeyboardKey.keyS,
  PhysicalKeyboardKey.keyT,
  PhysicalKeyboardKey.keyU,
  PhysicalKeyboardKey.keyV,
  PhysicalKeyboardKey.keyW,
  PhysicalKeyboardKey.keyX,
  PhysicalKeyboardKey.keyY,
  PhysicalKeyboardKey.keyZ,
];

// MARK: General

class GeneralPage extends StatelessWidget {
  const GeneralPage({super.key});

  static const flagLabels = {
    'menuBarCover': ('Cover the macOS menu bar', 'Lets the top bar sit over the menu bar.'),
    'dockHideNative': ('Allow hiding the macOS Dock', 'Lets themes hide the Dock (put back when you quit).'),
    'hotCorner': ('Top-left hot corner', 'Moving the pointer into the top-left corner opens Activities.'),
  };

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return CustomizerPage(
      title: 'General',
      subtitle: 'Settings for the app itself, whatever the theme.',
      children: [
        SettingsGroup(
          title: 'Startup',
          children: [
            FutureBuilder<bool>(
              future: ctrl.bridge.host.launchAtLogin(),
              builder: (context, snap) => _LoginSwitch(initial: snap.data ?? false, ctrl: ctrl),
            ),
          ],
        ),
        ValueListenableBuilder<Map<String, bool>>(
          valueListenable: ctrl.flags,
          builder: (context, flags, _) => SettingsGroup(
            title: 'Workarounds',
            description: 'Each macOS workaround can be switched off if a macOS update breaks it (ADR-0001).',
            children: [
              for (final e in flagLabels.entries)
                SettingRow(
                  title: e.value.$1,
                  subtitle: e.value.$2,
                  controlWidth: 60,
                  control: Switch(value: flags[e.key] ?? true, onChanged: (v) => ctrl.setFlag(e.key, v)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginSwitch extends StatefulWidget {
  const _LoginSwitch({required this.initial, required this.ctrl});
  final bool initial;
  final ShellController ctrl;

  @override
  State<_LoginSwitch> createState() => _LoginSwitchState();
}

class _LoginSwitchState extends State<_LoginSwitch> {
  late bool _on = widget.initial;

  @override
  void didUpdateWidget(_LoginSwitch old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial) _on = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: 'Open at login',
      subtitle: 'Start the shell when you log in to your Mac.',
      controlWidth: 60,
      control: Switch(
        value: _on,
        onChanged: (v) async {
          try {
            await widget.ctrl.bridge.host.setLaunchAtLogin(v);
            if (mounted) setState(() => _on = v);
          } catch (e) {
            if (context.mounted) toast(context, 'Could not change login item: $e');
          }
        },
      ),
    );
  }
}

// MARK: Diagnostics

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Timer? _timer;
  DiagnosticsInfo? _info;
  final List<FrameTiming> _timings = [];

  late final ShellController _ctrl = Shell.of(context);

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ctrl.customizerVisible.addListener(_visibilityChanged);
      _visibilityChanged();
    });
  }

  /// A hidden Customizer keeps this page mounted; never poll while hidden
  /// (idle budget).
  void _visibilityChanged() {
    _timer?.cancel();
    _timer = null;
    if (_ctrl.customizerVisible.value) {
      _poll();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.customizerVisible.removeListener(_visibilityChanged);
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> t) {
    _timings.addAll(t);
    if (_timings.length > 240) _timings.removeRange(0, _timings.length - 240);
  }

  Future<void> _poll() async {
    try {
      final info = await _ctrl.bridge.diagnostics.info();
      if (mounted) setState(() => _info = info);
    } catch (_) {}
  }

  double _p95(Duration Function(FrameTiming) f) {
    if (_timings.isEmpty) return 0;
    final v = _timings.map((t) => f(t).inMicroseconds / 1000).toList()..sort();
    return v[(v.length * 0.95).floor().clamp(0, v.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    final i = _info;
    return CustomizerPage(
      title: 'Diagnostics',
      subtitle: 'Live health of the native services (DESIGN.md §7). No telemetry leaves this Mac.',
      children: [
        if (i == null)
          const LinearProgressIndicator()
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric('Shortcuts registered', '${i.hotkeysRegistered}'),
              _Metric(
                'Shortcuts refused by macOS',
                ctrl.rejectedShortcuts.value.isEmpty
                    ? 'none'
                    : ctrl.rejectedShortcuts.value.map(prettyChord).join(', '),
              ),
              _Metric('Crash guardian', i.guardianRunning ? 'running' : 'not running'),
              _Metric('UI build p95', '${_p95((t) => t.buildDuration).toStringAsFixed(1)} ms'),
              _Metric('Raster p95', '${_p95((t) => t.rasterDuration).toStringAsFixed(1)} ms'),
              // Frames that missed 60 fps, across every panel, while this page
              // is open: open it, use the dock/launcher, then read it.
              _Metric(
                'Slow frames (> 16.7 ms)',
                '${_timings.where((t) => t.totalSpan.inMicroseconds > 16700).length} of ${_timings.length}',
              ),
            ],
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

// MARK: Safety

class SafetyPage extends StatefulWidget {
  const SafetyPage({super.key});

  @override
  State<SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends State<SafetyPage> {
  List<String> _journal = const [];
  bool _hasSnapshot = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final safety = Shell.of(context).bridge.safety;
    final journal = await safety.journal();
    final snap = await safety.hasSnapshot();
    if (mounted) {
      setState(() {
        _journal = journal.reversed.toList();
        _hasSnapshot = snap;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Shell.of(context);
    return CustomizerPage(
      title: 'Safety',
      subtitle: 'Your original macOS settings were saved before the first change. Everything can be put back.',
      actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_hasSnapshot ? Icons.inventory_2_outlined : Icons.info_outline),
          title: Text(_hasSnapshot ? 'Original settings snapshot saved' : 'No snapshot yet (nothing has been changed)'),
          subtitle: const Text('~/Library/Application Support/MacGnomeCustom/snapshots/original.json'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await ctrl.bridge.safety.restoreRuntime();
                await _refresh();
                if (context.mounted) toast(context, 'macOS Dock restored');
              },
              icon: const Icon(Icons.dock_outlined),
              label: const Text('Show the macOS Dock'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () async {
                if (!await confirm(
                  context,
                  'Restore macOS?',
                  'Dock, menu bar, dark mode, accent colour and wallpaper go back to how they were before '
                      'mac-gnome-custom first changed them. The shell will switch to the Classic Mac theme.',
                  action: 'Restore',
                )) {
                  return;
                }
                await ctrl.restoreMacOS();
                await _refresh();
                if (context.mounted) toast(context, 'macOS restored');
              },
              icon: const Icon(Icons.settings_backup_restore_rounded),
              label: const Text('Restore macOS to original'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                if (await confirm(context, 'Quit the shell?', 'The macOS Dock comes back.', action: 'Quit')) {
                  await ctrl.bridge.host.quit();
                }
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Quit mac-gnome-custom'),
            ),
          ],
        ),
        const SectionTitle('Emergency'),
        const Text(
          '• If the shell crashes, a guardian process restores the Dock.\n'
          '• From Terminal: "mac-gnome-custom.app/Contents/MacOS/mac-gnome-custom --restore".',
        ),
        const SectionTitle('Change journal'),
        if (_journal.isEmpty) const Text('No changes recorded.'),
        for (final line in _journal.take(100)) Text(line, style: const TextStyle(fontFamily: 'Menlo', fontSize: 12)),
      ],
    );
  }
}
