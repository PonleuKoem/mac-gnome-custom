# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-09-25

First public release.

### Added

- Top bar covering the macOS menu bar: Activities button, clock with calendar, active app name, status icons and read-only quick settings.
- Dock:
  - GNOME-style dash inside Activities, or always visible; floating or full-width panel, on the bottom, left or right edge.
  - macOS-style magnification and the Dock's native right-click menu.
  - Hover card listing the app's windows.
  - Keeps maximized windows clear of the dock, using the native Dock as an invisible spacer.
- Optional window previews (off by default): pictures of an app's windows on hover; click one to switch to exactly that window. Needs Accessibility and Screen Recording, granted by the user.
- Activities launcher with an app grid, fuzzy search, smooth scrolling and a top-left hot corner.
- Theme engine:
  - JSON themes with inheritance (`extends`), hot reload, validation with per-token fallbacks, and `.mgctheme` import/export.
  - Nine built-in themes: GNOME Adwaita, GNOME Dark, Ubuntu, Windows 11, Classic Mac, iOS, Android, Tidepool and Overprint.
  - `tokens.scale` (*Interface size*) scales text, icons and corners together; top-bar text always fits the macOS menu bar.
- Customizer:
  - Theme gallery with live previews.
  - Per-theme Style, Top bar, Dock, Launcher, Desktop and Shortcuts pages, each with a live preview and a reset button on every changed setting.
  - App-wide Windows & privacy, General, Safety and Diagnostics pages.
  - Layout adapts to the window size.
- Safety: snapshot of the original macOS settings before the first change, change journal, one-click restore, crash guardian and a `--restore` command.
- `make install` signs with an Apple Development identity when available, so granted permissions survive rebuilds.

### Security

- Interface-only scope ([ADR-0012](docs/adr/0012-interface-only-scope.md)): no keystroke monitoring, no control of other apps and no private Apple APIs; global shortcuts use the public hotkey API. See [SECURITY.md](SECURITY.md).

[Unreleased]: https://github.com/PonleuKoem/mac-gnome-custom/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/PonleuKoem/mac-gnome-custom/releases/tag/v0.1.0
