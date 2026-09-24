# Contributing

Thanks for your interest in mac-gnome-custom. Bug reports, new themes, documentation fixes and code are all welcome.

## Before you start

- Search existing [issues](https://github.com/PonleuKoem/mac-gnome-custom/issues) first.
- For larger changes, open an issue to discuss the approach before writing code.
- Anything that needs new macOS permissions or touches other apps must fit the interface-only scope in [ADR-0012](docs/adr/0012-interface-only-scope.md); if it doesn't, propose an ADR first.
- Report security problems privately (see [SECURITY.md](SECURITY.md)).

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE) and that you will follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

Requirements: macOS 14+, Xcode 16+, Flutter 3.35+ (stable), CocoaPods.

```bash
git clone https://github.com/PonleuKoem/mac-gnome-custom.git
```

```bash
cd mac-gnome-custom && make test
```

```bash
make run
```

`make run` builds a debug version and launches it. The first launch shows onboarding; nothing on your Mac changes until you press **Start**, and quitting restores the Dock.

To keep development runs away from your real settings, point the app at a scratch folder:

```bash
MGC_SUPPORT_DIR=/tmp/mgc-dev app/build/macos/Build/Products/Debug/mac-gnome-custom.app/Contents/MacOS/mac-gnome-custom
```

If something goes wrong, `make restore` puts macOS back to the first-run snapshot.

## Project structure

- `app/`: the Flutter app. Every surface is drawn here and the shell's policy lives in `lib/src/core/shell_controller.dart`.
- `packages/shellkit/`: the Flutter plugin with the native macOS services.
  - `macos/Core/` is plain Swift, also buildable as a SwiftPM package.
  - `macos/Classes/` holds the Flutter glue.
- `packages/shellkit/pigeons/messages.dart`: the typed Dart↔Swift contract. After editing it, run `make gen` and commit both generated files.
- `docs/adr/`: architecture decision records. Add one for any decision that changes scope, permissions or architecture.

## Checks

Run these before opening a pull request; CI runs the same ones:

```bash
make analyze
```

```bash
make test
```

- **Golden images** (`app/test/goldens/`) are rendered with the macOS system font, so run them on macOS. After an intentional UI change, run `make goldens` and review the changed images in your diff. CI skips the pixel comparison, because fonts differ between macOS versions, but still renders every golden scene.
- **New behaviour needs tests:** controller tests use a fake native bridge (`app/test/support/fakes.dart`); Swift logic in `macos/Core/` gets XCTest cases.
- **Multi-view self-check:** after upgrading Flutter, run the app with `MGC_SPIKE_S1=1`. It reports how the engine's views map to native panels, then quits.

## Contributing a theme

Themes are pure data, so they're a great first contribution.

1. Create `app/assets/themes/<id>/theme.json` (and optional `wallpapers/`). Use [docs/theme.schema.json](docs/theme.schema.json) and the existing themes as references.
2. Add the folder to `app/pubspec.yaml` under `assets`, and the id to `builtInThemeIds` in `app/lib/src/theme/theme_repository.dart`.
3. Wallpapers must be your own work or openly licensed; say which in the pull request. Generated wallpapers live in `tools/`.
4. Run `make test`; the preset tests check that every built-in theme parses without warnings.

## Pull requests

- Keep each pull request focused on one change, and describe what changed and why.
- Match the surrounding code style: `dart format` (line length 120) and the existing Swift style.
- Update the README, the schema or an ADR when behaviour or scope changes, and add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).
- Include screenshots for visible UI changes.
