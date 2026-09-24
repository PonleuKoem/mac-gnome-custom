import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mac_gnome_custom/src/core/bridge.dart';
import 'package:mac_gnome_custom/src/core/shell_controller.dart';
import 'package:mac_gnome_custom/src/theme/theme_repository.dart';
import 'package:mac_gnome_custom/src/theme/theme_store.dart';
import 'package:path/path.dart' as p;
import 'package:shellkit/shellkit.dart';

import 'disk_bundle.dart';

/// Records every native call the controller makes.
class Calls {
  final List<String> log = [];
  final Map<String, (RectD, bool)> shown = {};
  final Set<String> hidden = {};
  final List<SystemConfig> applied = [];
  List<Keybinding> bindings = [];

  /// What the fake native dock menu "picks".
  String? dockMenuAnswer;
  void add(String s) => log.add(s);
}

final screen = ScreenInfo(
  id: 1,
  frame: RectD(x: 0, y: 0, w: 1512, h: 982),
  visibleFrame: RectD(x: 0, y: 37, w: 1512, h: 945),
  menuBarHeight: 37,
  scale: 2,
  isMain: true,
);

AppInfo app(String bundle, {bool active = false}) => AppInfo(
  bundleId: bundle,
  name: bundle.split('.').last,
  path: '/Applications/$bundle.app',
  pid: 1,
  isActive: active,
  isHidden: false,
);

class FakeHost extends ShellHostApi {
  FakeHost(this.c);
  final Calls c;
  @override
  Future<List<SurfaceSpec>> surfaces() async => [
    SurfaceSpec(viewId: 2, surfaceId: 'topbar:1', kind: 'topbar', screenId: 1),
    SurfaceSpec(viewId: 3, surfaceId: 'dock', kind: 'dock', screenId: 1),
    SurfaceSpec(viewId: 4, surfaceId: 'overview', kind: 'overview', screenId: 1),
    SurfaceSpec(viewId: 5, surfaceId: 'switcher', kind: 'switcher', screenId: 1),
    SurfaceSpec(viewId: 6, surfaceId: 'popover', kind: 'popover', screenId: 1),
  ];
  @override
  Future<List<ScreenInfo>> screens() async => [screen];
  @override
  Future<void> ready() async {}
  @override
  Future<void> showSurface(String surfaceId, RectD rect, bool takeKeyboard) async {
    c.shown[surfaceId] = (rect, takeKeyboard);
    c.hidden.remove(surfaceId);
  }

  @override
  Future<void> hideSurface(String surfaceId) async {
    c.shown.remove(surfaceId);
    c.hidden.add(surfaceId);
  }

  @override
  Future<void> setBlurRegions(String surfaceId, List<RRectD> regions, bool dark) async {}

  @override
  Future<void> openCustomizer() async => c.add('openCustomizer');

  @override
  Future<void> setHitRegion(String surfaceId, RectD? rect) async =>
      c.add('setHitRegion $surfaceId ${rect == null ? 'null' : '${rect.x},${rect.y},${rect.w},${rect.h}'}');
}

class FakeApps extends AppApi {
  FakeApps(this.c, this.running_);
  final Calls c;
  final List<AppInfo> running_;
  @override
  Future<List<AppInfo>> running() async => running_;
  List<InstalledApp> installed_ = const [];
  @override
  Future<List<InstalledApp>> installed() async => installed_;
  @override
  Future<Uint8List?> icon(String bundleIdOrPath, int sizePx) async => null;
  @override
  Future<void> activate(String bundleId) async => c.add('activate $bundleId');
  @override
  Future<void> launch(String bundleIdOrPath) async => c.add('launch $bundleIdOrPath');
  @override
  Future<int> windowCount(String bundleId) async => 3;

