# shellkit

The native macOS side of mac-gnome-custom, packaged as a Flutter plugin.

- `pigeons/messages.dart`: the typed Dart↔Swift contract. Regenerate the bindings with `make gen` from the repository root.
- `macos/Core/`: plain Swift with no Flutter dependency (safety snapshot and journal, crash guardian, preferences, app index, hotkeys). It is also a SwiftPM package; run its tests with `swift test` in `macos/`.
- `macos/Classes/`: Flutter glue: native panels (`SurfaceManager`), the host API implementation (`ShellRuntime`), the dock menu and opt-in window previews.

See [DESIGN.md](../../DESIGN.md) and the [ADRs](../../docs/adr/README.md) for the architecture.
