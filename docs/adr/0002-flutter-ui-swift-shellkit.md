# ADR-0002: Flutter for presentation, a Swift "ShellKit" package for OS integration

**Status:** Accepted (Flutter is a project constraint)
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §3, §4.4, §10 · ADR-0003, ADR-0008

## Context

The app is to be built with Flutter. Nearly everything the shell does *to the OS*, though, has no Flutter plugin and can only be done natively: the AX API, CGEventTap, ScreenCaptureKit, NSWorkspace, IOKit, CoreAudio, CoreWLAN, `defaults`, and NSPanel window levels. We need a clear line so each layer stays testable and Dart doesn't turn into a thin wrapper around dozens of ad-hoc channels.

## Decision

- **Flutter/Dart owns presentation and policy:** every pixel of every surface, animation, theming, layout, and decisions such as which window to focus next or which workspace a window belongs to.
- **Swift owns truth and side effects:** all OS state, permissions, and anything that touches other processes or system preferences. It lives in a **standalone Swift package, `ShellKit`**, with no Flutter dependency, so it can be unit-tested with `swift test`. The Flutter `Runner` target only boots ShellKit and wires it to the bridge.
- Dart never shells out and never writes preferences directly.

## Options Considered

### Option A: Flutter UI + Swift ShellKit package (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium: two languages, one typed bridge |
| Cost | ~35–45% of the code in Swift |
| Scalability | Good: services reusable by the guardian and a future CLI |
| Team familiarity | Flutter is familiar; Swift/AppKit is a learning cost |

**Pros:** any look is possible; hot reload for UI iteration; native layer testable in isolation.
**Cons:** higher memory than pure native; two toolchains; text input and accessibility behave less like native macOS.

### Option B: Flutter-heavy (dart:ffi to C APIs, minimal Swift)
| Dimension | Assessment |
|-----------|------------|
| Complexity | High: AX and ScreenCaptureKit are CF/ObjC and async-block heavy, and awkward through FFI |
| Cost | Lower Swift count, much more fragile glue |
| Scalability | Poor: callbacks from AXObserver and event taps crossing into Dart isolates is error-prone |
| Team familiarity | Low |

**Pros:** "mostly Dart."
**Cons:** event taps must return in microseconds, and a Dart round-trip there is unacceptable. Callback lifetimes are hard to get right.

### Option C: Pure SwiftUI/AppKit
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium |
| Cost | Lowest memory, most native feel |
| Scalability | Good |
| Team familiarity | Lower |

**Pros:** one language, no bridge.
**Cons:** breaks the Flutter constraint; arbitrary theming (e.g. Windows 11 or GNOME looks) takes more work in SwiftUI.

## Trade-off Analysis

Option B tries to avoid Swift but moves the hardest real-time code (event taps, AX observers) into the least suitable place. Option C is technically cleanest but ignores the project's constraint. Option A matches each language to what it's good at, and the package boundary keeps the native half from becoming untestable glue inside `Runner/`.

## Consequences

- **Easier:** UI iteration; unit-testing services; reusing ShellKit in `mgc-guardian` (ADR-0010).
- **Harder:** maintainers need working knowledge of AppKit/AX; debugging spans two runtimes.
- **Revisit:** if Swift grows past ~50%, check whether some surfaces (such as the switcher) should be native.

## Action Items

1. [ ] Create `macos/ShellKit` as a local Swift package; add it to the Runner target.
2. [ ] Define service protocols (`WindowServicing`, `CaptureServicing`…) so tests can use fakes.
3. [ ] Add `swift test` to CI next to `flutter test`.
