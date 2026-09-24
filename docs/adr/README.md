# Architecture Decision Records: mac-gnome-custom

These records capture the key decisions behind [DESIGN.md](../../DESIGN.md). To change a decision, add a new ADR that supersedes the old one. Don't edit accepted records in place.

| ADR | Decision | Status | Gate |
|-----|----------|--------|------|
| [0001](0001-shell-overlay-not-system-modification.md) | Shell overlay, not SIP-off injection | Accepted | — |
| [0002](0002-flutter-ui-swift-shellkit.md) | Flutter for presentation, Swift `ShellKit` for OS | Accepted | — |
| [0003](0003-single-flutter-engine-multi-view.md) | One Flutter engine, many native panels | **Accepted** (validated) | — |
| [0004](0004-cover-native-menu-bar.md) | Cover the visible menu bar | Accepted | Verify on notched and external displays |
| [0005](0005-hide-native-dock-via-defaults.md) | Hide the Dock with preferences, never kill it | Accepted | — |
| [0006](0006-virtual-workspaces-offscreen-parking.md) | Virtual workspaces via off-screen parking | **Superseded** by 0012 | — |
| [0007](0007-window-identity-private-symbol.md) | Accept `_AXUIElementGetWindow` (with fallback) | **Superseded** by 0012 | — |
| [0008](0008-pigeon-bridge-delta-events.md) | Pigeon bridge + delta event stream | Accepted | — |
| [0009](0009-declarative-theme-packs.md) | Declarative JSON theme packs | Accepted | — |
| [0010](0010-safety-snapshot-journal-guardian.md) | Snapshot + journal + guardian process | Accepted | — |
| [0011](0011-distribute-outside-app-store.md) | Developer ID + notarization + Sparkle | Accepted (Sparkle pending) | — |
| [0012](0012-interface-only-scope.md) | **Interface-only: no keyboard monitoring or system control; Accessibility and Screen Recording only for opt-in window previews** | **Accepted** | — |

## How the decisions depend on each other

```
0001 Overlay shell ──┬─► 0004 Cover menu bar
                     ├─► 0005 Hide Dock ───────┐
                     ├─► 0006 Virtual workspaces├─► 0010 Safety/guardian  (must ship before 0005/0006 go live)
                     └─► 0007 Private symbol ◄──┘ (0006 needs stable IDs)
0002 Flutter+Swift ──┬─► 0003 One engine, N views
                     └─► 0008 Pigeon bridge
0009 Theme packs ────────► 0010 (the `system` block goes through the journal)
0001 + 0010 ─────────────► 0011 Non-sandboxed distribution
```

## Review findings (2026-09-24)

> Design-stage review, kept for history. Items about workspaces, window parking, thumbnails and private symbols refer to features later removed by [ADR-0012](0012-interface-only-scope.md).

These came from reviewing DESIGN.md while writing the ADRs.

| # | Finding | Severity | Resolution |
|---|---------|----------|------------|
| 1 | Default keybinding `appGrid: cmd+a` overrode **Select All** in every app | High | Changed to `superDoubleTap` (GNOME's own gesture) in DESIGN.md §4.6 |
| 2 | `workspace.1: cmd+1` overrode tab/view switching in browsers, Finder and editors | High | Changed to `ctrl+1…9`; the conflict checker must flag macOS's "Switch to Desktop N" |
| 3 | Thumbnails were returned as PNG, adding 10–30 ms of encoding per tile against a < 100 ms overview budget | Medium | Raw BGRA + dimensions (ADR-0008) |
| 4 | The guardian heartbeat thread wasn't specified, so a hung main thread could go undetected | Medium | Heartbeat from the main run loop (ADR-0010) |
| 5 | Private `_AXUIElementGetWindow` contradicted the "no private frameworks" rule without saying so | Low | Recorded as an explicit exception with fallback (ADR-0007) |
| 6 | One shared Dart isolate means Customizer rebuilds can make the always-visible top bar jank | Low | Heavy work goes to `Isolate.run`; Customizer can move to its own engine if needed (ADR-0003) |
| 7 | Cmd+` still cycles into parked windows | Low | Swallow it in HotkeyService (ADR-0006) |

**Overall:** the architecture holds up. Its biggest risks are concentrated in three spikes (S1, S2, S6) that each have a documented fallback, and the single catastrophic failure mode (a stranded user) is covered before any native UI gets hidden. The main thing to watch is Phase 4 (4 weeks): if S6 finds many apps that resist parking, add a week there.
