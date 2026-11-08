# T145d: the Settings -> Clock pane and the end-to-end suite (both lines)

Unit U4 of `docs/SPEC-clock-v3.md` (section 5), size L. The author approved the spec, the mockup
`tools/.cache/clockv3/index.html` and decisions D1-D3 on 2026-11-08 (`docs/DECISIONS.md`, "Clock v3").
U1-U3 are committed (T145a `3c37952`, T145b `075edf9`, T145c `7b222e4`).

## Goal

- `UI/ClockSettings.lua` rewritten from the mockup (spec 3): one pane, no tabs, top to bottom:
  1. PREVIEW: a `ClockBar` on a ground strip; chips In a fight (`1:20`, the 5SR line running), Running out
     (`0:15`), Filling (`FULL 0:45`), Full (`FULL`) and Live (the real face); Show on screen
     (`Clock:Preview(60)`).
  2. BAR: Width (100-400), Height (3-30), Shape (Rectangle / Rounded / Pill), Frame (None / Border /
     Game frame), Texture (the scrolling list: SpellTuner's, EllesmereUI's, your UI's), Font (EllesmereUI's /
     SpellTuner's), Fill (Mana blue / Class colour / Custom, a swatch while Custom), Background (a swatch
     with opacity), 5SR line (On / Off). A choice the client cannot honour shows the renderer's reason
     (`look.notes`) in muted text beside it, and stays clickable.
  3. TEXTS: one row per kind (Time, Mana, Mana / max, Mana %, Regen, 5SR, Rest). An on row shows Place,
     Align, X, Y, Size, Colour, Outline; the Time row adds Time as (1:20 / 80s) and Warn colours. An off
     row shows only its switch, its name and a sample in muted text; its fields are hidden (P1). Place,
     Align and Outline step on a click (right-click back).
  4. PRESETS: SpellTuner, EllesmereUI, Undo (shown only while an undo is held).
  5. WHEN: the line's own switches (`CLOCK_SWITCHES.when`).
- `CS.CONTROLS`: the control registry the pane is built from. Each entry: `id`, `kind`
  (`buttons` / `slider` / `dropdown` / `swatch` / `check` / `number` / `step`), `key` (a store path),
  `values` (the test's sample values), `visible(look)`, `affects` (the `Drawn()` fields it changes),
  `write(value)` through `ClockStore` (one write, one `CLOCK_LOOK`).
- `UI/Dashboard_Forever.lua`, `UI/Dashboard.lua`: `CLOCK_SWITCHES` minus the `show` group (the Rest text has
  its own switch; TBC's `db.showRest` / `db.showCooldown` stay for the feeds' face).
- `Engine/ClockFace.lua`: the slot system removed (`KINDS`, `TEXT_SLOTS`, `TEXT_HOME`, `TEXT_LABEL`,
  `TEXT_WORDS`, `TEXT_OPTIONS`, `TEXT`, `ResolveText`, `DefaultSlots`, `Slots`, `ItemPieces`); `LineString`,
  `Segments`, `JoinSegments`, `ValueText`, `Time`, `Tone`, `ToneRGB` / `ToneHex`, `SAMPLES` stay.
- `UI/Feeds.lua`, `Integrations/Surface_LDB.lua`: no `ClockLook` provider read for slots; the feeds draw the
  default `LineString`. The `ClockLook` provider leaves `UI/ClockSettings.lua`.
- `UI/ClockStore.lua`: `SetMany(map)` (several fields, one write, one `CLOCK_LOOK`) for the Background
  swatch (colour and opacity in one move). Nothing else in the schema changes.
- U3's open point 3: on Forever the E5 driver never shows a refill. Find whether it is the harness or the
  model; out of combat while regenerating the clock must read `FULL <time>`, and `FULL` at full -- a test
  either way; a model fix only within the spec's rules (ClockWords / ManaModel).

## Files

- `UI/ClockSettings.lua`, `UI/ClockStore.lua` (`SetMany`), `UI/Dashboard_Forever.lua`, `UI/Dashboard.lua`,
  `Engine/ClockFace.lua`, `UI/Feeds.lua`, `Integrations/Surface_LDB.lua`.
- `tools/clocke2e.lua` (new, spec 4.2 E1-E7), `tools/lib/clockdrive.lua` (helpers),
  `tools/clocksettings.lua` (re-based on the new pane; the 36 `SKIP_U4` ids ported or removed, none
  skipped), `tools/clocktextcheck.lua` (cut to what is not the slot system), `tools/surfacecheck.lua` and
  `tools/euicheck.lua` (T114's "the feed follows Line's slots" re-based: the default `LineString`),
  `tools/clockfacecheck.lua` if it reads a removed name, `tools/data/expected-counts.json`.

**Scope frozen:** the integrations block (`CS.BuildIntegrations`, the LDB / ElvUI / EllesmereUI switches)
and the Look controls (`CS.LookControls`) move unchanged. No change to `UI/ClockBar.lua`'s contract,
`Engine/ClockWords.lua` or `Engine/ManaPool_Forever.lua` unless the open point needs it.

## Acceptance

- Spec 4.2 E1-E7 green on both flavours (E7 Forever) in `tools/clocke2e.lua`; the inert list is empty with
  no exception list.
- The pane matches the mockup's controls one to one.
- `tools/clocksettings.lua` has no skipped check.
- `apicheck` 0 findings; `textcheck` clean; `make check` green at the commit.

## Report

`docs/review/T145de-implementer-report.md` (with T145e).
