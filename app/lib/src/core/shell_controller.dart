import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shellkit/shellkit.dart';

import '../theme/shell_theme.dart';
import '../theme/theme_store.dart';
import 'algorithms.dart';
import 'bridge.dart';
import 'caches.dart';
import 'stores.dart';
import 'ui_state.dart';

class DockItem {
  const DockItem({required this.bundleId, required this.pinned, required this.running});
  final String bundleId;
  final bool pinned;
  final bool running;
}

/// Policy lives here (DESIGN.md §3): which surfaces are visible and where, what
/// each shortcut does, and pushing the theme to native.
///
/// Interface-only scope (ADR-0012): the shell draws its own surfaces, opens
/// apps the way the Dock does, and changes only appearance settings. It never
/// reads or controls other apps' windows.
class ShellController {
  ShellController({required this.bridge, required this.themes});

  final ShellBridge bridge;
  final ThemeStore themes;

  final apps = AppsStore();
  final system = SystemStore();
  final surfaces = SurfacesStore();
  final ui = ShellUi();
  final flags = ValueNotifier<Map<String, bool>>({});

  /// Whether the Customizer window is open (pages pause their timers).
  final customizerVisible = ValueNotifier<bool>(false);

  /// Page the Customizer should switch to (see [openCustomizer]).
  final customizerPage = ValueNotifier<String?>(null);

  /// Shortcuts macOS refused to register (taken by macOS or another app).
  final rejectedShortcuts = ValueNotifier<List<String>>(const []);

  late final icons = IconCache(bridge.apps, () => themes.theme.iconPackDir);

  StreamSubscription<ShellEvent>? _events;
  final Map<String, _Placement> _placed = {};
  Rect? _dockHit;
  bool _dockVisible = false;
  bool _dockPointerInside = false;
  Rect? _dockCardRect;
  Timer? _applyDebounce;
  bool? _lastDark;
  bool _started = false;

  ShellTheme get theme => themes.theme;

  // MARK: Startup

  Future<void> start() async {
    if (_started) return;
    _started = true;
    // Subscribe first, then pull snapshots, so nothing falls in between.
    _events = bridge.eventStream.listen(_onEvent, onError: (Object e) => debugPrint('event stream: $e'));
    await Future.wait(
      [
        bridge.host.surfaces().then(surfaces.setSurfaces),
        bridge.host.screens().then(surfaces.setScreens),
        bridge.apps.running().then(apps.setRunning),
        bridge.system.status().then((s) => system.value = s),
        bridge.diagnostics.info().then((i) => flags.value = Map.of(i.flags)),
      ].map((f) => f.catchError((Object e) => debugPrint('startup: $e'))),
    );
    themes.addListener(_themeChanged);
    for (final l in <Listenable>[ui, surfaces, flags, apps]) {
      l.addListener(_syncSurfaces);
    }
    system.addListener(_systemChanged);
    unawaited(refreshInstalledApps());
    _themeChanged();
    await bridge.host.ready();
  }

  void dispose() {
    _events?.cancel();
    _applyDebounce?.cancel();
  }

  Future<void> refreshInstalledApps() async {
    try {
      apps.setInstalled(await bridge.apps.installed());
    } catch (e) {
      debugPrint('installed apps: $e');
    }
  }

  // MARK: Events

  void _onEvent(ShellEvent e) {
    switch (e) {
      case AppsChangedEvent():
        apps.setRunning(e.apps);
      case SystemStatusEvent():
        system.value = e.status;
      case HotkeyEvent():
        handleAction(e.action);
      case ScreensChangedEvent():
        surfaces.setScreens(e.screens);
      case SurfacesChangedEvent():
        final ids = e.surfaces.map((s) => s.surfaceId).toSet();
        _placed.removeWhere((id, _) => !ids.contains(id));
        surfaces.setSurfaces(e.surfaces);
      case SurfaceDismissedEvent():
        if (e.surfaceId == 'overview') ui.closeOverview();
        if (e.surfaceId == 'popover') ui.closePopover();
      case CustomizerVisibilityEvent():
        customizerVisible.value = e.visible;
    }
  }

  // MARK: Actions (shortcuts, hot corner, UI buttons)

  void handleAction(String action) {
    if (!active) return;
    switch (action) {
      case 'overview':
      case 'appGrid':
      case 'hotcorner':
        toggleOverview();
    }
  }

  void toggleOverview() {
    if (ui.overviewOpen) {
      ui.closeOverview();
    } else {
      unawaited(refreshInstalledApps());
      ui.openOverview();
    }
  }

