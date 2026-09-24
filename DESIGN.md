# mac-gnome-custom: System Design & Build Plan

A macOS app with a Flutter UI that replaces the parts of the macOS interface you interact with most (top bar, dock, launcher, window switcher, workspaces, overview) with themable versions you control. The first preset is GNOME. You can also build any other look.

- **Dev machine:** macOS 26.6 (Tahoe), Flutter 3.35.3 stable
- **Status:** original design document. It predates the implementation; where they differ, the code, the [ADRs](docs/adr/README.md) and §14 win
- **Decisions:** see [docs/adr/](docs/adr/README.md) (ADR-0001 … ADR-0011)
- **Implementation:** v0.1 in this repository — see [README.md](README.md) and [SECURITY.md](SECURITY.md); deviations are listed in §14
- **Scope change (2026-09-24):** after the security audit the app became **interface-only** ([ADR-0012](docs/adr/0012-interface-only-scope.md)). Workspaces, the window overview, ⌘Tab, app menus, thumbnails and system controls described below were removed; the app needs no Accessibility or Screen Recording permission. Sections describing them are kept for history.

---

## 0. TL;DR

1. **macOS can't be re-skinned the way GNOME can.** System Integrity Protection (SIP) and the sealed system volume block patching the Dock, the menu bar, or other apps' window chrome. The only approach that survives macOS updates is a **shell overlay**: we draw our own top bar, dock, overview and switcher as floating panels, then hide or cover the native ones. SketchyBar, AeroSpace, AltTab and Raycast work the same way, and between them they show each piece is possible.
2. **Flutter handles the look. Swift handles the OS.** Plan on roughly 35–45% of the code being Swift: Accessibility (AX) window control, ScreenCaptureKit thumbnails, the event-tap hotkeys, system settings, and permissions. Flutter renders every surface through one engine with multiple views.
3. **The design is driven by the theme engine.** A theme is a folder containing `theme.json` and assets, with design tokens, layout, an icon pack, wallpaper, system appearance and keybindings. GNOME is just the first preset.
4. **Safety comes first.** Before changing anything, the app snapshots the original macOS settings. A small guardian helper restores them if the shell crashes, so you never end up with no Dock and no working launcher.
5. **Plan:** 7 phases, about 15–18 weeks for one developer. Phase 0 is a set of throwaway spikes that settle the five technical unknowns before any real code gets written.

---

## 1. Requirements

### 1.1 Functional (v1)

