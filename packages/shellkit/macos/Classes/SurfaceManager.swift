import AppKit
import FlutterMacOS

/// A borderless, non-activating panel: clicking it never takes activation away
/// from the app the user is working in (so the top bar's app menu targets the
/// right app). Keyboard is opt-in per surface (overview search, popovers).
final class ShellPanel: NSPanel {
  var acceptsKeyboard = false
  var onResignKey: (() -> Void)?

  override var canBecomeKey: Bool { acceptsKeyboard }
  override var canBecomeMain: Bool { false }

  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }

  /// The Flutter controller rendering this panel.
  weak var flutterController: FlutterViewController?

  /// Window-local (top-left) rect that takes clicks; elsewhere clicks go
  /// through to the windows beneath. nil = the whole window is interactive.
  /// See SurfaceManager.updatePassThrough.
  var hitRect: CGRect?

  /// Pointer events go straight to the Flutter controller. In these panels
  /// the Flutter view is embedded in our own container (for the blur view),
  /// and events AppKit hands to the view never reached the controller —
  /// key or not (verified live: the same click works via the controller and
  /// is lost via the view). That broke dock clicks first, then every click,
  /// scroll and gesture in the Activities launcher. Hover/enter/exit already
  /// reach the controller through its own tracking area. Keyboard events are
  /// left to AppKit (first responder / text input).
  override func sendEvent(_ event: NSEvent) {
    guard let fc = flutterController else { return super.sendEvent(event) }
    switch event.type {
    case .leftMouseDown:
      // A click in a keyboard surface (launcher search) should also focus it.
      if acceptsKeyboard, !isKeyWindow { makeKey() }
      fc.mouseDown(with: event)
    case .leftMouseUp: fc.mouseUp(with: event)
    case .leftMouseDragged: fc.mouseDragged(with: event)
    case .rightMouseDown: fc.rightMouseDown(with: event)
    case .rightMouseUp: fc.rightMouseUp(with: event)
    case .rightMouseDragged: fc.rightMouseDragged(with: event)
    case .otherMouseDown: fc.otherMouseDown(with: event)
    case .otherMouseUp: fc.otherMouseUp(with: event)
    case .otherMouseDragged: fc.otherMouseDragged(with: event)
    case .scrollWheel: fc.scrollWheel(with: event)
    case .magnify: fc.magnify(with: event)
    case .rotate: fc.rotate(with: event)
    default: super.sendEvent(event)
    }
  }
}

/// One Flutter view hosted in a native window.
final class Surface {
  let spec: SurfaceSpec
  let controller: FlutterViewController
  let window: NSWindow
  /// Holds one blur view per frosted shape, behind the Flutter view.
  let blurContainer: NSView?
  var blurViews: [NSVisualEffectView] = []
  var visible = false

  init(spec: SurfaceSpec, controller: FlutterViewController, window: NSWindow, blurContainer: NSView?) {
    self.spec = spec
    self.controller = controller
    self.window = window
    self.blurContainer = blurContainer
  }
}

/// Creates and positions every shell surface (DESIGN.md §4.1). All surfaces
/// share one FlutterEngine with multi-view enabled (ADR-0003).
final class SurfaceManager {
  var onSurfacesChanged: (([SurfaceSpec]) -> Void)?
  var onDismissed: ((String) -> Void)?
  var onCustomizerVisibility: ((Bool) -> Void)?

  private let engine: FlutterEngine
  private(set) var surfaces: [String: Surface] = [:]
  private var clickMonitor: Any?

  init(engine: FlutterEngine) {
    self.engine = engine
  }

  var specs: [SurfaceSpec] { surfaces.values.map(\.spec) }

  // MARK: Levels

