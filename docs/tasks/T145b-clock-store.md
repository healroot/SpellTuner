# T145b: the clock's look stored dense and versioned; the migration; the presets (both lines)

Unit U2 of `docs/SPEC-clock-v3.md` (section 5), size M. The author approved the spec, the mockup
`tools/.cache/clockv3/index.html` and decisions D1-D3 on 2026-11-08 (`docs/DECISIONS.md`, "Clock v3").

## Goal

- `UI/ClockStore.lua` (`ST.ClockStore`): the v3 schema of spec 1.5 (`db.clockLook = { v = 3, ... }`,
  dense: 12 bar fields and 7 texts x 8 fields), `Normalize` (a missing or invalid field put back from the
  default and named), `Migrate` (v1, v2, none, garbage -> v3; pure and idempotent), `MigrateStored`,
  `Look` (a validated copy), `Get`, `Set` / `SetText` / `ApplyPreset` / `Undo` / `Reset` (each one write
  and one `CLOCK_LOOK`; a refused value writes nothing), `PRESETS` (SpellTuner, EllesmereUI; spec 1.4 and
  the mockup's values), `DumpLine`.
- Decision D3: the migration turns the moving line on (`line = true` always), and names the change.
- P2: no preset may set `line = false` or `texts.time.on = false`; `ApplyPreset` refuses one that would.

## Files

- `UI/ClockStore.lua` (new; every main TOC just before `UI/ClockView.lua`);
- `tools/clockstorecheck.lua` (new), `tools/data/clock-v2-author.lua` (the author's store of
  2026-11-08, copied from the Forever saved variables and limited to `clockLook`),
  `tools/data/expected-counts.json`.

**Scope frozen:**
- `db.clockLook` is not rewritten at login. `MigrateStored` exists but is called only by the tests
  until U3 (T145c) wires it at `MD_READY`. Nothing reads the store yet.
- `CV.Migrate`'s v1 rules (and `CV.ResetBarLook`, which the T142 build ran on the same stores) are
  copied in, not shared.

## Acceptance

- Spec 4.4 and 4.5 green on both flavours (`tools/clockstorecheck.lua`).
- The author's golden matches spec section 1.5 field for field.
- The dump notes name every dropped key.

## Report

`docs/review/T145ab-implementer-report.md`.
