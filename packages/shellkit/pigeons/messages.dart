// Contract between the Flutter UI and the native ShellKit services.
// Regenerate with `make gen` (see repo Makefile). ADR-0008.
//
// Interface-only scope (ADR-0012): nothing here reads other apps' windows,
// screen contents or keystrokes, or controls the system beyond appearance.
//
// Coordinates: every rect is in points with a TOP-LEFT origin, relative to the
// surface's screen.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    swiftOut: 'macos/Classes/Messages.g.swift',
    dartPackageName: 'shellkit',
  ),
)
class RectD {
  RectD(this.x, this.y, this.w, this.h);
  double x;
  double y;
  double w;
  double h;
}

class RRectD {
  RRectD(this.rect, this.radius);
  RectD rect;
  double radius;
}

class ScreenInfo {
  ScreenInfo(this.id, this.frame, this.visibleFrame, this.menuBarHeight, this.scale, this.isMain);
  int id;
  RectD frame;
  RectD visibleFrame;
  double menuBarHeight;
  double scale;
  bool isMain;
}

/// What a Flutter view renders. `kind` is one of: topbar, dock, overview,
/// popover, customizer.
class SurfaceSpec {
  SurfaceSpec(this.viewId, this.surfaceId, this.kind, this.screenId);
  int viewId;
  String surfaceId;
  String kind;
  int screenId;
}

class AppInfo {
  AppInfo(this.bundleId, this.name, this.path, this.pid, this.isActive, this.isHidden);
  String bundleId;
  String name;
  String path;
  int pid;
  bool isActive;
  bool isHidden;
}

class InstalledApp {
  InstalledApp(this.bundleId, this.name, this.path);
  String bundleId;
  String name;
  String path;
}

/// Read-only status for the top-bar indicators (the shell never changes
/// volume, Wi-Fi or power: interface-only scope, ADR-0012).
class SystemStatus {
  SystemStatus(
    this.batteryPercent,
    this.charging,
    this.onBattery,
    this.volume,
    this.muted,
    this.wifiOn,
    this.wifiSsid,
    this.wifiRssi,
    this.darkMode,
  );

  /// -1 when the machine has no battery.
  int batteryPercent;
  bool charging;
  bool onBattery;
  double volume;
  bool muted;
  bool wifiOn;
  String? wifiSsid;
  int wifiRssi;
  bool darkMode;
}

class Keybinding {
  Keybinding(this.action, this.chord);

  /// e.g. "overview", "switcher", "workspace.next", "workspace.3".
  String action;

  /// e.g. "superTap", "superDoubleTap", "cmd+tab", "ctrl+alt+right".
  String chord;
}

/// The `system` block of a theme, resolved. Null fields are left untouched.
class SystemConfig {
  SystemConfig(
    this.hideNativeDock,
    this.darkMode,
    this.accentColor,
    this.wallpaperPath,
    this.dockReserveEdge,
    this.dockReserveThickness,
  );
  bool hideNativeDock;
  bool? darkMode;

  /// macOS accent index: -1 graphite, 0 red, 1 orange, 2 yellow, 3 green,
  /// 4 blue, 5 purple, 6 pink; null = multicolor/untouched.
  int? accentColor;
  String? wallpaperPath;

  /// Keep the native Dock as a spacer on this edge (bottom | left | right) so
  /// macOS keeps windows clear of the shell's dock; null = hide/restore only.
  String? dockReserveEdge;
  double? dockReserveThickness;
}

/// One of an app's windows, for the dock's opt-in thumbnails.
class WindowSummary {
  WindowSummary(this.id, this.title, this.width, this.height, this.onScreen, this.minimized, this.thumbnail);
  int id;
  String title;
  double width;
  double height;
  bool onScreen;
  bool minimized;

  /// PNG, or null when macOS can't capture it (e.g. minimized).
  Uint8List? thumbnail;
}

/// State of the two permissions the opt-in window thumbnails need.
class ThumbnailPermissions {
  ThumbnailPermissions(this.screenRecording, this.accessibility);
  bool screenRecording;
  bool accessibility;
}

class DiagnosticsInfo {
  DiagnosticsInfo(this.hotkeysRegistered, this.guardianRunning, this.flags);

  /// Global shortcuts currently registered with macOS (public
  /// RegisterEventHotKey API: the shell only ever receives these chords).
  int hotkeysRegistered;
  bool guardianRunning;
  Map<String, bool> flags;
}

// ───────────────────────────── Events (native → Dart) ─────────────────────────────

sealed class ShellEvent {}

class AppsChangedEvent extends ShellEvent {
  AppsChangedEvent(this.apps);
  List<AppInfo> apps;
}

class SystemStatusEvent extends ShellEvent {
  SystemStatusEvent(this.status);
  SystemStatus status;
}

class HotkeyEvent extends ShellEvent {
  HotkeyEvent(this.action);

  /// Keybinding action ("overview", "appGrid") or "hotcorner".
  String action;
}

