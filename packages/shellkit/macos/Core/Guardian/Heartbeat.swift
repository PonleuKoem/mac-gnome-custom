import Foundation

/// "<pid> <unix-time> <alive|clean>" written by the shell every second from the
/// MAIN run loop, so a hung main thread stops the heartbeat (ADR-0010).
public struct Heartbeat: Equatable {
  public enum State: String { case alive, clean }
  public var pid: pid_t
  public var timestamp: TimeInterval
  public var state: State

  public init(pid: pid_t, timestamp: TimeInterval, state: State) {
    self.pid = pid
    self.timestamp = timestamp
    self.state = state
  }

  public var encoded: String { "\(pid) \(timestamp) \(state.rawValue)\n" }

  public static func parse(_ text: String) -> Heartbeat? {
    let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
    guard parts.count == 3, let pid = pid_t(parts[0]), let ts = TimeInterval(parts[1]),
          let state = State(rawValue: String(parts[2])) else { return nil }
    return Heartbeat(pid: pid, timestamp: ts, state: state)
  }

  public static func read(from url: URL = Paths.heartbeat) -> Heartbeat? {
    (try? String(contentsOf: url, encoding: .utf8)).flatMap(parse)
  }
}

public final class HeartbeatWriter {
  private let url: URL
  private var timer: Timer?

  public init(url: URL = Paths.heartbeat) {
    self.url = url
  }

  /// Must be called on the main thread.
  public func start() {
    beat(.alive)
    let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.beat(.alive) }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  /// Tells the guardian this exit is intentional.
  public func stopClean() {
    timer?.invalidate()
    timer = nil
    beat(.clean)
  }

  private func beat(_ state: Heartbeat.State) {
    let hb = Heartbeat(pid: getpid(), timestamp: Date().timeIntervalSince1970, state: state)
    try? hb.encoded.write(to: url, atomically: true, encoding: .utf8)
  }
}

/// Gives up relaunching after `limit` crashes inside `window` seconds.
public struct CrashPolicy: Codable, Equatable {
  public var crashes: [TimeInterval] = []
  public var limit = 3
  public var window: TimeInterval = 60

  public init() {}

  public mutating func record(_ t: TimeInterval) {
    crashes.append(t)
    crashes = crashes.filter { t - $0 <= window }
  }

  public func shouldGiveUp(now: TimeInterval) -> Bool {
    crashes.filter { now - $0 <= window }.count >= limit
  }

  static var url: URL { Paths.supportDirectory.appendingPathComponent("crashes.json") }

  public static func load() -> CrashPolicy {
    (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(CrashPolicy.self, from: $0) } ?? CrashPolicy()
  }

  public func save() {
    if let data = try? JSONEncoder().encode(self) { try? Paths.atomicWrite(data, to: Self.url) }
  }
}
