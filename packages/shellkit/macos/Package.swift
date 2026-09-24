// swift-tools-version:5.9
// Standalone build of the pure-Swift core (no Flutter) so it can be unit-tested
// with `swift test` (ADR-0002).
// The Flutter plugin (shellkit.podspec) compiles the same Core/ sources.
// Interface-only scope (ADR-0012): no ApplicationServices (AX) or
// ScreenCaptureKit; hotkeys use the public Carbon RegisterEventHotKey API.
import PackageDescription

let package = Package(
  name: "ShellKitCore",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ShellKitCore", targets: ["ShellKitCore"]),
  ],
  targets: [
    .target(
      name: "ShellKitCore",
      path: "Core",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("IOKit"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("AudioToolbox"),
        .linkedFramework("CoreWLAN"),
      ]
    ),
    .testTarget(name: "ShellKitCoreTests", dependencies: ["ShellKitCore"], path: "Tests"),
  ]
)
