# ADR-0010: A safety model built on snapshot, journal and an external guardian process

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §4.8 · ADR-0005, ADR-0006, ADR-0009

## Context

The running shell takes over critical system functions: the Dock is hidden (ADR-0005), Cmd+Tab is swallowed, and windows may be parked off-screen (ADR-0006). If the shell crashes or hangs, the user may be left with no Dock, no switcher, and windows stuck in a corner. That's the worst outcome this product can produce. Crashes are likely during development and plausible in production (AX calls into hung apps, engine bugs).

## Decision

Use three layers:

1. **Snapshot:** on first run, before any change, write `snapshots/original.json` with every preference we might touch. It's write-once and never overwritten.
2. **Journal:** every system change goes through `SafetyService.apply(mutation)`, which appends `{key, before, after, ts}` to `journal.jsonl`. Restore replays the journal in reverse, then enforces the snapshot.
3. **Guardian:** `mgc-guardian` is a separate, tiny Swift LaunchAgent (registered with `SMAppService.agent`) that links only the Safety and Workspace parts of ShellKit. It watches the shell with `kqueue NOTE_EXIT` plus a 1 s heartbeat:
   - unclean exit or 3 missed heartbeats → relaunch the shell
   - **3 crashes within 60 s** → restore the snapshot, unpark windows from `workspace-state.json`, `killall Dock`, and post a notification

Also: a **panic hotkey** (Ctrl+Opt+Cmd+Esc, registered by both processes) and a `--restore` CLI mode.

## Options Considered

### Option A: Snapshot + journal + external guardian (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium: second target, IPC heartbeat |
| Cost | ~1 week total |
| Scalability | Every new system mutation automatically becomes reversible |
| Team familiarity | Medium |

**Pros:** survives crashes, hangs and `kill -9`; recovery doesn't depend on the broken process.
**Cons:** a second binary to sign and ship; the guardian itself must be close to bug-free (keep it tiny).

### Option B: In-process restore (signal handlers / `applicationWillTerminate`)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low |
| Cost | Low |
| Scalability | — |
| Team familiarity | High |

**Pros:** simple.
**Cons:** doesn't run on hangs, `kill -9`, or many crash types, which are exactly the cases that matter.

### Option C: No system changes (never hide Dock/menu bar)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Lowest |
| Cost | — |
| Scalability | — |
| Team familiarity | — |

**Pros:** nothing to restore.
**Cons:** two docks, two bars; fails the goal.

## Trade-off Analysis

B protects against the easy cases only. A costs roughly a week and turns "stranded user" into "brief flicker then back to macOS". Given how severe the failure is, A is required before the shell hides anything native. Phase 1 therefore comes before Phase 3.

## Consequences

- **Easier:** aggressive experiments during development, since kill -9 is always safe; clean uninstall.
- **Harder:** every new system-touching feature has to be written as a journaled mutation. Code review should reject direct `defaults` writes.
- **Revisit:** whether the guardian should also watch for a *hung* main thread (heartbeat sent from the main run loop, not a background thread). Recommended: yes.

## Action Items

1. [ ] `SystemMutation` protocol with `apply()` / `revert()`; all `defaults`, wallpaper and appearance writes go through it.
2. [ ] Guardian target + `SMAppService.agent` registration + heartbeat over a Unix domain socket.
3. [ ] Send the heartbeat from the **main run loop** so hangs are detected.
4. [ ] Test: `kill -9` the shell 3× in 60 s → verify Dock, menu bar, wallpaper and windows are restored.
5. [ ] Panic hotkey in both processes; `--restore` CLI.

## Implementation notes (2026-09-24)

- **Deviation:** the guardian is the app's own executable started with `--guardian --parent <pid>` via
  `posix_spawn` + `POSIX_SPAWN_SETSID` (own session, survives the shell) instead of an
  `SMAppService.agent` LaunchAgent. Same code signature and TCC grants, no extra bundle build phase.
  A single instance is enforced with `flock` on `guardian.lock`.
- Heartbeat is a file (`heartbeat`: pid, time, alive|clean) written from the main run loop every
  second; the guardian only trusts heartbeats from its parent pid.
- Debug builds restore but never relaunch (Xcode's Stop is a SIGKILL).
- Scopes: `runtime` changes (Dock hiding) are undone on every quit/crash; `persistent` ones (dark mode,
  accent, wallpaper) only by "Restore macOS" / panic chord / `--restore`.
