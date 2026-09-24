import Cocoa
import FlutterMacOS
import shellkit

/// One engine shared by every surface (ADR-0003). Created lazily because
/// MainMenu.xib's window (the Customizer) asks for it during nib loading,
/// before applicationDidFinishLaunching.
enum ShellEngine {
  static let shared: FlutterEngine = {
    let engine = ShellKitEntry.makeEngine()
    RegisterGeneratedPlugins(registry: engine)
    engine.run(withEntrypoint: nil)
    return engine
  }()
}

/// The same executable also runs as the crash guardian (`--guardian`) and as a
/// restore tool (`--restore`), so both share its signature and permissions.
@main
struct Entry {
  static func main() {
    if ShellKitEntry.handleCommandLine(CommandLine.arguments) { return }
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
  }
}

class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    ShellKitEntry.start(engine: ShellEngine.shared)
    if ShellKitEntry.isFirstRun {
      ShellKitEntry.showCustomizer(engine: ShellEngine.shared)
    }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    ShellKitEntry.willTerminate()
  }

  // The shell keeps running with no normal windows open.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  // Clicking the app in Finder/Launchpad while it runs opens the Customizer.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    ShellKitEntry.showCustomizer(engine: ShellEngine.shared)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }
}
