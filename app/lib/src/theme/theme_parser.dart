import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import 'json_util.dart';
import 'shell_theme.dart';

/// Current theme schema version. Bump with a migration in [migrate].
const themeSchemaVersion = 1;

/// Built-in defaults every theme extends. A theme file only has to state what
/// it changes; an invalid value falls back per token with a warning.
const Map<String, dynamic> defaultThemeJson = {
  'schema': 1,
  'id': 'default',
  'name': 'Default',
  'tokens': {
    'color': {
      'bar.bg': '#000000',
      'bar.fg': '#ffffff',
      'accent': '#3584e4',
      'surface': '#242424',
      'surface.fg': '#ffffff',
      'overview.scrim': '#000000cc',
      'dock.bg': '#2e2e33e6',
      'popover.bg': '#303030',
      'popover.fg': '#ffffff',
      'tile.bg': '#ffffff14',
      'tile.selected': '#3584e4',
      'workspace.active': '#ffffff',
      'workspace.inactive': '#ffffff66',
      'danger': '#e01b24',
      'icon.plate': '#ffffff',
      'bar.border': '#00000000',
    },
    'font': {'family': 'Cantarell', 'size.bar': 14, 'weight.bar': 700, 'size.body': 14},
    'radius': {'tile': 12, 'popover': 14, 'dock': 18, 'button': 999},
    'blur': {'dock': 24, 'popover': 0, 'bar': 0},
    'motion': {'overview.ms': 250, 'curve': 'easeOutCubic'},
    'icon': {'shape': 'native'},
    'texture': {'scrim': 'none', 'strength': 0.1},
    // Interface size: one multiplier for text, icons and corners, so a theme
    // stays in proportion when made bigger or smaller.
    'scale': 1.0,
  },
  'layout': {
    'topBar': {
      'enabled': true,
      'left': ['activities'],
      'center': ['clock'],
      'right': ['appName', 'indicators'],
      'clockFormat': 'EEE MMM d  HH:mm',
    },
    'dock': {
      'mode': 'overviewOnly',
      'position': 'bottom',
      'iconSize': 56,
      'showRunningDots': true,
      'showAppGridButton': true,
      'showCustomizerButton': true,
      'reserveSpace': true,
      'magnification': 1.5,
      'pinned': ['com.apple.finder', 'com.apple.Safari', 'com.apple.mail', 'com.apple.Terminal'],
      'style': 'floating',
    },
    'launcher': {'iconSize': 72, 'labels': true},
  },
  'system': {'darkMode': 'untouched', 'accent': null, 'wallpaper': null, 'nativeDock': 'hidden'},
  'icons': {'pack': null},
  // Public RegisterEventHotKey chords only (ADR-0012). Not ⌃Space: that
  // switches input sources (e.g. Khmer ↔ English).
  'keybindings': {'overview': 'alt+space', 'appGrid': 'ctrl+alt+space'},
};

const _curves = <String, Curve>{
  'linear': Curves.linear,
  'ease': Curves.ease,
  'easeIn': Curves.easeIn,
  'easeOut': Curves.easeOut,
  'easeInOut': Curves.easeInOut,
  'easeOutCubic': Curves.easeOutCubic,
  'easeInOutCubic': Curves.easeInOutCubic,
  'easeOutQuart': Curves.easeOutQuart,
  'easeOutBack': Curves.easeOutBack,
  'fastOutSlowIn': Curves.fastOutSlowIn,
};

/// Range of `tokens.scale` (Interface size).
const minInterfaceScale = 0.75;
const maxInterfaceScale = 1.5;

List<String> get curveNames => _curves.keys.toList();

/// Upgrades older theme files in place. Only v1 exists today.
Map<String, dynamic> migrate(Map<String, dynamic> json) => json;

class ThemeParser {
  ThemeParser._(this._json, this._dir);

  final Map<String, dynamic> _json;
  final String? _dir;
  final List<String> _warnings = [];

