import XCTest
@testable import ShellKitCore

final class ChordTests: XCTestCase {
  func testParsesModifiersAndKeys() {
    XCTAssertEqual(Trigger.parse("cmd+shift+tab"), .chord(Chord(keyCode: 48, modifiers: [.cmd, .shift])))
    XCTAssertEqual(Trigger.parse("ctrl+alt+right"), .chord(Chord(keyCode: 124, modifiers: [.ctrl, .alt])))
    XCTAssertEqual(Trigger.parse("Super+A"), .chord(Chord(keyCode: 0, modifiers: [.cmd])))
    XCTAssertEqual(Trigger.parse("cmd+`"), .chord(Chord(keyCode: 50, modifiers: [.cmd])))
    XCTAssertEqual(Trigger.parse("superTap"), .superTap)
    XCTAssertEqual(Trigger.parse("superDoubleTap"), .superDoubleTap)
  }

  func testRejectsGarbage() {
    XCTAssertNil(Trigger.parse("cmd+"))
    XCTAssertNil(Trigger.parse("cmd+a+b"))
    XCTAssertNil(Trigger.parse("hyper+x"))
  }

  func testDescriptionRoundTrips() {
    for text in ["ctrl+alt+right", "shift+cmd+3", "cmd+tab", "ctrl+1"] {
      guard case .chord(let c)? = Trigger.parse(text) else { return XCTFail(text) }
      XCTAssertEqual(c.description, text)
    }
  }

  func testConflicts() {
    XCTAssertEqual(ShortcutConflicts.conflicts(for: "cmd+a"), ["Select All"])
    XCTAssertTrue(ShortcutConflicts.conflicts(for: "ctrl+1").first!.contains("Desktop 1"))
    XCTAssertEqual(ShortcutConflicts.conflicts(for: "cmd+j"), ["⌘+key is used by many apps"])
    XCTAssertEqual(ShortcutConflicts.conflicts(for: "ctrl+alt+right"), [])
    XCTAssertEqual(ShortcutConflicts.conflicts(for: "superTap"), [])
  }
}


final class GlobalHotkeysTests: XCTestCase {
  func testCarbonModifierMapping() {
    // cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096 (Carbon Events.h)
    XCTAssertEqual(GlobalHotkeys.carbonModifiers([.cmd]), 256)
    XCTAssertEqual(GlobalHotkeys.carbonModifiers([.alt]), 2048)
    XCTAssertEqual(GlobalHotkeys.carbonModifiers([.ctrl, .alt, .shift, .cmd]), 256 | 512 | 2048 | 4096)
  }

  func testDefaultShortcutsParse() {
    XCTAssertEqual(Trigger.parse("alt+space"), .chord(Chord(keyCode: 49, modifiers: [.alt])))
    XCTAssertEqual(Trigger.parse("ctrl+alt+space"), .chord(Chord(keyCode: 49, modifiers: [.ctrl, .alt])))
  }

  func testLoneSuperTapCannotBeRegistered() {
    let h = GlobalHotkeys()
    XCTAssertEqual(h.setBindings([("overview", "superTap")]), ["superTap"], "needs keyboard monitoring (ADR-0012)")
    XCTAssertEqual(h.registeredCount, 0)
  }
}
