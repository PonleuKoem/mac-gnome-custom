import Foundation

/// A preference value we know how to snapshot and restore.
public enum PrefValue: Codable, Equatable, CustomStringConvertible {
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)

  public init?(any: Any?) {
    switch any {
    case let n as NSNumber:
      // CFBoolean bridges to NSNumber; tell them apart by type ID.
      if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
      else if CFNumberIsFloatType(n) { self = .double(n.doubleValue) }
      else { self = .int(n.intValue) }
    case let s as String: self = .string(s)
    default: return nil
    }
  }

  public var propertyListValue: CFPropertyList {
    switch self {
    case .bool(let b): return b as CFBoolean
    case .int(let i): return i as NSNumber
    case .double(let d): return d as NSNumber
    case .string(let s): return s as CFString
    }
  }

  public var description: String {
    switch self {
    case .bool(let b): return "\(b)"
    case .int(let i): return "\(i)"
    case .double(let d): return "\(d)"
    case .string(let s): return "\"\(s)\""
    }
  }
}

/// Reads/writes another app's preference domain. Abstracted for tests.
public protocol PreferenceStore: AnyObject {
  func value(domain: String, key: String) -> PrefValue?
  /// `nil` deletes the key.
  func set(domain: String, key: String, value: PrefValue?)
  func synchronize(domain: String)
}

/// CFPreferences-backed store. Works for foreign domains because the app is not
/// sandboxed (ADR-0011). `NSGlobalDomain` maps to kCFPreferencesAnyApplication.
public final class CFPreferenceStore: PreferenceStore {
  public init() {}

  private func appID(_ domain: String) -> CFString {
    domain == PrefKey.globalDomain ? kCFPreferencesAnyApplication : domain as CFString
  }

  public func value(domain: String, key: String) -> PrefValue? {
    let v = CFPreferencesCopyValue(key as CFString, appID(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    return PrefValue(any: v)
  }

  public func set(domain: String, key: String, value: PrefValue?) {
    CFPreferencesSetValue(key as CFString, value?.propertyListValue, appID(domain),
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
  }

  public func synchronize(domain: String) {
    CFPreferencesSynchronize(appID(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
  }
}

public final class InMemoryPreferenceStore: PreferenceStore {
  public var storage: [String: PrefValue] = [:]
  public private(set) var syncCount = 0
  public init() {}
  public func value(domain: String, key: String) -> PrefValue? { storage["\(domain)/\(key)"] }
  public func set(domain: String, key: String, value: PrefValue?) { storage["\(domain)/\(key)"] = value }
  public func synchronize(domain: String) { syncCount += 1 }
}

/// Whether a change must be undone when the shell stops (runtime), or survives
/// until the user explicitly restores macOS (persistent). DESIGN.md §4.8.
public enum MutationScope: String, Codable {
  case runtime
  case persistent
}

public struct PrefKey: Hashable, Codable {
  public static let globalDomain = "NSGlobalDomain"
  public static let dockDomain = "com.apple.dock"

  public let domain: String
  public let key: String
  public let scope: MutationScope

  public static let dockAutohide = PrefKey(domain: dockDomain, key: "autohide", scope: .runtime)
  public static let dockAutohideDelay = PrefKey(domain: dockDomain, key: "autohide-delay", scope: .runtime)
  public static let dockAutohideTime = PrefKey(domain: dockDomain, key: "autohide-time-modifier", scope: .runtime)
  // Used when the native Dock stays visible as a spacer under the shell's dock,
  // so macOS keeps windows clear of it (see SKSystemConfig.dockReserve).
  public static let dockTilesize = PrefKey(domain: dockDomain, key: "tilesize", scope: .runtime)
  public static let dockOrientation = PrefKey(domain: dockDomain, key: "orientation", scope: .runtime)
  public static let dockMagnification = PrefKey(domain: dockDomain, key: "magnification", scope: .runtime)
  public static let accentColor = PrefKey(domain: globalDomain, key: "AppleAccentColor", scope: .persistent)
  public static let highlightColor = PrefKey(domain: globalDomain, key: "AppleHighlightColor", scope: .persistent)
  public static let hideMenuBar = PrefKey(domain: globalDomain, key: "_HIHideMenuBar", scope: .runtime)

  /// Every preference the app may ever touch. Snapshotted before the first change.
  public static let tracked: [PrefKey] = [
    dockAutohide, dockAutohideDelay, dockAutohideTime, accentColor, highlightColor, hideMenuBar,
    dockTilesize, dockOrientation, dockMagnification,
  ]

  public static let dockKeys: Set<PrefKey> = [
    dockAutohide, dockAutohideDelay, dockAutohideTime, dockTilesize, dockOrientation, dockMagnification,
  ]
}
