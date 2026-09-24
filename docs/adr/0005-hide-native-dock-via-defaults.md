# ADR-0005: Hide the native Dock with preferences; never kill or unload it

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §2, §4.8 · ADR-0010

## Context

Our own dock/dash replaces the native Dock. The Dock process (`com.apple.dock`) is more than the icon strip, though: it also runs **Mission Control, Spaces, Launchpad, hot corners and part of window minimizing**. launchd restarts it whenever it exits.

## Decision

Hide the Dock visually by writing, through SafetyService (journaled and reversible):

```
com.apple.dock autohide              = true
com.apple.dock autohide-delay        = 1000     # seconds before reveal
com.apple.dock autohide-time-modifier= 0
```

then run `killall Dock`, which **restarts** it with the new settings. The Dock process always keeps running.

## Options Considered

### Option A: autohide + huge delay (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low |
| Cost | None |
| Scalability | N/A |
| Team familiarity | High: widely used trick |

**Pros:** Mission Control, Spaces and minimize animations keep working; fully reversible.
**Cons:** the Dock can still appear in some edge cases (e.g. hitting the edge while dragging a file); visible Dock restart flicker when applying.

### Option B: Unload or kill the Dock permanently
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium: fighting launchd, and SIP protects the launch agent |
| Cost | Breaks Mission Control, Spaces and minimize |
| Scalability | — |
| Team familiarity | Low |

**Pros:** Dock never appears.
**Cons:** breaks core OS features; a crash leaves the user badly stranded.

### Option C: Keep the native Dock and just theme its size/position
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low |
| Cost | None |
| Scalability | — |
| Team familiarity | High |

**Pros:** zero risk.
**Cons:** two docks, or no custom dock.

## Trade-off Analysis

A gives almost everything B does (the Dock is out of sight) without breaking the OS. The leftover edge cases are cosmetic. C doesn't meet the goal.

## Consequences

- **Easier:** restore is just rewriting three preferences and restarting the Dock.
- **Harder:** the user has no Dock if our shell crashes, which is why the guardian (ADR-0010) exists.
- **Revisit:** check each macOS release that `autohide-delay` is still honoured.

## Action Items

1. [ ] Implement as a journaled `SystemMutation` in SafetyService.
2. [ ] Debounce `killall Dock`: at most once per 500 ms of theme edits.
3. [ ] Feature flag `dock.hideNative`.
