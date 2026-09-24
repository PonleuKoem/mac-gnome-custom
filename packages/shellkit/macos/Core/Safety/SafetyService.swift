import Foundation

/// Pristine macOS state captured before the app changes anything. Write-once.
public struct Snapshot: Codable, Equatable {
  public struct Pref: Codable, Equatable {
    public let domain: String
    public let key: String
    public let value: PrefValue?
  }

  public var createdAt: Date
  public var prefs: [Pref]
  public var darkMode: Bool
  public var wallpapers: [String: String]

  public func value(for key: PrefKey) -> PrefValue? {
    prefs.first { $0.domain == key.domain && $0.key == key.key }?.value
  }

  /// Whether the key was recorded at all (snapshots from older versions
  /// predate some tracked keys; those must never be "restored" to absent).
  public func has(_ key: PrefKey) -> Bool {
    prefs.contains { $0.domain == key.domain && $0.key == key.key }
  }
}

/// Keep the native Dock visible as an invisible spacer: macOS then keeps
/// windows (maximize, tiling, zoom) clear of that screen edge, and the shell's
/// own dock is drawn over it. There is no public API for a third-party window
/// to reserve screen space, and moving other apps' windows would need
/// Accessibility (ADR-0012), so this is the interface-only way.
public struct DockReserve: Equatable {
  public var edge: String  // bottom | left | right
  public var thickness: Double  // points the shell's dock needs

  public init(edge: String, thickness: Double) {
    self.edge = edge
    self.thickness = thickness
  }

  /// Native Dock icon size for a strip about `thickness` points deep
  /// (measured on macOS 26: strip = tilesize + 20). The shell then reads the
  /// real strip (NSScreen.visibleFrame) and fits itself to it, so this only
  /// has to be close.
  ///
  /// Rounded up to 4 pt steps: small icon-size tweaks (a Customizer slider)
  /// then don't restart the Dock each time — the shell fits its icons to the
  /// strip, and the strip is never smaller than needed.
  public var tileSize: Double { (((thickness - 20) / 4).rounded(.up) * 4).clamped(to: 16...128) }
}

extension Comparable {
  func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

public struct JournalEntry: Codable, Equatable {
  public var ts: Date
  public var kind: String       // pref | darkMode | wallpaper | restore
  public var target: String     // "domain/key", "appearance", display id
  public var before: String?
  public var after: String?
  public var scope: MutationScope

  public var line: String {
    let f = ISO8601DateFormatter()
    return "\(f.string(from: ts))  [\(scope.rawValue)] \(kind) \(target): \(before ?? "∅") → \(after ?? "∅")"
  }
}

/// The resolved `system` block of a theme (mirror of the Pigeon SystemConfig).
public struct SKSystemConfig: Equatable {
  public var hideNativeDock: Bool
  public var darkMode: Bool?
  public var accentColor: Int?
  public var wallpaperPath: String?
  /// When set (and Dock changes are allowed), the native Dock is kept as a
  /// spacer instead of being hidden. Takes precedence over hideNativeDock.
  public var dockReserve: DockReserve?

  public init(hideNativeDock: Bool, darkMode: Bool? = nil, accentColor: Int? = nil, wallpaperPath: String? = nil,
              dockReserve: DockReserve? = nil) {
    self.hideNativeDock = hideNativeDock
    self.darkMode = darkMode
    self.accentColor = accentColor
    self.wallpaperPath = wallpaperPath
    self.dockReserve = dockReserve
  }
}

/// Snapshot → journal → apply → restore (ADR-0010). Every system mutation the
/// app performs goes through here; nothing else writes foreign preferences.
public final class SafetyService {
  private let prefs: PreferenceStore
  private let actions: SystemActions
  private let snapshotURL: URL
  private let journalURL: URL
  private let now: () -> Date
  private let dockRestartDelay: TimeInterval
  private var pendingDockRestart: DispatchWorkItem?

  public init(
    prefs: PreferenceStore = CFPreferenceStore(),
    actions: SystemActions = LiveSystemActions(),
    snapshotURL: URL = Paths.originalSnapshot,
    journalURL: URL = Paths.journal,
    dockRestartDelay: TimeInterval = 0.5,
    now: @escaping () -> Date = Date.init
  ) {
    self.prefs = prefs
    self.actions = actions
    self.snapshotURL = snapshotURL
    self.journalURL = journalURL
    self.dockRestartDelay = dockRestartDelay
    self.now = now
  }