  /// Brings an app forward or launches it — through LaunchServices, like the
  /// Dock (native AppService).
  void activate(String bundleId) {
    if (apps.runningApp(bundleId) != null) {
      bridge.apps.activate(bundleId);
    } else {
      bridge.apps.launch(bundleId);
    }
  }

  // MARK: Dock

  List<DockItem> dockItems() {
    final pinned = theme.layout.pinned;
    final running = apps.running.map((a) => a.bundleId).toSet();
    return [
      for (final b in pinned) DockItem(bundleId: b, pinned: true, running: running.contains(b)),
      for (final a in apps.running)
        if (!pinned.contains(a.bundleId)) DockItem(bundleId: a.bundleId, pinned: false, running: true),
    ];
  }

  /// The Dock's right-click menu, as a native macOS menu next to the icon.
  /// [anchor] is the icon's rect on the main screen (top-left origin).
  Future<void> showDockMenu(String bundleId, Rect anchor, DockPosition edge) async {
    final pinned = theme.layout.pinned.contains(bundleId);
    final String? action;
    try {
      action = await bridge.apps.showDockMenu(
        bundleId,
        RectD(x: anchor.left, y: anchor.top, w: anchor.width, h: anchor.height),
        edge.name,
        pinned,
      );
    } catch (e) {
      debugPrint('dock menu: $e');
      return;
    }
    switch (action) {
      case 'open':
        ui.closeOverview();
        activate(bundleId);
      case 'keep':
        setPinned(bundleId, true);
      case 'remove':
        setPinned(bundleId, false);
    }
  }

  void setPinned(String bundleId, bool pinned) {
    final list = List<String>.of(theme.layout.pinned);
    list.remove(bundleId);
    if (pinned) list.add(bundleId);
    themes.setOverride('layout.dock.pinned', list);
  }

  // MARK: Flags

  Future<void> setFlag(String name, bool enabled) async {
    flags.value = {...flags.value, name: enabled};
    await bridge.diagnostics.setFlag(name, enabled);
  }

  bool flag(String name) => flags.value[name] ?? name != 'windowThumbnails';

  /// OPT-IN window thumbnails in the dock's hover label (off by default;
  /// needs Screen Recording + Accessibility, see Customizer → Windows &
  /// privacy).
  bool get windowThumbnails => flag('windowThumbnails');

  /// Opens the Customizer, optionally at one of its pages ('dock', 'windows'…).
  Future<void> openCustomizer({String? page}) async {
    ui.closeOverview();
    if (page != null) customizerPage.value = page;
    await bridge.host.openCustomizer();
  }

  /// The user asked for window previews (Customizer switch, or the button in
  /// a dock icon's hover card): turn them on, let macOS show its permission
  /// prompts, and open the page that shows what's still missing.
  Future<void> enableWindowPreviews() async {
    await setFlag('windowThumbnails', true);
    await bridge.diagnostics.requestThumbnailPermissions();
    await openCustomizer(page: 'windows');
  }

  // MARK: Theme → native

  /// Before onboarding the shell is inert: no surfaces, no shortcuts, no
  /// system changes — only the Customizer.
  bool get active => themes.onboarded;

  void _themeChanged() {
    final bindings = [
      if (active)
        for (final e in theme.keybindings.entries) Keybinding(action: e.key, chord: e.value),
    ];
    bridge.hotkeys
        .setBindings(bindings)
        .then<void>((failed) => rejectedShortcuts.value = failed)
        .catchError((Object e) => debugPrint('bindings: $e'));
    _scheduleApplySystem();
    _syncSurfaces();
  }

  void _systemChanged() {
    final dark = system.value?.darkMode;
    if (dark != null && dark != _lastDark) {
      _lastDark = dark;
      // Light/dark wallpaper pairs follow the appearance.
      if (theme.system.appearance == Appearance.untouched) _scheduleApplySystem();
    }
  }

  /// Pushes the theme's `system` block (debounced so dragging a slider in the
  /// Customizer doesn't restart the Dock repeatedly). Only after onboarding.
  void _scheduleApplySystem() {
    _applyDebounce?.cancel();
    if (!themes.onboarded) return;
    _applyDebounce = Timer(const Duration(milliseconds: 500), applySystemNow);
  }

