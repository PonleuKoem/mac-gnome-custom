import AppKit

/// Side effects outside preferences. Abstracted so SafetyService is testable.
public protocol SystemActions: AnyObject {
  func restartDock()
  func darkMode() -> Bool
  func setDarkMode(_ dark: Bool)
  /// Current wallpaper per display (key = display ID as string).
  func wallpapers() -> [String: String]
  func setWallpaper(_ url: URL, display: String?)
  func notifyAppearanceChanged()
}

public final class LiveSystemActions: SystemActions {
  /// When true, AppleScript runs off the calling thread. It blocks until System
  /// Events answers — including while the first-use Automation prompt is on
  /// screen — which on the main thread would stop the heartbeat and make the
  /// guardian kill a healthy shell. CLI/guardian use `false`
  /// because they exit right after.
  private let async: Bool
  private static let scriptQueue = DispatchQueue(label: "mgc.applescript", qos: .userInitiated)

  public init(async: Bool = true) {
    self.async = async
  }

  public func restartDock() {
    // launchd restarts the Dock immediately with the new preferences. We never
    // leave it dead: it also runs Mission Control and Spaces (ADR-0005).
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    p.arguments = ["Dock"]
    try? p.run()
  }

  public func darkMode() -> Bool {
    UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String == "Dark"
  }

  public func setDarkMode(_ dark: Bool) {
    // Needs the Automation permission for System Events; the first call prompts.
    let src = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
    let work = {
      var error: NSDictionary?
      NSAppleScript(source: src)?.executeAndReturnError(&error)
      if let error { Log.system.error("setDarkMode failed: \(error, privacy: .public)") }
    }
    if async { Self.scriptQueue.async(execute: work) } else { work() }
  }

  public func wallpapers() -> [String: String] {
    var out: [String: String] = [:]
    for screen in NSScreen.screens {
      if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
        out[String(screen.displayID)] = url.absoluteString
      }
    }
    return out
  }

  public func setWallpaper(_ url: URL, display: String?) {
    for screen in NSScreen.screens where display == nil || String(screen.displayID) == display {
      do {
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
      } catch {
        Log.system.error("setWallpaper failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  public func notifyAppearanceChanged() {
    let center = DistributedNotificationCenter.default()
    center.postNotificationName(NSNotification.Name("AppleColorPreferencesChangedNotification"), object: nil,
                                userInfo: nil, deliverImmediately: true)
    center.postNotificationName(NSNotification.Name("AppleAquaColorVariantChanged"), object: nil,
                                userInfo: nil, deliverImmediately: true)
  }
}
