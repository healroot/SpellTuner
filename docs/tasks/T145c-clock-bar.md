# T145c: the clock's renderer (ClockBar) and its two hosts (both lines)

Unit U3 of `docs/SPEC-clock-v3.md` (section 5), size L: the timing / state unit. The author approved the
spec, the mockup `tools/.cache/clockv3/index.html` and decisions D1-D3 on 2026-11-08 (`docs/DECISIONS.md`,
"Clock v3"). U1 (`Engine/ClockWords.lua`, T145a) and U2 (`UI/ClockStore.lua`, T145b) are committed.

## Goal

- `UI/ClockBar.lua` (`ST.ClockBar`, spec 2.3): `New(host, draw)`, `:Apply(look)`, `:Paint(words)`,
  `:PaintPower(withMax)`, `:Message(text)`, `:Pulse()`, `:Drawn()`.
  - `Apply` is the only function that anchors, sizes or sets a font; it runs on a look change only (P5).
    No string is measured; no text changes the frame's size; the host's hit-rect insets reach the outside
    texts (`size + 2` per side).
  - `Paint` sets a text only when its string changed and the time's colour only when its tone changed;
    no allocation; the power kinds are the power path's.
  - `PaintPower(withMax)`: `draw.pool(bar)`, with `withMax` `draw.poolMax(bar)` first; each shown power
    text through `draw.powerText(fs, kind)`, else the model's words from the last `Paint`, marked modelled.
  - The moving line (P4): one driver frame, its `OnUpdate` set once in `New` and never cleared; it reads
    `draw.fsrEnd()`, `barW` and `lineOn` (set by `Apply`) and places the line and its back, or hides them
    once.
  - `Drawn()`: a plain snapshot from the renderer's own write cache, never read back from a region.
  - Failure modes of spec 2.6: `eui:*` texture / `eui` font without EllesmereUI, no masks, no game atlas --
    each a fallback and a note in `look.notes`.
- `UI/Clock_Forever.lua` (spec 2.5): the tick is `Pool:Project` -> `ManaModel.Face` ->
  `ClockWords.Build(face, look, steady, now, wordsOut, Pool:QuietFull(now))` -> `Paint`, `PaintPower(true)`;
  `UNIT_POWER_FREQUENT` -> `PaintPower()`; `UNIT_MAXPOWER` -> `PaintPower(true)`; `CLOCK_LOOK` /
  `STYLE_CHANGED` -> `Apply`; `KeepCentre` only for a Width change; the steady latch reset when a preview
  ends; the hover's bar sentence from `look.line`. Frame, drag, hover and the one visibility owner stay.
- `UI/Widget.lua` (TBC): the same, with `ST:GetClockFace()`, latch nil and quietFull false; the power path
  through the TBC adapter.
- `Client/API.lua`: `DrawUnitPowerMax(bar, unit, powerType)` (min / max) and the value-only
  `DrawUnitPower(bar, unit, powerType, smooth)` (T142-T143 review W1). `Client/API_TBC.lua`:
  `ST.API.DrawPowerText` (plain reads; the same kinds and formats).
- `ClockStore.MigrateStored` wired at `MD_READY`; `tools/data/import-forever-sv.lua` rebuilt
  (`tools/importfixture.lua`).
- `UI/ClockView.lua` deleted; the three main TOCs list `UI/ClockBar.lua` in its place.
- `UI/ClockSettings.lua`: a minimal working pane until U4 -- `CS.Refresh` reads `ClockStore.Look()`, its
  preview is a `ClockBar`; the integrations block and the Look controls unchanged.
- `tools/wowstub.lua`: `S.VisibleOnUpdate(on)` (opt-in: `S.Tick` runs `OnUpdate` only on visible frames)
  and region call counters.

## Files

- `UI/ClockBar.lua` (new); `UI/Clock_Forever.lua`, `UI/Widget.lua`, `UI/ClockSettings.lua`;
  `Client/API.lua`, `Client/API_TBC.lua`; the three main TOCs; `UI/ClockView.lua` (deleted).
- `tools/wowstub.lua`, `tools/clockbarcheck.lua` (new), `tools/lib/clockdrive.lua` (new: the E5 / E6
  drivers U4 reuses), `tools/clockui.lua` (cut down to the hosts' visibility, drag and hover),
  `tools/stylecheck.lua` (golden re-based); the suites that read `ST.ClockView` re-based on the new regions;
  `tools/clocksettings.lua` (checks of removed keys skipped, marked "U4");
  `tools/data/expected-counts.json`, `tools/data/import-forever-sv.lua`.

**Scope frozen:** no change to `Engine/ClockWords.lua`, `UI/ClockStore.lua`'s schema, `Engine/ClockFace.lua`
(its slot system leaves in U4), `UI/Feeds.lua` or `Integrations/Surface_LDB.lua` (U4).

## Acceptance

- Spec 4.3 green on both flavours (`tools/clockbarcheck.lua`).
- E5 and E6 of spec 4.2 pass when driven from the host without the pane (`tools/lib/clockdrive.lua`).
- `apicheck` 0 findings; no `UI/ClockView.lua` reference left in code or TOCs (`grep`).
- `make check` green at the commit.

## Report

`docs/review/T145c-implementer-report.md`.
