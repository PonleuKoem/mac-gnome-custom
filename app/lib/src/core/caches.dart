import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:shellkit/shellkit.dart';

/// App icons: the theme's icon pack (`<bundleId>.png`) wins, otherwise the
/// native icon rendered at the requested size. Cached per theme pack.
class IconCache {
  IconCache(this._apps, this._packDir);

  final AppApi _apps;
  final String? Function() _packDir;
  final Map<String, Future<ImageProvider?>> _futures = {};
  final Map<String, ImageProvider?> _ready = {};
  String? _cachedPack;

  /// Bumped whenever the icon pack changes, so widgets reload.
  int generation = 0;

  /// Synchronously available provider (null if not loaded yet).
  ImageProvider? peek(String bundleIdOrPath, int size) {
    _checkPack();
    return _ready[_key(bundleIdOrPath, size)];
  }

  Future<ImageProvider?> get(String bundleIdOrPath, int size) {
    _checkPack();
    final key = _key(bundleIdOrPath, size);
    return _futures.putIfAbsent(key, () async {
      final pack = _cachedPack;
      if (pack != null && !bundleIdOrPath.startsWith('/')) {
        final file = File(p.join(pack, '$bundleIdOrPath.png'));
        if (file.existsSync()) return _ready[key] = FileImage(file);
      }
      try {
        final bytes = await _apps.icon(bundleIdOrPath, size);
        return _ready[key] = bytes == null ? null : MemoryImage(bytes);
      } catch (_) {
        return _ready[key] = null;
      }
    });
  }

  void _checkPack() {
    final pack = _packDir();
    if (pack != _cachedPack) {
      _cachedPack = pack;
      _futures.clear();
      _ready.clear();
      generation++;
    }
  }

  String _key(String id, int size) => '$id@$size';
}