| ID | Feature | GNOME equivalent |
|----|---------|------------------|
| F1 | Custom **top bar**: Activities button, clock + calendar popover, focused-app menu, system indicators (battery, Wi-Fi, volume), quick-settings panel | Top bar |
| F2 | Custom **dock/dash** with pinned and running apps. Modes: overview-only (GNOME default), always-on, or intellihide | Dash / Dash-to-Dock |
| F3 | **Activities overview**: live window thumbnails, search, workspace strip, triggered by the Super key or a hot corner | Activities |
| F4 | **App grid** launcher with fuzzy search and folders | Show Applications |
| F5 | **Window switcher** with thumbnails, per app and per window | Alt+Tab / Alt+` |
| F6 | **Dynamic virtual workspaces** that always keep one empty workspace at the end | Workspaces |
| F7 | **Theme engine** covering colors, fonts, radii, blur, spacing, layout, icon packs, wallpaper, macOS dark mode and accent. Supports presets, import/export and live preview | Shell themes + Tweaks |
| F8 | **Keybinding editor** that detects conflicts with macOS shortcuts | Settings → Keyboard |
| F9 | **One-click restore**, which puts macOS back exactly the way it was | — |

### 1.2 Non-functional

| Concern | Target |
|---|---|
| Hotkey → overview visible | < 100 ms p95 (thumbnails may stream in afterwards) |
| Idle CPU | < 1% with no animation running |
| Memory | < 300 MB total (host + engine + thumbnail cache) |
| Animation | 60 fps, and 120 fps on ProMotion displays |
| Crash safety | The user always keeps a way to launch apps and switch windows |
| OS support | macOS 14 Sonoma and later (required for `SCScreenshotManager`), Apple Silicon first |
| No SIP disabling, no injection | Must survive macOS point updates |

### 1.3 Constraints & assumptions

- The UI is **Flutter** (a project constraint). OS integration is **Swift/AppKit**, since there's no alternative.
- The app is distributed **outside the Mac App Store** with Developer ID signing and notarization. The App Sandbox doesn't allow controlling other apps' windows or writing `com.apple.dock` preferences.
- One user, one Mac, one to three displays. Nothing server-side.
- One developer, part-time or full-time. Week estimates assume full-time.
- *Assumption:* "change the full interface" means the **shell** (bars, dock, launcher, switching, workspaces, wallpaper, appearance). Other apps' title bars, buttons and fonts **cannot** be changed without disabling SIP and injecting code, and that's out of scope (see §9).

---

## 2. What macOS actually lets us change

| Surface | Changeable? | Mechanism |
|---|---|---|
| Menu bar | **Cover it** | An `NSPanel` at `.statusBar` level placed over it (§4.1). Optional auto-hide via `_HIHideMenuBar` |
| App menus (File/Edit…) | **Re-host them** | Read the frontmost app's `kAXMenuBarAttribute` over AX and render it in Flutter. Clicking an item triggers `AXPress` |
| Menu-bar status items | **Partly** | `AXExtrasMenuBar` provides items and actions. Icons need a ScreenCaptureKit capture of the menu-bar strip. Spike-level risk |
| Dock | **Hide it** | `com.apple.dock autohide=1, autohide-delay=1000`, then `killall Dock`. **Never** leave the Dock process dead: it also runs Mission Control, Launchpad and Spaces |
| Launcher / App grid | **Replace it** | Our own UI. App index from `NSMetadataQuery` (`kMDItemContentType == com.apple.application-bundle`) |
| Cmd+Tab switcher | **Replace it** | A `CGEventTap` swallows the chord and shows our switcher |
| Spaces / workspaces | **Emulate them** | No public API exists to create or switch Spaces. We use virtual workspaces that park windows off-screen, the way AeroSpace does (§4.7) |
| Window move/resize/focus/close | **Yes** | AX API (`AXUIElementSetAttributeValue`, `AXRaise`, `kAXPressAction` on the close button) |
| Window thumbnails | **Yes** | ScreenCaptureKit (needs Screen Recording permission) |
| Wallpaper | **Yes** | `NSWorkspace.setDesktopImageURL(_:for:options:)` per screen |
| Dark mode | **Yes** | AppleScript to System Events (needs Automation permission) |
| Accent / highlight color | **Mostly** | `defaults write -g AppleAccentColor` and `AppleHighlightColor`. Running apps may need a relaunch to pick it up |
| App icons (in our shell) | **Yes** | Icon-pack mapping from bundle ID to image. Applies only to our dock, grid and switcher |
| App icons (Finder/system) | **Opt-in, limited** | `NSWorkspace.setIcon(_:forFile:options:)` works on `/Applications` apps. It doesn't work on sealed `/System/Applications`, and app updates reset it |
| Other apps' title bars, fonts, controls | **No** | Would need SIP off plus code injection. Rejected |
| Notification Center | **No** | Its database is TCC-protected. We can offer our own calendar/clock popover |
| Login screen, system font, cursor theme | **No / fragile** | Out of scope |

On macOS 26 the native menu bar is transparent by default, so our covering panel has to be fully opaque or use its own blur. Otherwise the native menu bar shows through.

---

## 3. High-level architecture

```
┌──────────────────────────────── mac-gnome-custom.app (non-sandboxed) ───────────────────────────────┐
│                                                                                                     │
│  ┌─────────────────────────────── Flutter (Dart) — 1 engine, N views ──────────────────────────┐    │
│  │  Surfaces (one FlutterView each)                                                             │    │
│  │   TopBar  │  Dock/Dash  │  Overview  │  AppGrid  │  Switcher  │  Popovers  │  Customizer    │    │
│  │  ─────────────────────────────────────────────────────────────────────────────────────────  │    │
│  │  State (Riverpod):  WindowsStore · AppsStore · WorkspaceStore · SystemStatusStore · ThemeStore│    │
│  │  Theme engine: load/validate theme pack → ThemeData + ShellTokens → hot-reload on file change │    │
│  └───────────────────────────────────────▲──────────────┬───────────────────────────────────────┘    │
│                        Pigeon HostApi (req/resp)│  EventChannel (stream of ShellEvent)             │
│  ┌───────────────────────────────────────┴──────────────▼───────────────────────────────────────┐    │
│  │  Swift Shell Host (AppKit)                                                                    │    │
│  │   SurfaceManager ── creates/positions NSPanels per screen, blur masks, key focus, click-thru  │    │
│  │   WindowService  ── AXObserver per app → normalized WindowModel; move/focus/close/minimize    │    │
│  │   WorkspaceService ─ virtual workspaces (park/unpark windows), per-display                    │    │
│  │   AppService     ── NSWorkspace running apps + launch/quit; Spotlight app index               │    │
│  │   CaptureService ── ScreenCaptureKit thumbnails, LRU cache, concurrency limit                 │    │
│  │   HotkeyService  ── CGEventTap: Super-tap, Cmd+Tab, custom chords, hot corners                │    │
│  │   MenuService    ── AX menu bar of frontmost app → tree; AXPress                              │    │
│  │   SystemService  ── battery (IOKit), audio (CoreAudio), Wi-Fi (CoreWLAN), BT, appearance,     │    │
│  │                      wallpaper, defaults writes                                               │    │
│  │   PermissionService ─ AX / Screen Recording / Automation / Input Monitoring status + prompts   │    │
│  │   SafetyService  ── snapshot original settings, apply journal, restore                        │    │
│  └──────────────────────────────────────────────────────────────────────────────────────────────┘    │
└───────────────┬─────────────────────────────────────────────────────────────────────────────────────┘
                │ heartbeat (XPC / Unix socket, 1 s)
