import AppKit
import FlutterMacOS

/// Registered by `RegisterGeneratedPlugins(registry: engine)`; wires the Pigeon
/// channels to the shared runtime.
public class ShellKitPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    ShellRuntime.shared.attach(messenger: registrar.messenger)
  }
}

/// Entry points for the Runner target (app/macos/Runner).
public enum ShellKitEntry {
  /// Returns true if the process was started in a helper mode and has been
  /// handled (the caller must then not start the UI).
  ///   --guardian …  watchdog (never returns)
  ///   --restore     put macOS back to the first-run snapshot and exit
  public static func handleCommandLine(_ arguments: [String]) -> Bool {
    if arguments.contains("--guardian") {
      Guardian.run(arguments: arguments)
    }
    if arguments.contains("--restore") {
      Guardian.restoreCommand(arguments: arguments)
    }
    return false
  }

  /// Creates the single shared engine with multi-view enabled (ADR-0003).
  /// `enableMultiView` is not public API in Flutter 3.35; it must be called
  /// before any view controller is attached.
  public static func makeEngine() -> FlutterEngine {
    let engine = FlutterEngine(name: "mac-gnome-custom", project: nil, allowHeadlessExecution: true)
    let selector = NSSelectorFromString("enableMultiView")
    if engine.responds(to: selector) {
      engine.perform(selector)
    } else {
      Log.surfaces.fault("FlutterEngine.enableMultiView missing: multi-view unavailable (see ADR-0003 fallback)")
    }
    return engine
  }

  private static var manager: SurfaceManager?

  static func surfaces(for engine: FlutterEngine) -> SurfaceManager {
    if let manager { return manager }
    let m = SurfaceManager(engine: engine)
    manager = m
    return m
  }

  /// View controller for the Customizer window defined in MainMenu.xib.
  public static func makeCustomizerController(engine: FlutterEngine) -> FlutterViewController {
    surfaces(for: engine).makeCustomizerController()
  }

  public static func registerCustomizer(window: NSWindow, controller: FlutterViewController, engine: FlutterEngine) {
    surfaces(for: engine).registerCustomizer(window: window, controller: controller)
  }

  public static func customizerDidClose(engine: FlutterEngine) {
    surfaces(for: engine).customizerClosed()
  }

  public static func showCustomizer(engine: FlutterEngine) {
    surfaces(for: engine).showCustomizer()
  }

  /// Builds the shell surfaces and starts every service.
  public static func start(engine: FlutterEngine) {
    ShellRuntime.shared.start(surfaces: surfaces(for: engine))
  }

  /// First launch (no snapshot yet): the Customizer opens for onboarding.
  public static var isFirstRun: Bool { !SafetyService().hasSnapshot }

  public static func willTerminate() {
    ShellRuntime.shared.willTerminate()
  }
}
