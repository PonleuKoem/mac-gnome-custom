# ADR-0008: A typed Pigeon bridge: request/response APIs plus one delta event stream

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §4.3 · ADR-0002, ADR-0003

## Context

Dart and ShellKit exchange about 30 operations (focus a window, launch an app, set wallpaper…) and a high-frequency flow of OS events: an AX move storm of ~120/s during a drag, focus changes, app launches, battery and volume, hotkeys. Thumbnails are large binary data (~400 KB raw per tile). Hand-written `MethodChannel` code is stringly typed and drifts between the two languages.

## Decision

- **Pigeon** generates every contract (`@HostApi` for Dart→Swift calls, `@EventChannelApi` for Swift→Dart streams) from one `pigeons/shell_api.dart` file.
- **One event stream** (`ShellEvents`) carries a sealed `ShellEvent` union. Window updates are **deltas** (`upserted` / `removed`), and there's a `list()` call for resyncing.
- Swift **coalesces** AX events in 16 ms buckets and sends only the latest state per window.
- **Thumbnails travel by request**, never on the event stream. They're sent as raw BGRA plus dimensions (no PNG encoding, to save 10–30 ms per tile), and can move to Flutter external textures later.

## Options Considered

### Option A: Pigeon + delta events (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low–medium: codegen step |
| Cost | Build step; Pigeon version upgrades |
| Scalability | Deltas keep traffic proportional to change, not to window count |
| Team familiarity | Medium: standard Flutter tooling |

**Pros:** compile-time safety on both sides; one place to read the whole API; easy to mock in tests.
**Cons:** codegen friction; sealed-class support depends on the Pigeon version, so check during S1.

### Option B: Hand-written MethodChannel/EventChannel with maps
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low at first, high over time |
| Cost | Drift bugs |
| Scalability | Same |
| Team familiarity | High |

**Pros:** no codegen.
**Cons:** stringly typed, no refactoring safety, duplicated models.

### Option C: dart:ffi to a C ABI exported from Swift
| Dimension | Assessment |
|-----------|------------|
| Complexity | High |
| Cost | Manual memory management; callbacks into isolates |
| Scalability | Lowest latency |
| Team familiarity | Low |

**Pros:** synchronous, zero-copy possible.
**Cons:** far too much ceremony for what's mostly low-rate control calls.

## Trade-off Analysis

The bridge carries control traffic plus one bursty stream, which is exactly what channels handle well. Pigeon removes B's main weakness at little cost. C's speed only matters for thumbnails, and those are better served by external textures than by FFI.

## Consequences

- **Easier:** refactors; fake ShellKit for widget tests; reading the full contract in one file.
- **Harder:** every API change needs a regeneration step, so add it to a `make gen` target and CI.
- **Revisit:** external textures (`FlutterTexture`) for live previews; splitting streams if one busy stream becomes a bottleneck.

## Action Items

1. [ ] Write `pigeons/shell_api.dart`; generate into `lib/bridge/` and `ShellKit/Bridge/`.
2. [ ] Implement 16 ms coalescing in `WindowService` and test it with a synthetic move storm.
3. [ ] Change `thumbnail()` to return `{width, height, bytesPerRow, bgra}` (update DESIGN.md §4.3).
4. [ ] CI check that the generated files are up to date.
