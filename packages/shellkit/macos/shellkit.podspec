# Native side of the shell (ADR-0002). Classes/ = Flutter glue, Core/ = pure
# Swift services that also build standalone via macos/Package.swift.
Pod::Spec.new do |s|
  s.name             = 'shellkit'
  s.version          = '0.1.0'
  s.summary          = 'Native macOS services for mac-gnome-custom.'
  s.description      = 'Window control, workspaces, capture, hotkeys and system integration for the mac-gnome-custom shell.'
  s.homepage         = 'https://github.com/ponleu/mac-gnome-custom'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ponleu' => 'koemponleu@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift', 'Core/**/*.swift'
  s.dependency 'FlutterMacOS'
  # Interface-only scope (ADR-0012): no ApplicationServices/AX, no ScreenCaptureKit.
  s.frameworks       = 'AppKit', 'Carbon', 'IOKit', 'CoreAudio', 'AudioToolbox', 'CoreWLAN', 'ServiceManagement',
                     'ScreenCaptureKit', 'ApplicationServices'
  s.platform         = :osx, '14.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
