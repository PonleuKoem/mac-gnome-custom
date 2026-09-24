import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'json_util.dart';
import 'shell_theme.dart';
import 'theme_parser.dart';

const builtInThemeIds = [
  'gnome-adwaita',
  'gnome-dark',
  'ubuntu',
  'win11',
  'classic-mac',
  'ios',
  'android',
  'opus-tidepool',
  'fable-overprint',
];

class ThemeEntry {
  ThemeEntry({required this.id, required this.name, required this.builtIn, required this.dir, required this.json});

  final String id;
  final String name;
  final bool builtIn;

  /// Folder holding the theme's assets (wallpapers, icons); may be null for
  /// built-ins when running from tests.
  final String? dir;

  /// The theme's own JSON (before `extends` is resolved).
  final Map<String, dynamic> json;
}

/// Loads built-in presets (bundled assets) and user themes
/// (`~/Library/Application Support/MacGnomeCustom/themes/<id>/theme.json`),
/// resolves `extends`, watches for edits (hot reload), imports and exports
/// `.mgctheme` packs (ADR-0009).
class ThemeRepository {
  ThemeRepository({required this.userDir, AssetBundle? bundle, String? assetRoot})
    : _bundle = bundle ?? rootBundle,
      _assetRoot = assetRoot ?? _defaultAssetRoot();

  final String userDir;
  final AssetBundle _bundle;
  final String? _assetRoot;
  final Map<String, ThemeEntry> _entries = {};

