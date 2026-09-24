# ADR-0011: Ship outside the Mac App Store: non-sandboxed, Developer ID, notarized, Sparkle updates

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §8 · ADR-0001, ADR-0010

## Context

The shell needs to: control other apps' windows through AX, install a system-wide `CGEventTap`, write `com.apple.dock` and global preferences, send Apple Events to System Events, and register a LaunchAgent. The App Sandbox blocks writing other domains' preferences and effectively blocks AX control of other apps. App Review also rejects apps that replace system UI in this way.

## Decision

Distribute a **non-sandboxed, Hardened Runtime app signed with Developer ID and notarized**, as a DMG. Updates go through **Sparkle 2** (EdDSA-signed appcast). Entitlements: `com.apple.security.automation.apple-events` only; no sandbox.

## Options Considered

### Option A: Developer ID + notarization + Sparkle (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low–medium: notarytool in CI, appcast hosting |
| Cost | Apple Developer Program ($99/yr); static hosting for the appcast |
| Scalability | Fine for any number of users |
| Team familiarity | Medium |

**Pros:** every capability available; Gatekeeper-friendly; our own update schedule.
**Cons:** no App Store discovery or payments; we host updates ourselves.

### Option B: Mac App Store
| Dimension | Assessment |
|-----------|------------|
| Complexity | — |
| Cost | — |
| Scalability | — |
| Team familiarity | — |

**Pros:** discovery, trust, payments.
**Cons:** not possible: the sandbox and review rules forbid the core features.

### Option C: Unsigned / ad-hoc builds (personal use only)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Lowest |
| Cost | Free |
| Scalability | Local builds only |
| Team familiarity | High |

**Pros:** no Apple account needed during early development.
**Cons:** Gatekeeper warnings; **TCC grants (Accessibility, Screen Recording) reset whenever the signature changes**, so every rebuild asks for permissions again.

## Trade-off Analysis

B isn't viable. C is fine for spikes, but TCC churn quickly makes daily use painful, so switch to a stable signing identity (at least an Apple Development certificate) by Phase 1 and to Developer ID before sharing builds.

## Consequences

- **Easier:** full platform access; fast releases.
- **Harder:** we own update infrastructure and the trust story (clear permission explanations during onboarding).
- **Revisit:** Setapp or similar channels, if distribution becomes a goal.

## Action Items

1. [ ] Sign debug builds with a stable Apple Development identity from Phase 1.
2. [ ] CI: build → sign → `notarytool submit --wait` → staple → DMG, on tags.
3. [ ] Integrate Sparkle 2 with EdDSA keys (private key only in CI secrets).
4. [ ] Sign and notarize the `mgc-guardian` target as part of the same bundle.
