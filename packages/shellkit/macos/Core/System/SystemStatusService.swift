import AppKit
import AudioToolbox
import CoreAudio
import CoreWLAN
import IOKit.ps

public struct SKSystemStatus: Equatable {
  public var batteryPercent: Int = -1
  public var charging = false
  public var onBattery = false
  public var volume: Double = 0
  public var muted = false
  public var wifiOn = false
  public var wifiSsid: String?
  public var wifiRssi = 0
  public var darkMode = false
}

private func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
  guard let context else { return }
  Unmanaged<SystemStatusService>.fromOpaque(context).takeUnretainedValue().refresh()
}

/// READ-ONLY battery (IOKit), volume (CoreAudio), Wi-Fi (CoreWLAN) and
/// appearance for the top-bar indicators. The shell never changes volume,
/// Wi-Fi or power state (interface-only scope, ADR-0012). Main thread.
public final class SystemStatusService {
  public var onChange: ((SKSystemStatus) -> Void)?
  public private(set) var status = SKSystemStatus()
  private var wifiTimer: Timer?
  private var audioDevice: AudioDeviceID = 0
  private var audioListener: AudioObjectPropertyListenerBlock?
  private var themeObserver: NSObjectProtocol?

  public init() {}

  public func start() {
    let context = Unmanaged.passUnretained(self).toOpaque()
    if let source = IOPSNotificationCreateRunLoopSource(powerSourceChanged, context)?.takeRetainedValue() {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }
    listenAudio()
    themeObserver = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
    ) { [weak self] _ in self?.refresh() }
    wifiTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
    refresh()
  }

  public func refresh() {
    var s = SKSystemStatus()
    Self.readBattery(into: &s)
    s.volume = Double(Self.volume(audioDevice) ?? 0)
    s.muted = Self.muted(audioDevice) ?? false
    if let wifi = CWWiFiClient.shared().interface() {
      s.wifiOn = wifi.powerOn()
      s.wifiSsid = wifi.ssid()  // nil without Location permission on macOS 14+
      s.wifiRssi = wifi.rssiValue()
    }
    s.darkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    if s != status {
      status = s
      onChange?(s)
    }
  }

  // MARK: Battery

  static func readBattery(into s: inout SKSystemStatus) {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
    for source in list {
      guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
            desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
      let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
      let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
      s.batteryPercent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
      s.charging = desc[kIOPSIsChargingKey] as? Bool ?? false
      s.onBattery = desc[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
    }
  }

  // MARK: Audio

  private static func address(_ selector: AudioObjectPropertySelector,
                              _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  static func defaultOutputDevice() -> AudioDeviceID {
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
  }

  static func volume(_ device: AudioDeviceID) -> Float32? {
    var v = Float32(0)
    var size = UInt32(MemoryLayout<Float32>.size)
    var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
    return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &v) == noErr ? v : nil
  }

  static func muted(_ device: AudioDeviceID) -> Bool? {
    var v = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
    return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &v) == noErr ? v != 0 : nil
  }

  private func listenAudio() {
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      DispatchQueue.main.async { self?.refresh() }
    }
    audioListener = block
    var defaultAddr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main) { [weak self] _, _ in
      self?.attachToDefaultDevice()
      self?.refresh()
    }
    attachToDefaultDevice()
  }

  private func attachToDefaultDevice() {
    guard let block = audioListener else { return }
    if audioDevice != 0 {
      var v = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
      var m = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
      AudioObjectRemovePropertyListenerBlock(audioDevice, &v, .main, block)
      AudioObjectRemovePropertyListenerBlock(audioDevice, &m, .main, block)
    }
    audioDevice = Self.defaultOutputDevice()
    var v = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
    var m = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
    AudioObjectAddPropertyListenerBlock(audioDevice, &v, .main, block)
    AudioObjectAddPropertyListenerBlock(audioDevice, &m, .main, block)
  }
}