┌───────────────▼───────────────┐        ┌─────────────────────────────────────────────┐
│ mgc-guardian (LaunchAgent,    │        │ ~/Library/Application Support/MacGnomeCustom │
│ SMAppService.agent)           │        │   settings.json · themes/ · snapshots/ ·     │
│ relaunches shell; if 3 crashes│        │   workspace-state.json · logs/               │
│ in 60 s → restores snapshot   │        └─────────────────────────────────────────────┘
└───────────────────────────────┘
```

**Rule of thumb for splitting the work:** Swift owns *truth and side effects*: OS state, permissions, anything that touches other processes. Dart owns *presentation and policy*: layout, animation, theming, and decisions such as which window to focus next. Dart never calls `defaults` directly. It asks the Swift services to act.

---

## 4. Deep dive

### 4.1 Surfaces: native panels hosting Flutter views

Every shell surface is an `NSPanel` whose content is a `FlutterViewController`:

```swift
final class ShellPanel: NSPanel {
  override var canBecomeKey: Bool { acceptsKeyboard }   // overview search, grid search
  override var canBecomeMain: Bool { false }
  var acceptsKeyboard = false
}

func makePanel(frame: NSRect, level: NSWindow.Level) -> ShellPanel {
  let p = ShellPanel(contentRect: frame,
                     styleMask: [.borderless, .nonactivatingPanel],   // never steals app activation
                     backing: .buffered, defer: false)
  p.level = level                        // topBar: .statusBar  overview: .popUpMenu - 1
  p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
  p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
  p.hidesOnDeactivate = false
  return p
}
```

| Surface | Level | Size | Keyboard |
|---|---|---|---|
| TopBar (per screen) | `.statusBar` | screen width × menu-bar height (read it from `NSScreen.safeAreaInsets` / `NSStatusBar.system.thickness`, since notched screens are taller) | no |
| Dock | `.statusBar` | tight to content | no |
| Overview / AppGrid | `.popUpMenu - 1` | full screen | yes |
| Switcher | `.popUpMenu - 1` | tight, centered | captured via event tap |
| Popovers (calendar, quick settings) | `.statusBar + 1` | tight | yes |
| Customizer | normal window | resizable | yes |

**The top-bar trick (recommended, "Option A"):** leave the native menu bar *visible* and put our opaque panel on top of it. That way `NSScreen.visibleFrame` still leaves the top strip out, so zoomed and maximized windows stop below our bar with no extra work. macOS has no "strut" API for third-party bars, so the alternative ("Option B") would be to auto-hide the menu bar and nudge any window that slides under the bar. Menus opened from the keyboard (such as Cmd+? Help) still draw above us at popup level, which is what we want.

**Dock placement:** GNOME's default dash appears only inside the overview, so the default needs no screen-space reservation. The always-on mode uses *intellihide*, which hides the dock whenever a window overlaps it.

**Blur:** Flutter's `BackdropFilter` only blurs Flutter pixels. It can't see the desktop behind the panel. For real frosted glass, put an `NSVisualEffectView` behind a transparent `FlutterView` (`flutterVC.backgroundColor = .clear`). Dart reports its blur shapes (a list of rounded rects) through `SurfaceApi.setBlurRegions`, and Swift uses them to build the effect view's `maskImage`.

**Click-through:** panels are sized tightly to their content. The full-screen overview captures every click, and clicking empty space closes it.

**Displays and fullscreen:** listen for `NSApplication.didChangeScreenParametersNotification` and rebuild the per-screen surfaces. The top bar hides when the frontmost window on that screen has `AXFullScreen == true`.

### 4.2 Flutter engine strategy

- **Primary:** run **one `FlutterEngine` with several `FlutterViewController`s**. The macOS embedder supports multiple views per engine. On the Dart side, use `runWidget(ViewCollection(views: [...]))` and map each `FlutterView.viewId` to a surface through a registry the host sends at startup. With one engine there's one isolate: shared stores, no state syncing between windows, and a single Dart heap.
- **Fallback:** run one engine per surface and sync state over the host. That costs tens of MB per engine and brings cross-engine consistency problems. Use it only if Spike S1 fails.
- Don't depend on the experimental high-level multi-window API (`RegularWindow` and related). The panels need special levels and collection behaviours, which only native code controls.
- **Idle cost:** Flutter renders only when something changes, so a static clock that repaints once a minute costs close to nothing. Avoid endless implicit animations such as spinners or shimmer in always-visible surfaces.

### 4.3 Bridge API (Pigeon)

Pigeon generates type-safe Dart↔Swift code: `@HostApi` for requests and `@EventChannelApi` for streams. Sketch:

```dart
// pigeons/shell_api.dart
class WindowInfo {
  late int id;            // CGWindowID
  late int pid;
  late String bundleId;
  late String title;
  late Rect frame;
  late int screenId;
  late int workspace;     // virtual workspace index
  late bool isMinimized, isFullscreen, isFocused;
}
class AppInfo { late String bundleId; late String name; late String path; late bool running; late int? pid; }
class Rect { late double x, y, w, h; }
class Thumbnail { late int width, height, bytesPerRow; late Uint8List bgra; }

sealed class ShellEvent {}
class WindowsChanged extends ShellEvent { late List<WindowInfo> upserted; late List<int> removed; }
class FocusChanged   extends ShellEvent { late int? windowId; late String? bundleId; }
class AppsChanged    extends ShellEvent { late List<AppInfo> running; }
class SystemStatus   extends ShellEvent { late int battery; late bool charging; late double volume; late String? ssid; }
class HotkeyFired    extends ShellEvent { late String action; }   // "overview", "switcher.next", "workspace.2" …
class ScreensChanged extends ShellEvent { late List<ScreenInfo> screens; }
class PermissionsChanged extends ShellEvent { late Map<String, bool> granted; }

