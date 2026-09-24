import Foundation
import os

/// Unified logging, one category per service. View with:
///   log stream --predicate 'subsystem == "dev.ponleu.macgnomecustom"'
public enum Log {
  public static let subsystem = "dev.ponleu.macgnomecustom"
  public static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
  public static let apps = Logger(subsystem: subsystem, category: "apps")
  public static let system = Logger(subsystem: subsystem, category: "system")
  public static let safety = Logger(subsystem: subsystem, category: "safety")
  public static let guardian = Logger(subsystem: subsystem, category: "guardian")
  public static let surfaces = Logger(subsystem: subsystem, category: "surfaces")
}
