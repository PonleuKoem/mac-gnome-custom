# ADR-0012: Interface-only scope — no privileged access to other apps or the system

**Status:** Accepted (2026-09-24, after a security review)
**Deciders:** Maintainers
**Supersedes:** ADR-0006 (virtual workspaces), ADR-0007 (private window-identity symbol); narrows ADR-0004 (no re-hosted app menus) and ADR-0005/0010 (nothing to unpark)
**Related:** [SECURITY.md](../../SECURITY.md) (security model)

## Context

A security review asked whether the app behaves "like a jailbreak". The decision is that it should customize **only the Mac interface**, with every feature that needs broad control of the system or other apps removed.

It never was a jailbreak: no SIP changes, no root, no kernel or system extensions, no code injection, no network. But v0.1 used powerful capabilities beyond appearance:

| Capability | Permission | Used for |
|---|---|---|
| CGEventTap (sees every keystroke, can swallow keys) | Accessibility | ⌘-tap, ⌘Tab replacement |
| Accessibility control of other apps (move/raise/close windows, press menu items) | Accessibility | Workspaces, overview, app menus |
| ScreenCaptureKit window images | Screen Recording | Overview thumbnails |
| Synthesized ⌃⌘Q, `pmset sleepnow`, loginwindow log-out/restart/shutdown, Wi-Fi power, volume/mute | Automation / none | Quick settings |
| `_AXUIElementGetWindow` (private) | — | Window identity |

## Decision

The app is an **interface customizer**. It may:

- draw its own top bar, dock and launcher panels;
- open or bring forward apps through LaunchServices (as the Dock does), and from the dock's native right-click menu hide, quit or (with ⌥) force-quit an app and show it in Finder (public `NSRunningApplication` / `NSWorkspace`, as the Dock does). From the same menu the user may also toggle **Open at Login** (System Events, the Automation permission dark mode already uses; only on an explicit choice) and **Show All Windows** (after activating the app, the shell runs Apple's own Mission Control app in its App Exposé mode, argument `2`; the shell calls no private API and reads no window data, and macOS draws the previews). The menu has no window list (titles need Screen Recording) and no app-provided items (private Dock IPC);
- change **appearance** settings the user picks: Dock auto-hide, wallpaper, dark mode (via System Events, Automation prompt), accent colour — snapshotted, journaled, reversible;
- keep windows clear of an always-visible shell dock by leaving the **native Dock visible as a spacer** (its size, edge and magnification set to match, the shell's dock drawn over it). macOS has no public API for a third-party window to reserve screen space, and resizing other apps' windows would need Accessibility; the native Dock is the only public way. These Dock keys are runtime-scoped: restored on quit and by the guardian;
- read status for display: battery, volume level, Wi-Fi on/off, running apps, mouse position (hot corner), and **how many windows an app has open** for the dock's hover label (window-server metadata — owner, layer, size — never titles or contents, which need Screen Recording);
- register **global shortcuts only through `RegisterEventHotKey`**, which delivers exactly the registered chords and nothing else.

It must **not**: read keystrokes, capture the screen or other apps' windows, move/close/click anything inside other apps, synthesize input, change volume/Wi-Fi/power, lock or log out, use private Apple APIs, or connect to the network.

Consequently the app needs **no Accessibility and no Screen Recording permission** — with one opt-in exception below.

### Opt-in exception: window previews

Users want small pictures of an app's windows on hover, to switch to one specific window. That is impossible without both permissions, so it exists only as an **opt-in feature, off by default** (Customizer → Windows & privacy → *Window previews*, flag `windowThumbnails`):

- **Screen Recording:** list the hovered app's windows (titles) and capture small thumbnails, on demand while its dock icon is hovered; kept in memory for that card only, never stored or sent.
- **Accessibility:** raise the one window the user clicked (un-minimizing it). Windows are matched by frame and title — no private window-id API. With Accessibility alone (Screen Recording not granted yet) the card lists the windows by title, without pictures, and clicking still works.
- Every native entry point re-checks the flag and the permissions; turning the switch off stops all of it (the user can also revoke the permissions in System Settings). The permission prompts appear only when the user turns it on.
- **Discoverability (2026-09-24):** with previews off, the hover card shows one placeholder per open window (from the permission-free count) and a *Turn on previews…* button; the user's click turns the flag on, lets macOS show its prompts and opens the Windows & privacy page. The "N windows — show all" link to App Exposé was removed from the card (it proved unreliable); *Show All Windows* stays in the right-click menu.
- **Signing:** `make install` signs with the builder's Apple Development identity when one exists, so macOS keeps these permissions across reinstalls (an ad-hoc signature looks like a new app every build).

## Options considered

| Option | Keeps | Risk |
|---|---|---|
| **A. Interface-only (chosen)** | Top bar, dock, launcher + search, themes, wallpaper, dark mode, accent, Dock hiding | Lowest: no privileged TCC permissions |
| B. Opt-in advanced features | Everything, off by default | Privileged code still shipped; one toggle away |
| C. Remove only system controls | Workspaces, overview, ⌘Tab, thumbnails | Accessibility + Screen Recording + keyboard monitoring remain |

## Consequences

- **Removed:** virtual workspaces, window overview and thumbnails, ⌘Tab / ⌘` switcher, lone-⌘ tap, app menus in the top bar, power/lock/Wi-Fi/volume controls, the probe CLI, the private symbol.
- **Changed:** "Activities" is now an app launcher (search + grid + dash). Default shortcuts are ⌥Space and ⌃⌥Space (not ⌃Space, which switches input sources). Themes that still say `superTap` get a warning and the default chord.
- **Simpler safety:** the guardian only restores the Dock; nothing is ever parked off-screen.
- **Full-screen apps:** panels no longer join other apps' full-screen spaces (`.fullScreenAuxiliary` dropped), so the shell never inspects other windows to decide when to hide.
- **Remaining non-public API:** `FlutterEngine.enableMultiView` — Flutter's, not Apple's; it affects only this app's own rendering (ADR-0003).
- **Revisit:** if a future macOS offers public, permission-free APIs for window overviews, reconsider.
