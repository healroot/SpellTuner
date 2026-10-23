# T131 review: Bar by default, +bonus shares fitted from many readings

Reviewer: independent (Opus 5.5, high). Scope: `git diff dad5483..HEAD` (791758c, a12a298,
84dfc05, 30af07a) against `docs/tasks/T131-bar-default-bonus-fit.md`. Suites run:
`tools/run.sh --flavour forever tools/bookcheck.lua` (41 ok), `tools/whatifcheck.lua` (10 ok),
plus a scratch probe through the real `Spells/Book.lua` (described under M1). `make check` not
run (separate gate).

**Verdict: fail** -- 0 blockers, 1 major, 3 minors.

## What holds

- `Fit` (Spells/Book.lua:1210-1228): every ordered pair with `db > 0`, interval
  `[(dv - 2 TOL)/db, (dv + 2 TOL)/db]`, intersection as max of lows / min of highs; empty
  returns the flag; fewer than two distinct bonuses returns nil. Correct.
- Empty intersection and same-bonus/different-value both reset to the newest point, with
  `ST:Debug("other", ...)` naming spell and readings (Book.lua:1270-1291). Per spec.
- `Trim` (Book.lua:1232-1252) keeps the first lowest and highest, then the newest from the end;
  the new point is always kept; order preserved. The MAX_POINTS test pins 0/100 and 40..90.
- Old-shape entries (no `v`) are deleted in `StoredFit` on the first read (Book.lua:483-486);
  `Measured` hands out only narrow, `0 < counts <= 2` fits.
- Kind/school rule kept: `StoredFit` refuses another kind or a different school; `AddReading`
  starts a new entry then. Either-or damage halves stay estimated.
- No reading in combat (`MeasureBonus` returns), none from a stale bonus (`Reading`), none
  from stale text (`e.stale`, `descState == "ok"`). The T124 combat/stale test can fail (it
  clears 90125 and asserts nothing was stored).
- For a value that is ONE rounded number (Rejuvenation's "X over 12 sec", a min-max average)
  the truth is always inside `[lo, hi]`, so the R3 90% / R4 80% report cannot recur: a narrow
  share needs about 50 bonus of span and then lies within 0.04 of the truth.
- Words: ASCII only, no bare `|` in any added line; bookshapecheck pins the card / how / tip
  strings for both a fit and a measuring estimate.
- Bar default: `CV.DEFAULT_LAYOUT` read by RegisterDefaults, both `Stored` fallbacks, the
  resolver and the dump's non-default test. A fresh install cannot draw Line: both clocks and
  the settings preview build from `CV.Look` -> `CV.Resolve`, which always sets a renderable
  layout, so the `"line"` fallbacks left in `View:SetLook` (ClockView.lua:1254), `CV.Build`
  (1300, 1307), `View:Paint` (1416) and ClockSettings `Layout(p)` (666, before `p.look` exists;
  `CS.Refresh` re-reads it) are unreachable in practice.
- `fit` / `measuring` out of `BONUS_SIG` (Book.lua:1137): acceptable. A new reading is a new
  heal bonus, and `SpellsPane:Signature` already carries `Book:Bonus("heal")`, so the open card
  re-renders; any reading that moves the text moves the generation through `value`. What is
  left (a damage-only bonus change too small to move the text, or `n` growing with lo/hi
  unchanged) leaves only a stale "N readings" or a stale measuring range until the next render.
  Including them would also break bookshapecheck 8 (bonus moves, text unchanged, generation
  kept).

## Major

**M1. Spells/Book.lua:472 / 1218 -- `ROUND_TOL = 0.5` per value is too small for a value that
sums several rounded numbers, so a narrow wrong share is still possible and good fits reset.**
`PartValue` -> `Parse.Total` (Spells/Parse.lua:415-431) adds `(min+max)/2 + over + tick * n`.
A hybrid (Regrowth, Moonfire: avg + over) is off by up to 1.0; a channel or tick-built HoT
(Tranquility "X every 2 sec for 10 sec", 5 ticks, in the druid's Forever book) by up to 2.5.
Probe through the real code (scratch script, Forever flavour): a Tranquility-shaped spell, true
share 0.50 rounded per tick, read at +0 and +55 -> `Book._Measured` returns **0.545,
[0.527, 0.564], narrow, measured, and the truth outside it** (the same 5-10 point error the task
set out to remove). Stepping +7 at a time it resets every third scan and never measures (the
interval `[0.57, 0.86]` already excludes 0.50). A hybrid (0.30 direct + 0.43 over) read at
+0, +55, +61 gets an empty intersection and resets on a correct reading. The task named this
constant as "the one knob" for per-tick rounding, but the parse already says how many rounded
terms the value has. Fix: tolerance per entry = 0.5 x (1 for a min/max pair, +1 for `over`,
+n for `tick` x n), passed into `Fit`; or refuse to fit tick-built totals. Add a bookcheck
case with a per-tick channel and a hybrid.

## Minors

**m1. CHANGELOG.md:9-10 -- "A clock you set to Line stays Line" is not what happens.**
`ST:RegisterDefaults` -> `FillDefaults` (Core.lua:339-347, 396) writes `layout = "line"` into
every existing `SpellTunerDB.clockLook`, so every install that ran 0.17.2 or earlier stays
Line whether or not the player chose it. Only a new install, or a deleted `clockLook`, gets Bar.
That is the spec's "no migration", but the player-facing line should say "for a new install"
(TESTING section 53.1 already does).

**m2. Spells/Book.lua:540-547 -- the measuring hint promises a measurement that never comes.**
When the span is already 50 or more but the fit is refused by `Narrow` for `counts <= 0` or
`> 2` (a value that does not move with the bonus, or a text that lagged the bonus read: dv = 0
-> `[-0.01, 0.01]`, midpoint 0), `need` is clamped to 1 and the card reads
`measuring -0.01-0.01, swap about 1 more +Healing out of combat`, which no swap fixes. Show
the measuring words only when `hi - lo > MAX_SPREAD`; a negative `lo` also prints as
`-0.01-0.01`.

**m3. UI/ClockView.lua:1254, 1300, 1307, 1416; UI/ClockSettings.lua:666, 669 -- the
unreachable fallbacks still say `"line"`.** Harmless today (see above), but they contradict
`CV.DEFAULT_LAYOUT`; a future caller passing a look without a layout would draw Line.
Read `CV.DEFAULT_LAYOUT` there too.

## Notes (not findings)

- By spec, a reset keeps the newest point even when the newest is the outlier (for example one
  scan where the text lags the bonus). One such scan wipes a good fit; the next swap
  re-measures. If the probe shows the description lagging `GetSpellBonusHealing`, consider
  replacing the point at that bonus and re-fitting, and resetting only when the fit is still
  empty.
- `fit.n` counts the kept points (at most 8), not every reading. The words say "readings";
  that is fine.