  Future<void> applySystemNow() async {
    if (!themes.onboarded) return;
    // A theme that failed to load (defaults standing in) or a transient
    // mismatch must never push a different look onto macOS.
    if (theme.degraded || theme.id != themes.activeId) return;
    final s = theme.system;
    final bool? dark = switch (s.appearance) {
      Appearance.dark => true,
      Appearance.light => false,
      Appearance.untouched => null,
    };
    final effectiveDark = dark ?? system.value?.darkMode ?? false;
    final reserve = reservesDockSpace;
    try {
      await bridge.safety.applySystem(
        SystemConfig(
          hideNativeDock: s.hideNativeDock,
          darkMode: dark,
          accentColor: s.accent,
          wallpaperPath: s.wallpaperFor(dark: effectiveDark),
          dockReserveEdge: reserve ? theme.layout.dockPosition.name : null,
          dockReserveThickness: reserve ? dockThickness() : null,
        ),
      );
    } catch (e) {
      debugPrint('applySystem: $e');
    }
  }

  /// "Restore macOS": switch to the Classic Mac look first and cancel any
  /// pending theme apply, so nothing re-applies after the restore.
  Future<void> restoreMacOS() async {
    themes.setActive('classic-mac');
    _applyDebounce?.cancel();
    await bridge.safety.restoreAll();
    _applyDebounce?.cancel();
  }

  // MARK: Surface placement

  void _syncSurfaces() {
    final main = surfaces.mainScreen;
    if (main == null) return;
    if (!active) {
      for (final spec in surfaces.all) {
        if (spec.kind != 'customizer') _place(spec.surfaceId, false, Rect.zero);
      }
      return;
    }
    final layout = theme.layout;

    // Full-screen apps live in their own Space, where the panels don't
    // appear (native collection behaviour), so no window inspection is needed.
    for (final spec in surfaces.all.where((s) => s.kind == 'topbar')) {
      final s = surfaces.screens[spec.screenId];
      if (s == null) continue;
      final visible = layout.topBarEnabled && flag('menuBarCover');
      _place(spec.surfaceId, visible, Rect.fromLTWH(0, 0, s.frame.w, s.menuBarHeight));
    }

    // While macOS reserves the dock's strip, the dock stays up and the
    // launcher opens above it (it also covers the native spacer Dock).
    final strip = dockStrip(main);
    final dockVisible = layout.dockMode == DockMode.always && (strip != null || !ui.overviewOpen);
    _place('dock', dockVisible, dockRect(main));
    _dockVisible = dockVisible;
    _syncDockHit();

    final top = main.menuBarHeight;
    var launcher = Rect.fromLTWH(0, top, main.frame.w, main.frame.h - top);
    if (strip != null) {
      launcher = switch (layout.dockPosition) {
        DockPosition.bottom => Rect.fromLTRB(launcher.left, launcher.top, launcher.right, strip.top),
        DockPosition.left => Rect.fromLTRB(strip.right, launcher.top, launcher.right, launcher.bottom),
        DockPosition.right => Rect.fromLTRB(launcher.left, launcher.top, strip.left, launcher.bottom),
      };
    }
    _place('overview', ui.overviewOpen, launcher, keyboard: true);

    final pop = ui.popover;
    if (pop != null) {
      _place('popover', true, _popoverRect(pop, main));
    } else {
      _place('popover', false, Rect.zero);
    }
  }

  /// Dock rect relative to the main screen. A `floating` dock is an island
  /// sized to its icons, 8 pt off the edge; a `panel` dock spans the whole
  /// edge (below the menu-bar area when vertical).
  /// Whether the native Dock is kept as a spacer so macOS keeps windows clear
  /// of the shell's dock (ADR-0012: there is no public API for a third-party
  /// window to reserve screen space, and resizing other apps' windows would
  /// need Accessibility).
  bool get reservesDockSpace {
    final layout = theme.layout;
    return active &&
        layout.dockMode == DockMode.always &&
        layout.reserveDockSpace &&
        theme.system.hideNativeDock &&
        flag('dockHideNative');
  }

  /// Depth of the strip the shell asks macOS to reserve: the dock's own
  /// thickness, plus the 8 pt margins around a floating island.
  double dockThickness() {
    final layout = theme.layout;
    final t = dockSize(items: 1, iconSize: layout.dockIconSize, vertical: false).height;
    return layout.dockStyle == DockStyle.panel ? t : t + 16;
  }

