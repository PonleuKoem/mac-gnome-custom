import AppKit
import FlutterMacOS
import ServiceManagement

/// Buffers nothing: Dart subscribes first, then pulls initial state.
final class EventSink: EventsStreamHandler {
  private var sink: PigeonEventSink<ShellEvent>?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<ShellEvent>) {
    self.sink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    sink = nil
  }

  func send(_ event: ShellEvent) {
    sink?.success(event)
  }
}

/// Owns every native service and implements the Pigeon host APIs. Main thread.
///
/// Interface-only scope (ADR-0012): nothing here reads other apps' windows,
/// screen contents or keystrokes, and nothing changes the system beyond
/// appearance (Dock visibility, wallpaper, dark mode, accent colour).
final class ShellRuntime {
  static let shared = ShellRuntime()

  let flags = FeatureFlags.shared
  let hotkeys = GlobalHotkeys()
  let hotCorner = HotCornerMonitor()
  let apps = AppService()
  let system = SystemStatusService()
  let safety = SafetyService()
  let heartbeat = HeartbeatWriter()
  let events = EventSink()
  var surfaceManager: SurfaceManager?
  private var lastSystemConfig: SKSystemConfig?
  /// Keeps App Nap from throttling the heartbeat timer while no surface is
  /// visible; the guardian would otherwise think we hung.
  private var activity: NSObjectProtocol?
  private var started = false
  private var attached = false

  // MARK: Wiring

  func attach(messenger: FlutterBinaryMessenger) {
    guard !attached else { return }
    attached = true
    EventsStreamHandler.register(with: messenger, streamHandler: events)
    ShellHostApiSetup.setUp(binaryMessenger: messenger, api: self)
    AppApiSetup.setUp(binaryMessenger: messenger, api: self)
    SystemApiSetup.setUp(binaryMessenger: messenger, api: self)
    HotkeyApiSetup.setUp(binaryMessenger: messenger, api: self)
    SafetyApiSetup.setUp(binaryMessenger: messenger, api: self)
    DiagnosticsApiSetup.setUp(binaryMessenger: messenger, api: self)
  }

  func start(surfaces: SurfaceManager) {
    guard !started else { return }
    started = true
    surfaceManager = surfaces
    surfaces.onSurfacesChanged = { [weak self] specs in
      self?.events.send(SurfacesChangedEvent(surfaces: specs))
      self?.events.send(ScreensChangedEvent(screens: NSScreen.screens.map(ScreenInfo.init)))
    }
    surfaces.onDismissed = { [weak self] id in self?.events.send(SurfaceDismissedEvent(surfaceId: id)) }
    surfaces.onCustomizerVisibility = { [weak self] visible in
      // A recorder left open in a closed Customizer must not keep shortcuts off.
      if !visible { self?.hotkeys.setSuspended(false) }
      self?.events.send(CustomizerVisibilityEvent(visible: visible))
    }
    surfaces.rebuild()
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                           object: nil, queue: .main) { _ in surfaces.rebuild() }

    activity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep],
      reason: "Desktop shell: heartbeat and hotkeys must not be napped"
    )
    // Heartbeat before the guardian, so it never reads a stale file (ADR-0010).
    heartbeat.start()
    #if DEBUG
      Guardian.spawn(relaunch: false)  // Xcode "stop" is a SIGKILL; restore but don't relaunch
    #else
      Guardian.spawn(relaunch: true)
    #endif

    apps.onChange = { [weak self] list in self?.events.send(AppsChangedEvent(apps: list.map(AppInfo.init))) }
    system.onChange = { [weak self] s in self?.events.send(SystemStatusEvent(status: SystemStatus(s))) }
    hotkeys.onAction = { [weak self] action in self?.events.send(HotkeyEvent(action: action)) }
    hotCorner.onTrigger = { [weak self] in self?.events.send(HotkeyEvent(action: "hotcorner")) }
    flags.onChange = { [weak self] flag, enabled in self?.flagChanged(flag, enabled) }

    apps.start()
    system.start()
    hotCorner.start()
    // Pre-load for the dock menu's Open at Login checkmarks (never prompts).
    LoginItems.shared.refreshIfPermitted()
    if WindowThumbnails.enabled {
      let p = WindowThumbnails.permissions()
      Log.apps.info("window previews on: screenRecording=\(p.screenRecording) accessibility=\(p.accessibility)")
    }
  }

  func willTerminate() {
    safety.restoreRuntime()
    heartbeat.stopClean()
  }

  private func flagChanged(_ flag: FeatureFlag, _ enabled: Bool) {
    if flag == .dockHideNative, let c = lastSystemConfig {
      safety.apply(c, dockHidingAllowed: enabled)
    }
  }
}