@HostApi() abstract class WindowApi {
  List<WindowInfo> list();
  void focus(int id); void close(int id); void minimize(int id); void setFrame(int id, Rect f);
  @async Thumbnail? thumbnail(int id, int maxWidthPx);   // raw BGRA + width/height/bytesPerRow (no PNG encode); null if unavailable
}
@HostApi() abstract class WorkspaceApi { void switchTo(int screenId, int index); void moveWindow(int id, int index); }
@HostApi() abstract class AppApi { List<AppInfo> installed(); void launch(String bundleId); void quit(String bundleId); Uint8List icon(String bundleId, int px); }
@HostApi() abstract class MenuApi { MenuNode frontmostMenu(); void press(List<int> path); }
@HostApi() abstract class SystemApi { void setDarkMode(bool on); void setAccent(int c); void setWallpaper(int screenId, String path); void setVolume(double v); }
@HostApi() abstract class SurfaceApi { void show(String surface, int screenId); void hide(String surface); void setBlurRegions(int viewId, List<RRect> r); void setKeyboard(int viewId, bool on); }
@HostApi() abstract class HotkeyApi { void register(List<Keybinding> b); List<String> conflicts(Keybinding b); }
@HostApi() abstract class SafetyApi { void snapshotIfNeeded(); void restoreAll(); }
@EventChannelApi() abstract class ShellEvents { ShellEvent events(); }
```

**Contract rules:**
- Events carry **deltas** (`upserted`/`removed`), not full lists. `list()` exists for resyncing.
- Swift **coalesces** AX notifications in a 16 ms window before emitting. A single drag can fire hundreds of move events.
- Thumbnails travel as `Uint8List` through a *request* rather than inside events, so large bitmaps never clog the event stream. Later we can switch to a Flutter **external texture** (`FlutterTexture`) for zero-copy live previews.

### 4.4 Native services, key details

**WindowService**
- For each running app, create an `AXUIElementCreateApplication(pid)` plus an `AXObserver` subscribed to: `kAXWindowCreated`, `kAXUIElementDestroyed`, `kAXFocusedWindowChanged`, `kAXWindowMoved`, `kAXWindowResized`, `kAXTitleChanged`, `kAXWindowMiniaturized`, `kAXWindowDeminiaturized`. App launches and quits come from `NSWorkspace` notifications.
- Mapping an AX element to its `CGWindowID` needs `_AXUIElementGetWindow`. It's a private symbol inside a public framework, and AltTab, Rectangle and yabai have relied on it for years. This is the *one* private call we accept. Keep it isolated behind a protocol, with a fallback heuristic that matches on pid, frame and title against `CGWindowListCopyWindowInfo`.
- Filter out non-standard windows: `AXSubrole == AXStandardWindow`, minimum size, and not our own pid.
- Each app gets its own serial queue for AX calls. **AX calls block when the target app is hung**, so apply a timeout (`AXUIElementSetMessagingTimeout(el, 0.25)`) and never make these calls on the main thread.

**CaptureService**
- Use `SCShareableContent.current` for the window list, cached for 1 s, and `SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow:), configuration:)` for each window, scaled to its tile size.
- Keep an LRU cache of about 60 entries keyed by `windowId`. Invalidate an entry on resize or title change, or once it's over 2 s old *while the overview is open*.
- Allow at most 4 captures at a time. Opening the overview first requests the thumbnails for the visible workspace, then pre-warms the rest.
- Minimized windows or windows on other virtual workspaces can't be captured cleanly, so serve the last cached image, dimmed.

**HotkeyService**
- Create a `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, …)` for `keyDown`, `keyUp` and `flagsChanged`.
- **Super-tap detection:** Cmd goes down and comes back up within 300 ms with no other key pressed in between, and then we fire `overview`.
- Swallow configured chords such as Cmd+Tab by returning `nil` from the callback.
- **Watch for `tapDisabledByTimeout` and re-enable the tap immediately.** macOS disables slow taps, so the callback must return in microseconds and post its work to another queue.
- Detect hot corners with a `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` check against screen corners, including a dwell time.

**MenuService:** reads `kAXMenuBarAttribute` from the frontmost app, walks it lazily (only when the user opens a menu), and returns a `MenuNode` tree with titles, enabled state, shortcut and children. `press(path)` performs `AXPress` on that node.

**SystemService:** battery via `IOPSCopyPowerSourcesInfo` plus a notification run-loop source; volume via CoreAudio `kAudioDevicePropertyVolumeScalar` listeners; Wi-Fi via CoreWLAN (on Sonoma and later, the SSID needs Location permission, otherwise show signal only); dark mode via `NSAppleScript` to System Events. Brightness control needs private API, so it's **not in v1**.

### 4.5 Dart app structure

```
lib/
  main.dart                     # runWidget(ViewCollection) + surface registry
  bridge/                       # pigeon-generated + thin wrappers, event demux
  core/
    stores/                     # Riverpod notifiers: windows, apps, workspaces, system, focus
    theme/                      # schema, loader, validator, resolver → ShellTheme (tokens)
    keybindings/
  surfaces/
    top_bar/  dock/  overview/  app_grid/  switcher/  popovers/  customizer/
  widgets/                      # themed primitives: ShellButton, Pill, IconTile, BlurRegion
  presets/                      # built-in themes (gnome_adwaita, gnome_dark, win11, classic_mac)
