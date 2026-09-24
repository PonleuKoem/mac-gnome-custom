import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'json_util.dart';
import 'shell_theme.dart';
import 'theme_repository.dart';

/// The active theme plus the user's live overrides, persisted in
/// `settings.json` (DESIGN.md §6). Overrides are kept per theme so switching
/// themes never loses tweaks.
class ThemeStore extends ChangeNotifier {
  ThemeStore({required this.repository, required this.settingsPath});

  final ThemeRepository repository;
  final String settingsPath;

  String _activeId = builtInThemeIds.first;
  Map<String, Map<String, dynamic>> _overrides = {};
  bool _onboarded = false;
  late ShellTheme _theme;
  StreamSubscription<void>? _watch;
  Timer? _saveDebounce;

  ShellTheme get theme => _theme;
  String get activeId => _activeId;
  bool get onboarded => _onboarded;
  Map<String, dynamic> get overrides => _overrides[_activeId] ?? const {};
  bool get hasOverrides => overrides.isNotEmpty;

  /// How many settings the user changed on theme [id] (default: active).
  int changeCount([String? id]) {
    final o = _overrides[id ?? _activeId];
    return o == null ? 0 : leafCount(o);
  }

  /// Whether the user changed [path] on the active theme.
  bool isOverridden(String path) => hasPath(overrides, path);

  Future<void> load() async {
    await repository.load();
    try {
      final file = File(settingsPath);
      if (file.existsSync()) {
        final json = Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map);
        _activeId = json['activeTheme'] as String? ?? _activeId;
        _onboarded = json['onboarded'] as bool? ?? false;
        final o = json['overrides'];
        if (o is Map) {
          _overrides = o.map((k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)));
        }
      }
    } catch (e) {
      debugPrint('settings.json unreadable, using defaults: $e');
    }
    if (repository[_activeId] == null) _activeId = builtInThemeIds.first;
    _resolve();
    _watch = repository.watch().listen((_) {
      _resolve();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _resolve() {
    _theme = repository.resolve(_activeId, overrides: overrides);
  }

  void _changed() {
    _resolve();
    notifyListeners();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), saveNow);
  }

  void saveNow() {
    final json = {'activeTheme': _activeId, 'onboarded': _onboarded, 'overrides': _overrides};
    final file = File(settingsPath);
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
    tmp.renameSync(file.path);
  }

  void setActive(String id) {
    if (repository[id] == null || id == _activeId) return;
    _activeId = id;
    _changed();
  }

  void setOnboarded(bool value) {
    _onboarded = value;
    _changed();
  }

  /// Sets a single value, e.g. `tokens.color.accent` → `#ff7800`.
  void setOverride(String path, Object? value) {
    _overrides[_activeId] = writePath(overrides, path, value);
    _changed();
  }

  /// Current effective value at [path] (theme merged with overrides).
  Object? valueAt(String path) => readPath(_theme.raw, path);

  /// Puts one setting back to the theme's own value.
  void clearOverride(String path) {
    if (!isOverridden(path)) return;
    final next = removePath(overrides, path);
    if (next.isEmpty) {
      _overrides.remove(_activeId);
    } else {
      _overrides[_activeId] = next;
    }
    _changed();
  }

  /// Resets theme [id] (default: active) to how it ships.
  void resetOverrides([String? id]) {
    if (_overrides.remove(id ?? _activeId) == null) return;
    _changed();
  }

  /// Saves the current look as a new user theme that `extends` the active one.
  Future<String> saveAsNew(String name) async {
    final json = deepMerge({'name': name, 'id': name, 'extends': _activeId}, overrides);
    final id = await repository.saveUserTheme(json);
    _overrides.remove(_activeId);
    _activeId = id;
    _changed();
    return id;
  }

  Future<String> import(String path) async {
    final id = await repository.importTheme(path);
    _resolve();
    notifyListeners();
    return id;
  }

  Future<void> export(String destPath) => repository.exportTheme(_activeId, overrides, destPath);

  Future<void> delete(String id) async {
    await repository.delete(id);
    _overrides.remove(id);
    if (_activeId == id) _activeId = builtInThemeIds.first;
    _changed();
  }

  /// Folder that holds user themes (for "Open themes folder").
  String get userThemesDir => repository.userDir;

  static String defaultSettingsPath(String supportDir) => p.join(supportDir, 'settings.json');
}
