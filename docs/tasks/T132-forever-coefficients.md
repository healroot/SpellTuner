# T132: Forever's +bonus estimates from talentsforever's per-rank coefficients

Author's export (2026-10-23, Forever beta, druid level 25; the Spells Overview export)
against talentsforever `data.json` (generated 2026-10-22, `spell_desc[...]` `d` =
base text at level 60 with no gear, `co` = Forever coefficient string). One snapshot,
so the bonus is inferred: Wrath R1-R4, Moonfire, Starfire and Entangling Roots all fit
**spell damage ~96** with the site's `co` and **no low-level penalty** (Wrath R1 counts
the full 42.9%); Rejuvenation R2-R4, Healing Touch R2-R4 and Regrowth R1-R2 (both parts)
and R3's HoT fit **+healing ~165** with the site's `co`, again with no penalty.

Our estimate (`Spells/Coefficients.lua` `Coef.Estimate`) is Classic's: cast / 3.5,
HoT / 15, and the sub-20 penalty. On Forever that is wrong. For example, Rejuvenation R3
gives 0.68 where the real share is 0.80, Healing Touch R2 0.31 where it is 0.57, and
Wrath R1 0.12 where it is 0.43.

Author's ruling (2026-10-04, `docs/DECISIONS.md`): talentsforever is the preliminary
source of truth until verified in game. The author asked (2026-10-23) for its numbers
to become the base estimates. A measured share (T131) still wins.

Left to measurement, **not** typed in: Healing Touch R1 (export implies ~0.26 vs the
site's 0.429), Rejuvenation R1 (~0.64 vs 0.80), Regrowth R3 direct (~0.22 vs 0.286, or
the site's base text is stale). They go in `docs/TESTING.md` as the ranks to check.

## 1. Generated table (`tools/buildcoefs.py` -> `Data/Coefs_Forever.lua`)

- Like `tools/buildtalents.py`: reads a `data.json` path and writes `-- GENERATED, do
  not hand edit`, with the source's `generated` date, the attribution line and
  "PRELIMINARY until verified in game".
- Shape: `ST.CoefRules = { [spellId] = { direct = 0.429?, heal = 0.429?, tick = 0.20?, name, rank } }`
  for every class's `spell_desc` row whose `co` it recognises: "N% of spell power
  (direct)" goes to `direct`, "(heal)" to `heal`, "(per tick)" to `tick`; parts of one
  kind are added up. (Review B1, lead's ruling: the site's "(direct)" is the damage part
  and "(heal)" the heal part, so the two are never summed; `Coef.Estimate` reads `heal`
  for a heal, else `direct`, and `direct` for damage, else `heal`. Holy Shock R1 is 0.429
  either way, never 0.858.)
- Any other wording is skipped and named in the header by count, with the first few
  phrases. Never guess.
- Rows with `s ~= "beta"` are skipped. Honour `fx` / `asis` notes by skipping those
  rows, listed in the header.
- Commit the generated file. List it in both Forever TOCs before `Spells/Book.lua`;
  TBC gets nothing.

## 2. The estimate (`Spells/Coefficients.lua`, Forever path only)

- `Coef.Estimate(e, shape)`: when `ST.CoefRules` has `e.id`:
  `counts = (direct or 0) + (tick or 0) * ticks`.
- `ticks` = the entry's duration / its tick interval. Use the parsed interval when
  `Spells/Parse.lua` gives one; else 3 s, the vanilla HoT/DoT tick, with the why saying
  "3 s ticks assumed".
- (Review M1, the lead's ruling, 2026-10-23, replacing the line above: no tick period is
  guessed for an arbitrary spell.) The per-tick share uses the period parsed from the
  spell's own text, else 3 s only for the families the author's 2026-10-23 export confirmed
  -- Rejuvenation, Regrowth (its HoT), Moonfire (its DoT) -- kept as a named table in
  `Spells/Coefficients.lua` with its provenance; the why says "3 s ticks (measured
  2026-10-23)". Any other spell (Wild Growth, Insect Swarm, Mind Flay, Blizzard,
  Consecration, Holy Fire, Flamestrike, ...) takes the old rule whole, direct part
  included, and its why ends "(tick period unknown -- old rule)".
- A channel uses its own tick count from duration / interval.
- No sub-20 factor on this path. The group rule stays.
- The why reads, for example, `20% x 4 ticks (talentsforever)` or
  `28.6% + 7.1% x 7 ticks (talentsforever)`.
- Keep `BaseCast` / T129 only for the old path, which is the fallback for an id with
  no row. A literal coefficient still lives only in `Spells/Coefficients.lua` and the
  generated data file; adjust `tools/bookshapecheck.lua`'s literal rule to allow the
  generated file.
- TBC's estimates are unchanged.
- (Lead's addition, 2026-10-23: Forever may scale a low rank by the player's level.) Each v = 2
  `bonusCounts` entry stores the player's level (`ST.player.level`); an entry read at another
  level is old -- its points are dropped and the estimate shows until it is measured again. No
  penalty is modelled in the estimate. One oracle in `tools/bookcheck.lua`.

## 3. Tests

A Forever suite (`tools/coefscheck.lua`, or extend `tools/talentscheck.lua`):
- The data file's shape: positive numbers, no NaN, at least the druid ranks below.
- Through the real Book on the stub, against the author's export values:
  - Rejuvenation R1-R4: 0.80 each.
  - Healing Touch R1-R4: 0.429 / 0.571 / 0.714 / 0.857.
  - Regrowth R2: 0.286 + 0.071 x 7.
  - Wrath R1: 0.429.
  - Moonfire R1: 0.15 + 0.13 x 3.
- An id with no row falls back to the old rule with its old why.
- A measured share still wins over the generated estimate.
- Move goldens only where these cases change them, and list each in the report.

## 4. Docs

- `docs/TOOLS.md`: the generator and the suite.
- Expected counts.
- `CHANGELOG.md` under `## 0.17.3`.
- `docs/TESTING.md`: a step with the three left-to-measurement ranks and the gear swap.
- `docs/REFERENCES-FOREVER.md` §1: coefficients now used, preliminary.
- `docs/DECISIONS.md`: a dated line saying the base estimates come from talentsforever's
  `co` on the author's word, 2026-10-23.
- **Do not edit CLAUDE.md.**

## Acceptance

Section 3 passes; `make check` green (apicheck 0, textcheck 0, counts); TBC unchanged.
