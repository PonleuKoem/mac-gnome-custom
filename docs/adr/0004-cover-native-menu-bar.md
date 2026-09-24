# ADR-0004: Cover the native menu bar instead of auto-hiding it

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §2, §4.1 · ADR-0001

## Context

The GNOME top bar has to sit where the macOS menu bar is. macOS gives third-party bars no way to reserve screen space (unlike X11's `_NET_WM_STRUT`), so `NSScreen.visibleFrame`, which apps use when zooming or maximizing, only takes the native menu bar and Dock into account.

Complications:
- Notched MacBooks have a taller menu bar (it follows the notch safe area).
- On macOS 26 the menu bar is transparent by default.
- App menus (File/Edit/…) must stay reachable; we re-host them via AX (DESIGN.md §4.4 MenuService).
- Menus opened from the keyboard (Cmd+? Help, Ctrl+F2) draw at popup level.

## Decision

Keep the native menu bar **visible**, and cover it on each screen with an **opaque `NSPanel` at `.statusBar` level**, sized exactly to the menu bar's height. Opaque includes our own blur: nothing may show through. Hide our bar when the screen's frontmost window is fullscreen.

## Options Considered

### Option A: Cover the visible menu bar (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low: one panel per screen, height read from the system |
| Cost | None ongoing |
| Scalability | Works per screen, including notch geometry |
| Team familiarity | Medium |

**Pros:** `visibleFrame` still leaves out the bar strip, so maximized windows stop below it automatically; no window fighting; keyboard-opened native menus still appear (above us).
**Cons:** bar height is fixed to the menu bar's height (a GNOME bar is ~32 px, close to macOS); if our panel fails to draw, the native bar shows (a graceful failure); macOS can momentarily reveal the native bar, e.g. during Space-switch animations.

### Option B: Auto-hide the menu bar (`_HIHideMenuBar`) + draw our bar + nudge windows
| Dimension | Assessment |
|-----------|------------|
| Complexity | High: every window move/resize has to be watched and corrected |
| Cost | CPU on each AX move event; visible "snap back" on zoom |
| Scalability | Worse with many windows and apps that fight moves |
| Team familiarity | Medium |

**Pros:** any bar height; bar can go at the bottom.
**Cons:** hovering at the top edge reveals the native bar *over* ours; windows slide under our bar until nudged.

### Option C: Keep the native menu bar and add our widgets as status items
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low |
| Cost | Low |
| Scalability | Limited by the menu bar's right side |
| Team familiarity | High |

**Pros:** fully native, zero risk.
**Cons:** not a GNOME bar: no Activities button on the left, no centered clock, no theming of the bar itself.

## Trade-off Analysis

A gets a correct work area for free, and the rest of the design depends on that. B's extra flexibility (custom height, bottom bar) is paid for with constant window correction and a visible conflict at the top edge. C is too limited. A bottom bar (Windows-style preset) can still be done with Option B's nudge logic later, scoped to that preset only.

## Consequences

- **Easier:** window layout, workspace frame restoration, fullscreen handling.
- **Harder:** bar height is not freely themable. The theme's `topBar.height` accepts `"menubar"` only in v1.
- **Revisit:** bottom or side bars for non-GNOME presets (would need Option B's nudge logic); macOS changes to menu-bar layering.

## Action Items

1. [ ] Verify on a notched MacBook and an external display, with macOS 26's transparent bar.
2. [ ] Confirm keyboard-invoked native menus and Help search still appear above the panel.
3. [ ] Detect fullscreen (`AXFullScreen`) per screen and hide our bar.
4. [ ] Put this behind the feature flag `menuBar.cover`.