```

- **State:** Riverpod. `WindowsStore` is a `Map<int, WindowInfo>` updated from event deltas. Everything else derives from it, e.g. `windowsOnWorkspace(screen, ws)` and `appsWithWindows`.
- **Every visual** reads from `ShellTheme.of(context)`. No colors or sizes are hard-coded in surfaces. That's what makes "any interface" possible.
- **Layout is data:** the top bar is described as `left/center/right` lists of *widget IDs* (`activities`, `appMenu`, `clock`, `indicators`, `workspaces`, and so on) resolved through a registry. Users rearrange bars without code changes.

### 4.6 Theme engine & data model

A **theme pack** is a folder, or a zipped `.mgctheme`:

```
gnome-adwaita/
  theme.json
  wallpapers/day.jpg, night.jpg
  icons/ (optional icon pack: <bundleId>.png | mapping.json)
  fonts/ (bundled into the shell only: Cantarell, Inter …)
```

```jsonc
{
  "schema": 1,
  "id": "gnome-adwaita",
  "name": "GNOME Adwaita",
  "extends": null,                       // allows "extends": "gnome-adwaita" + overrides
  "tokens": {
    "color": { "bar.bg": "#000000", "bar.fg": "#ffffff", "accent": "#3584e4",
               "surface": "#242424", "overview.scrim": "#000000cc" },
    "font":  { "family": "Cantarell", "size.bar": 14, "weight.bar": 700 },
    "radius": { "tile": 12, "popover": 14, "dock": 18 },
    "blur":  { "dock": 24, "popover": 0 },
    "motion": { "overview.ms": 250, "curve": "easeOutCubic" }
  },
  "layout": {
    "topBar":  { "enabled": true, "height": "menubar",
                 "left": ["activities", "workspaces"], "center": ["clock"], "right": ["indicators", "quickSettings"] },
    "dock":    { "mode": "overviewOnly", "position": "bottom", "iconSize": 56, "showRunningDots": true },
    "overview":{ "trigger": ["superTap", "hotCorner:topLeft"], "showAppGridButton": true },
    "workspaces": { "mode": "dynamic", "perDisplay": false }
  },
  "system": {                             // applied through SafetyService (journaled + reversible)
    "darkMode": "dark", "accent": "blue", "wallpaper": { "light": "wallpapers/day.jpg", "dark": "wallpapers/night.jpg" },
    "nativeDock": "hidden", "nativeMenuBar": "covered"
  },
  "icons": { "pack": "icons/", "fallback": "system" },
  "keybindings": { "overview": "superTap", "appGrid": "superDoubleTap", "switcher": "cmd+tab",
                   "workspace.next": "ctrl+alt+right", "workspace.1": "ctrl+1" }
  // never default to plain cmd+<key>: it collides with app shortcuts (cmd+a = Select All, cmd+1 = tab 1)
}
```

- **Resolution order:** built-in defaults, then the `extends` chain, then this theme, then the user's live overrides from the Customizer. The result is an immutable `ShellTheme`.
- **Validation:** JSON Schema is checked when the pack loads. Invalid values fall back per token, with a warning shown in the Customizer. A bad theme never crashes the shell.
- **Hot reload:** a file watcher on `themes/` re-resolves and rebuilds within one frame, which makes it easy to author themes in a text editor.
- **Applying the `system.*` block** is a *transaction* (§4.8). Token and layout changes are pure Dart and instant.

### 4.7 Virtual workspaces

macOS has no public Spaces API, so we emulate workspaces with the same approach AeroSpace uses:

1. Every managed window lives on **one native Space**. Onboarding tells the user to disable "Automatically rearrange Spaces" and advises against keeping several native Spaces.
2. `WorkspaceStore` assigns each window to a workspace index. New windows go to the active workspace.
3. **Switching to workspace N:** save the current frames of windows on the old workspace, then move each of them to a *parked* position at the screen's bottom-right corner, with only 1 px on-screen because macOS clamps windows that are fully off-screen. Then restore the saved frames of workspace N's windows and focus the most recently used one.
4. **Dynamic behaviour:** there's always exactly one empty workspace at the end, and empty workspaces in the middle collapse, as in GNOME.
5. **Persistence:** `workspace-state.json` stores `{bundleId, title, workspace, frame}` and matches it up again heuristically after a relaunch.
6. **On quit or restore, all parked windows are unparked.** This is mandatory. The guardian does it as well.

**Trade-offs:** switching can flicker for a frame on very large windows. Some apps (a few Electron or Java apps) fight programmatic moves, so fall back to minimizing them. Native Mission Control still shows parked windows.

### 4.8 Safety: snapshot, journal, restore, guardian

This is the most important reliability feature. If the shell crashes while the Dock is hidden and Cmd+Tab is swallowed, the user is stranded.

- **First run snapshot**, saved to `snapshots/original.json`, done once and never overwritten: `com.apple.dock` values `autohide`, `autohide-delay`, `autohide-time-modifier`, `orientation`, `tilesize`; `NSGlobalDomain` values `_HIHideMenuBar`, `AppleInterfaceStyle`, `AppleAccentColor`, `AppleHighlightColor`; the wallpaper URL for each screen; the relevant `com.apple.symbolichotkeys` entries; and a list of any icons we changed.
- **Apply journal:** every system mutation appends `{key, before, after, ts}`. Restoring replays the journal in reverse, then falls back to the snapshot.
- **Guardian:** `mgc-guardian` is a tiny Swift LaunchAgent registered with `SMAppService.agent(plistName:)`. It watches the shell's pid with a `kqueue` `NOTE_EXIT` plus a 1 s heartbeat. The heartbeat is sent from the shell's **main run loop**, so a hung main thread counts as a crash. On an unclean exit it relaunches the shell. After **3 crashes in 60 s** it restores the Dock and menu bar settings, unparks windows, runs `killall Dock`, and posts a notification.
- **Panic hotkey:** Ctrl+Opt+Cmd+Esc restores everything and quits.
- **Uninstall:** "Restore macOS & Quit" in the Customizer, plus a `restore` CLI mode (`mac-gnome-custom --restore`).

### 4.9 Permissions & onboarding

| Permission | Needed for | Check | Degraded mode if denied |
|---|---|---|---|
| Accessibility | window control, menus, event tap | `AXIsProcessTrustedWithOptions` | Top bar + launcher only; no switcher or workspaces |
| Screen Recording | thumbnails, window titles | `CGPreflightScreenCaptureAccess` | Icons instead of thumbnails |
| Automation (System Events) | dark mode toggle | first call triggers prompt | Hide the toggle |
| Location (optional) | Wi-Fi SSID | CoreLocation | Show signal only |

Onboarding is a step-by-step Flutter wizard that polls grant status (there's no callback for it) and deep-links to `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. **Dev gotcha:** TCC grants are tied to the code signature, so sign debug builds with a stable identity. Otherwise every rebuild asks for permissions again.