  static let topBarLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
  static let dockLevel = NSWindow.Level.statusBar
  static let overviewLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 2)
  static let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)

  // MARK: Building

  /// Builds per-screen and singleton surfaces; call again on screen changes.
  func rebuild() {
    let screens = NSScreen.screens
    guard let main = screens.first else { return }
    var wanted: [(id: String, kind: String, screen: NSScreen)] = []
    for s in screens { wanted.append(("topbar:\(s.displayID)", "topbar", s)) }
    wanted.append(("dock", "dock", main))
    wanted.append(("overview", "overview", main))
    wanted.append(("popover", "popover", main))

    let wantedIds = Set(wanted.map(\.id))
    for (id, surface) in surfaces where id != "customizer" && !wantedIds.contains(id) {
      surface.window.orderOut(nil)
      surface.window.contentViewController = nil
      surfaces.removeValue(forKey: id)
    }
    for w in wanted where surfaces[w.id] == nil {
      surfaces[w.id] = makePanelSurface(id: w.id, kind: w.kind, screen: w.screen)
    }
    // Keep existing top bars pinned to their (possibly resized) screens.
    for s in screens {
      if let bar = surfaces["topbar:\(s.displayID)"], !bar.visible {
        bar.window.setFrame(defaultFrame(kind: "topbar", screen: s), display: false)
      }
    }
    installClickMonitor()
    onSurfacesChanged?(specs)
  }

  private func makePanelSurface(id: String, kind: String, screen: NSScreen) -> Surface {
    let panel = ShellPanel(contentRect: defaultFrame(kind: kind, screen: screen),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = {
      switch kind {
      case "topbar": return Self.topBarLevel
      case "dock": return Self.dockLevel
      case "overview": return Self.overviewLevel
      default: return Self.overlayLevel
      }
    }()
    // No `.fullScreenAuxiliary`: shell panels stay out of other apps'
    // full-screen spaces by themselves, so the shell never needs to inspect
    // other apps' windows to know when to hide (ADR-0012).
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    // Must be set EXPLICITLY. Left at its default, a transparent window gets
    // per-pixel click-through — and the window server can't see pixels drawn
    // by Flutter's Metal layer, so every click fell through to the window
    // behind (dock icons did nothing). Panels are sized to their content, so
    // catching clicks on the whole rect is correct.
    panel.ignoresMouseEvents = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isMovable = false
    panel.animationBehavior = .none
    panel.title = id  // not shown (borderless); identifies the panel in logs

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    controller.backgroundColor = .clear
    controller.mouseTrackingMode = .always

    // Real frosted glass: blur views sit behind the transparent Flutter view,
    // one per shape Dart reports (setBlurRegions).
    let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
    container.wantsLayer = true
    let flutterView = controller.view
    flutterView.frame = container.bounds
    flutterView.autoresizingMask = [.width, .height]
    container.addSubview(flutterView)
    panel.contentView = container
    panel.flutterController = controller
    // Keep the controller alive; the panel owns its view hierarchy only.
    objc_setAssociatedObject(panel, &Self.controllerKey, controller, .OBJC_ASSOCIATION_RETAIN)

    let spec = SurfaceSpec(viewId: Int64(controller.viewIdentifier), surfaceId: id, kind: kind,
                           screenId: Int64(screen.displayID))
    let surface = Surface(spec: spec, controller: controller, window: panel, blurContainer: container)
    panel.onResignKey = { [weak self, weak surface, weak panel] in
      guard let self, let surface, let panel, surface.visible, panel.acceptsKeyboard else { return }
      self.onDismissed?(surface.spec.surfaceId)
    }
    Log.surfaces.info("surface \(id, privacy: .public) → view \(controller.viewIdentifier)")
    return surface
  }

  private static var controllerKey = 0

  /// The Customizer lives in the normal window from MainMenu.xib.
  func makeCustomizerController() -> FlutterViewController {
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    controller.mouseTrackingMode = .inKeyWindow
    return controller
  }

  func registerCustomizer(window: NSWindow, controller: FlutterViewController) {
    let spec = SurfaceSpec(viewId: Int64(controller.viewIdentifier), surfaceId: "customizer", kind: "customizer",
                           screenId: Int64(NSScreen.main?.displayID ?? 0))
    surfaces["customizer"] = Surface(spec: spec, controller: controller, window: window, blurContainer: nil)
  }

  private func defaultFrame(kind: String, screen: NSScreen) -> NSRect {
    let f = screen.frame
    switch kind {
    case "topbar":
      let h = screen.menuBarHeight
      return NSRect(x: f.minX, y: f.maxY - h, width: f.width, height: h)
    case "overview":
      let h = screen.menuBarHeight
      return NSRect(x: f.minX, y: f.minY, width: f.width, height: f.height - h)
    case "dock":
      return NSRect(x: f.midX - 300, y: f.minY + 8, width: 600, height: 80)
    default:
      return NSRect(x: f.maxX - 380, y: f.maxY - 460, width: 360, height: 420)
    }
  }

  // MARK: Showing

  func show(_ id: String, rect: CGRect, takeKeyboard: Bool) {
    guard let surface = surfaces[id] else { return }
    if id == "customizer" { showCustomizer(); return }
    let screen = NSScreen.screens.first { Int64($0.displayID) == surface.spec.screenId } ?? NSScreen.screens.first
    guard let screen else { return }
    let frame = Geometry.cocoaFrame(screenRelative: rect, screenCocoaFrame: screen.frame)
    if surface.window.frame != frame { surface.window.setFrame(frame, display: true) }
    surface.visible = true
    if let panel = surface.window as? ShellPanel {
      panel.acceptsKeyboard = takeKeyboard
      if takeKeyboard {
        panel.makeKeyAndOrderFront(nil)
      } else {
        panel.orderFrontRegardless()
      }
      updatePassThrough(panel, initial: true)
    }
  }

  func hide(_ id: String) {
    guard let surface = surfaces[id] else { return }
    surface.visible = false
    if id == "customizer" {
      surface.window.close()
      return
    }
    (surface.window as? ShellPanel)?.acceptsKeyboard = false
    surface.window.orderOut(nil)
  }

  func showCustomizer() {
    guard let surface = surfaces["customizer"] else { return }
    surface.visible = true
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
    surface.window.makeKeyAndOrderFront(nil)
    onCustomizerVisibility?(true)
  }

  func customizerClosed() {
    surfaces["customizer"]?.visible = false
    NSApp.setActivationPolicy(.accessory)
    onCustomizerVisibility?(false)
  }

  // MARK: Blur

  /// One NSVisualEffectView per shape, framed to it and clipped by a small
  /// 9-slice rounded mask. Moving/resizing a shape (the dock growing while it
  /// magnifies) only changes a frame — nothing is re-rasterised, unlike
  /// redrawing a full-window mask image on every update.
  func setBlurRegions(_ id: String, regions: [RRectD], dark: Bool) {
    guard let surface = surfaces[id], let container = surface.blurContainer else { return }
    let flutterView = surface.controller.view
    while surface.blurViews.count < regions.count {
      let effect = NSVisualEffectView()
      effect.blendingMode = .behindWindow
      effect.state = .active
      effect.material = .hudWindow
      // Top-left anchored, matching Dart's coordinates, until the next report.
      effect.autoresizingMask = [.minYMargin]
      container.addSubview(effect, positioned: .below, relativeTo: flutterView)
      surface.blurViews.append(effect)
    }
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let height = container.bounds.height
    for (i, effect) in surface.blurViews.enumerated() {
      guard i < regions.count else {
        effect.isHidden = true
        continue
      }
      let r = regions[i].rect.cgRect
      let frame = NSRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height)
      if effect.frame != frame { effect.frame = frame }
      let radius = min(CGFloat(regions[i].radius), r.width / 2, r.height / 2)
      let key = Int(radius.rounded())
      if effect.maskImage == nil || effect.identifier?.rawValue != "r\(key)" {
        effect.maskImage = Self.roundedMask(radius: CGFloat(key))
        effect.identifier = NSUserInterfaceItemIdentifier("r\(key)")
      }
      effect.appearance = appearance
      effect.isHidden = false
    }
  }

  private static var maskCache: [Int: NSImage] = [:]

  /// A stretchable rounded-rect mask: corners stay round at any size.
  static func roundedMask(radius: CGFloat) -> NSImage {
    let key = Int(radius)
    if let cached = maskCache[key] { return cached }
    let r = max(0, radius)
    let side = r * 2 + 1
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
    image.resizingMode = .stretch
    maskCache[key] = image
    return image
  }

  // MARK: Click-through outside the hit region

  private var moveMonitors: [Any] = []

  func setHitRegion(_ id: String, rect: CGRect?) {
    guard let panel = surfaces[id]?.window as? ShellPanel else { return }
    panel.hitRect = rect
    if rect == nil {
      panel.ignoresMouseEvents = false
    } else {
      installMoveMonitors()
      updatePassThrough(panel, initial: true)
    }
  }

  /// A panel with a hit rect takes clicks only while the pointer is inside
  /// that rect; everywhere else clicks go through to the windows beneath.
  /// The shell keeps the rect to what's actually there (the dock, its
  /// magnified icons while the pointer is on them, the hover card while it
  /// shows), so the dock window's empty room never swallows a click. Only
  /// the pointer position is read — the same thing the hot corner uses.
  private func updatePassThrough(_ panel: ShellPanel, initial: Bool = false) {
    guard let hit = panel.hitRect, panel.isVisible else { return }
    // Never switch in the middle of a click or drag that started here.
    if !initial, !panel.ignoresMouseEvents, NSEvent.pressedMouseButtons != 0 { return }
    let p = NSEvent.mouseLocation
    let f = panel.frame
    let screenHit = NSRect(x: f.minX + hit.minX, y: f.maxY - hit.maxY, width: hit.width, height: hit.height)
    let inside = screenHit.contains(p)
    guard panel.ignoresMouseEvents == inside else { return }
    panel.ignoresMouseEvents = !inside
    if !inside {
      // The panel gets no more pointer events now; tell Flutter where the
      // pointer went so hover state (magnification, hover card) ends.
      let local = NSPoint(x: p.x - f.minX, y: p.y - f.minY)
      if let e = NSEvent.mouseEvent(with: .mouseMoved, location: local, modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                    context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
        panel.flutterController?.mouseMoved(with: e)
      }
    }
  }

  private func installMoveMonitors() {
    guard moveMonitors.isEmpty else { return }
    let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
    let update: () -> Void = { [weak self] in
      guard let self else { return }
      for s in self.surfaces.values where s.visible {
        if let panel = s.window as? ShellPanel, panel.hitRect != nil { self.updatePassThrough(panel) }
      }
    }
    if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in update() }) { moveMonitors.append(g) }
    if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { e in update(); return e }) {
      moveMonitors.append(l)
    }
  }

  // MARK: Dismissal

  /// Clicking anywhere outside a visible keyboard surface (overview, popover)
  /// dismisses it, like a menu.
  private func installClickMonitor() {
    guard clickMonitor == nil else { return }
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      guard let self else { return }
      let p = NSEvent.mouseLocation
      for s in self.surfaces.values where s.visible && s.spec.kind != "customizer" && s.spec.kind != "topbar" && s.spec.kind != "dock" {
        if !s.window.frame.contains(p) { self.onDismissed?(s.spec.surfaceId) }
      }
    }
  }
}