  /// The strip macOS actually reserved on the dock's edge (from the screen's
  /// visible frame, i.e. where the native spacer Dock sits), or null.
  Rect? dockStrip(ScreenInfo main) {
    if (!reservesDockSpace) return null;
    final f = main.frame, v = main.visibleFrame;
    final top = main.menuBarHeight;
    final Rect strip;
    switch (theme.layout.dockPosition) {
      case DockPosition.bottom:
        final inset = (f.y + f.h) - (v.y + v.h);
        if (inset < 8) return null;
        strip = Rect.fromLTWH(0, f.h - inset, f.w, inset);
      case DockPosition.left:
        final inset = v.x - f.x;
        if (inset < 8) return null;
        strip = Rect.fromLTWH(0, top, inset, f.h - top);
      case DockPosition.right:
        final inset = (f.x + f.w) - (v.x + v.w);
        if (inset < 8) return null;
        strip = Rect.fromLTWH(f.w - inset, top, inset, f.h - top);
    }
    return strip;
  }

  /// Room beside the dock for its hover card: the app's name and a row of
  /// its windows (pictures when window previews are on, else placeholders).
  static const dockLabelRoom = 210.0;
  static const dockLabelWidth = 1000.0;

  /// The dock window: its resting rect plus fixed room for magnified icons
  /// and the hover label. The window never resizes on hover (that re-created
  /// Flutter's surface twice per hover and could flicker); the extra room
  /// lets clicks through until the pointer reaches the dock itself (see
  /// [dockHitRect]).
  Rect dockRect(ScreenInfo main) {
    final rest = dockRestRect(main);
    final layout = theme.layout;
    final m = math.max(1.0, layout.dockMagnification);
    final size = layout.dockIconSize;
    final slot = size * 1.18;
    final headroom = size * (m - 1) + 8 + dockLabelRoom;
    // A floating island also gets longer as icons spread apart; the ends
    // leave room for a label centred on the first/last icon.
    const labelWidth = dockLabelWidth;
    // Along a side dock the card only needs its own height (it extends
    // sideways, into the headroom).
    final along = layout.dockPosition == DockPosition.bottom ? labelWidth : dockLabelRoom + 60;
    final extra = layout.dockStyle == DockStyle.panel ? 0.0 : math.max(slot * (m - 1) * 2.6, along);
    final top = main.menuBarHeight;
    final grown = switch (layout.dockPosition) {
      DockPosition.bottom => Rect.fromLTRB(
        rest.left - extra / 2,
        rest.top - headroom,
        rest.right + extra / 2,
        rest.bottom,
      ),
      DockPosition.left => Rect.fromLTRB(
        rest.left,
        rest.top - extra / 2,
        rest.right + headroom + labelWidth - 60,
        rest.bottom + extra / 2,
      ),
      DockPosition.right => Rect.fromLTRB(
        rest.left - headroom - labelWidth + 60,
        rest.top - extra / 2,
        rest.right,
        rest.bottom + extra / 2,
      ),
    };
    return Rect.fromLTRB(
      math.max(0, grown.left),
      math.max(top, grown.top),
      math.min(main.frame.w, grown.right),
      math.min(main.frame.h, grown.bottom),
    );
  }

  /// The part of the dock window that takes clicks at rest (the dock itself),
  /// in window coordinates; null when the window is just the dock.
  Rect? dockHitRect(ScreenInfo main) {
    final window = dockRect(main);
    final rest = dockRestRect(main);
    if (window == rest) return null;
    return rest.shift(-window.topLeft);
  }

  /// The pointer entered/left the dock itself (its icons magnify out of it).
  void setDockPointerInside(bool inside) {
    if (inside == _dockPointerInside) return;
    _dockPointerInside = inside;
    _syncDockHit();
  }

  /// Where the dock's hover card is drawn (window coordinates), or null once
  /// it's gone.
  void setDockCardRect(Rect? rect) {
    if (rect == _dockCardRect) return;
    _dockCardRect = rect;
    _syncDockHit();
  }

  /// The part of the dock window that takes clicks right now: the dock; the
  /// room its icons magnify into while the pointer is on it; the hover card
  /// while it shows (and the gap between them). Everything else lets clicks
  /// through to the apps beneath.
  Rect? dockActiveRect(ScreenInfo main) {
    final rest = dockHitRect(main);
    if (rest == null) return null;
    if (!_dockPointerInside && _dockCardRect == null) return rest;
    final layout = theme.layout;
    final m = math.max(1.0, layout.dockMagnification);
    final size = layout.dockIconSize;
    final grow = size * (m - 1) + 8;
    final along = size * 1.18 * (m - 1) * 1.3;
    var hit = switch (layout.dockPosition) {
      DockPosition.bottom => Rect.fromLTRB(rest.left - along, rest.top - grow, rest.right + along, rest.bottom),
      DockPosition.left => Rect.fromLTRB(rest.left, rest.top - along, rest.right + grow, rest.bottom + along),
      DockPosition.right => Rect.fromLTRB(rest.left - grow, rest.top - along, rest.right, rest.bottom + along),
    };
    final card = _dockCardRect;
    if (card != null) hit = hit.expandToInclude(card);
    final window = dockRect(main);
    return hit.intersect(Offset.zero & window.size);
  }

