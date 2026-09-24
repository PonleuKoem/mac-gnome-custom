import AppKit

/// A detached watchdog process (same executable, `--guardian`). If the shell
/// crashes or hangs while the native Dock is hidden, the guardian puts it back
/// so the user is never left without a Dock (ADR-0010).
///
/// Deviation from ADR-0010: the guardian is spawned by the shell with
/// `setsid` instead of an `SMAppService` LaunchAgent, which avoids an extra
/// bundle build phase. It survives the shell's death because it lives in its
/// own session.
public enum Guardian {
  static let pollInterval: TimeInterval = 1
  /// Seconds of *awake* time without a new heartbeat before the shell counts
  /// as hung.
  static let staleAfter: TimeInterval = 5

  static var ownerFile: URL { Paths.supportDirectory.appendingPathComponent("guardian.owner") }

  // MARK: Launching (shell side)

  /// Ensures a guardian watches THIS shell. A guardian from a previous run may
  /// still hold the lock for a moment (quit → relaunch, crash relaunch), so we
  /// retry until one owned by our pid is running.
  public static func spawn(relaunch: Bool, attempt: Int = 0) {
    if isWatching(pid: getpid()) { return }
    if !isRunning, let exe = Bundle.main.executablePath {
      launch(exe: exe, relaunch: relaunch)
    }
    guard attempt < 15 else {
      Log.guardian.fault("no guardian could be started; crash protection is off for this session")
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { spawn(relaunch: relaunch, attempt: attempt + 1) }
  }

  private static func launch(exe: String, relaunch: Bool) {
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    // POSIX_SPAWN_SETSID: new session, so the guardian outlives the shell.
    posix_spawnattr_setflags(&attr, Int16(0x0400))
    var args = [exe, "--guardian", "--parent", String(getpid())]
    if relaunch { args.append("--relaunch") }
    let cArgs = args.map { strdup($0) } + [nil]
    defer { cArgs.forEach { free($0) } }
    var pid: pid_t = 0
    let rc = posix_spawn(&pid, exe, nil, &attr, cArgs, environ)
    if rc == 0 {
      Log.guardian.info("guardian spawned pid=\(pid)")
    } else {
      Log.guardian.error("guardian spawn failed rc=\(rc)")
    }
  }

  /// True when some process holds the guardian lock.
  public static var isRunning: Bool {
    let fd = open(Paths.guardianLock.path, O_RDWR | O_CREAT, 0o644)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    if flock(fd, LOCK_EX | LOCK_NB) == 0 {
      flock(fd, LOCK_UN)
      return false
    }
    return true
  }

  /// True when a running guardian was started for `pid`.
  public static func isWatching(pid: pid_t) -> Bool {
    guard isRunning, let text = try? String(contentsOf: ownerFile, encoding: .utf8) else { return false }
    let parts = text.split(separator: " ")
    return parts.count == 2 && pid_t(parts[1]) == pid
  }

  // MARK: Running (guardian side)

  /// Parses `--guardian --parent <pid> [--relaunch]` and runs. Never returns.
  public static func run(arguments: [String]) -> Never {
    let parent = arguments.firstIndex(of: "--parent").flatMap { i in
      i + 1 < arguments.count ? pid_t(arguments[i + 1]) : nil
    } ?? getppid()
    run(parent: parent, relaunch: arguments.contains("--relaunch"))
  }

  public static func run(parent: pid_t, relaunch: Bool) -> Never {
    let lock = open(Paths.guardianLock.path, O_RDWR | O_CREAT, 0o644)
    guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
      Log.guardian.info("another guardian is running; exiting")
      exit(0)
    }
    try? "\(getpid()) \(parent)".write(to: ownerFile, atomically: true, encoding: .utf8)
    Log.guardian.info("guardian started pid=\(getpid()) parent=\(parent) relaunch=\(relaunch)")

    // Staleness is measured on the guardian's own monotonic clock (which stops
    // while the Mac sleeps), from when the heartbeat file last CHANGED — never
    // by comparing wall-clock stamps, which jump after sleep.
    var monitor = HeartbeatMonitor(parent: parent, staleAfter: staleAfter)

    while true {
      Thread.sleep(forTimeInterval: pollInterval)
      let verdict = monitor.observe(Heartbeat.read(), uptime: ProcessInfo.processInfo.systemUptime,
                                    parentAlive: isAlive(parent))
      switch verdict {
      case .keepWatching:
        continue
      case .cleanExit, .neverStarted:
        releaseAndExit(lock, code: 0)
      case .crashed, .hung:
        break
      }

      if verdict == .hung {
        Log.guardian.error("shell pid=\(parent) stopped responding; killing it")
        kill(parent, SIGKILL)
      } else {
        Log.guardian.error("shell pid=\(parent) exited without a clean heartbeat")
      }

      recover()
      let now = Date().timeIntervalSince1970
      var policy = CrashPolicy.load()
      policy.record(now)
      policy.save()
      if policy.shouldGiveUp(now: now) {
        notify("mac-gnome-custom crashed \(policy.limit) times in a minute. macOS has been restored.")
        releaseAndExit(lock, code: 1)
      }
      // Release the lock BEFORE relaunching so the new shell can start its own
      // guardian immediately.
      flock(lock, LOCK_UN)
      close(lock)
      if relaunch, let url = appBundleURL() {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in done.signal() }
        _ = done.wait(timeout: .now() + 10)
      } else {
        notify("mac-gnome-custom stopped unexpectedly. macOS has been restored.")
      }
      exit(0)  // the relaunched shell spawns a fresh guardian
    }
  }

  private static func releaseAndExit(_ lock: Int32, code: Int32) -> Never {
    flock(lock, LOCK_UN)
    close(lock)
    exit(code)
  }

  static func isAlive(_ pid: pid_t) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
  }

  /// Restores runtime changes (the hidden Dock), or everything. Runs
  /// synchronously: the caller exits right after.
  public static func recover(all: Bool = false) {
    let safety = SafetyService(actions: LiveSystemActions(async: false))
    if all { safety.restoreAll() } else { safety.restoreRuntime() }
    Log.guardian.info("recovered (\(all ? "everything" : "runtime changes", privacy: .public))")
  }

  // MARK: --restore from a terminal

  /// `--restore` typed in Terminal would run with *Terminal's* permissions
  /// (the responsible process), which usually lack Accessibility for this app.
  /// Re-launching through LaunchServices makes the app its own responsible
  /// process so its own grants apply.
  public static func restoreCommand(arguments: [String]) -> Never {
    if !arguments.contains("--via-launchservices"), getppid() != 1, let url = appBundleURL() {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      // No `-W`: the restore process exits too quickly for `open` to track it;
      // wait for its status file instead.
      try? FileManager.default.removeItem(at: restoreStatusFile)
      var args = ["-n"]
      // Keep an isolated support dir (tests) across the LaunchServices hop.
      if let dir = ProcessInfo.processInfo.environment["MGC_SUPPORT_DIR"] { args += ["--env", "MGC_SUPPORT_DIR=\(dir)"] }
      p.arguments = args + ["-a", url.path, "--args", "--restore", "--via-launchservices"]
      if (try? p.run()) != nil {
        p.waitUntilExit()
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
          if let status = try? String(contentsOf: restoreStatusFile, encoding: .utf8) {
            print("mac-gnome-custom: \(status)")
            exit(status.contains("could not") ? 2 : 0)
          }
          Thread.sleep(forTimeInterval: 0.2)
        }
        print("mac-gnome-custom: restore did not report back; check ~/Library/Application Support/MacGnomeCustom")
        exit(3)
      }
    }
    recover(all: true)
    let status = "macOS restored to the first-run snapshot."
    try? status.write(to: restoreStatusFile, atomically: true, encoding: .utf8)
    print("mac-gnome-custom: \(status)")
    exit(0)
  }

  static var restoreStatusFile: URL { Paths.supportDirectory.appendingPathComponent("restore-status.txt") }

  private static func appBundleURL() -> URL? {
    let url = Bundle.main.bundleURL
    return url.pathExtension == "app" ? url : nil
  }

  private static func notify(_ message: String) {
    // Automated tests (MGC_NO_NOTIFY) must not pop notifications.
    if ProcessInfo.processInfo.environment["MGC_NO_NOTIFY"] != nil { return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "display notification \"\(message)\" with title \"mac-gnome-custom\""]
    try? p.run()
    p.waitUntilExit()
  }
}

