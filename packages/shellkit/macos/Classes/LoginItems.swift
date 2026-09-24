import AppKit

/// "Options ▸ Open at Login" for other apps, the way the Dock offers it:
/// through System Events (the same Automation permission dark mode uses).
/// Only ever changed by an explicit menu choice; nothing is added on its own.
///
/// AppleScript can block while macOS asks for permission, so it never runs
/// on the main thread (a stalled main thread stops the heartbeat).
/// The menu shows the last known state; the list is refreshed in the
/// background at start (only if permission was already given, so no prompt
/// appears unasked), after every change, and after every menu.
final class LoginItems {
  static let shared = LoginItems()

  private let queue = DispatchQueue(label: "mgc.loginitems", qos: .userInitiated)
  private(set) var paths: Set<String> = []
  private(set) var loaded = false

  func contains(_ url: URL) -> Bool { paths.contains(url.standardizedFileURL.path) }

  /// Refresh without ever prompting: skipped until the user has allowed
  /// Automation of System Events (e.g. by a theme switching dark mode).
  func refreshIfPermitted() {
    guard Self.systemEventsPermission() == noErr else { return }
    refresh()
  }

  func refresh() {
    queue.async { [weak self] in
      let result = Self.run("tell application \"System Events\" to get the path of every login item")
      var found: Set<String> = []
      if let list = result, list.numberOfItems > 0 {
        for i in 1...list.numberOfItems {
          if let p = list.atIndex(i)?.stringValue { found.insert(URL(fileURLWithPath: p).standardizedFileURL.path) }
        }
      } else if let single = result?.stringValue {
        found.insert(URL(fileURLWithPath: single).standardizedFileURL.path)
      }
      DispatchQueue.main.async {
        self?.paths = found
        self?.loaded = result != nil
      }
    }
  }

  func set(_ url: URL, enabled: Bool) {
    let path = Self.quote(url.standardizedFileURL.path)
    let script = enabled
      ? "tell application \"System Events\" to if not (exists (first login item whose path is \(path))) then make login item at end with properties {path:\(path), hidden:false}"
      : "tell application \"System Events\" to delete (every login item whose path is \(path))"
    queue.async { [weak self] in
      _ = Self.run(script)
      Log.apps.info("open at login \(enabled ? "on" : "off", privacy: .public): \(url.lastPathComponent, privacy: .public)")
      self?.refresh()
    }
  }

  private static func run(_ source: String) -> NSAppleEventDescriptor? {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let error { Log.apps.error("login items: \(error, privacy: .public)") }
    return error == nil ? result : nil
  }

  private static func quote(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  /// Automation permission for System Events, asked without prompting.
  static func systemEventsPermission() -> OSStatus {
    var target = AEAddressDesc()
    let bundle = "com.apple.systemevents"
    let created = bundle.withCString { AECreateDesc(typeApplicationBundleID, $0, bundle.utf8.count, &target) }
    guard created == noErr else { return OSStatus(created) }
    defer { AEDisposeDesc(&target) }
    return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
  }
}
