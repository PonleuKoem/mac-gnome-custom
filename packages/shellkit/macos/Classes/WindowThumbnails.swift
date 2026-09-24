import AppKit
import FlutterMacOS
import ApplicationServices
import ScreenCaptureKit

/// OPT-IN window thumbnails for the dock (flag `windowThumbnails`, off by
/// default). The one exception to ADR-0012's interface-only scope, and only
/// while the user has it on:
/// - Screen Recording: list an app's windows with titles and take small
///   thumbnails of them, on demand while its dock icon is hovered. Kept in
///   memory for that label only; never stored or sent anywhere.
/// - Accessibility: bring the one window the user clicked to the front. With
///   Accessibility alone (Screen Recording not granted yet) windows are listed
///   by title, without pictures.
/// Every entry point re-checks the flag and the permissions itself.
enum WindowThumbnails {
  static var enabled: Bool { FeatureFlags.shared.isEnabled(.windowThumbnails) }

  static func permissions() -> ThumbnailPermissions {
    ThumbnailPermissions(screenRecording: CGPreflightScreenCaptureAccess(), accessibility: AXIsProcessTrusted())
  }

  /// Shows macOS's own prompts. Only called when the user turns the feature on.
  static func requestPermissions() {
    if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
    if !AXIsProcessTrusted() {
      let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
      _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
  }

  static func openSettings(pane: String) {
    let anchor = pane == "Accessibility" ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
      NSWorkspace.shared.open(url)
    }
  }

