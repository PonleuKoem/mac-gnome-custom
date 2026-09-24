import AppKit
import FlutterMacOS

// Core (SK*) models → Pigeon messages.

extension RectD {
  init(_ r: CGRect) {
    self.init(x: Double(r.minX), y: Double(r.minY), w: Double(r.width), h: Double(r.height))
  }

  var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

extension AppInfo {
  init(_ a: SKApp) {
    self.init(bundleId: a.bundleId, name: a.name, path: a.path, pid: Int64(a.pid), isActive: a.isActive,
              isHidden: a.isHidden)
  }
}

extension InstalledApp {
  init(_ a: SKInstalledApp) {
    self.init(bundleId: a.bundleId, name: a.name, path: a.path)
  }
}

extension SystemStatus {
  init(_ s: SKSystemStatus) {
    self.init(batteryPercent: Int64(s.batteryPercent), charging: s.charging, onBattery: s.onBattery,
              volume: s.volume, muted: s.muted, wifiOn: s.wifiOn, wifiSsid: s.wifiSsid,
              wifiRssi: Int64(s.wifiRssi), darkMode: s.darkMode)
  }
}

extension ScreenInfo {
  init(_ s: NSScreen) {
    let main = NSScreen.screens.first
    self.init(id: Int64(s.displayID), frame: RectD(s.topLeftFrame), visibleFrame: RectD(s.topLeftVisibleFrame),
              menuBarHeight: Double(s.menuBarHeight), scale: Double(s.backingScaleFactor), isMain: s == main)
  }
}
