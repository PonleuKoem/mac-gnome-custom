import XCTest
@testable import ShellKitCore

final class FakeActions: SystemActions {
  var dark = false
  var walls: [String: String] = ["1": "file:///original.jpg"]
  var dockRestarts = 0
  var appearanceNotifications = 0

  func restartDock() { dockRestarts += 1 }
  func darkMode() -> Bool { dark }
  func setDarkMode(_ d: Bool) { dark = d }
  func wallpapers() -> [String: String] { walls }
  func setWallpaper(_ url: URL, display: String?) {
    for k in walls.keys where display == nil || display == k { walls[k] = url.absoluteString }
  }
  func notifyAppearanceChanged() { appearanceNotifications += 1 }
}

final class SafetyServiceTests: XCTestCase {
  var dir: URL!
  var prefs: InMemoryPreferenceStore!
  var actions: FakeActions!
  var service: SafetyService!

  override func setUp() {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    prefs = InMemoryPreferenceStore()
    prefs.set(domain: "com.apple.dock", key: "autohide", value: .bool(false))
    prefs.set(domain: "NSGlobalDomain", key: "AppleAccentColor", value: .int(3))
    actions = FakeActions()
    service = makeService()
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: dir)
  }

  func makeService() -> SafetyService {
    SafetyService(prefs: prefs, actions: actions,
                  snapshotURL: dir.appendingPathComponent("original.json"),
                  journalURL: dir.appendingPathComponent("journal.jsonl"),
                  dockRestartDelay: 0)
  }

  func testApplyHidesDockAndJournals() {
    service.apply(SKSystemConfig(hideNativeDock: true))
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "autohide"), .bool(true))
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "autohide-delay"), .double(1000))
    XCTAssertEqual(actions.dockRestarts, 1)
    XCTAssertEqual(service.journalLines().count, 3)
  }

  func testApplyIsIdempotent() {
    service.apply(SKSystemConfig(hideNativeDock: true))
    service.apply(SKSystemConfig(hideNativeDock: true))
    XCTAssertEqual(actions.dockRestarts, 1, "no change → no Dock restart")
  }

  func testSnapshotIsWriteOnce() {
    service.apply(SKSystemConfig(hideNativeDock: true, darkMode: true))
    // A fresh service must not re-snapshot the modified state.
    let second = makeService()
    let snap = try! XCTUnwrap(second.ensureSnapshot())
    XCTAssertEqual(snap.value(for: .dockAutohide), .bool(false))
    XCTAssertFalse(snap.darkMode)
  }

  func testRestoreRuntimeOnlyUndoesDock() {
    service.apply(SKSystemConfig(hideNativeDock: true, darkMode: true, accentColor: 5))
    service.restoreRuntime()
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "autohide"), .bool(false))
    XCTAssertNil(prefs.value(domain: "com.apple.dock", key: "autohide-delay"), "absent before → deleted")
    XCTAssertTrue(actions.dark, "appearance is persistent")
    XCTAssertEqual(prefs.value(domain: "NSGlobalDomain", key: "AppleAccentColor"), .int(5))
  }

  func testRestoreAllReturnsToSnapshot() {
    let wallpaper = dir.appendingPathComponent("w.jpg")
    FileManager.default.createFile(atPath: wallpaper.path, contents: Data())
    service.apply(SKSystemConfig(hideNativeDock: true, darkMode: true, accentColor: 5, wallpaperPath: wallpaper.path))
    XCTAssertEqual(actions.walls["1"], wallpaper.absoluteString)
    service.restoreAll()
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "autohide"), .bool(false))
    XCTAssertEqual(prefs.value(domain: "NSGlobalDomain", key: "AppleAccentColor"), .int(3))
    XCTAssertFalse(actions.dark)
    XCTAssertEqual(actions.walls["1"], "file:///original.jpg")
    XCTAssertGreaterThan(actions.appearanceNotifications, 0)
  }

  func testTurningDockHidingOffRestoresDockKeys() {
    service.apply(SKSystemConfig(hideNativeDock: true))
    service.apply(SKSystemConfig(hideNativeDock: false))
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "autohide"), .bool(false))
    XCTAssertEqual(actions.dockRestarts, 2)
  }

  func testFlagOffPreventsDockHiding() {
    service.apply(SKSystemConfig(hideNativeDock: true), dockHidingAllowed: false)
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "autohide"), .bool(false))
  }

  func testDockReserveKeepsNativeDockAsSpacerAndRestores() {
    prefs.set(domain: "com.apple.dock", key: "tilesize", value: .int(48))
    service.apply(SKSystemConfig(hideNativeDock: true, dockReserve: DockReserve(edge: "left", thickness: 70)))
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "autohide"), .bool(false), "visible, so macOS reserves space")
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "orientation"), .string("left"))
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "tilesize"), .double(52))
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "magnification"), .bool(false))
    XCTAssertNil(prefs.value(domain: "com.apple.dock", key: "autohide-delay"), "no hide delay in spacer mode")
    XCTAssertEqual(actions.dockRestarts, 1)

    // Switching to plain hiding puts size/position back and hides.
    service.apply(SKSystemConfig(hideNativeDock: true))
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "tilesize"), .int(48))
    XCTAssertNil(prefs.value(domain: "com.apple.dock", key: "orientation"))
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "autohide"), .bool(true))

    service.apply(SKSystemConfig(hideNativeDock: true, dockReserve: DockReserve(edge: "bottom", thickness: 90)))
    service.restoreRuntime()
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "tilesize"), .int(48))
    XCTAssertNil(prefs.value(domain: "com.apple.dock", key: "orientation"))
    XCTAssertNil(prefs.value(domain: "com.apple.dock", key: "magnification"))
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "autohide"), .bool(false))
  }

  func testOldSnapshotGainsNewKeysWithoutLosingTheUsersDockSettings() throws {
    // A snapshot written before tilesize/orientation/magnification were tracked.
    let old = Snapshot(createdAt: Date(), prefs: [.init(domain: "com.apple.dock", key: "autohide", value: .bool(false))],
                       darkMode: false, wallpapers: [:])
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    try enc.encode(old).write(to: dir.appendingPathComponent("original.json"))
    prefs.set(domain: "com.apple.dock", key: "tilesize", value: .int(36))
    prefs.set(domain: "com.apple.dock", key: "orientation", value: .string("right"))

    // A restore before any apply must not delete keys the snapshot never saw.
    service.restoreRuntime()
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "tilesize"), .int(36))

    service.apply(SKSystemConfig(hideNativeDock: true, dockReserve: DockReserve(edge: "bottom", thickness: 80)))
    service.restoreRuntime()
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "tilesize"), .int(36))
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "orientation"), .string("right"))
    XCTAssertTrue(try XCTUnwrap(service.loadSnapshot()).has(.dockTilesize), "migrated snapshot was saved")
  }

  func testDockTileSizeMovesInStepsSoSmallTweaksDontRestartTheDock() {
    XCTAssertEqual(DockReserve(edge: "bottom", thickness: 70).tileSize, 52)
    XCTAssertEqual(DockReserve(edge: "bottom", thickness: 71).tileSize, 52)
    XCTAssertEqual(DockReserve(edge: "bottom", thickness: 72).tileSize, 52)
    XCTAssertEqual(DockReserve(edge: "bottom", thickness: 73).tileSize, 56)
    XCTAssertGreaterThanOrEqual(DockReserve(edge: "bottom", thickness: 73).tileSize + 20, 73, "strip never too small")
    service.apply(SKSystemConfig(hideNativeDock: true, dockReserve: DockReserve(edge: "bottom", thickness: 70)))
    XCTAssertFalse(service.apply(SKSystemConfig(hideNativeDock: true, dockReserve: DockReserve(edge: "bottom", thickness: 71))),
                   "same step → no Dock restart")
    XCTAssertEqual(actions.dockRestarts, 1)
  }

  func testMulticolorAccentDeletesKey() {
    service.apply(SKSystemConfig(hideNativeDock: false, accentColor: 99))
    XCTAssertNil(prefs.value(domain: "NSGlobalDomain", key: "AppleAccentColor"))
  }
}