/// Pure decision logic of the guardian loop (unit-tested).
public struct HeartbeatMonitor {
  public enum Verdict: Equatable { case keepWatching, cleanExit, neverStarted, crashed, hung }

  let parent: pid_t
  let staleAfter: TimeInterval
  let startupGrace: TimeInterval
  private var startedAt: TimeInterval?
  private var lastStamp: TimeInterval?
  private var lastChangeAt: TimeInterval?

  public init(parent: pid_t, staleAfter: TimeInterval, startupGrace: TimeInterval = 10) {
    self.parent = parent
    self.staleAfter = staleAfter
    self.startupGrace = startupGrace
  }

  /// - Parameters:
  ///   - uptime: monotonic, sleep-excluding clock (`ProcessInfo.systemUptime`).
  public mutating func observe(_ hb: Heartbeat?, uptime: TimeInterval, parentAlive: Bool) -> Verdict {
    if startedAt == nil { startedAt = uptime }
    // Only trust heartbeats from the shell that spawned us; an old file from a
    // previous run (possibly "clean") must not end the watch.
    guard let hb, hb.pid == parent else {
      if !parentAlive { return .crashed }
      return uptime - startedAt! > startupGrace ? .neverStarted : .keepWatching
    }
    if hb.state == .clean { return .cleanExit }
    if !parentAlive { return .crashed }
    if hb.timestamp != lastStamp {
      lastStamp = hb.timestamp
      lastChangeAt = uptime
      return .keepWatching
    }
    return uptime - (lastChangeAt ?? uptime) > staleAfter ? .hung : .keepWatching
  }
}