  // MARK: Snapshot

  public var hasSnapshot: Bool { FileManager.default.fileExists(atPath: snapshotURL.path) }

  public func loadSnapshot() -> Snapshot? {
    guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    return try? dec.decode(Snapshot.self, from: data)
  }

  /// Captures the pristine state once. Never overwrites an existing file —
  /// not even an unreadable one: a second capture would record *our* changes
  /// as "original". Returns nil when no trustworthy snapshot exists,
  /// in which case nothing may be changed.
  @discardableResult
  public func ensureSnapshot() -> Snapshot? {
    if FileManager.default.fileExists(atPath: snapshotURL.path) {
      if let existing = loadSnapshot() { return migrated(existing) }
      Log.safety.fault("snapshot exists but is unreadable; refusing to change system settings")
      return nil
    }
    let snap = Snapshot(
      createdAt: now(),
      prefs: PrefKey.tracked.map { .init(domain: $0.domain, key: $0.key, value: prefs.value(domain: $0.domain, key: $0.key)) },
      darkMode: actions.darkMode(),
      wallpapers: actions.wallpapers()
    )
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    do {
      try FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Paths.atomicWrite(enc.encode(snap), to: snapshotURL)
      Log.safety.info("snapshot written")
      return snap
    } catch {
      Log.safety.fault("could not write snapshot: \(error.localizedDescription, privacy: .public); refusing to change system settings")
      return nil
    }
  }

  /// Adds keys tracked since the snapshot was taken, with their current
  /// values. Safe: this app never wrote a key before tracking it, so the
  /// current value is still the user's own. Existing entries are untouched.
  private func migrated(_ snap: Snapshot) -> Snapshot {
    let missing = PrefKey.tracked.filter { !snap.has($0) }
    guard !missing.isEmpty else { return snap }
    var out = snap
    out.prefs += missing.map { .init(domain: $0.domain, key: $0.key, value: prefs.value(domain: $0.domain, key: $0.key)) }
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    do {
      try Paths.atomicWrite(enc.encode(out), to: snapshotURL)
      Log.safety.info("snapshot: recorded \(missing.count) newly tracked keys")
    } catch {
      Log.safety.error("snapshot: could not record new keys: \(error.localizedDescription, privacy: .public)")
    }
    return out
  }

  // MARK: Apply

  /// Returns whether the Dock is being restarted (its settings changed).
  @discardableResult
  public func apply(_ config: SKSystemConfig, dockHidingAllowed: Bool = true) -> Bool {
    guard let snap = ensureSnapshot() else { return false }
    var dockChanged = false

    var dockTargets: [PrefKey: PrefValue?] = [:]
    if let reserve = config.dockReserve, dockHidingAllowed {
      dockTargets = [
        .dockAutohide: .bool(false),
        .dockOrientation: .string(reserve.edge),
        .dockTilesize: .double(reserve.tileSize),
        .dockMagnification: .bool(false),
      ]
    } else if config.hideNativeDock && dockHidingAllowed {
      dockTargets = [.dockAutohide: .bool(true), .dockAutohideDelay: .double(1000), .dockAutohideTime: .double(0)]
    }
    // Every Dock key not set above goes back to the user's original value.
    for key in PrefKey.dockKeys {
      if let target = dockTargets[key] {
        dockChanged = setPref(key, target) || dockChanged
      } else if snap.has(key) {
        dockChanged = setPref(key, snap.value(for: key)) || dockChanged
      }
    }

    if let dark = config.darkMode, actions.darkMode() != dark {
      record(kind: "darkMode", target: "appearance", before: "\(!dark)", after: "\(dark)", scope: .persistent)
      actions.setDarkMode(dark)
    }

    if let accent = config.accentColor {
      // -1…6 are explicit colours; "key absent" means Multicolor, which we
      // express as any value outside that range.
      let changed = setPref(.accentColor, (-1...6).contains(accent) ? .int(accent) : nil)
      if changed { actions.notifyAppearanceChanged() }
    }

    if let path = config.wallpaperPath, FileManager.default.fileExists(atPath: path) {
      let url = URL(fileURLWithPath: path)
      let current = actions.wallpapers()
      if current.values.contains(where: { $0 != url.absoluteString }) || current.isEmpty {
        record(kind: "wallpaper", target: "all", before: current.values.first, after: url.absoluteString, scope: .persistent)
        actions.setWallpaper(url, display: nil)
      }
    }

    if dockChanged { scheduleDockRestart() }
    return dockChanged
  }

