import AppKit

/// The dock's right-click menu, drawn the way the real Dock draws it: a
/// native NSMenu with the Dock's own items — Options ▸ (Keep in Dock / Remove
/// from Dock, Open at Login, Show in Finder), Show All Windows, Hide or Show,
/// Quit (Force Quit while ⌥ is held) or Open; the Finder gets New Finder
/// Window and no Quit.
///
/// Interface-only (ADR-0012): no list of the app's windows (their titles need
/// Screen Recording) and no app-provided items (the Dock gets those from apps
/// over a private channel).
final class DockMenu: NSObject {
  private let bundleId: String
  private var picked: String?

  init(bundleId: String) {
    self.bundleId = bundleId
  }

  /// Pops the menu up next to `anchor` (Cocoa screen coordinates), runs the
  /// native actions, and returns the one the shell handles: "open", "keep",
  /// "remove", or nil.
  func present(anchor: CGRect, edge: String, pinned: Bool) -> String? {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    let appURL = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    let isFinder = bundleId == "com.apple.finder"

    let menu = NSMenu()
    menu.autoenablesItems = false
    if isFinder {
      menu.addItem(item("New Finder Window", "finderWindow"))
      menu.addItem(.separator())
    }

    let options = NSMenu()
    options.autoenablesItems = false
    if pinned && running == nil {
      options.addItem(item("Remove from Dock", "remove"))
    } else {
      let keep = item("Keep in Dock", pinned ? "remove" : "keep")
      keep.state = pinned ? .on : .off
      options.addItem(keep)
    }
    if let appURL, !isFinder {
      let login = item("Open at Login", "login")
      login.state = LoginItems.shared.contains(appURL) ? .on : .off
      options.addItem(login)
    }
    if appURL != nil {
      options.addItem(.separator())
      options.addItem(item("Show in Finder", "finder"))
    }
    let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
    optionsItem.submenu = options
    menu.addItem(optionsItem)
    menu.addItem(.separator())

    if let running {
      menu.addItem(item("Show All Windows", "allWindows"))
      menu.addItem(item(running.isHidden ? "Show" : "Hide", running.isHidden ? "open" : "hide"))
      // The Dock offers no Quit for the Finder.
      if !isFinder {
        menu.addItem(item("Quit", "quit"))
        // Swapped in while ⌥ is held, as in the Dock.
        let force = item("Force Quit", "forceQuit")
        force.keyEquivalentModifierMask = [.option]
        force.isAlternate = true
        menu.addItem(force)
      }
    } else {
      menu.addItem(item("Open", "open"))
    }

    // Off the dock's edge, centred on the icon, like the Dock's menus.
    let size = menu.size
    let location: NSPoint
    switch edge {
    case "left": location = NSPoint(x: anchor.maxX + 8, y: anchor.midY + size.height / 2)
    case "right": location = NSPoint(x: anchor.minX - 8 - size.width, y: anchor.midY + size.height / 2)
    default: location = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 8 + size.height)
    }
    menu.popUp(positioning: nil, at: location, in: nil)

    switch picked {
    case "finder":
      if let appURL { NSWorkspace.shared.activateFileViewerSelecting([appURL]) }
    case "finderWindow":
      NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
    case "login":
      if let appURL { LoginItems.shared.set(appURL, enabled: !LoginItems.shared.contains(appURL)) }
    case "allWindows":
      if let running { Self.showAllWindows(of: running) }
    case "hide":
      running?.hide()
    case "quit":
      running?.terminate()
    case "forceQuit":
      running?.forceTerminate()
    default:
      LoginItems.shared.refreshIfPermitted()
      return picked
    }
    LoginItems.shared.refreshIfPermitted()
    return nil
  }

  /// "Show All Windows" (App Exposé): bring the app forward the Dock's way,
  /// then run Apple's own Mission Control app in its "front app's windows"
  /// mode (argument 2 — read from its code: 0 Mission Control, 1 Show
  /// Desktop, 2 App Exposé). The shell calls no private API itself and reads
  /// no window data; macOS draws the live previews.
  static func showAllWindows(of app: NSRunningApplication) {
    let expose = {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
      p.arguments = ["2"]
      do { try p.run() } catch { Log.apps.error("show all windows: \(error.localizedDescription, privacy: .public)") }
    }
    if app.isActive { return expose() }
    var token: NSObjectProtocol?
    token = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { note in
      guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
        == app.processIdentifier else { return }
      if let t = token { NSWorkspace.shared.notificationCenter.removeObserver(t) }
      token = nil
      // Let the activation settle so Exposé picks this app as the front one.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: expose)
    }
    if let url = app.bundleURL { AppService.openViaLaunchServices(url, reason: "show all windows") }
    // Don't wait forever if activation never comes.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      if let t = token { NSWorkspace.shared.notificationCenter.removeObserver(t) }
      token = nil
    }
  }

  private func item(_ title: String, _ action: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = action
    return item
  }

  @objc private func pick(_ sender: NSMenuItem) {
    picked = sender.representedObject as? String
  }
}