class ScreensChangedEvent extends ShellEvent {
  ScreensChangedEvent(this.screens);
  List<ScreenInfo> screens;
}

class SurfacesChangedEvent extends ShellEvent {
  SurfacesChangedEvent(this.surfaces);
  List<SurfaceSpec> surfaces;
}

class SurfaceDismissedEvent extends ShellEvent {
  SurfaceDismissedEvent(this.surfaceId);

  /// The panel lost key focus or the user clicked outside it.
  String surfaceId;
}

class CustomizerVisibilityEvent extends ShellEvent {
  CustomizerVisibilityEvent(this.visible);
  bool visible;
}

@EventChannelApi()
abstract class ShellEventsApi {
  ShellEvent events();
}

// ───────────────────────────── Host APIs (Dart → native) ─────────────────────────────

@HostApi()
abstract class ShellHostApi {
  /// Called once the Dart side is ready to receive events.
  void ready();
  List<SurfaceSpec> surfaces();
  List<ScreenInfo> screens();
  String supportDirectory();

  /// Position (screen-relative, top-left origin) and show a surface.
  void showSurface(String surfaceId, RectD rect, bool takeKeyboard);
  void hideSurface(String surfaceId);
  void setBlurRegions(String surfaceId, List<RRectD> regions, bool dark);

  /// Part of the surface (surface coordinates) that takes clicks at rest; the
  /// rest of the window lets clicks through until the pointer enters this
  /// rect. Null = the whole window. Lets the dock keep a fixed, larger window
  /// for magnified icons without resizing on hover.
  void setHitRegion(String surfaceId, RectD? rect);
  void openCustomizer();
  void setLaunchAtLogin(bool enabled);
  bool launchAtLogin();

  @async
  String? pickPath(bool directory, List<String> extensions);
  @async
  String? savePath(String suggestedName);
  void quit();
}

@HostApi()
abstract class AppApi {
  List<AppInfo> running();
  @async
  List<InstalledApp> installed();
  @async
  Uint8List? icon(String bundleIdOrPath, int sizePx);
  void launch(String bundleIdOrPath);
  void activate(String bundleId);
  void hide(String bundleId);
  void quit(String bundleId);

  /// The Dock's right-click menu for an app, as a native macOS menu at
  /// [anchor] (the icon's rect on the main screen, top-left origin), placed
  /// off the dock's [edge] (bottom | left | right). Show in Finder, Hide and
  /// (Force) Quit happen natively; returns what the shell must do: "open",
  /// "keep" (pin), "remove" (unpin), or null when dismissed.
  @async
  String? showDockMenu(String bundleId, RectD anchor, String edge, bool pinned);

  /// How many windows the app has open (window-server metadata only: no
  /// titles, no contents, no permission). For the dock's hover label.
  int windowCount(String bundleId);

  /// The Dock's "Show All Windows" (App Exposé) for this app.
  void showAllWindows(String bundleId);

  /// OPT-IN (flag `windowThumbnails`, off by default; ADR-0012 exception).
  /// The app's real windows with small thumbnails. Empty while the flag is
  /// off or permissions are missing — enforced natively.
  @async
  List<WindowSummary> windows(String bundleId, int thumbnailWidthPx);

  /// OPT-IN: bring exactly this window to the front (un-minimizing it).
  void focusWindow(String bundleId, int windowId);
}

@HostApi()
abstract class SystemApi {
  SystemStatus status();

  /// Appearance only (via System Events; macOS asks for Automation once).
  void setDarkMode(bool dark);
}

@HostApi()
abstract class HotkeyApi {
  /// Registers global shortcuts with the public RegisterEventHotKey API.
  /// Only these exact chords are ever delivered to the shell; no other key
  /// press is visible to it. Chords macOS reserves (e.g. ⌘Tab) are rejected.
  /// Returns the chords that could NOT be registered.
  List<String> setBindings(List<Keybinding> bindings);

  /// Unregisters every shortcut while the Customizer records a new one, so
  /// the pressed chord reaches the Customizer window.
  void setSuspended(bool suspended);

  /// Human-readable conflicts with well-known macOS shortcuts.
  List<String> conflicts(String chord);
}

@HostApi()
abstract class SafetyApi {
  /// Snapshot (first run only) → journal → apply. Idempotent.
  void applySystem(SystemConfig config);

  /// Undo runtime changes (the hidden Dock). Called on quit.
  void restoreRuntime();

  /// Undo everything back to the first-run snapshot.
  void restoreAll();
  List<String> journal();
  bool hasSnapshot();
}

@HostApi()
abstract class DiagnosticsApi {
  DiagnosticsInfo info();
  void setFlag(String name, bool enabled);

  /// Screen Recording / Accessibility status for the opt-in thumbnails.
  ThumbnailPermissions thumbnailPermissions();

  /// Ask macOS for them (only from the user turning thumbnails on).
  void requestThumbnailPermissions();

  /// Open System Settings → Privacy & Security at "ScreenCapture" or
  /// "Accessibility".
  void openPrivacySettings(String pane);
}