  void _syncDockHit() {
    final main = surfaces.mainScreen;
    final hit = _dockVisible && main != null ? dockActiveRect(main) : null;
    if (hit == _dockHit) return;
    _dockHit = hit;
    bridge.host.setHitRegion('dock', hit == null ? null : RectD(x: hit.left, y: hit.top, w: hit.width, h: hit.height));
  }

  /// Where the dock itself sits (without the room for magnified icons).
  Rect dockRestRect(ScreenInfo main) {
    final strip = dockStrip(main);
    if (strip != null) return strip;
    final layout = theme.layout;
    final vertical = layout.dockPosition != DockPosition.bottom;
    final count = dockItems().length + (layout.showAppGridButton ? 1 : 0) + (layout.showCustomizerButton ? 1 : 0);
    final size = dockSize(items: count, iconSize: layout.dockIconSize, vertical: vertical);
    if (layout.dockStyle == DockStyle.panel) {
      final top = main.menuBarHeight;
      return switch (layout.dockPosition) {
        DockPosition.bottom => Rect.fromLTWH(0, main.frame.h - size.height, main.frame.w, size.height),
        DockPosition.left => Rect.fromLTWH(0, top, size.width, main.frame.h - top),
        DockPosition.right => Rect.fromLTWH(main.frame.w - size.width, top, size.width, main.frame.h - top),
      };
    }
    final w = size.width.clamp(0.0, main.frame.w - 16);
    final h = size.height.clamp(0.0, main.frame.h - 16);
    return switch (layout.dockPosition) {
      DockPosition.bottom => Rect.fromLTWH((main.frame.w - w) / 2, main.frame.h - h - 8, w, h),
      DockPosition.left => Rect.fromLTWH(8, (main.frame.h - h) / 2, w, h),
      DockPosition.right => Rect.fromLTWH(main.frame.w - w - 8, (main.frame.h - h) / 2, w, h),
    };
  }

  static const popoverDefaultSizes = {PopoverKind.calendar: Size(320, 356), PopoverKind.quickSettings: Size(360, 150)};

  /// Popover rect relative to the MAIN screen (the popover panel lives there;
  /// offsets place it on other screens too).
  Rect _popoverRect(PopoverState pop, ScreenInfo main) {
    final screen = surfaces.screens[pop.screenId] ?? main;
    final size = pop.size ?? popoverDefaultSizes[pop.kind]!;
    final a = pop.anchor;
    var x = a.center.dx - size.width / 2;
    var y = screen.menuBarHeight + 6;
    x = x.clamp(8.0, screen.frame.w - size.width - 8);
    y = y.clamp(8.0, screen.frame.h - size.height - 8);
    final offset = Offset(screen.frame.x - main.frame.x, screen.frame.y - main.frame.y);
    return Rect.fromLTWH(x, y, size.width, size.height).shift(offset);
  }

  void _place(String surfaceId, bool visible, Rect rect, {bool keyboard = false}) {
    final next = _Placement(visible, rect, keyboard);
    if (_placed[surfaceId] == next) return;
    final wasVisible = _placed[surfaceId]?.visible ?? false;
    _placed[surfaceId] = next;
    if (visible) {
      bridge.host.showSurface(surfaceId, RectD(x: rect.left, y: rect.top, w: rect.width, h: rect.height), keyboard);
    } else if (wasVisible) {
      bridge.host.hideSurface(surfaceId);
    }
  }
}

@immutable
class _Placement {
  const _Placement(this.visible, this.rect, this.keyboard);
  final bool visible;
  final Rect rect;
  final bool keyboard;

  @override
  bool operator ==(Object other) =>
      other is _Placement && other.visible == visible && other.keyboard == keyboard && (!visible || other.rect == rect);

  @override
  int get hashCode => Object.hash(visible, keyboard, visible ? rect : null);
}

/// Gives every surface access to the controller.
class Shell extends InheritedWidget {
  const Shell({super.key, required this.controller, required super.child});

  final ShellController controller;

  static ShellController of(BuildContext context) => context.getInheritedWidgetOfExactType<Shell>()!.controller;
  static ShellController? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<Shell>()?.controller;

  @override
  bool updateShouldNotify(Shell oldWidget) => controller != oldWidget.controller;
}