  /// The app's real windows (titled, or on screen — apps keep untitled hidden
  /// helper windows), each with a thumbnail `width` pixels wide.
  static func windows(bundleId: String, width: Int, completion: @escaping ([WindowSummary]) -> Void) {
    guard enabled else { return completion([]) }
    guard CGPreflightScreenCaptureAccess() else { return completion(titledWindows(bundleId: bundleId)) }
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, error in
      guard let content else {
        Log.apps.error("thumbnails: \(error?.localizedDescription ?? "no content", privacy: .public)")
        return DispatchQueue.main.async { completion([]) }
      }
      let minimized = axMinimizedFrames(bundleId: bundleId)
      let wins = content.windows.filter { w in
        w.owningApplication?.bundleIdentifier == bundleId && w.windowLayer == 0
          && w.frame.width >= 100 && w.frame.height >= 60
          && (w.isOnScreen || !(w.title ?? "").isEmpty)
      }
      .sorted { ($0.isOnScreen ? 0 : 1, $0.windowID) < ($1.isOnScreen ? 0 : 1, $1.windowID) }
      .prefix(8)
      Task {
        var out: [WindowSummary] = []
        for w in wins {
          let config = SCStreamConfiguration()
          let scale = Double(width) / max(1, w.frame.width)
          config.width = width
          config.height = max(1, Int(w.frame.height * scale))
          config.showsCursor = false
          config.ignoreShadowsSingleWindow = true
          var png: Data?
          if let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: config) {
            png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
          }
          out.append(WindowSummary(
            id: Int64(w.windowID), title: w.title ?? "", width: w.frame.width, height: w.frame.height,
            onScreen: w.isOnScreen, minimized: minimized.contains { $0.equalTo(w.frame) },
            thumbnail: png.map { FlutterStandardTypedData(bytes: $0) }))
        }
        let result = out
        DispatchQueue.main.async { completion(result) }
      }
    }
  }

  /// Brings exactly this window forward: matched to its Accessibility element
  /// by title and frame (no private window-id lookup), un-minimized and
  /// raised; the app is activated the Dock's way, then the window is raised
  /// again so the app's own activation can't put another window on top.
  /// Without Accessibility only the app is brought forward.
  static func focus(bundleId: String, windowId: Int64) {
    guard enabled, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
      Log.apps.info("focus window: previews off or \(bundleId, privacy: .public) not running")
      return
    }
    guard AXIsProcessTrusted() else {
      Log.apps.error("focus window \(windowId): Accessibility not allowed; only activating \(bundleId, privacy: .public)")
      if let url = app.bundleURL { AppService.openViaLaunchServices(url, reason: "activate \(bundleId) (no Accessibility)") }
      return
    }
    if windowId < 0 {
      // From [titledWindows]: no window-server id, match the listed title/frame.
      let listed = titledCache[bundleId] ?? []
      let i = Int(-windowId) - 1
      let element = listed.indices.contains(i)
        ? match(AXUIElementCreateApplication(app.processIdentifier), title: listed[i].title, frame: listed[i].frame)
        : nil
      bringForward(app, element, windowId: windowId)
      return
    }
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
      let target = content?.windows.first { Int64($0.windowID) == windowId }
      DispatchQueue.main.async {
        let element = target.flatMap {
          match(AXUIElementCreateApplication(app.processIdentifier), title: $0.title ?? "", frame: $0.frame)
        }
        bringForward(app, element, windowId: windowId)
      }
    }
  }

  private static func bringForward(_ app: NSRunningApplication, _ element: AXUIElement?, windowId: Int64) {
    guard let url = app.bundleURL else { return }
    guard let element else {
      Log.apps.error("focus window \(windowId): no matching window; activating the app only")
      AppService.openViaLaunchServices(url, reason: "activate (window \(windowId) not found)")
      return
    }
    raise(element, in: app)
    AppService.openViaLaunchServices(url, reason: "focus window \(windowId)") { _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { raise(element, in: app) }
    }
  }

  /// Un-minimizes, makes main (and the app's focused window) and raises one
  /// window.
  private static func raise(_ element: AXUIElement, in app: NSRunningApplication) {
    var minimized: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimized)
    if (minimized as? Bool) == true {
      AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }
    AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                 kAXFocusedWindowAttribute as CFString, element)
    let result = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    if result != .success { Log.apps.error("raise failed: AXError \(result.rawValue)") }
  }

  /// What [titledWindows] last listed per app, so a click can find it again.
  private static var titledCache: [String: [(title: String, frame: CGRect)]] = [:]

  /// Accessibility only (no Screen Recording): the app's standard windows on
  /// this desktop, front to back, by title — no pictures. Ids are -1, -2, …
  /// (positions in this list; see [focus]).
  static func titledWindows(bundleId: String) -> [WindowSummary] {
    guard enabled, AXIsProcessTrusted(),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return [] }
    var listed: [(title: String, frame: CGRect)] = []
    var out: [WindowSummary] = []
    for e in axWindows(AXUIElementCreateApplication(app.processIdentifier)) {
      var subrole: CFTypeRef?
      AXUIElementCopyAttributeValue(e, kAXSubroleAttribute as CFString, &subrole)
      guard (subrole as? String) == (kAXStandardWindowSubrole as String),
            let f = frame(of: e), f.width >= 100, f.height >= 60 else { continue }
      var m: CFTypeRef?
      AXUIElementCopyAttributeValue(e, kAXMinimizedAttribute as CFString, &m)
      let minimized = (m as? Bool) == true
      listed.append((title(of: e), f))
      out.append(WindowSummary(id: -Int64(listed.count), title: listed.last!.title, width: f.width, height: f.height,
                               onScreen: !minimized, minimized: minimized, thumbnail: nil))
      if out.count == 8 { break }
    }
    titledCache[bundleId] = listed
    return out
  }

  private static func axWindows(_ axApp: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
  }

  private static func frame(of element: AXUIElement) -> CGRect? {
    var pos: CFTypeRef?, size: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
  }

  private static func title(of element: AXUIElement) -> String {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
    return value as? String ?? ""
  }

  /// Best match by frame (same coordinate space as the window server), then title.
  private static func match(_ axApp: AXUIElement, title: String, frame target: CGRect) -> AXUIElement? {
    let candidates = axWindows(axApp).compactMap { e in frame(of: e).map { (e, $0) } }
    func distance(_ r: CGRect) -> CGFloat {
      abs(r.minX - target.minX) + abs(r.minY - target.minY) + abs(r.width - target.width) + abs(r.height - target.height)
    }
    let ranked = candidates.sorted { a, b in
      let ta = Self.title(of: a.0) == title ? 0 : 1, tb = Self.title(of: b.0) == title ? 0 : 1
      return (distance(a.1), ta) < (distance(b.1), tb)
    }
    guard let best = ranked.first, distance(best.1) < 8 || Self.title(of: best.0) == title else { return nil }
    return best.0
  }

  /// Frames of the app's minimized windows (Accessibility), to label them.
  private static func axMinimizedFrames(bundleId: String) -> [CGRect] {
    guard AXIsProcessTrusted(),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return [] }
    return axWindows(AXUIElementCreateApplication(app.processIdentifier)).compactMap { e in
      var m: CFTypeRef?
      AXUIElementCopyAttributeValue(e, kAXMinimizedAttribute as CFString, &m)
      return (m as? Bool) == true ? frame(of: e) : nil
    }
  }
}