  // MARK: Restore

  /// Undoes runtime-scoped changes (the hidden Dock, the hidden menu bar).
  /// Called on normal quit and by the guardian after a crash.
  public func restoreRuntime() {
    guard let snap = loadSnapshot() else {
      restoreDockDefaults()
      return
    }
    var dockChanged = false
    for key in PrefKey.tracked where key.scope == .runtime && snap.has(key) {
      let changed = setPref(key, snap.value(for: key))
      if changed && PrefKey.dockKeys.contains(key) { dockChanged = true }
    }
    if dockChanged { restartDockNow() }
  }

  /// Returns macOS to the first-run snapshot.
  public func restoreAll() {
    guard let snap = loadSnapshot() else {
      restoreDockDefaults()
      return
    }
    var dockChanged = false
    var appearanceChanged = false
    for key in PrefKey.tracked where snap.has(key) {
      let changed = setPref(key, snap.value(for: key))
      if changed && PrefKey.dockKeys.contains(key) { dockChanged = true }
      if changed && key.domain == PrefKey.globalDomain { appearanceChanged = true }
    }
    if actions.darkMode() != snap.darkMode {
      record(kind: "darkMode", target: "appearance", before: "\(!snap.darkMode)", after: "\(snap.darkMode)", scope: .persistent)
      actions.setDarkMode(snap.darkMode)
    }
    let current = actions.wallpapers()
    for (display, urlString) in snap.wallpapers where current[display] != urlString {
      if let url = URL(string: urlString) {
        record(kind: "wallpaper", target: display, before: current[display], after: urlString, scope: .persistent)
        actions.setWallpaper(url, display: display)
      }
    }
    if appearanceChanged { actions.notifyAppearanceChanged() }
    if dockChanged { restartDockNow() }
    record(kind: "restore", target: "all", before: nil, after: nil, scope: .persistent)
  }

  /// Without a snapshot, undo only a Dock hide that is recognisably OURS (the
  /// 1000 s reveal delay) by returning to macOS defaults. A user's own
  /// auto-hide setting is left alone.
  private func restoreDockDefaults() {
    guard prefs.value(domain: PrefKey.dockDomain, key: PrefKey.dockAutohideDelay.key) == .double(1000) else { return }
    var changed = false
    // Only the auto-hide keys: size, position and magnification are the user's.
    for key in [PrefKey.dockAutohide, .dockAutohideDelay, .dockAutohideTime]
    where prefs.value(domain: key.domain, key: key.key) != nil {
      changed = setPref(key, nil) || changed
    }
    if changed { restartDockNow() }
  }

  // MARK: Journal

  public func journalLines(limit: Int = 200) -> [String] {
    guard let text = try? String(contentsOf: journalURL, encoding: .utf8) else { return [] }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    return text.split(separator: "\n").suffix(limit).compactMap {
      (try? dec.decode(JournalEntry.self, from: Data($0.utf8)))?.line
    }
  }

  // MARK: Internals

  /// Writes a tracked preference if it differs; returns whether it changed.
  @discardableResult
  private func setPref(_ key: PrefKey, _ value: PrefValue?) -> Bool {
    let before = prefs.value(domain: key.domain, key: key.key)
    guard before != value else { return false }
    record(kind: "pref", target: "\(key.domain)/\(key.key)", before: before?.description, after: value?.description, scope: key.scope)
    prefs.set(domain: key.domain, key: key.key, value: value)
    prefs.synchronize(domain: key.domain)
    return true
  }

  private func record(kind: String, target: String, before: String?, after: String?, scope: MutationScope) {
    let entry = JournalEntry(ts: now(), kind: kind, target: target, before: before, after: after, scope: scope)
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    guard var data = try? enc.encode(entry) else { return }
    data.append(0x0A)
    if let handle = try? FileHandle(forWritingTo: journalURL) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: journalURL)
    }
  }

  private func scheduleDockRestart() {
    pendingDockRestart?.cancel()
    guard dockRestartDelay > 0 else { actions.restartDock(); return }
    let item = DispatchWorkItem { [weak self] in self?.actions.restartDock() }
    pendingDockRestart = item
    DispatchQueue.main.asyncAfter(deadline: .now() + dockRestartDelay, execute: item)
  }

  private func restartDockNow() {
    pendingDockRestart?.cancel()
    pendingDockRestart = nil
    actions.restartDock()
  }
}
