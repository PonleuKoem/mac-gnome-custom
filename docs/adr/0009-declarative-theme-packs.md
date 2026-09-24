# ADR-0009: Themes as declarative JSON packs (tokens + layout + system + keybindings)

**Status:** Accepted
**Date:** 2026-09-24
**Deciders:** Maintainers
**Related:** DESIGN.md §4.5, §4.6 · ADR-0010

## Context

The product promise is "change the interface to whatever I like", with GNOME as only the first preset. Looks have to be creatable without writing code, shareable as files, and safe to load from strangers. Flutter release builds are AOT-compiled, so **Dart code can't be loaded at runtime**. Themes also touch real system settings (wallpaper, dark mode, Dock), which must stay reversible.

## Decision

A theme is a **folder (or zipped `.mgctheme`)** containing `theme.json` and assets. `theme.json` has five blocks:

| Block | Effect | Applied by |
|---|---|---|
| `tokens` | colors, fonts, radii, blur, motion | Dart, instant |
| `layout` | which widgets sit where in each surface, dock mode, overview triggers | Dart, instant |
| `icons` | icon-pack mapping (bundle ID → image) | Dart, instant |
| `keybindings` | action → chord | ShellKit HotkeyService |
| `system` | wallpaper, dark mode, accent, native Dock/menu-bar handling | ShellKit SafetyService (journaled) |

Resolution order: **defaults → `extends` chain → theme → user overrides**. The result is an immutable `ShellTheme`. The schema is versioned (`"schema": 1`) and checked against a JSON Schema. Invalid values fall back one token at a time.

## Options Considered

### Option A: Declarative JSON packs (chosen)
| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium: schema, resolver, widget registry |
| Cost | Every new look needs its layout primitives to exist in the widget registry |
| Scalability | Good: themes are data; a gallery or sharing is trivial later |
| Team familiarity | High |

**Pros:** safe to share; hot reload from a text editor; the Customizer is just a JSON editor with previews; `extends` makes variants cheap.
**Cons:** limited to what the registry can express; a radically new widget still needs an app release.

### Option B: Runtime code extensions (embedded Lua/JS via JavaScriptCore)
| Dimension | Assessment |
|-----------|------------|
| Complexity | High: sandboxed API design, security review |
| Cost | Large |
| Scalability | Most expressive |
| Team familiarity | Low |

**Pros:** GNOME-extension-level power.
**Cons:** security surface; scope far beyond v1.

### Option C: Hard-coded presets in Dart
| Dimension | Assessment |
|-----------|------------|
| Complexity | Low |
| Cost | Every look needs a release |
| Scalability | Poor |
| Team familiarity | High |

**Pros:** quickest to first GNOME look.
**Cons:** breaks the "whatever I like" promise.

## Trade-off Analysis

A covers what most people mean by "theme" (colors, fonts, shapes, arrangement, icons, wallpaper) safely and shareably. B is the natural v2 for power users, and A's widget-registry design doesn't block it: extension widgets would just be new registry entries. C would make the first milestone quicker, but the design would have to be undone later.

## Consequences

- **Easier:** presets are just folders; users share one file; the Customizer and a text editor work on the same thing.
- **Harder:** keeping schema compatibility, so migrations are needed when `schema` goes up; the widget registry must be designed with care up front.
- **Revisit:** extension scripting (B); a signed theme gallery.

## Action Items

1. [ ] Write `theme.schema.json` v1 and a `tools/validate-theme` CLI.
2. [ ] Build the widget registry (`activities`, `clock`, `appMenu`, `indicators`, `workspaces`, `quickSettings`…).
3. [ ] Ship 4 presets: gnome-adwaita, gnome-dark, win11, classic-mac, each using `extends` where it fits.
4. [ ] Add a golden test per preset per surface.
