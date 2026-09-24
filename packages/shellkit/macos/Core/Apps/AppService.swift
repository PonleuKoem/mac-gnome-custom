import AppKit

public struct SKApp: Equatable {
  public var bundleId: String
  public var name: String
  public var path: String
  public var pid: pid_t
  public var isActive: Bool
  public var isHidden: Bool
}

public struct SKInstalledApp: Equatable {
  public var bundleId: String
  public var name: String
  public var path: String
}

/// Running apps, the installed-app index, icons, and launching (DESIGN.md §4.4).
/// Main thread unless noted.
public final class AppService {
  public var onChange: (([SKApp]) -> Void)?
  private var observers: [NSObjectProtocol] = []
  private var installedCache: ([SKInstalledApp], Date)?
  private let iconCache = LRUCache<String, Data>(capacity: 400)
  private let ioQueue = DispatchQueue(label: "mgc.apps.io", qos: .userInitiated)

  public init() {}

  public func start() {
    let nc = NSWorkspace.shared.notificationCenter
    let names: [Notification.Name] = [
      NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
      NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
      NSWorkspace.didUnhideApplicationNotification,
    ]
    for name in names {
      observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        guard let self else { return }
        self.onChange?(self.running())
      })
    }
  }

  public func running() -> [SKApp] {
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    return NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
      .map {
        SKApp(bundleId: $0.bundleIdentifier ?? "", name: $0.localizedName ?? "", path: $0.bundleURL?.path ?? "",
              pid: $0.processIdentifier, isActive: $0.processIdentifier == front, isHidden: $0.isHidden)
      }
  }

  // MARK: Installed apps

  static let searchRoots = [
    "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
    NSHomeDirectory() + "/Applications", "/System/Library/CoreServices/Applications",
  ]

  /// Scans the standard app folders (two levels deep, so vendor folders like
  /// /Applications/Adobe X/ are included). Cached for 60 s. Completion on main.
  public func installed(completion: @escaping ([SKInstalledApp]) -> Void) {
    if let (apps, at) = installedCache, Date().timeIntervalSince(at) < 60 {
      completion(apps)
      return
    }
    ioQueue.async { [weak self] in
      let apps = Self.scan(roots: Self.searchRoots, keep: Set([Bundle.main.bundleIdentifier].compactMap { $0 }))
      DispatchQueue.main.async {
        self?.installedCache = (apps, Date())
        completion(apps)
      }
    }
  }

  /// `keep`: bundle ids listed even though they are background-only — the
  /// shell itself is an LSUIElement app, and opening it from the launcher
  /// shows the Customizer.
  static func scan(roots: [String], keep: Set<String> = []) -> [SKInstalledApp] {
    let fm = FileManager.default
    var seen = Set<String>()
    var out: [SKInstalledApp] = []
    func add(_ url: URL) {
      guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !seen.contains(id) else { return }
      // Skip background-only helpers.
      if !keep.contains(id), bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true ||
         bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool == true { return }
      seen.insert(id)
      let name = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
      out.append(SKInstalledApp(bundleId: id, name: name, path: url.path))
    }
    for root in roots {
      guard let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil) else { continue }
      for item in items {
        if item.pathExtension == "app" {
          add(item)
        } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let sub = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
          sub.filter { $0.pathExtension == "app" }.forEach(add)
        }
      }
    }
    if let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") { add(finder) }
    return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  // MARK: Icons

  /// PNG icon for a bundle id or an app path. Completion on main.
  public func icon(for bundleIdOrPath: String, size: Int, completion: @escaping (Data?) -> Void) {
    let key = "\(bundleIdOrPath)@\(size)"
    if let data = iconCache.get(key) { completion(data); return }
    guard let path = resolvePath(bundleIdOrPath) else { completion(nil); return }
    ioQueue.async { [weak self] in
      let image = NSWorkspace.shared.icon(forFile: path)
      let data = Self.png(image, size: size)
      if let data { self?.iconCache.set(key, data) }
      DispatchQueue.main.async { completion(data) }
    }
  }

  static func png(_ image: NSImage, size: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
  }

  private func resolvePath(_ bundleIdOrPath: String) -> String? {
    if bundleIdOrPath.hasPrefix("/") { return bundleIdOrPath }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdOrPath)?.path
  }

  // MARK: Control

  public func launch(_ bundleIdOrPath: String) {
    guard let path = resolvePath(bundleIdOrPath) else {
      Log.apps.error("launch: no app for \(bundleIdOrPath, privacy: .public)")
      return
    }
    Self.openViaLaunchServices(URL(fileURLWithPath: path), reason: "launch \(bundleIdOrPath)")
  }

  /// Brings a running app forward (or launches it).
  ///
  /// `NSRunningApplication.activate()` is only a *request* since macOS 14
  /// (cooperative activation) and is normally ignored when the caller isn't
  /// the active app — which the shell, an accessory app, never is. Opening
  /// the app through LaunchServices is what the real Dock and launchers do:
  /// it activates the app, unhides it, and sends a "reopen" so an app with
  /// no windows opens one.
  public func activate(_ bundleId: String) {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first,
          let url = app.bundleURL else {
      launch(bundleId)
      return
    }
    if app.isHidden { app.unhide() }
    Self.openViaLaunchServices(url, reason: "activate \(bundleId)")
  }

  /// Activating (or launching) an app the way the Dock does. Main thread.
  public static func openViaLaunchServices(_ url: URL, reason: String,
                                           completion: ((NSRunningApplication?) -> Void)? = nil) {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    config.addsToRecentItems = false
    NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
      if let error {
        Log.apps.error("\(reason, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
      } else {
        Log.apps.info("\(reason, privacy: .public) → pid \(app?.processIdentifier ?? -1)")
      }
      completion?(app)
    }
  }

  /// Windows of a running app shown on the current desktop, for the dock's
  /// hover label. Uses only window-server metadata (owner, layer, size) —
  /// never titles or contents, which would need Screen Recording (ADR-0012).
  /// Only windows actually on screen count: apps keep hidden helper windows
  /// (Chrome: address-bar dropdown, find bar, pop-ups) that are never shown.
  public func windowCount(_ bundleId: String) -> Int {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.processIdentifier,
          let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return 0 }
    return list.filter { w in
      guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
            (w[kCGWindowLayer as String] as? Int) == 0,
            (w[kCGWindowAlpha as String] as? Double ?? 0) > 0,
            let b = w[kCGWindowBounds as String] as? [String: Any],
            let width = b["Width"] as? Double, let height = b["Height"] as? Double else { return false }
      return width >= 100 && height >= 60
    }.count
  }

  public func hide(_ bundleId: String) {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.hide()
  }

  public func quit(_ bundleId: String) {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.terminate()
  }
}
