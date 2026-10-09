# mac-gnome-custom

[![CI](https://github.com/PonleuKoem/mac-gnome-custom/actions/workflows/ci.yml/badge.svg)](https://github.com/PonleuKoem/mac-gnome-custom/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)

A themable desktop shell for macOS, built with Flutter and Swift. It redraws the parts of the Mac interface you use all day — **a top bar, a dock and an Activities launcher** — in the look you choose: GNOME, Ubuntu, Windows 11, iOS, Android, or one you design yourself, without writing code.

It is an **overlay, not a modification**: it never patches macOS, never needs SIP disabled, and puts everything back when you quit.

<!-- Screenshots: add images to docs/images/ and reference them here, e.g.
![GNOME Adwaita](docs/images/gnome-adwaita.png) -->

## Contents

- [Features](#features)
- [Built-in themes](#built-in-themes)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Privacy and permissions](#privacy-and-permissions)
- [Restoring macOS](#restoring-macos)
- [Creating themes](#creating-themes)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Known limitations](#known-limitations)
- [Contributing](#contributing) · [Security](#security) · [License](#license)

## Features

- **Top bar** covering the macOS menu bar: Activities button, clock with calendar, the active app's name, status icons (battery, Wi-Fi, volume) and quick settings. Items can be rearranged per theme.
- **Dock**, always visible or only inside Activities (GNOME-style), floating or as a full-width panel, on the bottom, left or right edge.
  - macOS-style magnification on hover.
  - The native Dock's right-click menu (Keep in Dock, Open at Login, Show in Finder, Show All Windows, Hide, Quit, ⌥ Force Quit).
  - Hover card with the app's open windows; with optional window previews, click a preview to switch to exactly that window.
  - Keeps maximized windows clear of the dock, like the macOS Dock does.
- **Activities launcher**: full-screen app grid with fuzzy search, opened from the top bar, a keyboard shortcut or the top-left hot corner.
- **Themes as data**: a theme is a JSON file plus optional wallpapers and icons. Themes can inherit from each other, hot-reload while you edit them, and be shared as `.mgctheme` files.
- **Customizer** (settings window):
  - Theme gallery with live previews.
  - Per-theme pages for Style, Top bar, Dock, Launcher, Desktop and Shortcuts; each theme keeps its own settings.
  - One *Interface size* control that scales text, icons and corners together.
  - Every changed setting shows a reset button.
- **Safety first**: original macOS settings are snapshotted before the first change, every change is journaled, and a guardian process restores the Dock if the shell crashes.

## Built-in themes

| Theme | Look |
|---|---|
| GNOME Adwaita / GNOME Dark | GNOME 4x: top bar, dash inside Activities |
| Ubuntu | Left-edge panel dock, orange accent |
| Windows 11 | Centred taskbar-style dock, no top bar |
| Classic Mac | The macOS menu bar and Dock, untouched |
| iOS | Translucent frosted dock, no running indicators |
| Android | Material You colours, circular icons |
| Tidepool | Original: a bioluminescent night tide, dock on the right |
| Overprint | Original: a two-ink risograph poster, cream panel dock |
| Dracula | The Dracula palette: purple accent, moonlit wallpaper with bats, centred dock |

Theme names describe the look they are inspired by. This project is not affiliated with or endorsed by Apple, the GNOME Foundation, Canonical, Microsoft or Google.

## Requirements

- macOS 14 Sonoma or later, Apple silicon or Intel (developed on macOS 26 Tahoe)
- To build from source:
  - Xcode 16 or later, with its command-line tools
  - Flutter 3.35 or later (stable channel)
  - CocoaPods

## Installation

There are no prebuilt downloads yet; build it from source.

1. **Install the tools** (skip any you already have):

   ```bash
   xcode-select --install
   ```

   ```bash
   brew install --cask flutter
   ```

   ```bash
   brew install cocoapods
   ```

2. **Clone and install:**

   ```bash
   git clone https://github.com/PonleuKoem/mac-gnome-custom.git
   ```

   ```bash
   cd mac-gnome-custom && make install
   ```

   `make install` builds a release version and copies it to `/Applications/mac-gnome-custom.app`.

3. **Open it** from Launchpad, Spotlight or `/Applications`.

**Code signing:** if your keychain has an *Apple Development* certificate (any free Apple ID signed in to Xcode provides one), `make install` signs the app with it, so macOS keeps any permissions you grant across rebuilds. Without one the app is signed ad hoc, and macOS treats each rebuild as a new app. To choose the identity yourself, set `SIGN_ID`:

```bash
make install SIGN_ID="Apple Development: Your Name (TEAMID)"
```

**Uninstall:** `make uninstall` quits and removes the app. Your settings stay in `~/Library/Application Support/MacGnomeCustom/`; delete that folder to remove them too.

## Usage

### First launch

The first launch opens **onboarding**. Nothing on your Mac changes until you pick a look and press **Start**. Until then the shell shows no panels, registers no shortcuts and changes no settings.

### Everyday use

| To | Do |
|---|---|
| Open Activities (launcher) | Press **⌥Space**, click **Activities** in the top bar, or move the pointer into the top-left corner |
| Launch an app | In Activities, type part of its name and press **Enter**, or click it |
| Switch to an app | Click it in the dock |
| See an app's windows | Rest the pointer on its dock icon |
| App menu (Keep in Dock, Quit…) | Right-click, or click and hold, a dock icon |
| Open the Customizer | Click **⚙** at the end of the dock or in quick settings, or open the app again from Launchpad |

Shortcuts can be changed per theme in **Customizer → Shortcuts**. Combinations reserved by macOS, such as ⌘Tab and ⌘Space, can't be used.

### Customizer

- **Themes:** click a card to switch themes. The ⋯ menu on a card customizes it, saves a copy, exports it, or resets your changes.
- **Theme settings** (sidebar section named after the active theme):
  - **Style:** interface size, colours, fonts, icon shapes, corners, blur and animation.
  - **Top bar:** show or hide it, arrange its items, clock format.
  - **Dock:** visibility, style, position, size, magnification, pinned apps, keeping windows clear of the dock.
  - **Launcher:** icon size, labels, backdrop.
  - **Desktop:** wallpaper, light/dark mode, macOS accent colour.
  - **Shortcuts:** keyboard shortcuts.

  A live preview stays at the top of each page. A dot marks every setting you've changed; its **↺** button puts back the theme's value.
- **App settings:** Windows & privacy, General (open at login, workarounds), Safety, Diagnostics.

### Window previews (optional)

Hovering a dock icon always shows how many windows the app has. To see each window and switch to a specific one:

1. Hover an app with several windows and click **Turn on previews…**, or switch it on in **Customizer → Windows & privacy**.
2. In **System Settings → Privacy & Security**, allow mac-gnome-custom under **Accessibility** (to switch windows) and **Screen Recording** (for the pictures).
3. If macOS asks, quit and reopen mac-gnome-custom.

With only Accessibility allowed, windows are listed by title without pictures.

## Privacy and permissions

mac-gnome-custom only customizes the interface ([ADR-0012](docs/adr/0012-interface-only-scope.md)). It never:

- disables SIP, runs as root, installs system extensions or injects code into other apps;
- connects to the network or collects telemetry;
- reads keystrokes: shortcuts use macOS's public hotkey API, which reports only the exact combinations you set.

| Permission | When it's asked for | Why |
|---|---|---|
| Automation (System Events) | The first time a theme changes light/dark mode | Switching dark mode |
| Accessibility | Only if you turn on window previews | Bringing the window you click to the front |
| Screen Recording | Only if you turn on window previews | Small pictures of an app's windows, taken while you hover its icon, kept in memory, never saved or sent |

The only macOS settings it changes are the ones a theme sets: Dock visibility and size, wallpaper, dark mode and accent colour. See [SECURITY.md](SECURITY.md) for the full security model.

## Restoring macOS

- **Quit** the shell: the macOS Dock comes back as it was.
- **Customizer → Safety → Restore macOS to original** puts back everything from the snapshot taken before the first change.
- **If the shell crashes or hangs**, a guardian process restores the Dock (and relaunches the shell; after three crashes in a minute it stops and leaves macOS restored).
- **From Terminal:**

  ```bash
  /Applications/mac-gnome-custom.app/Contents/MacOS/mac-gnome-custom --restore
  ```

State lives in `~/Library/Application Support/MacGnomeCustom/`: `settings.json`, `themes/`, `snapshots/original.json` and `journal.jsonl`.

## Creating themes

A theme is a folder containing `theme.json`, plus optional `wallpapers/` and `icons/<bundleId>.png`. Put it in `~/Library/Application Support/MacGnomeCustom/themes/<id>/`; it reloads as you save. Or build a look in the Customizer and choose **Save a copy…**, then **Export…** to share it as a `.mgctheme` file.

```jsonc
{
  "schema": 1,
  "id": "sunset",
  "name": "Sunset",
  "extends": "gnome-dark",                 // inherit everything not set here
  "tokens": {
    "scale": 1.1,                          // interface size (0.75–1.5)
    "color": { "accent": "#ff7800", "bar.bg": "#1a0f0a", "icon.plate": "#fff3e6" },
    "radius": { "tile": 18 },
    "icon": { "shape": "circle" }          // native | circle | squircle | rounded
  },
  "layout": {
    "topBar": { "left": ["activities"], "center": ["clock"], "right": ["indicators"] },
    "dock": { "mode": "always", "style": "panel", "position": "bottom", "iconSize": 48 },
    "launcher": { "iconSize": 88, "labels": false }
  },
  "system": { "darkMode": "dark", "accent": "orange", "wallpaper": "wallpapers/sunset.jpg" },
  "keybindings": { "overview": "alt+space" }
}
```

- **Reference:** every key is documented in [docs/theme.schema.json](docs/theme.schema.json); the built-in themes in [app/assets/themes/](app/assets/themes/) are complete examples.
- **Invalid values** never crash the shell: each one falls back to its default and is listed on the Customizer's Themes page.
- **Imported files are checked:** `.mgctheme` imports are size-limited, and paths that would leave the theme folder are rejected.

## Troubleshooting

| Problem | Fix |
|---|---|
| Clicking a window preview doesn't switch windows | Allow **Accessibility** for mac-gnome-custom in System Settings. If it's listed but doesn't work (common after a rebuild), remove it with **–**, add `/Applications/mac-gnome-custom.app` again with **+**, and reopen the app. |
| Permissions reset after every rebuild | The build was signed ad hoc. Sign in to Xcode with an Apple ID to get an Apple Development certificate, then run `make install` again. |
| A shortcut does nothing | Another app or macOS already uses it. **Customizer → Diagnostics** lists refused shortcuts; pick another in **Customizer → Shortcuts**. |
| The macOS Dock is missing after a crash | Open the app and quit it, or run the `--restore` command above. |
| The top bar overlaps the macOS menu bar | Check **Customizer → General → Cover the macOS menu bar**, or turn the top bar off for the theme. |
| Start over with a theme | **Customizer → Themes**, ⋯ on the card → **Reset changes**. |

## Development

```bash
make help       # list all targets
make test       # Swift core tests + Dart tests (incl. golden images)
make run        # debug build and launch
make goldens    # re-render golden images after an intentional UI change
make gen        # regenerate the Dart↔Swift bridge after editing pigeons/messages.dart
```

**Architecture:**

- **Flutter** draws every surface. One engine renders several native panels (top bar, dock, launcher, popovers, Customizer), and the shell's policy lives in Dart.
- **Swift** (`packages/shellkit`) does everything that touches macOS: panels, hotkeys, app launching, appearance settings, the safety snapshot and the crash guardian.
- **Typed bridge:** the two sides talk over [Pigeon](https://pub.dev/packages/pigeon).

The reasoning behind each choice is in [docs/adr/](docs/adr/README.md); the original design document is [DESIGN.md](DESIGN.md).

```
app/                        Flutter app: UI and shell policy
  lib/src/core/             ShellController, stores, icon cache, algorithms
  lib/src/theme/            theme parser, repository (extends, import/export), per-theme overrides
  lib/src/surfaces/         top bar, dock, Activities launcher, popovers
  lib/src/customizer/       Customizer window
  assets/themes/            built-in themes and wallpapers
  test/                     unit, controller (fake native bridge) and golden-image tests
packages/shellkit/          Flutter plugin with the native services
  pigeons/messages.dart     Dart↔Swift contract
  macos/Core/               pure Swift, also a SwiftPM package (swift test)
  macos/Classes/            Flutter glue: panels, host APIs, dock menu, window previews
docs/                       ADRs and the theme JSON schema
tools/                      wallpaper and app-icon generators
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [CHANGELOG.md](CHANGELOG.md) for release notes.

### Releasing a signed build

1. In Xcode (`app/macos/Runner.xcworkspace` → Runner target → Release), set your team, the *Developer ID Application* identity and **Hardened Runtime = Yes**. Hardened runtime is off in the repository because it breaks ad-hoc-signed builds.
2. Run `make release`.
3. Notarize with `xcrun notarytool submit … --wait`, then run `xcrun stapler staple` on the app or DMG.

## Known limitations

- Other apps' title bars, fonts and controls can't be themed; that would need disabling SIP ([ADR-0001](docs/adr/0001-shell-overlay-not-system-modification.md)).
- There are no virtual workspaces, window overview or ⌘Tab replacement: they need broad control of other apps, which the app deliberately avoids ([ADR-0012](docs/adr/0012-interface-only-scope.md)).
- The dock and launcher appear on the main display only; the top bar appears on every display.
- Quick settings show status only (and toggle dark mode); they don't control Wi-Fi, volume or power.
- No automatic updates yet.

## Contributing

Bug reports, themes and pull requests are welcome; please read [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md) first.

## Security

Please report vulnerabilities privately as described in [SECURITY.md](SECURITY.md), not in public issues.

## License

[MIT](LICENSE) © 2026 Ponleu Koem