final class SafetySnapshotEdgeTests: XCTestCase {
  func testUnreadableSnapshotIsNeverOverwrittenAndBlocksChanges() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let snapURL = dir.appendingPathComponent("original.json")
    try Data("{ corrupted".utf8).write(to: snapURL)
    let prefs = InMemoryPreferenceStore()
    let actions = FakeActions()
    let s = SafetyService(prefs: prefs, actions: actions, snapshotURL: snapURL,
                          journalURL: dir.appendingPathComponent("j.jsonl"), dockRestartDelay: 0)
    s.apply(SKSystemConfig(hideNativeDock: true))
    XCTAssertNil(prefs.value(domain: "com.apple.dock", key: "autohide"), "no trustworthy snapshot → no changes")
    XCTAssertEqual(try String(contentsOf: snapURL, encoding: .utf8), "{ corrupted", "file untouched")
  }

  func testRestoreWithoutSnapshotOnlyUndoesOurOwnDockHide() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let prefs = InMemoryPreferenceStore()
    let actions = FakeActions()
    let s = SafetyService(prefs: prefs, actions: actions, snapshotURL: dir.appendingPathComponent("none.json"),
                          journalURL: dir.appendingPathComponent("j.jsonl"), dockRestartDelay: 0)
    // The user's own auto-hide (normal delay) is left alone.
    prefs.set(domain: "com.apple.dock", key: "autohide", value: .bool(true))
    s.restoreRuntime()
    XCTAssertEqual(prefs.value(domain: "com.apple.dock", key: "autohide"), .bool(true))
    XCTAssertEqual(actions.dockRestarts, 0)
    // Our sentinel hide is undone back to macOS defaults.
    prefs.set(domain: "com.apple.dock", key: "autohide-delay", value: .double(1000))
    s.restoreRuntime()
    XCTAssertNil(prefs.value(domain: "com.apple.dock", key: "autohide"))
    XCTAssertNil(prefs.value(domain: "com.apple.dock", key: "autohide-delay"))
    XCTAssertEqual(actions.dockRestarts, 1)
  }
}