// MARK: - Host APIs

extension ShellRuntime: ShellHostApi {
  func ready() throws {
    Log.surfaces.info("Dart side ready")
  }

  func surfaces() throws -> [SurfaceSpec] { surfaceManager?.specs ?? [] }

  func screens() throws -> [ScreenInfo] { NSScreen.screens.map(ScreenInfo.init) }

  func supportDirectory() throws -> String { Paths.supportDirectory.path }

  func showSurface(surfaceId: String, rect: RectD, takeKeyboard: Bool) throws {
    surfaceManager?.show(surfaceId, rect: rect.cgRect, takeKeyboard: takeKeyboard)
  }

  func hideSurface(surfaceId: String) throws { surfaceManager?.hide(surfaceId) }

  func setHitRegion(surfaceId: String, rect: RectD?) throws {
    surfaceManager?.setHitRegion(surfaceId, rect: rect?.cgRect)
  }

  func setBlurRegions(surfaceId: String, regions: [RRectD], dark: Bool) throws {
    surfaceManager?.setBlurRegions(surfaceId, regions: regions, dark: dark)
  }

  func openCustomizer() throws { surfaceManager?.showCustomizer() }

  func setLaunchAtLogin(enabled: Bool) throws {
    do {
      if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      throw PigeonError(code: "login-item", message: error.localizedDescription, details: nil)
    }
  }

  func launchAtLogin() throws -> Bool { SMAppService.mainApp.status == .enabled }

  func pickPath(directory: Bool, extensions: [String], completion: @escaping (Result<String?, Error>) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = directory
    panel.canChooseFiles = !directory || !extensions.isEmpty
    panel.allowsMultipleSelection = false
    if !extensions.isEmpty { panel.allowedContentTypes = extensions.compactMap { .init(filenameExtension: $0) } }
    NSApp.activate()
    panel.begin { response in completion(.success(response == .OK ? panel.url?.path : nil)) }
  }

  func savePath(suggestedName: String, completion: @escaping (Result<String?, Error>) -> Void) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = suggestedName
    NSApp.activate()
    panel.begin { response in completion(.success(response == .OK ? panel.url?.path : nil)) }
  }

  func quit() throws { NSApp.terminate(nil) }
}

extension ShellRuntime: AppApi {
  func running() throws -> [AppInfo] { apps.running().map(AppInfo.init) }

  func installed(completion: @escaping (Result<[InstalledApp], Error>) -> Void) {
    apps.installed { completion(.success($0.map(InstalledApp.init))) }
  }

  func icon(bundleIdOrPath: String, sizePx: Int64, completion: @escaping (Result<FlutterStandardTypedData?, Error>) -> Void) {
    apps.icon(for: bundleIdOrPath, size: Int(sizePx)) { data in
      completion(.success(data.map { FlutterStandardTypedData(bytes: $0) }))
    }
  }

  func launch(bundleIdOrPath: String) throws {
    Log.apps.info("dart → launch \(bundleIdOrPath, privacy: .public)")
    if isSelf(bundleIdOrPath) { return showCustomizerFromLauncher() }
    apps.launch(bundleIdOrPath)
  }

  func activate(bundleId: String) throws {
    Log.apps.info("dart → activate \(bundleId, privacy: .public)")
    if isSelf(bundleId) { return showCustomizerFromLauncher() }
    apps.activate(bundleId)
  }

  /// The shell's own entry in the launcher or dock opens its Customizer,
  /// the same as clicking the app again in Finder or Launchpad.
  private func isSelf(_ bundleIdOrPath: String) -> Bool {
    bundleIdOrPath == Bundle.main.bundleIdentifier || bundleIdOrPath == Bundle.main.bundlePath
  }

  private func showCustomizerFromLauncher() {
    surfaceManager?.showCustomizer()
  }

