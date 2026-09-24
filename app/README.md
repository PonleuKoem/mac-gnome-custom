# mac-gnome-custom app

The Flutter application: every surface (top bar, dock, Activities launcher, popovers, Customizer) and the shell's policy. Native services come from [`packages/shellkit`](../packages/shellkit).

See the [repository README](../README.md) for installation and usage, and [CONTRIBUTING.md](../CONTRIBUTING.md) for the development workflow.

| Path | Contents |
|---|---|
| `lib/main.dart` | One engine, one Flutter view per native panel |
| `lib/src/core/` | `ShellController` (policy), stores, icon cache, algorithms |
| `lib/src/theme/` | Theme parser, repository (`extends`, import/export), store (per-theme overrides) |
| `lib/src/surfaces/` | Top bar, dock, Activities launcher, popovers |
| `lib/src/customizer/` | Customizer window |
| `assets/themes/` | Built-in themes |
| `test/` | Unit, controller (fake native bridge) and golden-image tests |
