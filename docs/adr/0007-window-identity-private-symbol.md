# ADR-0007: Accept one private symbol (`_AXUIElementGetWindow`) for window identity

**Status:** Superseded by [ADR-0012](0012-interface-only-scope.md) (2026-09-24) — removed with all window control.
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §4.4 · ADR-0001, ADR-0006

## Context

Two public APIs describe the same windows but don't link them:
- **AX (`AXUIElement`)**: lets us *act* on a window (move, focus, close) and observe events, but gives no stable numeric ID.
- **CGWindowList / ScreenCaptureKit**: gives a stable `CGWindowID` and thumbnails, but no way to act.

The overview has to map "this thumbnail" to "this AX element", and workspace state needs a stable key. `_AXUIElementGetWindow(AXUIElementRef, CGWindowID*)` is an unexported function in the public ApplicationServices framework. AltTab, Rectangle, Hammerspoon, AeroSpace and yabai have all relied on it for years.

ADR-0001 says "no private frameworks". This ADR records a deliberate, contained exception.

## Decision

Use `_AXUIElementGetWindow` through a `WindowIdentityResolving` protocol, loaded with `dlsym` at runtime so a missing symbol degrades gracefully instead of crashing. Ship a **heuristic fallback resolver** that matches on pid + frame (±2 px) + title against `CGWindowListCopyWindowInfo`, and switch to it automatically if the symbol isn't found.

## Options Considered

### Option A: Private symbol + heuristic fallback (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low: one call, isolated behind a protocol |
| Cost | Small risk that Apple removes the symbol |
| Scalability | O(1) per window |
| Team familiarity | Medium: widely used in open-source window managers |

**Pros:** exact, fast, stable IDs.
**Cons:** technically private; could disappear in a future macOS.

### Option B: Heuristic matching only
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium |
| Cost | Mismatches when two windows of one app share a title and frame (e.g. two new Terminal windows) |
| Scalability | O(n) per lookup |
| Team familiarity | High |

**Pros:** 100% public API.
**Cons:** wrong thumbnails or wrong window focused in real, common cases.

## Trade-off Analysis

Exact identity underpins the overview, switcher and workspaces, and B's failure mode (focusing the wrong window) is a correctness bug users will notice. A's risk is low (the symbol has been stable for over 10 years), and the fallback limits the damage to "occasionally imprecise" rather than "broken". The exception doesn't need an entitlement and doesn't affect notarization.

## Consequences

- **Easier:** one `id` field across Dart, thumbnails and persistence.
- **Harder:** we have to watch for the symbol disappearing. Diagnostics shows which resolver is active.
- **Revisit:** if Apple ships a public equivalent, or if the symbol is removed.

## Action Items

1. [ ] Implement `PrivateSymbolResolver` (dlsym) and `HeuristicResolver`; choose at startup.
2. [ ] Unit-test the heuristic resolver with fixture window lists (duplicate titles, same frames).
3. [ ] Show the active resolver on the Diagnostics page.

## Implementation notes (2026-09-24)

`dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow")` resolves on macOS 26.6 (`shellkit-probe permissions`
prints the active resolver; the Diagnostics page shows it too).
