import XCTest
@testable import ShellKitCore

final class AppScanTests: XCTestCase {
  private func makeApp(_ root: URL, _ name: String, id: String, uiElement: Bool) throws {
    let contents = root.appendingPathComponent("\(name).app/Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundlePackageType": "APPL"]
    if uiElement { info["LSUIElement"] = true }
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
  }

  /// Background helpers stay out of the launcher, but the shell itself (also
  /// an LSUIElement app) is listed so it can be found and opened.
  func testBackgroundOnlyAppsAreSkippedExceptTheShell() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try makeApp(root, "Editor", id: "com.example.editor", uiElement: false)
    try makeApp(root, "Helper", id: "com.example.helper", uiElement: true)
    try makeApp(root, "mac-gnome-custom", id: "dev.ponleu.macGnomeCustom", uiElement: true)

    let ids = AppService.scan(roots: [root.path], keep: ["dev.ponleu.macGnomeCustom"]).map(\.bundleId)
    XCTAssertTrue(ids.contains("com.example.editor"))
    XCTAssertTrue(ids.contains("dev.ponleu.macGnomeCustom"))
    XCTAssertFalse(ids.contains("com.example.helper"))
  }
}
