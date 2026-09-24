import XCTest
@testable import ShellKitCore

final class GeometryTests: XCTestCase {
  func testRoundTrip() {
    let cocoa = CGRect(x: 10, y: 20, width: 300, height: 200)
    let tl = Geometry.topLeft(fromCocoa: cocoa, primaryHeight: 1000)
    XCTAssertEqual(tl, CGRect(x: 10, y: 780, width: 300, height: 200))
    XCTAssertEqual(Geometry.cocoa(fromTopLeft: tl, primaryHeight: 1000), cocoa)
  }

  func testScreenRelativeFrame() {
    let screen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)  // Cocoa
    let r = Geometry.cocoaFrame(screenRelative: CGRect(x: 0, y: 0, width: 1920, height: 30), screenCocoaFrame: screen)
    XCTAssertEqual(r, CGRect(x: 1440, y: 1050, width: 1920, height: 30))
  }

  func testScreenIndex() {
    let screens = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 100, height: 100)]
    XCTAssertEqual(Geometry.screenIndex(for: CGRect(x: 120, y: 10, width: 10, height: 10), screens: screens), 1)
    XCTAssertEqual(Geometry.screenIndex(for: CGRect(x: 90, y: 10, width: 30, height: 10), screens: screens), 1)
  }
}

final class LRUCacheTests: XCTestCase {
  func testLRUEvicts() {
    let c = LRUCache<Int, String>(capacity: 2)
    c.set(1, "a")
    c.set(2, "b")
    _ = c.get(1)
    c.set(3, "c")
    XCTAssertNil(c.get(2))
    XCTAssertEqual(c.get(1), "a")
  }
}