  /// Builds a theme from an already-merged JSON map. [dir] resolves relative
  /// asset paths (wallpapers, icon pack).
  static ShellTheme parse(Map<String, dynamic> merged, {String? dir}) {
    final json = deepMerge(defaultThemeJson, migrate(merged));
    return ThemeParser._(json, dir)._build();
  }

  ShellTheme _build() {
    final schema = readPath(_json, 'schema');
    if (schema is num && schema > themeSchemaVersion) {
      _warn('schema $schema is newer than this app understands ($themeSchemaVersion)');
    }
    final scale = _number('tokens.scale', min: minInterfaceScale, max: maxInterfaceScale);
    final tokens = ShellTokens(
      colors: _colors(),
      fontFamily: _string('tokens.font.family'),
      barFontSize: _number('tokens.font.size.bar', min: 8, max: 32) * scale,
      barFontWeight: _weight('tokens.font.weight.bar'),
      bodyFontSize: _number('tokens.font.size.body', min: 8, max: 32) * scale,
      // Pill radii (≥ 99) stay pills.
      radii: _numberMap('tokens.radius', max: 999).map((k, v) => MapEntry(k, v >= 99 ? v : v * scale)),
      scale: scale,
      blur: _numberMap('tokens.blur', max: 100),
      overviewDuration: Duration(milliseconds: _number('tokens.motion.overview.ms', min: 0, max: 2000).round()),
      curve: _curve('tokens.motion.curve'),
      iconShape: _enum('tokens.icon.shape', IconShape.values),
      widgetWeights: _widgetWeights(),
      scrimTexture: _enum('tokens.texture.scrim', ScrimTexture.values),
      textureStrength: _number('tokens.texture.strength', min: 0, max: 1),
    );
    final layout = ShellLayout(
      topBarEnabled: _bool('layout.topBar.enabled'),
      left: _widgetList('layout.topBar.left'),
      center: _widgetList('layout.topBar.center'),
      right: _widgetList('layout.topBar.right'),
      clockFormat: _string('layout.topBar.clockFormat'),
      dockMode: _enum('layout.dock.mode', DockMode.values),
      dockPosition: _enum('layout.dock.position', DockPosition.values),
      dockIconSize: _number('layout.dock.iconSize', min: 24, max: 128) * scale,
      showRunningDots: _bool('layout.dock.showRunningDots'),
      pinned: _stringList('layout.dock.pinned').toSet().toList(growable: false),
      showAppGridButton: _bool('layout.dock.showAppGridButton'),
      showCustomizerButton: _bool('layout.dock.showCustomizerButton'),
      reserveDockSpace: _bool('layout.dock.reserveSpace'),
      dockMagnification: _number('layout.dock.magnification', min: 1, max: 2),
      dockStyle: _enum('layout.dock.style', DockStyle.values),
      launcherIconSize: _number('layout.launcher.iconSize', min: 48, max: 112) * scale,
      launcherLabels: _bool('layout.launcher.labels'),
    );
    final system = SystemBlock(
      appearance: _appearance(),
      accent: _accent(),
      wallpaperLight: _wallpaper('light'),
      wallpaperDark: _wallpaper('dark'),
      hideNativeDock: readPath(_json, 'system.nativeDock') != 'visible',
    );
    final pack = readPath(_json, 'icons.pack');
    return ShellTheme(
      id: _json['id'] is String ? _json['id'] as String : 'unnamed',
      name: _json['name'] is String ? _json['name'] as String : 'Unnamed theme',
      tokens: tokens,
      layout: layout,
      system: system,
      keybindings: _keybindings(),
      iconPackDir: pack is String && _dir != null ? p.normalize(p.join(_dir, pack)) : null,
      sourceDir: _dir,
      raw: _json,
      warnings: List.unmodifiable(_warnings),
    );
  }

  void _warn(String message) => _warnings.add(message);

  Object? _fallback(String path) => readPath(defaultThemeJson, path);