final class HeartbeatMonitorTests: XCTestCase {
  func hb(_ pid: pid_t, _ ts: TimeInterval, _ state: Heartbeat.State = .alive) -> Heartbeat {
    Heartbeat(pid: pid, timestamp: ts, state: state)
  }

  func testHealthyShellKeepsWatching() {
    var m = HeartbeatMonitor(parent: 7, staleAfter: 5)
    for t in 0..<20 {
      XCTAssertEqual(m.observe(hb(7, Double(1000 + t)), uptime: Double(t), parentAlive: true), .keepWatching)
    }
  }

  func testWallClockJumpAfterSleepIsNotAHang() {
    // Audit H1: after sleep the wall-clock stamp looks hours old, but the
    // monotonic clock barely moved and the stamp keeps changing.
    var m = HeartbeatMonitor(parent: 7, staleAfter: 5)
    XCTAssertEqual(m.observe(hb(7, 1000), uptime: 10, parentAlive: true), .keepWatching)
    XCTAssertEqual(m.observe(hb(7, 1000), uptime: 11, parentAlive: true), .keepWatching)
    XCTAssertEqual(m.observe(hb(7, 9000), uptime: 12, parentAlive: true), .keepWatching)
  }

  func testFrozenHeartbeatIsAHang() {
    var m = HeartbeatMonitor(parent: 7, staleAfter: 5)
    _ = m.observe(hb(7, 1000), uptime: 0, parentAlive: true)
    XCTAssertEqual(m.observe(hb(7, 1000), uptime: 4, parentAlive: true), .keepWatching)
    XCTAssertEqual(m.observe(hb(7, 1000), uptime: 6, parentAlive: true), .hung)
  }

  func testCrashAndCleanExit() {
    var m = HeartbeatMonitor(parent: 7, staleAfter: 5)
    XCTAssertEqual(m.observe(hb(7, 1000), uptime: 0, parentAlive: false), .crashed)
    var c = HeartbeatMonitor(parent: 7, staleAfter: 5)
    XCTAssertEqual(c.observe(hb(7, 1000, .clean), uptime: 0, parentAlive: false), .cleanExit)
  }

  func testIgnoresHeartbeatsOfOtherShells() {
    var m = HeartbeatMonitor(parent: 7, staleAfter: 5, startupGrace: 10)
    XCTAssertEqual(m.observe(hb(99, 1000, .clean), uptime: 0, parentAlive: true), .keepWatching,
                   "a previous run's clean file must not end the watch")
    XCTAssertEqual(m.observe(nil, uptime: 11, parentAlive: true), .neverStarted)
  }
}

final class PrefValueTests: XCTestCase {
  func testBridgesCFTypes() {
    XCTAssertEqual(PrefValue(any: kCFBooleanTrue), .bool(true))
    XCTAssertEqual(PrefValue(any: NSNumber(value: 3)), .int(3))
    XCTAssertEqual(PrefValue(any: NSNumber(value: 2.5)), .double(2.5))
    XCTAssertEqual(PrefValue(any: "Dark"), .string("Dark"))
    XCTAssertNil(PrefValue(any: nil))
  }
}

final class GuardianTests: XCTestCase {
  func testHeartbeatRoundTrip() {
    let hb = Heartbeat(pid: 42, timestamp: 1_700_000_000.5, state: .alive)
    XCTAssertEqual(Heartbeat.parse(hb.encoded), hb)
    XCTAssertNil(Heartbeat.parse("garbage"))
  }

  func testCrashPolicyGivesUpAfterThreeInAMinute() {
    var p = CrashPolicy()
    p.record(0)
    p.record(20)
    XCTAssertFalse(p.shouldGiveUp(now: 20))
    p.record(40)
    XCTAssertTrue(p.shouldGiveUp(now: 40))
    XCTAssertFalse(p.shouldGiveUp(now: 200), "old crashes age out")
  }

}
