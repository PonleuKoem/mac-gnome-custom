import Foundation

/// On-disk locations (DESIGN.md §6). `MGC_SUPPORT_DIR` overrides the root for tests.
public enum Paths {
  public static var supportDirectory: URL {
    if let override = ProcessInfo.processInfo.environment["MGC_SUPPORT_DIR"] {
      return ensure(URL(fileURLWithPath: override, isDirectory: true))
    }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return ensure(base.appendingPathComponent("MacGnomeCustom", isDirectory: true))
  }

  public static var themes: URL { ensure(supportDirectory.appendingPathComponent("themes", isDirectory: true)) }
  public static var snapshots: URL { ensure(supportDirectory.appendingPathComponent("snapshots", isDirectory: true)) }
  public static var logs: URL { ensure(supportDirectory.appendingPathComponent("logs", isDirectory: true)) }
  public static var originalSnapshot: URL { snapshots.appendingPathComponent("original.json") }
  public static var journal: URL { supportDirectory.appendingPathComponent("journal.jsonl") }
  public static var heartbeat: URL { supportDirectory.appendingPathComponent("heartbeat") }
  public static var guardianLock: URL { supportDirectory.appendingPathComponent("guardian.lock") }

  @discardableResult
  static func ensure(_ url: URL) -> URL {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// Writes via a temp file + rename so readers never see a half-written file.
  public static func atomicWrite(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
  }
}
