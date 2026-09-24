# ADR-0003: One Flutter engine driving several native panels (multi-view)

**Status:** Accepted (validated 2026-09-24 by the multi-view self-check: 1 engine → 7 views, 6/6 surfaces mapped, clean shutdown)
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §4.1, §4.2, §11 (S1) · ADR-0002

## Context

The shell has 5–7 surfaces showing at once: a top bar per screen, dock, overview, app grid, switcher, popovers and the Customizer. Each has to be its own `NSPanel`, because each needs its own window level, collection behaviour, key-window rules and frame. All of them read the same state (windows, apps, workspaces, theme).

Flutter's macOS embedder supports attaching several `FlutterViewController`s to one `FlutterEngine`. Dart can render into each `FlutterView` via `runWidget(ViewCollection(...))`. The high-level multi-window API (`RegularWindow` and related) is still experimental and doesn't expose panel levels or collection behaviours. As of Flutter 3.35 the multi-view path is less well-trodden than single-view.

## Decision

Run **one `FlutterEngine` with one `FlutterViewController` per surface panel**. Native code creates and configures every panel. At startup Dart receives a `viewId → surface` registry and renders the matching widget tree into each view. State lives once, in one isolate.

**Fallback if S1 fails:** one engine per surface, with state mirrored through ShellKit as the single source of truth.

## Options Considered

### Option A: Single engine, multiple views (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium: less-documented API, view registry plumbing |
| Cost | One Dart heap and one set of assets; lowest memory |
| Scalability | Adding a surface means adding a panel and a registry entry |
| Team familiarity | Low: few examples in the wild |

**Pros:** shared Riverpod stores with no syncing; one theme instance; lower RAM.
**Cons:** engine-level bugs affect every surface; jank in one surface (e.g. a heavy Customizer rebuild) can delay frames in the others, since they share a UI thread.

### Option B: One engine per surface
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium: state has to be mirrored across isolates |
| Cost | Tens of MB per engine; 6 engines could exceed the 300 MB budget |
| Scalability | Worse: every new surface costs memory and another sync path |
| Team familiarity | Medium: single-view per engine is the common case |

**Pros:** isolation, since one surface can't jank another; well-trodden path.
**Cons:** memory; consistency bugs (overview shows a stale window list while the top bar is up to date).

### Option C: Experimental Flutter multi-window API
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low in Dart |
| Cost | Low |
| Scalability | Unknown |
| Team familiarity | Low |

**Pros:** window creation from Dart.
**Cons:** no control over `NSWindow.Level`, `collectionBehavior`, `nonactivatingPanel`, or `canBecomeKey`, all of which the shell requires. The API is also still changing.

## Trade-off Analysis

The shell is state-heavy and every surface reflects the same window/app/workspace data, which strongly favours one isolate (A). B's isolation benefit is real but costs memory and brings consistency bugs we'd have to engineer away. C lacks the window-level control that makes a shell work. A carries the most *unknown* risk, so it's gated on a spike with a known fallback.

## Consequences

- **Easier:** state management; theme hot reload applies to every surface at once.
- **Harder:** avoiding main-isolate jank. Heavy work (theme validation, fuzzy search over 500 apps) must go to `Isolate.run`.
- **Revisit:** if the Customizer's rebuild cost hurts the bar's frame times, move the Customizer to its own engine (a hybrid of A and B).

## Action Items

1. [x] Multi-view self-check (`MGC_SPIKE_S1=1`): 3 transparent panels at different levels, one engine, shared counter. Measure memory and frame times.
2. [ ] Test S1 for key focus (typing into the overview search while another app stays active) and panel resizing.
3. [ ] If S1 fails, record the reason here, mark this ADR superseded, and write ADR for Option B.

## Implementation notes (2026-09-24)

- Flutter 3.35's macOS embedder only allows several `FlutterViewController`s per engine after calling
  the **non-public** `-[FlutterEngine enableMultiView]` before the first controller is attached
  (`ShellKitEntry.makeEngine()`). It is looked up with `responds(to:)`; if a future Flutter removes it
  we fall back to Option B. Track the public multi-window API and switch when it exposes window levels.
- Flutter 3.35 also runs Dart on the platform (main) thread ("merged UI and platform thread"). This
  makes the ADR-0002 rule — AX work and the event tap never on the main thread — even more important.
- Each panel hosts a minimal `MaterialApp` (Overlay, text editing, localizations); the Dart side maps
  `FlutterView.viewId → SurfaceSpec` pushed from native (`SurfacesChangedEvent`).
