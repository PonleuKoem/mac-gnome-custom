import CoreGraphics

public struct Modifiers: OptionSet, Hashable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let cmd = Modifiers(rawValue: 1)
  public static let ctrl = Modifiers(rawValue: 2)
  public static let alt = Modifiers(rawValue: 4)
  public static let shift = Modifiers(rawValue: 8)

  public init(_ flags: CGEventFlags) {
    var m: Modifiers = []
    if flags.contains(.maskCommand) { m.insert(.cmd) }
    if flags.contains(.maskControl) { m.insert(.ctrl) }
    if flags.contains(.maskAlternate) { m.insert(.alt) }
    if flags.contains(.maskShift) { m.insert(.shift) }
    self = m
  }
}

public struct Chord: Hashable, CustomStringConvertible {
  public let keyCode: UInt16
  public let modifiers: Modifiers

  public init(keyCode: UInt16, modifiers: Modifiers) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  public var description: String {
    var parts: [String] = []
    if modifiers.contains(.ctrl) { parts.append("ctrl") }
    if modifiers.contains(.alt) { parts.append("alt") }
    if modifiers.contains(.shift) { parts.append("shift") }
    if modifiers.contains(.cmd) { parts.append("cmd") }
    parts.append(KeyCodes.name(for: keyCode) ?? "key\(keyCode)")
    return parts.joined(separator: "+")
  }
}

/// A keybinding trigger as written in theme files.
public enum Trigger: Hashable {
  case chord(Chord)
  /// ⌘ pressed and released alone.
  case superTap
  /// Two ⌘ taps in quick succession.
  case superDoubleTap

  /// "cmd+shift+tab", "ctrl+alt+right". (`superTap` / `superDoubleTap` parse,
  /// but can't be registered: a lone ⌘ tap needs keyboard monitoring, which
  /// the interface-only build doesn't do — ADR-0012.)
  public static func parse(_ text: String) -> Trigger? {
    let t = text.trimmingCharacters(in: .whitespaces)
    switch t.lowercased() {
    case "supertap": return .superTap
    case "superdoubletap": return .superDoubleTap
    default: break
    }
    var mods: Modifiers = []
    var key: UInt16?
    for raw in t.lowercased().split(separator: "+").map(String.init) {
      switch raw {
      case "cmd", "command", "super", "meta": mods.insert(.cmd)
      case "ctrl", "control": mods.insert(.ctrl)
      case "alt", "opt", "option": mods.insert(.alt)
      case "shift": mods.insert(.shift)
      default:
        guard key == nil, let code = KeyCodes.code(for: raw) else { return nil }
        key = code
      }
    }
    guard let key else { return nil }
    return .chord(Chord(keyCode: key, modifiers: mods))
  }
}

/// US-ANSI virtual key codes (Carbon `kVK_*`).
public enum KeyCodes {
  static let table: [String: UInt16] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "equal": 24, "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29, "rightbracket": 30, "o": 31, "u": 32,
    "leftbracket": 33, "i": 34, "p": 35, "return": 36, "l": 37, "j": 38, "quote": 39, "k": 40,
    "semicolon": 41, "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47,
    "tab": 48, "space": 49, "grave": 50, "delete": 51, "escape": 53,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
    "f10": 109, "f11": 103, "f12": 111, "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119,
    "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
  ]
  static let aliases: [String: String] = [
    "enter": "return", "esc": "escape", "backtick": "grave", "`": "grave", "backspace": "delete",
    "-": "minus", "=": "equal", ",": "comma", ".": "period", "/": "slash", "[": "leftbracket",
    "]": "rightbracket", ";": "semicolon", "'": "quote", "\\": "backslash",
  ]
  static let reverse: [UInt16: String] = Dictionary(uniqueKeysWithValues: table.map { ($1, $0) })

  public static func code(for name: String) -> UInt16? {
    table[aliases[name] ?? name]
  }

  public static func name(for code: UInt16) -> String? { reverse[code] }

  public static let escape: UInt16 = 53
  public static let tab: UInt16 = 48
}

/// Well-known macOS and app shortcuts a binding would shadow (DESIGN.md F8).
public enum ShortcutConflicts {
  static let known: [String: String] = [
    "cmd+space": "Spotlight",
    "ctrl+space": "Select the previous input source",
    "cmd+tab": "macOS app switcher (reserved by macOS)",
    "cmd+grave": "Cycle windows of the app",
    "cmd+q": "Quit app", "cmd+w": "Close window", "cmd+c": "Copy", "cmd+v": "Paste", "cmd+x": "Cut",
    "cmd+a": "Select All", "cmd+z": "Undo", "cmd+s": "Save", "cmd+n": "New", "cmd+o": "Open",
    "cmd+p": "Print", "cmd+f": "Find", "cmd+t": "New tab", "cmd+h": "Hide app", "cmd+m": "Minimize",
    "cmd+comma": "App settings",
    "ctrl+up": "Mission Control", "ctrl+down": "Application windows",
    "ctrl+left": "Move one Space left", "ctrl+right": "Move one Space right",
    "shift+cmd+3": "Screenshot", "shift+cmd+4": "Screenshot selection", "shift+cmd+5": "Screenshot tools",
    "ctrl+cmd+q": "Lock Screen", "alt+cmd+escape": "Force Quit", "ctrl+cmd+f": "Full screen",
    "ctrl+cmd+space": "Emoji & Symbols",
  ]

  public static func conflicts(for text: String) -> [String] {
    guard case .chord(let chord)? = Trigger.parse(text) else { return [] }
    let normalized = chord.description
    var out: [String] = []
    if let hit = known[normalized] { out.append(hit) }
    if chord.modifiers == [.ctrl], let name = KeyCodes.name(for: chord.keyCode), let n = Int(name), (1...9).contains(n) {
      out.append("\"Switch to Desktop \(n)\" (if enabled in Keyboard Shortcuts › Mission Control)")
    }
    if chord.modifiers == [.cmd], out.isEmpty {
      out.append("⌘+key is used by many apps")
    }
    return out
  }
}