  func showDockMenu(bundleId: String, anchor: RectD, edge: String, pinned: Bool,
                    completion: @escaping (Result<String?, Error>) -> Void) {
    guard let main = NSScreen.screens.first else { return completion(.success(nil)) }
    let rect = Geometry.cocoaFrame(screenRelative: anchor.cgRect, screenCocoaFrame: main.frame)
    // Next run-loop turn: the menu runs its own tracking loop, which shouldn't
    // nest inside the platform-channel callback.
    DispatchQueue.main.async {
      let menu = DockMenu(bundleId: bundleId)
      let action = menu.present(anchor: rect, edge: edge, pinned: pinned)
      Log.apps.info("dock menu \(bundleId, privacy: .public) → \(action ?? "-", privacy: .public)")
      completion(.success(action))
    }
  }

  func windowCount(bundleId: String) throws -> Int64 { Int64(apps.windowCount(bundleId)) }

  func showAllWindows(bundleId: String) throws {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return }
    DockMenu.showAllWindows(of: app)
  }

  func windows(bundleId: String, thumbnailWidthPx: Int64, completion: @escaping (Result<[WindowSummary], Error>) -> Void) {
    WindowThumbnails.windows(bundleId: bundleId, width: Int(thumbnailWidthPx)) { completion(.success($0)) }
  }

  func focusWindow(bundleId: String, windowId: Int64) throws {
    WindowThumbnails.focus(bundleId: bundleId, windowId: windowId)
  }

  func hide(bundleId: String) throws { apps.hide(bundleId) }
  func quit(bundleId: String) throws { apps.quit(bundleId) }
}

extension ShellRuntime: SystemApi {
  func status() throws -> SystemStatus { SystemStatus(system.status) }

  func setDarkMode(dark: Bool) throws {
    // Through SafetyService so the change is journaled and reversible.
    var config = lastSystemConfig ?? SKSystemConfig(hideNativeDock: false)
    config.darkMode = dark
    safety.apply(config, dockHidingAllowed: flags.isEnabled(.dockHideNative))
    lastSystemConfig = config
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.system.refresh() }
  }
}

extension ShellRuntime: HotkeyApi {
  func setBindings(bindings: [Keybinding]) throws -> [String] {
    hotkeys.setBindings(bindings.map { (action: $0.action, trigger: $0.chord) })
  }

  func setSuspended(suspended: Bool) throws { hotkeys.setSuspended(suspended) }

  func conflicts(chord: String) throws -> [String] { ShortcutConflicts.conflicts(for: chord) }
}

extension ShellRuntime: SafetyApi {
  func applySystem(config: SystemConfig) throws {
    let reserve = zip2(config.dockReserveEdge, config.dockReserveThickness).map { DockReserve(edge: $0, thickness: $1) }
    let c = SKSystemConfig(hideNativeDock: config.hideNativeDock, darkMode: config.darkMode,
                           accentColor: config.accentColor.map(Int.init), wallpaperPath: config.wallpaperPath,
                           dockReserve: reserve)
    lastSystemConfig = c
    let dockRestarted = safety.apply(c, dockHidingAllowed: flags.isEnabled(.dockHideNative))
    // After a Dock restart the reserved strip (visible frame) changes; resend
    // the screens in case AppKit doesn't post a screen-parameters change.
    guard dockRestarted else { return }
    for delay in [1.5, 4.0] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.surfaceManager?.rebuild() }
    }
  }

  func restoreRuntime() throws { safety.restoreRuntime() }

  func restoreAll() throws {
    safety.restoreAll()
    lastSystemConfig = nil
  }

  func journal() throws -> [String] { safety.journalLines() }
  func hasSnapshot() throws -> Bool { safety.hasSnapshot }
}

extension ShellRuntime: DiagnosticsApi {
  func info() throws -> DiagnosticsInfo {
    DiagnosticsInfo(hotkeysRegistered: Int64(hotkeys.registeredCount), guardianRunning: Guardian.isRunning,
                    flags: flags.all)
  }

  func thumbnailPermissions() throws -> ThumbnailPermissions { WindowThumbnails.permissions() }

  func requestThumbnailPermissions() throws { WindowThumbnails.requestPermissions() }

  func openPrivacySettings(pane: String) throws { WindowThumbnails.openSettings(pane: pane) }

  func setFlag(name: String, enabled: Bool) throws {
    guard let flag = FeatureFlag(rawValue: name) else {
      throw PigeonError(code: "unknown-flag", message: name, details: nil)
    }
    flags.set(flag, enabled)
  }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
  guard let a, let b else { return nil }
  return (a, b)
}