  List<ThemeEntry> get entries {
    final list = _entries.values.toList();
    list.sort((a, b) {
      if (a.builtIn != b.builtIn) return a.builtIn ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  ThemeEntry? operator [](String id) => _entries[id];

  /// `…/Contents/Frameworks/App.framework/Resources/flutter_assets`, so theme
  /// assets (wallpapers) have real paths macOS can use.
  static String? _defaultAssetRoot() {
    try {
      final exe = File(Platform.resolvedExecutable);
      final contents = exe.parent.parent.path;
      final root = p.join(contents, 'Frameworks', 'App.framework', 'Resources', 'flutter_assets');
      return Directory(root).existsSync() ? root : null;
    } catch (_) {
      return null;
    }
  }

  /// (Re)loads every theme. Builds a new map and swaps it in at the end, so
  /// readers never see a half-loaded repository. A user theme
  /// that fails to parse keeps its last good version: a typo
  /// while editing must never switch the Mac to another theme.
  Future<void> load() async {
    final next = <String, ThemeEntry>{};
    final errors = <String, String>{};
    for (final id in builtInThemeIds) {
      try {
        final text = await _bundle.loadString('assets/themes/$id/theme.json');
        final json = Map<String, dynamic>.from(jsonDecode(text) as Map);
        final dir = _assetRoot == null ? null : p.join(_assetRoot, 'assets', 'themes', id);
        next[id] = ThemeEntry(id: id, name: json['name'] as String? ?? id, builtIn: true, dir: dir, json: json);
      } catch (e) {
        // A broken preset must never take the shell down.
        next[id] = ThemeEntry(id: id, name: id, builtIn: true, dir: null, json: {'id': id, 'name': id});
      }
    }
    final root = Directory(userDir);
    if (!root.existsSync()) root.createSync(recursive: true);
    for (final dir in root.listSync().whereType<Directory>()) {
      final file = File(p.join(dir.path, 'theme.json'));
      if (!file.existsSync()) continue;
      final folderId = p.basename(dir.path);
      try {
        final json = Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map);
        final id = (json['id'] as String?) ?? folderId;
        json['id'] = id;
        next[id] = ThemeEntry(id: id, name: json['name'] as String? ?? id, builtIn: false, dir: dir.path, json: json);
      } catch (e) {
        final previous = _entries.values.where((t) => !t.builtIn && t.dir == dir.path).firstOrNull;
        if (previous != null) next[previous.id] = previous;
        errors[previous?.id ?? folderId] = '$e';
      }
    }
    _entries
      ..clear()
      ..addAll(next);
    _loadErrors
      ..clear()
      ..addAll(errors);
  }

  final Map<String, String> _loadErrors = {};

  /// Resolves a theme with its `extends` chain plus [overrides] on top. Never
  /// throws: a missing or broken theme yields defaults marked `degraded`.
  ShellTheme resolve(String id, {Map<String, dynamic> overrides = const {}}) {
    final entry = _entries[id];
    if (entry == null) return _fallback(id, 'theme "$id" was not found');
    try {
      final warnings = <String>[
        if (_loadErrors[id] != null) 'theme.json has an error (showing the last good version): ${_loadErrors[id]}',
      ];
      final merged = mergedJson(entry, warnings: warnings);
      final theme = ThemeParser.parse(deepMerge(merged, overrides), dir: entry.dir);
      return theme.copyWith(sourceDir: entry.dir, warnings: [...warnings, ...theme.warnings]);
    } catch (e) {
      return _fallback(id, 'theme "$id" could not be loaded: $e');
    }
  }

  ShellTheme _fallback(String id, String why) =>
      ThemeParser.parse({'id': id, 'name': id}).copyWith(warnings: [why], degraded: true);

  /// The theme's JSON with its whole `extends` chain merged. Every layer's
  /// relative asset paths are made absolute against THAT layer's folder first,
  /// so inherited wallpapers keep working — and the chain is
  /// cycle-safe.
  Map<String, dynamic> mergedJson(ThemeEntry entry, {List<String>? warnings}) {
    Map<String, dynamic>? load(String pid) {
      final e = _entries[pid];
      return e == null ? null : _absolutize(e.json, e.dir);
    }

    return resolveExtends(_absolutize(entry.json, entry.dir), load, warnings: warnings);
  }

  static Map<String, dynamic> _absolutize(Map<String, dynamic> json, String? dir) {
    if (dir == null) return json;
    String abs(String path) => p.isAbsolute(path) ? path : p.normalize(p.join(dir, path));
    var out = json;
    final wallpaper = readPath(json, 'system.wallpaper');
    if (wallpaper is String && wallpaper.isNotEmpty) {
      out = writePath(out, 'system.wallpaper', abs(wallpaper));
    } else if (wallpaper is Map) {
      out = writePath(out, 'system.wallpaper', {
        for (final e in wallpaper.entries) e.key as String: e.value is String ? abs(e.value as String) : e.value,
      });
    }
    final pack = readPath(json, 'icons.pack');
    if (pack is String && pack.isNotEmpty) out = writePath(out, 'icons.pack', abs(pack));
    return out;
  }

  /// Emits (debounced) whenever a user theme file changes on disk.
  Stream<void> watch() {
    final controller = StreamController<void>.broadcast();
    Timer? debounce;
    StreamSubscription<FileSystemEvent>? sub;
    controller.onListen = () {
      sub = Directory(userDir).watch(recursive: true).listen((_) {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 250), () async {
          await load();
          controller.add(null);
        });
      });
    };
    controller.onCancel = () => sub?.cancel();
    return controller.stream;
  }

  /// Writes a user theme; returns its id (made unique if needed).
  Future<String> saveUserTheme(Map<String, dynamic> json, {bool overwrite = false}) async {
    var id = _slug(json['id'] as String? ?? json['name'] as String? ?? 'my-theme');
    if (!overwrite) {
      var n = 2;
      final base = id;
      while (_entries.containsKey(id)) {
        id = '$base-${n++}';
      }
    }
    final dir = Directory(p.join(userDir, id))..createSync(recursive: true);
    final out = Map<String, dynamic>.of(json)..['id'] = id;
    out['schema'] = themeSchemaVersion;
    await File(p.join(dir.path, 'theme.json')).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    await load();
    return id;
  }

