# T145a: the clock's words and the quiet pool (both lines; the pool Forever)

Unit U1 of `docs/SPEC-clock-v3.md` (section 5), size M. The author approved the spec and the mockup
`tools/.cache/clockv3/index.html` on 2026-11-08. The diagnosis is `docs/review/clock-v3-diagnosis.md`
(bug 2: "the times shows 10s, 5s, 0s when mana was full").

## Goal

- The words each clock text draws come from one pure function, `ST.ClockWords.Build(face, look, latch,
  now, out, quietFull)` (spec 2.2), with the FULL rule of spec 1.2 (P3: at full mana the clock says
  FULL; a refill time always carries FULL; a time is never `0s` / `0:00`).
- T144's Steady rules move to `Engine/ClockWords.lua`; `ManaModel.Steady` stays as an alias. Entering
  FULL snaps.
- The quiet pool (spec 2.4): `ClockWords.QuietFull(now, lastPowerEvent, lastSpend, base)`, and in
  `Engine/ManaPool_Forever.lua` the `UNIT_POWER_FREQUENT` bookkeeping, `Pool:QuietFull(now)`, the anchor
  "the game's pool stopped moving" on the tick (in and out of combat), the flag `Pool.QUIET_FULL` (on)
  and the dump line `pool: power events N, quiet-full anchors M`. QUIET = 3.0 s is VERIFY.

## Files

- `Engine/ClockWords.lua` (new, every main TOC right after `Engine/ClockFace.lua`);
- `Engine/ManaModel.lua` (`Steady` moved; an alias kept);
- `Engine/ManaPool_Forever.lua`;
- `SpellTuner_Mainline.toc`, `SpellTuner.toc`, `SpellTuner_TBC.toc`;
- `tools/clockwordscheck.lua` (new), `tools/data/expected-counts.json`.

**Scope frozen:** no UI file. `UI/Clock_Forever.lua` already registers `UNIT_POWER_FREQUENT` through
`ST:OnUnit`, so it is untouched; the pool's handler is registered before it.

## Acceptance

- Spec 4.1 green on both flavours (`tools/clockwordscheck.lua`):
  - the FULL rule as a table; no `0s` / `0:00` over every mode x value 0..12 x format;
  - the Steady sequences, and entering FULL snaps;
  - `QuietFull` at every boundary, nil inputs false;
  - `Build` with `out` passed allocates nothing over 1000 calls.
- The bug-2 face (`full`, ttf 0, in a fight) gives `FULL`.
- E7's rule cases pass as pure checks (and, on Forever, through the real pool's events and ticks).
- `make check` green.

## Report

`docs/review/T145ab-implementer-report.md`.