  /// What the native side lists when previews are on (null: three windows).
  List<WindowSummary>? windowList;
  @override
  Future<List<WindowSummary>> windows(String bundleId, int thumbnailWidthPx) async =>
      windowList ??
      [
        for (final (i, t) in ['Inbox', 'Docs — 100 tabs', 'News'].indexed)
          WindowSummary(id: 100 + i, title: t, width: 1200, height: 800, onScreen: i != 2, minimized: i == 2),
      ];
  @override
  Future<void> focusWindow(String bundleId, int windowId) async => c.add('focusWindow $bundleId $windowId');
  @override
  Future<void> showAllWindows(String bundleId) async => c.add('showAllWindows $bundleId');
  @override
  Future<String?> showDockMenu(String bundleId, RectD anchor, String edge, bool pinned) async {
    c.add('dockMenu $bundleId $edge pinned=$pinned at ${anchor.x.round()},${anchor.y.round()}');
    return c.dockMenuAnswer;
  }
}

class FakeSystem extends SystemApi {
  FakeSystem(this.c);
  final Calls c;
  @override
  Future<void> setDarkMode(bool dark) async => c.add('darkMode $dark');
  @override
  Future<SystemStatus> status() async => SystemStatus(
    batteryPercent: 80,
    charging: false,
    onBattery: true,
    volume: 0.5,
    muted: false,
    wifiOn: true,
    wifiRssi: -50,
    darkMode: false,
  );
}

class FakeHotkeys extends HotkeyApi {
  FakeHotkeys(this.c);
  final Calls c;
  @override
  Future<List<String>> setBindings(List<Keybinding> bindings) async {
    c.bindings = bindings;
    return [
      for (final b in bindings)
        if (refuse.contains(b.chord)) b.chord,
    ];
  }

  @override
  Future<List<String>> conflicts(String chord) async => const [];
  bool suspended = false;
  List<String> refuse = const [];
  @override
  Future<void> setSuspended(bool suspended) async => this.suspended = suspended;
}

class FakeSafety extends SafetyApi {
  FakeSafety(this.c);
  final Calls c;
  @override
  Future<void> applySystem(SystemConfig config) async => c.applied.add(config);
  @override
  Future<List<String>> journal() async => const [];
  @override
  Future<bool> hasSnapshot() async => false;
}

class FakeDiagnostics extends DiagnosticsApi {
  /// What macOS has granted (both off, as on a fresh Mac).
  bool screenRecording = false;
  bool accessibility = false;
  @override
  Future<void> setFlag(String name, bool enabled) async {}
  @override
  Future<ThumbnailPermissions> thumbnailPermissions() async =>
      ThumbnailPermissions(screenRecording: screenRecording, accessibility: accessibility);
  @override
  Future<void> requestThumbnailPermissions() async {}
  @override
  Future<void> openPrivacySettings(String pane) async {}
  @override
  Future<DiagnosticsInfo> info() async => DiagnosticsInfo(
    hotkeysRegistered: 2,
    guardianRunning: true,
    flags: {'menuBarCover': true, 'dockHideNative': true, 'hotCorner': true},
  );
}

Future<(ShellController, Calls, StreamController<ShellEvent>, ThemeStore, Directory)> harness({
  List<AppInfo> running = const [],
  bool onboarded = true,
}) async {
  final tmp = Directory.systemTemp.createTempSync('mgc-ctrl');
  final themes = ThemeStore(
    repository: ThemeRepository(
      userDir: p.join(tmp.path, 'themes'),
      bundle: DiskBundle(),
      assetRoot: Directory.current.path,
    ),
    settingsPath: p.join(tmp.path, 'settings.json'),
  );
  await themes.load();
  if (onboarded) themes.setOnboarded(true);
  final c = Calls();
  final events = StreamController<ShellEvent>.broadcast();
  final bridge = ShellBridge(
    host: FakeHost(c),
    apps: FakeApps(c, running),
    system: FakeSystem(c),
    hotkeys: FakeHotkeys(c),
    safety: FakeSafety(c),
    diagnostics: FakeDiagnostics(),
    eventStream: () => events.stream,
  );
  final ctrl = ShellController(bridge: bridge, themes: themes);
  await ctrl.start();
  return (ctrl, c, events, themes, tmp);
}