---

## 5. Key flows

**Pressing Super to open the Overview:**
```
CGEventTap (Swift, <50µs) ─flagsChanged Cmd↓…Cmd↑, no key between─► HotkeyFired("overview")
  └─► Dart OverviewController
        ├─ SurfaceApi.show("overview", activeScreen) ; setKeyboard(true)         ~5 ms
        ├─ render window tiles from WindowsStore (icons + cached thumbs)        first frame < 50 ms
        └─ for visible tiles: WindowApi.thumbnail(id, w)  (≤4 parallel)          stream in 30–150 ms
Click tile ─► WindowApi.focus(id) (+ WorkspaceApi.switchTo if needed) ─► animate out ─► hide panel
```

**Switching themes:**
```
Customizer picks "win11" ─► ThemeStore.resolve() ─► all views rebuild (tokens/layout)       instant
                         └► SafetyApi: diff theme.system vs current ─► journal ─► apply:
                              dock prefs + killall Dock, wallpaper, dark mode, accent
                              (debounced 500 ms so slider-dragging doesn't hammer Dock)
```

---

## 6. Storage

`~/Library/Application Support/MacGnomeCustom/`

| File | Content | Format |
|---|---|---|
| `settings.json` | active theme id, user overrides, onboarding state | JSON, atomic write (temp + rename) |
| `themes/<id>/` | user-installed theme packs | folder |
| `snapshots/original.json` | pristine macOS settings | JSON, write-once |
| `journal.jsonl` | applied mutations | append-only JSONL |
| `workspace-state.json` | window→workspace assignments | JSON, written every 5 s when dirty |
| `logs/` | rotating logs (`os_log` + file) | text |
| `~/Library/Caches/MacGnomeCustom/` | icon cache (PNG by bundleId+size) | files |

No database is needed. Every dataset is small (under 1 MB).

---

## 7. Performance & reliability

This app has no servers to scale. The load that matters is **event rate, window count and pixel throughput**.

| Load | Estimate | Handling |
|---|---|---|
| Windows | 20–150 | Map deltas; overview virtualizes above 40 tiles |
| AX events during a drag | ~120/s | coalesce in 16 ms buckets, send only the latest frame per window |
| Thumbnails per overview open | 10–40 × ~400×250 px | LRU cache + 4-way concurrency + pre-warm on hot-corner approach |
| Installed apps | 100–500 | index at startup + `NSMetadataQuery` live updates; icon cache on disk |
| Displays | 1–3 | per-screen surfaces; share one engine |

| Failure mode | Detection | Response |
|---|---|---|
| Target app hung, AX call blocks | 250 ms messaging timeout | mark window "unresponsive", skip, retry on next event |
| Event tap disabled by OS | `tapDisabledByTimeout` / `ByUserInput` event | re-enable immediately; log; if it repeats, show a banner |
| Permission revoked at runtime | poll every 5 s + on failure | switch to degraded mode, show a banner |
| Shell crash | guardian | relaunch → restore after 3 crashes/60 s |
| Bad theme file | schema validation | per-token fallback, warning in UI |
| Display unplugged mid-workspace | screen change notification | move orphaned windows (and parked ones) to main screen |
| macOS update changes behaviour | smoke test checklist per release | feature flags for each OS hack (menu-bar cover, dock hide, super-tap) |

