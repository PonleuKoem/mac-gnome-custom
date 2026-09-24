# Security

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Report them privately through GitHub's [private vulnerability reporting](https://github.com/PonleuKoem/mac-gnome-custom/security/advisories/new) (Security → Report a vulnerability).

Include the macOS version, the app version or commit, steps to reproduce and the impact you observed. You can expect an acknowledgement within a week. Fixes are released as soon as practical and credited in the changelog unless you prefer otherwise.

Only the latest commit on `main` is supported.

## Security model

mac-gnome-custom customizes the macOS **interface only** ([ADR-0012](docs/adr/0012-interface-only-scope.md)). It is an ordinary user-level app.

### What it never does

| Capability | Status |
|---|---|
| Disabling SIP, anything in Recovery, patching system files | Never |
| Running as root, `sudo`, privileged helpers (`SMJobBless`, `AuthorizationExecute`) | Never |
| Kernel, driver or system extensions | Never |
| Injecting code into other processes | Never |
| Network connections, telemetry | Never |
| Reading keystrokes (event taps) | Never. Global shortcuts use `RegisterEventHotKey`, which delivers only the registered combinations and needs no permission. |
| Synthesizing input, controlling power, volume or Wi-Fi | Never |
| Private Apple APIs | None used |

### Permissions

| Permission | Used for | When |
|---|---|---|
| Automation (System Events) | Switching dark mode, with a fixed AppleScript containing no user or theme input | The first time a theme changes dark mode |
| Accessibility | Raising the one window the user clicks in a dock hover card | Only with the opt-in *window previews* feature |
| Screen Recording | Small pictures of an app's windows while its dock icon is hovered; kept in memory for that moment, never written to disk or sent | Only with the opt-in *window previews* feature |

Window previews are **off by default**. Every native entry point (`WindowThumbnails.swift`) re-checks the feature flag and the permissions; with the feature off nothing is captured or controlled and macOS never shows either prompt.

### Remaining attack surface

| Item | Why it's needed | Mitigation |
|---|---|---|
| Not sandboxed | Writing the Dock's preferences and setting the wallpaper aren't possible from the App Sandbox | Only an allow-list of preference keys is ever written. Every change goes through `SafetyService`: snapshot first, then journal; fully reversible. |
| Writes `com.apple.dock` keys, `AppleAccentColor`, `AppleHighlightColor` and the wallpaper; restarts the Dock | Applying a theme | Undone on quit, on crash (guardian) and by *Restore macOS to original*. |
| Theme packs (`.mgctheme` zip files) from untrusted sources | Sharing themes | Paths escaping the theme folder (zip-slip) and absolute paths are rejected; the declared size is capped at 200 MB and checked before extraction, which runs off the UI thread. A theme can only set colours, layout, four appearance settings and shortcuts. Wallpapers are only displayed. |
| Global pointer-position and click-location monitors | Hot corner, dismissing popovers, dock click-through | They observe pointer location only — no keys or content — and need no permission. |
| Crash guardian (background process) | Restoring the Dock if the shell dies | Same binary and signature; it only signals its own parent process, and a lock file ensures a single instance. |
| `FlutterEngine.enableMultiView` (non-public Flutter API) | Rendering several panels from one engine | Flutter's API, not Apple's; affects only this app's own drawing ([ADR-0003](docs/adr/0003-single-flutter-engine-multi-view.md)). |
| `MGC_SUPPORT_DIR` and `MGC_NO_NOTIFY` environment variables | Tests | Anyone able to set this app's environment can already run code as the user. |
| Debug builds expose the Dart VM service on localhost | Development | Not present in release builds. |

### Distributing builds

Builds from `make install` are for local use. Anything distributed to others should be signed with a Developer ID, built with the hardened runtime and notarized (see the README).
