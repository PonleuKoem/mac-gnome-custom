import AppKit
import Carbon.HIToolbox

private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
  guard let event, let userData else { return OSStatus(eventNotHandledErr) }
  var id = EventHotKeyID()
  let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                 nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
  guard status == noErr else { return status }
  Unmanaged<GlobalHotkeys>.fromOpaque(userData).takeUnretainedValue().fired(id.id)
  return noErr
}

/// Global shortcuts through the public `RegisterEventHotKey` API
/// (interface-only scope, ADR-0012).
///
/// Unlike an event tap, this needs NO permission and the shell never sees any
/// key press except the exact registered chords. The trade-off: no lone-⌘ tap
/// and no taking over chords macOS reserves (⌘Tab, ⌘Space).
public final class GlobalHotkeys {
  /// Main thread.
  public var onAction: ((String) -> Void)?

  private var refs: [UInt32: EventHotKeyRef] = [:]
  private var actions: [UInt32: String] = [:]
  private var handler: EventHandlerRef?
  private var bindings: [(action: String, trigger: String)] = []
  private var suspended = false
  private static let signature: OSType = 0x4D47_4353  // "MGCS"

  public init() {}

  deinit { unregisterAll() }

  public var registeredCount: Int { refs.count }

  /// Replaces all shortcuts. Returns the chords that could not be registered
  /// (unparseable, or refused by macOS because another app owns them).
  @discardableResult
  public func setBindings(_ bindings: [(action: String, trigger: String)]) -> [String] {
    self.bindings = bindings
    return suspended ? [] : registerAll()
  }

  /// While the Customizer records a new shortcut, nothing is registered so
  /// the pressed chord reaches the Customizer window.
  public func setSuspended(_ value: Bool) {
    guard value != suspended else { return }
    suspended = value
    if value { unregisterAll() } else { registerAll() }
  }

  @discardableResult
  private func registerAll() -> [String] {
    unregisterAll()
    installHandlerIfNeeded()
    var failed: [String] = []
    var next: UInt32 = 1
    for b in bindings {
      guard case .chord(let chord)? = Trigger.parse(b.trigger) else {
        failed.append(b.trigger)
        continue
      }
      var ref: EventHotKeyRef?
      let id = EventHotKeyID(signature: Self.signature, id: next)
      let status = RegisterEventHotKey(UInt32(chord.keyCode), Self.carbonModifiers(chord.modifiers), id,
                                       GetApplicationEventTarget(), 0, &ref)
      if status == noErr, let ref {
        refs[next] = ref
        actions[next] = b.action
        next += 1
      } else {
        failed.append(b.trigger)
        Log.hotkeys.error("could not register \(b.trigger, privacy: .public) for \(b.action, privacy: .public) (status \(status))")
      }
    }
    return failed
  }

  private func unregisterAll() {
    for ref in refs.values { UnregisterEventHotKey(ref) }
    refs.removeAll()
    actions.removeAll()
  }

  private func installHandlerIfNeeded() {
    guard handler == nil else { return }
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec,
                        Unmanaged.passUnretained(self).toOpaque(), &handler)
  }

  fileprivate func fired(_ id: UInt32) {
    guard let action = actions[id] else { return }
    DispatchQueue.main.async { [weak self] in self?.onAction?(action) }
  }

  static func carbonModifiers(_ m: Modifiers) -> UInt32 {
    var out: UInt32 = 0
    if m.contains(.cmd) { out |= UInt32(cmdKey) }
    if m.contains(.shift) { out |= UInt32(shiftKey) }
    if m.contains(.alt) { out |= UInt32(optionKey) }
    if m.contains(.ctrl) { out |= UInt32(controlKey) }
    return out
  }
}

/// Top-left hot corner with a short dwell. Watches only the mouse *position*
/// (a global mouse-moved monitor needs no permission and sees no keys or
/// content). Main thread.
public final class HotCornerMonitor {
  public var onTrigger: (() -> Void)?
  private var monitors: [Any] = []
  private var armed = true
  private var enteredAt: Date?
  private let dwell: TimeInterval = 0.12
  private let flags: FeatureFlags

  public init(flags: FeatureFlags = .shared) {
    self.flags = flags
  }

  public func start() {
    guard monitors.isEmpty else { return }
    let handler: (NSEvent) -> Void = { [weak self] _ in self?.check() }
    if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
      monitors.append(g)
    }
    if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { e in handler(e); return e }) {
      monitors.append(l)
    }
  }

  private func check() {
    guard flags.isEnabled(.hotCorner) else { return }
    let p = NSEvent.mouseLocation
    let inCorner = NSScreen.screens.contains { s in
      p.x <= s.frame.minX + 2 && p.y >= s.frame.maxY - 2 && s.frame.insetBy(dx: -1, dy: -1).contains(p)
    }
    let farAway = NSScreen.screens.allSatisfy { s in !(p.x <= s.frame.minX + 30 && p.y >= s.frame.maxY - 30) }
    if inCorner && armed {
      if let t = enteredAt {
        if Date().timeIntervalSince(t) >= dwell {
          armed = false
          enteredAt = nil
          onTrigger?()
        }
      } else {
        enteredAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell + 0.01) { [weak self] in self?.check() }
      }
    } else if !inCorner {
      enteredAt = nil
      if farAway { armed = true }
    }
  }
}