  /// Imports a theme folder or a `.mgctheme` (zip) into the user directory.
  Future<String> importTheme(String path) async {
    final tmp = Directory.systemTemp.createTempSync('mgc-import');
    try {
      String source;
      if (FileSystemEntity.isDirectorySync(path)) {
        source = path;
      } else {
        // Off the UI isolate: every panel shares it.
        final bytes = File(path).readAsBytesSync();
        final dest = tmp.path;
        await Isolate.run(() => extractThemeArchive(bytes, dest));
        source = _findThemeRoot(tmp.path) ?? tmp.path;
      }
      final file = File(p.join(source, 'theme.json'));
      if (!file.existsSync()) throw const FormatException('No theme.json found');
      final json = Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map);
      final id = await saveUserTheme(json);
      // Copy assets next to theme.json.
      for (final entity in Directory(source).listSync(recursive: true).whereType<File>()) {
        final rel = p.relative(entity.path, from: source);
        if (rel == 'theme.json') continue;
        final dest = File(p.join(userDir, id, rel));
        dest.parent.createSync(recursive: true);
        entity.copySync(dest.path);
      }
      await load();
      return id;
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  String? _findThemeRoot(String dir) {
    if (File(p.join(dir, 'theme.json')).existsSync()) return dir;
    for (final sub in Directory(dir).listSync().whereType<Directory>()) {
      final found = _findThemeRoot(sub.path);
      if (found != null) return found;
    }
    return null;
  }

  /// Exports [id] merged with [overrides] (and its assets) as a `.mgctheme`.
  Future<void> exportTheme(String id, Map<String, dynamic> overrides, String destPath) async {
    final entry = _entries[id];
    if (entry == null) throw ArgumentError('unknown theme $id');
    final merged = deepMerge(mergedJson(entry), overrides);
    final archive = Archive();
    final wallpaper = readPath(merged, 'system.wallpaper');
    final walls = <String, dynamic>{
      if (wallpaper is String) 'light': wallpaper,
      if (wallpaper is Map) ...Map<String, dynamic>.from(wallpaper),
    };
    // Copy referenced wallpapers into the pack under wallpapers/.
    for (final key in walls.keys.toList()) {
      final path = walls[key];
      if (path is! String || !p.isAbsolute(path) || !File(path).existsSync()) {
        walls.remove(key);
        continue;
      }
      final name = 'wallpapers/$key-${p.basename(path)}';
      final bytes = File(path).readAsBytesSync();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      walls[key] = name;
    }
    final system = Map<String, dynamic>.from(merged['system'] as Map? ?? {});
    if (walls.isEmpty) {
      system.remove('wallpaper');
    } else {
      system['wallpaper'] = walls;
    }
    merged['system'] = system;
    final pack = readPath(merged, 'icons.pack');
    if (pack is String && Directory(pack).existsSync()) {
      for (final f in Directory(pack).listSync().whereType<File>()) {
        final bytes = f.readAsBytesSync();
        archive.addFile(ArchiveFile('icons/${p.basename(f.path)}', bytes.length, bytes));
      }
      merged['icons'] = {'pack': 'icons'};
    } else {
      merged.remove('icons');
    }
    final text = utf8.encode(const JsonEncoder.withIndent('  ').convert(merged));
    archive.addFile(ArchiveFile('theme.json', text.length, text));
    await File(destPath).writeAsBytes(ZipEncoder().encode(archive));
  }

  Future<void> delete(String id) async {
    final entry = _entries[id];
    if (entry == null || entry.builtIn || entry.dir == null) return;
    await Directory(entry.dir!).delete(recursive: true);
    await load();
  }

  static String _slug(String s) {
    final slug = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'theme' : slug;
  }
}

/// Extracts a `.mgctheme` zip into [destDir], refusing entries that would land
/// outside it ("zip slip": absolute paths or `..` segments) and capping the
/// total size so a hostile pack can't fill the disk.
void extractThemeArchive(List<int> bytes, String destDir, {int maxBytes = 200 * 1024 * 1024}) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final root = p.normalize(p.absolute(destDir));
  var total = 0;
  // Check declared sizes BEFORE decompressing anything (zip bombs).
  final declared = archive.files.where((f) => f.isFile).fold<int>(0, (s, f) => s + f.size);
  if (declared > maxBytes) throw const FormatException('Theme pack is too large');
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final target = p.normalize(p.join(root, file.name));
    if (p.isAbsolute(file.name) || !p.isWithin(root, target)) {
      throw FormatException('Refusing unsafe path in theme pack: ${file.name}');
    }
    final content = file.content;
    total += content.length;
    if (total > maxBytes) throw const FormatException('Theme pack is too large');
    File(target)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(content);
  }
}
