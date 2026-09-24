import 'dart:ui';

/// Deep-merges [over] onto [base]. Maps merge recursively; any other value
/// (including lists) in [over] replaces the base value. `null` in [over]
/// deletes the key, so user overrides can "unset" a preset value.
Map<String, dynamic> deepMerge(Map<String, dynamic> base, Map<String, dynamic> over) {
  final out = Map<String, dynamic>.of(base);
  over.forEach((key, value) {
    if (value == null) {
      out.remove(key);
    } else if (value is Map && out[key] is Map) {
      out[key] = deepMerge(Map<String, dynamic>.from(out[key] as Map), Map<String, dynamic>.from(value));
    } else {
      out[key] = value;
    }
  });
  return out;
}

/// Maps whose keys themselves contain dots (`bar.bg`, `size.bar`,
/// `workspace.1`): after one of these prefixes the rest of a path is ONE key.
const dottedKeyMaps = ['tokens.color', 'tokens.font', 'tokens.radius', 'tokens.blur', 'tokens.motion', 'keybindings'];

/// Splits `tokens.color.bar.bg` into `[tokens, color, bar.bg]`.
List<String> splitPath(String path) {
  for (final prefix in dottedKeyMaps) {
    if (path.startsWith('$prefix.')) return [...prefix.split('.'), path.substring(prefix.length + 1)];
  }
  return path.split('.');
}

/// Reads `a.b.c` from nested maps (see [splitPath]).
Object? readPath(Map<String, dynamic> json, String path) {
  Object? cur = json;
  for (final part in splitPath(path)) {
    if (cur is Map && cur.containsKey(part)) {
      cur = cur[part];
    } else {
      return null;
    }
  }
  return cur;
}

/// Writes `a.b.c` into nested maps, creating intermediate maps.
Map<String, dynamic> writePath(Map<String, dynamic> json, String path, Object? value) {
  final parts = splitPath(path);
  final out = Map<String, dynamic>.of(json);
  var cur = out;
  for (var i = 0; i < parts.length - 1; i++) {
    final next = cur[parts[i]];
    final copy = next is Map ? Map<String, dynamic>.from(next) : <String, dynamic>{};
    cur[parts[i]] = copy;
    cur = copy;
  }
  cur[parts.last] = value;
  return out;
}

/// Removes `a.b.c` (and any maps it leaves empty) from nested maps.
Map<String, dynamic> removePath(Map<String, dynamic> json, String path) {
  Map<String, dynamic> remove(Map<String, dynamic> map, List<String> parts) {
    final out = Map<String, dynamic>.of(map);
    if (parts.length == 1) {
      out.remove(parts.first);
    } else if (out[parts.first] is Map) {
      final inner = remove(Map<String, dynamic>.from(out[parts.first] as Map), parts.sublist(1));
      if (inner.isEmpty) {
        out.remove(parts.first);
      } else {
        out[parts.first] = inner;
      }
    }
    return out;
  }

  return remove(json, splitPath(path));
}

/// Whether [path] is set in [json] (even to null, which unsets a preset value).
bool hasPath(Map<String, dynamic> json, String path) {
  Object? cur = json;
  for (final part in splitPath(path)) {
    if (cur is Map && cur.containsKey(part)) {
      cur = cur[part];
    } else {
      return false;
    }
  }
  return true;
}

/// Number of leaf values in nested maps (lists count as one value).
int leafCount(Map<String, dynamic> json) =>
    json.values.fold(0, (n, v) => n + (v is Map ? leafCount(Map<String, dynamic>.from(v)) : 1));

/// Parses `#rgb`, `#rrggbb` or `#rrggbbaa` (CSS order: alpha last).
Color? parseColor(Object? value) {
  if (value is! String) return null;
  var hex = value.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex = '${hex}ff';
  if (hex.length != 8) return null;
  final v = int.tryParse(hex, radix: 16);
  if (v == null) return null;
  final rgb = v >> 8;
  final a = v & 0xff;
  return Color((a << 24) | rgb);
}

String colorToHex(Color c) {
  String two(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final base = '#${two(c.r)}${two(c.g)}${two(c.b)}';
  return c.a >= 0.999 ? base : '$base${two(c.a)}';
}
