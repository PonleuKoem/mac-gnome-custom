# ADR-0001: Build a shell overlay rather than modifying macOS itself

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §2, §9 · ADR-0004, ADR-0005, ADR-0006

## Context

The goal is to change "the full Mac interface" to any look, starting with GNOME. On macOS 11 and later, the system volume is sealed and System Integrity Protection (SIP) protects Dock.app, SystemUIServer, WindowServer and every Apple app. Two approaches have been used in practice:

1. **Modify the system**: disable SIP (partly or fully) and inject code into Dock/WindowServer or into every app (yabai's scripting addition, MacForge/mySIMBL plugins). This can restyle anything, including other apps' title bars and controls.
2. **Overlay a shell**: leave macOS untouched and draw replacement surfaces (bar, dock, launcher, switcher, overview) as our own windows. Native surfaces get hidden or covered through supported preferences, and other apps' windows are controlled through public Accessibility APIs. SketchyBar, AeroSpace, AltTab, Raycast and Übersicht all work this way.

The project is maintained by a single developer. The app should survive macOS point updates and be installable by a normal user.

## Decision

Use **Option B: shell overlay**. Restyling other apps' window chrome, fonts and controls is **explicitly out of scope**. The DESIGN.md §2 capability table is the product contract.

## Options Considered

### Option A: SIP-off + code injection
| Dimension | Assessment |
|-----------|------------|
| Complexity | High: reverse-engineering private Dock/WindowServer internals, per-architecture injection |
| Cost | High ongoing: breaks on most macOS releases, and sometimes on point updates |
| Scalability | Poor: every user must boot into Recovery and weaken security |
| Team familiarity | Low: niche expertise, little documentation |

**Pros:** truly "everything" can change (title bars, fonts, native Spaces, Dock internals).
**Cons:** security downgrade for the user; iOS-app and Apple Pay features stop working with SIP off; fragile; no notarization story; hard to support.

### Option B: Shell overlay (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium: public AppKit/AX/ScreenCaptureKit APIs plus a few well-known preference tricks |
| Cost | Low–medium upkeep: preference tricks need a re-check each macOS release |
| Scalability | Good: installs like a normal app, notarizable |
| Team familiarity | Medium: AppKit + AX documented, with several open-source reference apps |

**Pros:** safe, shippable, reversible; each surface is proven by existing apps.
**Cons:** can't restyle other apps; some seams stay visible (Mission Control, system alerts, native menus' look).

### Option C: Theme only what `defaults` exposes (wallpaper, accent, dark mode, Dock size)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low |
| Cost | Low |
| Scalability | Good |
| Team familiarity | High |

**Pros:** trivial, zero risk.
**Cons:** can't deliver the GNOME experience at all. No top bar, overview or workspaces.

## Trade-off Analysis

A gives the most visual coverage but fails the constraints that matter most for a solo project: survival across updates, and not asking users to weaken security. C is safe but misses the goal. B delivers roughly 80% of the *felt* experience, since the shell is what you touch all day, at a sustainable cost. The 20% it gives up (other apps' chrome) is also the part that changes most often across macOS versions.

## Consequences

- **Easier:** distribution (notarized DMG), onboarding, recovering from bugs (quit the app and macOS is back).
- **Harder:** anything that needs a supported API that doesn't exist (Spaces, reserving screen area). Each one needs an emulation (ADR-0004, ADR-0006).
- **Revisit:** an opt-in "advanced mode" with private APIs, if users ask for native Spaces integration.

## Action Items

1. [ ] Keep DESIGN.md §2 as the scope contract. Reject feature requests that need injection.
2. [ ] Put each OS "trick" (menu-bar cover, Dock hide, Super-tap) behind its own feature flag.
3. [ ] Add a per-macOS-release smoke-test checklist (run during each June beta).