  Map<String, Color> _colors() {
    final out = <String, Color>{};
    final defaults = Map<String, dynamic>.from(readPath(defaultThemeJson, 'tokens.color') as Map);
    final given = readPath(_json, 'tokens.color');
    final map = given is Map ? Map<String, dynamic>.from(given) : <String, dynamic>{};
    for (final key in {...defaults.keys, ...map.keys}) {
      final c = parseColor(map[key]);
      if (c != null) {
        out[key] = c;
      } else {
        if (map.containsKey(key)) _warn('tokens.color.$key: "${map[key]}" is not a #rrggbb[aa] color');
        final d = parseColor(defaults[key]);
        if (d != null) out[key] = d;
      }
    }
    // dock.fg follows surface.fg unless the theme sets it, so older themes
    // keep their look.
    out.putIfAbsent('dock.fg', () => out['surface.fg']!);
    return out;
  }

  /// `tokens.font.weight.<topBarWidget>` entries (weight.bar is the default).
  Map<String, FontWeight> _widgetWeights() {
    final font = readPath(_json, 'tokens.font');
    if (font is! Map) return const {};
    final out = <String, FontWeight>{};
    for (final e in font.entries) {
      final key = e.key as String;
      if (!key.startsWith('weight.') || key == 'weight.bar') continue;
      final widget = key.substring('weight.'.length);
      if (!topBarWidgets.containsKey(widget)) {
        _warn('tokens.font.$key: unknown top-bar widget "$widget"');
      } else if (e.value is num) {
        out[widget] = _toWeight(e.value as num);
      } else {
        _warn('tokens.font.$key: expected 100…900');
      }
    }
    return out;
  }

  double _number(String path, {double min = double.negativeInfinity, double max = double.infinity}) {
    final v = readPath(_json, path);
    if (v is num && v >= min && v <= max) return v.toDouble();
    _warn('$path: expected a number in [$min, $max], got "$v"');
    return (_fallback(path) as num).toDouble();
  }

  Map<String, double> _numberMap(String path, {double max = double.infinity}) {
    final out = <String, double>{};
    final defaults = Map<String, dynamic>.from(_fallback(path) as Map);
    final given = readPath(_json, path);
    final map = given is Map ? Map<String, dynamic>.from(given) : <String, dynamic>{};
    for (final key in {...defaults.keys, ...map.keys}) {
      final v = map[key];
      if (v is num && v >= 0 && v <= max) {
        out[key] = v.toDouble();
      } else {
        if (map.containsKey(key)) _warn('$path.$key: expected 0…$max, got "$v"');
        if (defaults[key] is num) out[key] = (defaults[key] as num).toDouble();
      }
    }
    return out;
  }

  String _string(String path) {
    final v = readPath(_json, path);
    if (v is String && v.isNotEmpty) return v;
    _warn('$path: expected text');
    return _fallback(path) as String;
  }

  bool _bool(String path) {
    final v = readPath(_json, path);
    if (v is bool) return v;
    _warn('$path: expected true/false');
    return _fallback(path) as bool;
  }

  static FontWeight _toWeight(num v) => FontWeight.values[((v.clamp(100, 900) / 100).round() - 1).clamp(0, 8)];

  FontWeight _weight(String path) {
    final v = readPath(_json, path);
    if (v is num) return _toWeight(v);
    _warn('$path: expected 100…900');
    return FontWeight.w700;
  }

  Curve _curve(String path) {
    final v = readPath(_json, path);
    if (v is String && _curves.containsKey(v)) return _curves[v]!;
    _warn('$path: unknown curve "$v" (use one of ${_curves.keys.join(', ')})');
    return Curves.easeOutCubic;
  }

  T _enum<T extends Enum>(String path, List<T> values) {
    final v = readPath(_json, path);
    for (final e in values) {
      if (e.name == v) return e;
    }
    _warn('$path: "$v" must be one of ${values.map((e) => e.name).join(', ')}');
    final d = _fallback(path);
    return values.firstWhere((e) => e.name == d);
  }

