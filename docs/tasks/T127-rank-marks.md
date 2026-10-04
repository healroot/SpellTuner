# T127: three rank marks -- eff, max, best

Author (2026-10-04): one "best" answers the wrong question for damage; wants
"the most efficient", "the most damage" and "the best trade-off". Approved
design and mockup: `docs/mockups/rank-marks.html` (cb9a9ef). Weights adjusted by
the author's own TBC reading: Wrath R8 / Starfire R6 (a small damage loss for a
3-5% efficiency gain) are the right picks, so a % of efficiency is worth more
than a % of output -- not 1:1.

## Rules (Spells/RankRules.lua, pure, both lines)

Over eligible, **non-dominated** rows (mockup Q1):

- `eff`  -- highest `f.eff`; no floor.
- `max`  -- highest `f.rate` (per second); top rank usually, a shorter-cast rank
  wins when it gives more per second (mockup Q4: max no longer means highest).
- `best` -- score(r) = (eff_r / eff_max - 1) - k * (1 - rate_r / rate_max);
  the highest score > 0 wins, else `max` (Q6: exactly 0 goes to max).
  - `ST.Rules.TRADE_K_DAMAGE = 0.25`, `ST.Rules.TRADE_K_HEAL = 0.15`, with
    provenance comments (author's reading 2026-10-04: +3-5% efficiency for a
    small damage loss is worth it; +5% for -50% is not -- 5 < 12.5).
  - Heals keep `SUGGESTED_FLOOR` (0.4 of the top's value) as an extra gate.
  - Both k are settings in Settings (a "Trade-off" row each: damage, heal;
    0..1 step 0.05) read at each call, so the author can tune them.
- Raw numbers, not After overheal (Q2: same as the Pareto filter today).
- `best` is what `suggested` is today: every reader of `suggested`
  (planner, simulator, rail, Overview, My spells, tooltip, strip -- Q5) keeps
  reading it; `eff` and `max` are new fields (`effRank` / `maxRank` or per-row
  flags -- choose one, document it in `Spells/BookShape.lua`).
- **Lifebloom** (TBC): marks over its stack variant rows. Mockup Q3: all
  variants cost the same on the same GCD, so one row holds all three; show it
  as `best` only.

## UI

- Rank tag column: one tag per row, priority best > max > eff; colours per the
  mockup (`best` accent, `max` text, `eff` good), token reads only.
- Rank card: a MARKS block listing every mark the rank holds with its one-line
  reason (mockup wording; the reason is the rule's numbers read back).
- Decision strip: `best` vs `max` (falls back to today's "same" sentence when
  they are one rank); fits as T124 follow-up 692572d does.
- Spell tooltip line follows best vs max.
- Header / tag tooltips explain the three marks (mockup text).
- What if moves all marks (they are computed from the what-if book already).

## Tests

`tools/` suites for RankRules (new cases: the TBC 5%/-50% damage example ->
best = max; a Forever x0.6 damage x3 efficiency rank -> best; a heal case;
shorter-cast max; k = 0 and k = 1 edges; Lifebloom variants), spellsui
(tags, card, strip at offsets -2..+2), settings rows; expected counts updated.
apicheck 0, textcheck 0.

## Docs

CHANGELOG `## 0.17.1` line; TESTING §50 step for the marks and the two
Trade-off settings; CLAUDE.md RankRules row (`Suggested` -> the three marks).
