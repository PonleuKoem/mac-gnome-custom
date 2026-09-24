# ADR-0006: Virtual workspaces built by parking windows off-screen

**Status:** Superseded by [ADR-0012](0012-interface-only-scope.md) (2026-09-24) — removed with all window control.
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §4.7 · ADR-0001, ADR-0007

## Context

GNOME workspaces are dynamic (there's always one empty workspace at the end), switch instantly, and appear as a strip in the overview. macOS Spaces have **no public API** to create, delete, switch, or move windows between them. The private SkyLight/CGS calls that yabai uses need SIP partly disabled on recent macOS for the operations we'd need, which ADR-0001 rules out. Mission Control's own animation is slow and can't be themed.

## Decision

Implement workspaces entirely in the app: all managed windows live on **one native Space**. Windows on inactive workspaces are **parked**: moved via AX so that only 1 px remains on-screen at the screen's bottom-right corner (macOS clamps windows that are fully off-screen), with their real frame saved. Switching unparks the target workspace's windows and parks the rest. This follows the approach proven by AeroSpace.

Invariant: **on quit, restore, or guardian recovery, every parked window is unparked.**

## Options Considered

### Option A: Off-screen parking (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium: frame bookkeeping, persistence, per-app quirks |
| Cost | AX moves on each switch (N windows × ~1–5 ms) |
| Scalability | Fine up to ~100 windows; switch time grows linearly |
| Team familiarity | Medium: AeroSpace is open source to learn from |

**Pros:** full control (dynamic workspaces, custom animations, per-display rules); no private APIs; works in a normal Space.
**Cons:** possible 1-frame flicker; some apps (a few Electron/Java apps) fight moves; parked windows still show in native Mission Control and Cmd+` cycling (which we swallow).

### Option B: Native Spaces via private SkyLight APIs
| Dimension | Assessment |
|-----------|------------|
| Complexity | High |
| Cost | Breaks with OS updates; needs SIP partly off for window→space moves |
| Scalability | Native |
| Team familiarity | Low |

**Pros:** real Spaces with native animations and Mission Control consistency.
**Cons:** violates ADR-0001.

### Option C: Minimize/hide inactive windows
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low |
| Cost | Minimize animation per window: slow |
| Scalability | Poor: switching takes seconds |
| Team familiarity | High |

**Pros:** simple, uses only public API.
**Cons:** slow, noisy animations; floods the minimized list; `NSRunningApplication.hide()` hides every window of the app, not per workspace.

## Trade-off Analysis

B is the "right" integration but is off the table. C is too slow to feel like GNOME. A is fast and flexible, and the known problem apps can be handled per app: fall back to C (minimize) for bundle IDs in a quirks list.

## Consequences

- **Easier:** GNOME-style dynamic workspaces, a workspace strip in the overview, drag-to-workspace, per-preset behaviour.
- **Harder:** crash safety (parked windows would be "lost" in the corner), which the guardian must handle; users with several native Spaces get confusing results, so onboarding recommends a single Space.
- **Revisit:** if Apple ever adds a public Spaces API; per-display independent workspaces (v2).

## Action Items

1. [ ] Spike S6: park and unpark 10 windows from 6 apps, measure switch time (< 150 ms) and frame accuracy.
2. [ ] Build a per-bundle quirks table (`park: minimize | skip | move`).
3. [ ] Persist `workspace-state.json` every 5 s when dirty; guardian reads it to unpark.
4. [ ] Swallow Cmd+` so parked windows aren't cycled into view.