  List<String> _stringList(String path) {
    final v = readPath(_json, path);
    if (v is List) return v.whereType<String>().toList(growable: false);
    _warn('$path: expected a list of strings');
    return (_fallback(path) as List).cast<String>();
  }

  List<String> _widgetList(String path) {
    final list = _stringList(path);
    final unknown = list.where((w) => !topBarWidgets.containsKey(w));
    for (final w in unknown) {
      _warn('$path: unknown widget "$w" (known: ${topBarWidgets.keys.join(', ')})');
    }
    return list.where(topBarWidgets.containsKey).toList(growable: false);
  }

  Appearance _appearance() {
    final v = readPath(_json, 'system.darkMode');
    switch (v) {
      case 'dark':
      case true:
        return Appearance.dark;
      case 'light':
      case false:
        return Appearance.light;
      case 'untouched':
      case null:
        return Appearance.untouched;
    }
    _warn('system.darkMode: use "dark", "light" or "untouched"');
    return Appearance.untouched;
  }

  int? _accent() {
    final v = readPath(_json, 'system.accent');
    if (v == null) return null;
    if (v is String && accentNames.containsKey(v)) return accentNames[v];
    _warn('system.accent: use one of ${accentNames.keys.join(', ')}');
    return null;
  }

  String? _wallpaper(String variant) {
    final w = readPath(_json, 'system.wallpaper');
    final Object? value = w is Map ? w[variant] : w;
    if (value is! String || value.isEmpty) return null;
    if (p.isAbsolute(value)) return value;
    if (_dir == null) return null;
    return p.normalize(p.join(_dir, value));
  }

  Map<String, String> _keybindings() {
    final defaults = Map<String, dynamic>.from(_fallback('keybindings') as Map);
    final given = readPath(_json, 'keybindings');
    final map = given is Map ? Map<String, dynamic>.from(given) : <String, dynamic>{};
    final out = <String, String>{};
    for (final key in {...defaults.keys, ...map.keys}) {
      if (!keybindingActions.containsKey(key)) {
        _warn('keybindings.$key: unknown action');
        continue;
      }
      final v = map.containsKey(key) ? map[key] : defaults[key];
      if (v is String && (v == 'superTap' || v == 'superDoubleTap')) {
        _warn(
          'keybindings.$key: "$v" needs keyboard monitoring, which this build does not do; '
          'using "${defaults[key]}"',
        );
        if (defaults[key] is String) out[key] = defaults[key] as String;
        continue;
      }
      if (v is String && v.isNotEmpty) out[key] = v;
    }
    return out;
  }
}

/// Resolves the `extends` chain. [load] returns a theme's own JSON by id.
/// Cycles and unknown parents are reported instead of recursing forever.
Map<String, dynamic> resolveExtends(
  Map<String, dynamic> json,
  Map<String, dynamic>? Function(String id) load, {
  List<String>? warnings,
}) {
  final chain = <Map<String, dynamic>>[json];
  final seen = <String>{if (json['id'] is String) json['id'] as String};
  var parentId = json['extends'];
  while (parentId is String) {
    if (seen.contains(parentId)) {
      warnings?.add('extends: cycle through "$parentId"');
      break;
    }
    final parent = load(parentId);
    if (parent == null) {
      warnings?.add('extends: unknown theme "$parentId"');
      break;
    }
    seen.add(parentId);
    chain.add(parent);
    parentId = parent['extends'];
  }
  var merged = <String, dynamic>{};
  for (final layer in chain.reversed) {
    merged = deepMerge(merged, layer);
  }
  merged['id'] = json['id'];
  merged['name'] = json['name'] ?? merged['name'];
  merged.remove('extends');
  return merged;
}

/// Convenience used by tests and the validator CLI.
Color hex(String s) => parseColor(s)!;
