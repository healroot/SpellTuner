# T131: the Bar layout by default; +bonus shares measured from many readings

Author's report (2026-10-23, Forever beta, last day): (a) the Bar clock layout
(`~FULL 1:15` on a bar) should be the default instead of Line; (b) the measured
+healing share of Rejuvenation reads 80% on Rank 4 and 90% on Rank 3, which cannot
both be right (R3 is learned below level 20, so its share is, if anything, lower).

Cause of (b), `Spells/Book.lua` `Book:MeasureBonus` (~L1158): a share is
`(value - prev.value) / (bonus - prev.bonus)` from the **last two scans only**, and
each new pair **overwrites** `ST.cdb.bonusCounts[id]`. The tooltip value is a
rounded integer, so the error is about `1 / (bonus - prev.bonus)`: a +10..+20 swap
moves the result by 0.05..0.1. The last small swap wins.

## 1. Bar is the default layout (`UI/ClockView.lua`)

- `ST:RegisterDefaults` clockLook, the `Stored()` fallbacks (~L495, ~L519) and the
  resolver's unknown-layout fallback (~L352) say `"bar"`. The dump line's
  "non-default" test (~L546) follows (`s.layout ~= CV.DEFAULT_LAYOUT`): one constant
  `CV.DEFAULT_LAYOUT = "bar"`, every one of those sites reads it.
- A saved `layout = "line"` is the player's choice and is kept (no migration).
- Both lines (the TBC widget and the Forever clock use the same store). Check that
  the Bar's defaults draw on both (`CV.BarsOK`; Forever's `mana = "game"`).
- Update tests/goldens the default moves (clockview, clocksettings, widget,
  forever clock suites -- whichever assert the default); list each in the report.

## 2. +bonus shares fitted from many readings (`Spells/Book.lua`)

Store, per spell id (and the existing kind / school rule), the readings instead of
one pair: `ST.cdb.bonusCounts[id] = { v = 2, points = { {bonus, value}, ... },
counts, lo, hi, at, bonus, kind?, school? }`.

- A reading is `(bonus, value)` from a scan out of combat (the existing gates:
  plain bonus, not stale, `descState == "ok"`). One point per distinct bonus (the
  newest value for that bonus); at most `MAX_POINTS = 8`, keeping the lowest and
  highest bonus and the newest in between.
- **Interval fit, rounding-aware.** Each value is read within `ROUND_TOL = 0.5`
  (a named constant; the tooltip rounds to an integer -- if a HoT's total turns out
  to be rounded per tick this is the one knob). For every pair i<j with
  `bonus_j - bonus_i > 0`, `counts` lies in `[(dv - 2*TOL)/db, (dv + 2*TOL)/db]`;
  `lo, hi` = the intersection over all pairs; `counts` = the midpoint.
- **Inconsistent points mean the base moved** (a talent, a level, a rank's text):
  when the intersection is empty, drop every point but the newest and start again
  (`ST:Debug("other", ...)` names the spell and the readings). Same when a point at
  an already-seen bonus has a different value.
- **Measured only when narrow:** `hi - lo <= MAX_SPREAD` (0.04, i.e. a gear swap of
  about 50 bonus or more). Below that the entry is still estimated: `e.bonus.from =
  "estimated"` as today, plus `e.bonus.measuring = { lo, hi, need }` where `need` is
  the bonus span still missing (`ceil(4*TOL / MAX_SPREAD - span)`), so the card can
  say so.
- `Measured(id, ...)` hands out only `v == 2` entries that are narrow; it returns
  `counts`, `lo`, `hi`, `#points`. **Old entries (no `v`) are dropped** on the first
  read -- they came from one pair and are the ones that are wrong. The CHANGELOG
  says so: "re-measure: swap gear out of combat".
- `Book._lastRead` goes away (the stored points replace it); the "two readings"
  rule becomes "two distinct bonuses", so a single swap that is wide enough still
  measures at once.
- Damage ranks (T124) follow the same path.

## 3. Words (`Spells/Words.lua` `W.Bonus`, `UI/SpellTip.lua`)

- Measured: card `80% measured (0.79-0.81, 4 readings, +0..+212), 23 Oct`; how
  `+Healing counts 80%, measured 23 Oct`; tip unchanged (`80%`).
- Estimated while measuring: card adds `-- measuring 0.70-0.95, swap about 40 more
  +Healing out of combat`; how adds `, measuring`.
- ASCII only, no bare `|` (textcheck).

## 4. Tests (oracles)

`tools/bookcheck.lua` (and `tools/whatifcheck.lua` where it seeds stores):
- A true share 0.80, tooltip values rounded: readings at bonus 0 and +15 -> not
  measured (spread > 0.04), `measuring` set; add +120 -> measured, `lo <= 0.80 <=
  hi`, `hi - lo <= 0.04`.
- Readings that produced R3 90% / R4 80% under the old code (pick values: R3 true
  0.68 read at +10 / +20) never yield a narrow wrong share.
- A talent change (value jumps at a seen bonus) resets to one point.
- An old-shape entry (`{ counts = 0.77, at, bonus }`, no `v`) is dropped and the
  estimate shows.
- Damage share with a school still refused for the other kind (T124 cases kept).
- `MAX_POINTS` keeps the extremes.
Rework the existing T122/T124 bonusCounts cases to the new shape; list each changed
assertion in the report.

## 5. Docs

`CHANGELOG.md` a new `## 0.17.3` section if none exists above 0.17.2 (do **not**
bump the TOC versions), `docs/TESTING.md` a step (Forever druid: take off a +healing
weapon and put it back out of combat; Rejuvenation R3 and R4 cards say `measured`
with a narrow range; R3 <= R4), `docs/TOOLS.md` counts, expected counts.
**Do not edit CLAUDE.md.**

## Acceptance

Section 4's oracles pass; `make check` green (apicheck 0, textcheck 0, counts).
