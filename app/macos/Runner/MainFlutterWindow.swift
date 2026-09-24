import Cocoa
import FlutterMacOS
import shellkit

/// The Customizer: the only regular window. It renders the "customizer"
/// surface from the shared engine and is hidden until needed.
class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let engine = ShellEngine.shared
    let controller = ShellKitEntry.makeCustomizerController(engine: engine)
    let windowFrame = frame
    contentViewController = controller
    setFrame(windowFrame, display: false)
    title = "mac-gnome-custom"
    minSize = NSSize(width: 820, height: 560)
    isReleasedWhenClosed = false
    delegate = self
    ShellKitEntry.registerCustomizer(window: self, controller: controller, engine: engine)
    super.awakeFromNib()
  }

  func windowWillClose(_ notification: Notification) {
    ShellKitEntry.customizerDidClose(engine: ShellEngine.shared)
  }
}
