import Foundation

/// Every OS "trick" sits behind a flag so it can be turned off when a macOS
/// update breaks it (ADR-0001). Stored in the app's own defaults.
public enum FeatureFlag: String, CaseIterable {
  /// Cover the native menu bar with our top bar (ADR-0004).
  case menuBarCover
  /// Hide the native Dock via its preferences (ADR-0005).
  case dockHideNative
  /// Top-left hot corner opens the launcher.
  case hotCorner
  /// OPT-IN, off by default: window thumbnails in the dock's hover label.
  /// Needs Screen Recording + Accessibility (the one exception to ADR-0012's
  /// interface-only scope, only while this is on).
  case windowThumbnails

  public var defaultValue: Bool { self != .windowThumbnails }
}

public final class FeatureFlags {
  public static let shared = FeatureFlags()
  private let defaults: UserDefaults
  public var onChange: ((FeatureFlag, Bool) -> Void)?

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func isEnabled(_ flag: FeatureFlag) -> Bool {
    let key = "flag.\(flag.rawValue)"
    return defaults.object(forKey: key) == nil ? flag.defaultValue : defaults.bool(forKey: key)
  }

  public func set(_ flag: FeatureFlag, _ enabled: Bool) {
    defaults.set(enabled, forKey: "flag.\(flag.rawValue)")
    onChange?(flag, enabled)
  }

  public var all: [String: Bool] {
    Dictionary(uniqueKeysWithValues: FeatureFlag.allCases.map { ($0.rawValue, isEnabled($0)) })
  }
}
