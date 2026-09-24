import 'package:flutter/foundation.dart';
import 'package:shellkit/shellkit.dart';

class AppsStore extends ChangeNotifier {
  List<AppInfo> _running = [];
  List<InstalledApp> _installed = [];

  List<AppInfo> get running => _running;
  List<InstalledApp> get installed => _installed;

  /// Bundle id of the frontmost app (from public NSWorkspace data).
  String? get activeBundle {
    for (final a in _running) {
      if (a.isActive) return a.bundleId;
    }
    return null;
  }

  AppInfo? runningApp(String bundleId) {
    for (final a in _running) {
      if (a.bundleId == bundleId) return a;
    }
    return null;
  }

  String nameFor(String bundleId) {
    final r = runningApp(bundleId);
    if (r != null) return r.name;
    for (final a in _installed) {
      if (a.bundleId == bundleId) return a.name;
    }
    return bundleId.split('.').last;
  }

  void setRunning(List<AppInfo> list) {
    _running = list;
    notifyListeners();
  }

  void setInstalled(List<InstalledApp> list) {
    _installed = list;
    notifyListeners();
  }
}

class SystemStore extends ValueNotifier<SystemStatus?> {
  SystemStore() : super(null);
}

/// Surfaces (Flutter view ↔ native panel) and screens.
class SurfacesStore extends ChangeNotifier {
  Map<int, SurfaceSpec> _byView = {};
  Map<int, ScreenInfo> _screens = {};

  Map<int, SurfaceSpec> get byView => _byView;
  Iterable<SurfaceSpec> get all => _byView.values;
  Map<int, ScreenInfo> get screens => _screens;

  ScreenInfo? get mainScreen {
    for (final s in _screens.values) {
      if (s.isMain) return s;
    }
    return _screens.values.isEmpty ? null : _screens.values.first;
  }

  SurfaceSpec? byId(String surfaceId) {
    for (final s in _byView.values) {
      if (s.surfaceId == surfaceId) return s;
    }
    return null;
  }

  /// Native re-sends surfaces and screens after display or Dock changes;
  /// identical updates are ignored so they don't relayout every panel.
  void setSurfaces(List<SurfaceSpec> list) {
    final next = {for (final s in list) s.viewId: s};
    if (mapEquals(next, _byView)) return;
    _byView = next;
    notifyListeners();
  }

  void setScreens(List<ScreenInfo> list) {
    final next = {for (final s in list) s.id: s};
    if (mapEquals(next, _screens)) return;
    _screens = next;
    notifyListeners();
  }
}
