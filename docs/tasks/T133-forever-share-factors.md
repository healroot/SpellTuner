# T133: Forever's +bonus estimate as separate factors -- site share x level penalty x talents

Author's exports (2026-10-23, Forever beta, druid level 25: ten readings, +0..+171 healing,
+0..+94 spell damage; level 26: eight readings, same gear steps, talents unchanged:
Improved Wrath 5, Moonglow 3, Naturalist 5, Nature's Focus 5, Reflection 3). Every rank is a
straight line in the bonus at both levels. The author's ruling (2026-10-23): keep each
multiplier a separate, named factor -- the spell's share is one, each talent another, the
low-rank level penalty another -- and use the derived rule **as a prediction** until more
levels and gear are tested after launch. A measured share still wins (T131).

## The formula (what the exports show)

    tooltip value = (base + bonus x share x P(rank, level)) x M(talents)
    counts (what +1 bonus adds)  =  share x P x M

- **share**: talentsforever's per-rank `co` (T132, `Data/Coefs_Forever.lua`). Every
  unpenalised rank matched it within rounding (HT R3/R4, Regrowth R1-R3 both parts,
  Rejuvenation R2-R4 at both levels).
- **P, the low-rank level penalty, heals only:**
  `P = max(0, 1 - 0.05 x max(0, playerLevel - start))`, `start = learnLevel + 17`.
  Measured ratio measured/share (rounding-aware interval over all readings):

  | rank (learned) | lvl 25 | lvl 26 | start that fits |
  |---|---|---|---|
  | Healing Touch R1 (1)  | 0.593-0.614 | 0.535-0.556 | 17 (one early) |
  | Rejuvenation R1 (4)   | 0.796-0.803 | 0.743-0.753 | 21 |
  | Healing Touch R2 (8)  | 0.996-1.005 | 0.943-0.958 | 25 |
  | Rejuvenation R2 (10)  | 1.00 | 0.996-1.001 | >= 26 (rule: 27) |
  | Regrowth R1 (12), HT R3 (14), ... | 1.00 | 1.00 | rule: 29, 31, ... |

  The step 0.05 per level fits all three penalised ranks at both levels; a ratio rule
  ((L + k) / level, TBC's shape) does not (HT R1 needs k 14.8-15.4 at 25, 13.9-14.5 at 26).
  Healing Touch R1 starts at 17, not 18: kept as a **measured start** in a named table
  (`MEASURED_START = { [5185] = 17 }`, provenance 2026-10-23, lvl 25-26), which wins over
  the rule. Floor at 0 is assumed (unmeasured): a named constant `LEVEL_FLOOR = 0`, so a measured floor
  is one edit. Under the rule a heal rank gives no bonus 37 levels after it is learned (HT R1 at
  37; at level 60 every rank learned at 23 or below). Damage has **no** penalty: Wrath R1 (learned
  1) and Moonfire R1 (4) count the full share at 26, where the heal rule would give 0.6 / 0.75.
- **M, talent multipliers**: Naturalist 5 ("increases all damage you deal by 5%") makes
  every damage rank x1.05 (Starfire 1.048-1.052, Wrath R1 1.036-1.055, Wrath R4 1.028-1.051,
  Entangling Roots 6% x 4 ticks x 1.05 = 0.252, measured 0.244-0.255), base included (ER R1
  21 = 20 x 1.05, the site's level-60 text). Heals had no multiplier talent. How two
  multipliers combine (product or sum) is **not measured**: product, said as assumed.

## 1. Talent multipliers, generated (`tools/buildtalents.py` -> `Data/Talents_Forever.lua`)

Extend the generator (same file, same header rules: count and name what it skips, never
guess) with `ST.TalentMults[class][talent] = { scope, pctPerRank = { ... } }`, each rank's
percent read from its own sentence. Recognised sentences only (anything else skipped, named):
- `increases all damage you deal by N%` -> scope `{ kind = "damage" }` (Naturalist)
- `Increases the damage done by your <School> and <School> spells by N%` -> `{ kind = "damage", schools = {...} }` (Moonfury)
- `Increases the effect(iveness)? of (all )?your healing spells by N%`, `Increases the amount healed by your spells by N%` -> `{ kind = "heal" }` (Gift of Nature, Purification, Spiritual Healing)
- `Increases the effect of your <Spell> spell by N%` -> `{ spells = { "<Spell>" } }` (Improved Rejuvenation)
A sentence with anything more after the percent (a condition, a second effect other than
the cast-time clause T129 already reads -- Naturalist's "Reduces the cast time ... and
increases all damage" is accepted) is skipped and named. Regenerate from the same
`data.json` (generated 2026-10-22); commit. PRELIMINARY until verified in game.

## 2. The factors on the entry (`Spells/Book.lua`, one more `Book.adjust` function)

`TalentMult(e, fam)`: for the player's class, every rule whose scope matches the entry
(kind from the entry's shape: heal / damage; school from the entry; spell by name) and
whose talent has rank r > 0 multiplies in `1 + pct[r] / 100`.
`e.talentMult = { factor = 1.05, words = "x1.05 Naturalist 5" }`. Ranks not read:
`words = "talents not read"`, factor 1. A rank above the rule's length: that talent named
"no rule", factor left out (never extrapolated). Nothing when no rule matches.

## 3. The estimate (`Spells/Coefficients.lua`, Forever row path only)

- `Coef.LevelPenalty(id, learnLevel, playerLevel, kind)` -> `P, start, source`:
  1 for damage, for an unknown level, or below the start; `source` `"measured"` (the
  table) or `"rule"`. Constants `LEVEL_STEP = 0.05`, `LEVEL_GRACE = 17`, `MEASURED_START`,
  with provenance comments. The coefficient-literal rule (`tools/bookshapecheck.lua`) still
  holds: these live here.
- `FromRow` multiplies `counts` by P (the whole rank, direct and per-tick parts) and by
  `e.talentMult.factor`, and says each factor:
  `42.9% x 0.55 level 26 (from 17, -5%/level) x1.05 Naturalist 5 (talentsforever, predicted)`.
  Factors equal to 1 are not said. At P = 0 the factor reads
  `x0 level 60 (from 17, -5%/level: no bonus at this level)` (HT R1). The old path (no row) and TBC are unchanged.
- The player level comes from `ST.player.level`; unreadable -> P = 1, said `level unknown`.

## 4. Measured vs predicted (`Spells/Book.lua` fit, `Spells/Words.lua`)

The measured share stays the number used. When an entry is measured AND has a row, store the
prediction beside it (`e.bonus.predicted = counts`, `e.bonus.factors = why`) and the card's
measured line adds:
- prediction inside `[lo, hi]`: `-- as predicted (42.9% x 0.55 level)`
- outside: `-- predicted 25.7% (42.9% x 0.60 level); unexplained x0.91`
The residual is shown, never applied anywhere. The "how" line and the tip are unchanged.
On a level change the measured entry is still dropped (T132); the estimate now carries P.

Card mockups (ASCII, no bare `|`):

    Healing Touch R1, level 26, estimated:
      +Healing  counts ~24% estimated (42.9% x 0.55 level 26 (from 17, -5%/level), predicted)
    Wrath R1, estimated:
      +Damage   counts ~45% estimated (42.9% x1.05 Naturalist 5, predicted)
    Rejuvenation R1, measured:
      +Healing  60% measured (0.59-0.60, 8 readings, +0..+171), 23 Oct -- as predicted (80% x 0.75 level)

## 5. Tests (oracles, `tools/coefscheck.lua` and `tools/talentscheck.lua`)

- LevelPenalty: HT R1 (5185) at 25 -> 0.60, at 26 -> 0.55, at 37 -> 0 (floor), at 16 -> 1;
  Rejuvenation R1 at 25 -> 0.80, 26 -> 0.75; HT R2 at 25 -> 1, 26 -> 0.95; Rejuvenation R2
  at 26 -> 1, 28 -> 0.95; damage (Wrath R1) at 26 -> 1; nil level -> 1.
- Through the real Book on the stub at level 26 with Naturalist 5: HT R1 0.429 x 0.55,
  Rejuvenation R1 0.80 x 0.75, Rejuvenation R3 0.80, Wrath R1 0.429 x 1.05, Entangling Roots
  R1 0.06 x 4 x 1.05; each inside the level-26 measured interval above.
- Generator: Naturalist, Moonfury, Gift of Nature, Improved Rejuvenation, Spiritual Healing
  parsed with every rank; an unrecognised sentence skipped and named; ranks not read ->
  factor 1, "talents not read"; a rank above the rule -> "no rule".
- Words: the three mockup lines; measured outside the prediction says `unexplained x0.91`.
- Move goldens only where these cases change them; list each in the report.

## 6. Docs

`docs/DECISIONS.md` dated line (the formula, a prediction on the author's word, the data
above); `docs/TESTING.md` a step for level 27/28 (exports at full gear and none: HT R1 0.50,
HT R2 0.90, Rejuvenation R1 0.70, Rejuvenation R2 1.00 at 27 and 0.95 at 28 if the rule
holds; and one heal-multiplier talent when taken; then HT R1 at 30 -> 0.35 and at 37 -> 0, the
first check of the far end and the floor); `docs/REFERENCES-FOREVER.md` §1;
`docs/TOOLS.md`, expected counts, `CHANGELOG.md` under `## 0.17.3`. **Do not edit CLAUDE.md.**

## Acceptance

Section 5 passes; `make check` green (apicheck 0, textcheck 0, counts); TBC unchanged.