**Observability:** use `os_log` with subsystems per service, plus an in-app **Diagnostics** page showing event rates, AX latency p95, thumbnail cache hit rate, engine frame times, and permission status. There's no telemetry by default.

---

## 8. Build, sign, distribute

- The Xcode project comes from `flutter create --platforms=macos`, with a **Swift package** `ShellKit` for the services so they can be unit-tested without Flutter, plus a second target `mgc-guardian`.
- Entitlements: **no sandbox** (`com.apple.security.app-sandbox = false`), plus Hardened Runtime and `com.apple.security.automation.apple-events`.
- Sign with Developer ID, notarize with `notarytool`, and ship a DMG. Auto-update through **Sparkle 2**.
- Launch at login with `SMAppService.mainApp.register()`.
- CI: GitHub Actions on a macOS runner runs `flutter test`, `swift test` for ShellKit, the build, and notarization on tags.

---

## 9. Trade-off analysis

| Decision | Chosen | Alternative | Why |
|---|---|---|---|
| How to change the UI | **Overlay shell** | SIP-off + code injection (MacForge/yabai SA style) | Injection can change *everything*, but it breaks with OS updates, weakens security, and needs manual setup in Recovery. The overlay is safe and shippable |
| UI toolkit | **Flutter** (project constraint) | SwiftUI | Flutter pros: you can draw literally any look, hot reload for fast iteration, one rendering model for every surface. Cons: more memory, a lot of native code anyway, text/IME and accessibility less native. Acceptable because this is a *shell*, not a document app |
| Engine topology | **1 engine, N views** | engine per surface | Shared state and lower memory. Risk: multi-view maturity on macOS, settled by Spike S1 |
| Menu bar | **Cover visible bar** (A) | Auto-hide + nudge windows (B) | Option A keeps `visibleFrame` correct for free. B frees ~0 px and adds window fighting |
| Workspaces | **Virtual (park off-screen)** | Native Spaces via private SkyLight API | Private Space switching needs SIP partly off on recent macOS. Virtual workspaces are fully under our control, with some flicker |
| Dock hiding | **autohide + 1000 s delay** | kill Dock / remove from launchd | The Dock process runs Mission Control, Spaces and Launchpad. Killing it breaks things |
| Bridge | **Pigeon** | hand-written MethodChannels / FFI | Typed contracts on both sides, generated code. FFI is overkill; only thumbnails might move to textures |
| Theme format | **JSON + assets folder** | Dart plugins / CSS | Declarative, shareable and safe. Dart can't load code at runtime anyway (AOT) |

---

## 10. Repository layout

```
mac-gnome-custom/
  DESIGN.md
  app/                              # Flutter project
    lib/ … (see §4.5)
    pigeons/shell_api.dart
    test/ (widget + golden tests per surface & preset)
    macos/
      Runner/                       # AppDelegate: boots ShellKit + FlutterEngine, registers views
      ShellKit/                     # Swift package: services (unit-tested, no Flutter dependency)
        Sources/ShellKit/{Windows,Workspaces,Capture,Hotkeys,Menus,System,Permissions,Safety,Surfaces}/
        Tests/
      Guardian/                     # mgc-guardian LaunchAgent target
  themes/                           # built-in presets (copied into bundle)
    gnome-adwaita/  gnome-dark/  win11/  classic-mac/
  spikes/                           # Phase 0 throwaway prototypes
  tools/                            # theme validator CLI, icon-pack builder
```

---

## 11. Plan

Estimates assume **one full-time developer**. Double them for part-time. Each phase ends in something you can use daily ("dogfoodable").

### Phase 0: De-risking spikes (1.5 weeks)
Throwaway code in `spikes/`. **Don't start Phase 1 until S1–S5 pass or have a documented fallback.**

| Spike | Question | Pass criteria |
|---|---|---|
| S1 | Can one Flutter engine drive 3 transparent `NSPanel`s at different window levels? | 3 views render independently with clear backgrounds; a `setState` in shared state updates all three |
| S2 | Can the top-bar panel cover the native menu bar, including notched screens and macOS 26's transparent bar? | nothing shows through; zoomed windows stop below the bar; menus still open via keyboard |
| S3 | Does AX enumerate, move and focus windows reliably for Safari, Chrome, VS Code, Finder, Slack and Terminal? | all six work; hung-app timeout verified |
| S4 | ScreenCaptureKit: 30 window thumbnails at 400 px | < 300 ms cold, < 50 ms cached |
| S5 | Event tap: Super-tap without false positives during Cmd+C / Cmd+Tab; swallowing Cmd+Tab | 0 false triggers over 200 scripted presses |
| S6 | Off-screen parking for 10 windows | switch < 150 ms, windows restore to exact frames |

### Phase 1: Foundation (2.5 weeks)
- Project skeleton, ShellKit package, Pigeon wiring, event demux, Riverpod stores
- PermissionService + onboarding wizard
- SafetyService: snapshot, journal, restore, panic hotkey; **guardian agent**
- Theme schema v1, loader, validator, `ShellTheme` resolution, hot reload
- Diagnostics page
- **Exit:** the app starts at login, shows an empty themed top bar, and restore brings back the pristine settings across a kill -9 test

### Phase 2: Top bar (2 weeks)
- Per-screen panels, layout-as-data widget registry
- Activities button, clock + calendar popover, workspace indicator
- App menu via MenuService
- Indicators: battery, volume (with slider), Wi-Fi; quick-settings panel (dark mode, volume, Wi-Fi toggle)
- Fullscreen auto-hide, display hot-plug
- **Exit:** you can use it all day in place of the native menu bar

### Phase 3: Dock & App Grid (2 weeks)
- App index, icon cache, icon packs
- Dock modes: overviewOnly / always / intellihide; pinned apps, running dots, context menu (quit, new window, pin)
- App grid with fuzzy search, folders, keyboard navigation
- Hide the native Dock through SafetyService
- **Exit:** native Dock hidden for a week with no need to bring it back

### Phase 4: Windows, overview, switcher, workspaces (4 weeks, the hardest phase)
- WindowService with AX observers, coalescing, id mapping
- CaptureService + cache
- Overview: tile layout algorithm (GNOME-like best fit), search across apps and windows, drag to workspace
- Switcher (app mode + window mode), swallowing Cmd+Tab
- Virtual workspaces with park/unpark, dynamic behaviour, persistence, keybindings
- **Exit:** a week of daily use with no stranded windows; overview p95 < 100 ms to first frame

### Phase 5: Theme engine & Customizer (2 weeks)
- Customizer window: live preview of every surface, token editors (color, font, radius, blur, motion), layout drag-and-drop
- System appearance block: dark mode, accent, wallpaper (light/dark pair)
- Presets: GNOME Adwaita, GNOME Dark, Windows 11, Classic Mac; `extends` inheritance
- Import/export `.mgctheme`; keybinding editor with conflict detection
- **Exit:** a new look built from scratch in under 15 minutes, with no code

### Phase 6: Hardening & release (2 weeks)
- Multi-monitor matrix, Stage Manager detection (warn), fullscreen and Split View edge cases
- Performance pass: idle CPU, memory, frame times; golden tests for presets
- Signing, notarization, Sparkle, DMG, first-run experience, uninstall/restore docs
- **Exit:** v1.0 notarized build; restore verified on a clean user account

**Total: about 16 weeks** (1.5 + 2.5 + 2 + 2 + 4 + 2 + 2).

### Milestone summary
```
wk 0─1.5   Spikes ✔ go/no-go
wk 1.5─4   Foundation (safe to run daily)
wk 4─6     Top bar         ← first "wow" moment
wk 6─8     Dock + App grid
wk 8─12    Overview/Switcher/Workspaces   ← feels like GNOME
wk 12─14   Customizer + presets           ← "any interface"
wk 14─16   Hardening → v1.0
```

---

## 12. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Flutter multi-view on macOS has gaps (focus, resizing, transparency) | Med | High | Spike S1; engine-per-surface fallback |
| A macOS update changes menu-bar or Dock behaviour | Med | Med | feature flags per hack; guardian restore; test on betas each June |
| AX unreliable for some apps (Electron, Java, games) | High | Med | per-bundle quirks table; minimize fallback for parking |
| Event tap latency makes typing feel laggy | Low | High | callback does nothing except enqueue; measure in Diagnostics |
| User gets stranded after a crash | Low | **Critical** | guardian, panic hotkey, `--restore` CLI, write-once snapshot |
| Scope creep toward "theme every app" | High | Med | §2 table is the contract; injection is explicitly out |
| TCC permission churn during development | High | Low | stable dev signing identity |

---

## 13. What to revisit as it grows

- **Extensions (like GNOME Shell extensions):** Dart can't load code at runtime. Candidates: declarative widgets with an embedded script engine (Lua or JS via JavaScriptCore) talking to a restricted shell API, or out-of-process extensions over a local socket, which are safer.
- **Theme gallery:** signed theme packs with a small index server once there are other users.
- **Live window previews** through `SCStream` into Flutter external textures, instead of static thumbnails.
- **Tiling mode** (like Pop!_OS / Forge) on top of WindowService, since the building blocks are already there.
- **Native Spaces integration** as an opt-in "advanced mode" for users who accept private APIs.
- **Accessibility of our own shell:** VoiceOver semantics on every surface. Flutter supports it, but it needs deliberate testing.

---

## 14. Implementation deviations (v0.1, 2026-09-24)

| Design said | Implemented | Why |
|---|---|---|
| Riverpod for state (§4.5) | `ChangeNotifier`/`ValueNotifier` stores + one `InheritedWidget` | No dependency; multi-view friendly; the stores are few and flat. Revisit if state grows. |
| Guardian as `SMAppService.agent` (§4.8) | Same executable, `posix_spawn` + `setsid` | See ADR-0010 notes. |
| Installed apps via `NSMetadataQuery` (§2) | Two-level scan of the standard app folders, cached 60 s | Deterministic, no Spotlight dependency; live updates not needed for a launcher. |
| Separate App Grid surface | App grid is a mode of the overview surface (GNOME behaviour) | One fewer panel. |
| `Uint8List` PNG thumbnails | Raw BGRA (`Thumbnail`) | ADR review finding #3. |
| Dock tooltips | Not implemented | A tightly sized panel would clip them; needs a separate tooltip panel. |
| App-grid folders (F4) | Not implemented | Post-v0.1. |
