# T133 review -- Forever +bonus estimate as separate factors

Reviewer: independent adversarial review (Opus 5.5), 2026-10-23.
Diff: `git diff 757db91..5258926` (task `docs/tasks/T133-forever-share-factors.md`).
Verdict: **fail** on one major (a small generator fix); otherwise sound.

## What was verified

- `Coef.LevelPenalty` against every oracle, by hand and through `tools/coefscheck.lua` (59 ok):
  HT R1 (5185, MEASURED_START 17) 25 -> 0.60, 26 -> 0.55, 37 -> 0, 16 -> 1; Rejuvenation R1
  (learned 4, start 21) 25 -> 0.80, 26 -> 0.75; HT R2 (8, start 25) 25 -> 1, 26 -> 0.95;
  Rejuvenation R2 (10, start 27) 26 -> 1, 28 -> 0.95; damage -> 1; nil / 0 player level -> 1.
  Integer `over`, so no float trouble at the start boundary.
- P multiplies the summed `counts` after direct + tick x ticks (`Spells/Coefficients.lua`
  FromRow), so the direct and per-tick parts both carry it; the M1 old-rule fallback and the
  no-row path are untouched; TBC has no `ST.CoefRules`, so its path is unchanged.
- learnLevel is `entry.level` from `ST.API.SpellLevelLearned` (`C_Spell.GetSpellLevelLearned`),
  the number the Spells export shows (`UI/SpellsPane.lua:225`), so the fit was made on the
  client's own values. Missing -> P 1 (see m2).
- The residual: `bonus.predicted` / `bonus.factors` are read only by `Spells/Words.lua`
  `Predicted`; nothing in Engine, WhatIf or the fit reads them. The measured share stays `counts`.
- Lua multi-return: `local est, _, short = Coef.Estimate(...)` (Book.lua:650), FromRow's
  `nil, reason[, true]` returns through Estimate as `nil, reason, nil`; `Num`/`Pct1` gsub chains
  truncate correctly. No `a and f() or b` introduced.
- Entries are rebuilt fresh on every scan (`Book:BuildEntry`, `ReadSpell`), so a stale
  `talentMult` cannot survive a respec; `PLAYER_LEVEL_UP` marks the book dirty (Book.lua:1664).
- Generator reproduces the committed file byte for byte from the 2026-10-22 export
  (`python3 -I tools/buildtalents.py <export> --out ...`; diff empty).
- Item (6): Improved Frostbolt's 2026-10-22 sentence names "Frostbolt and Frost Blast"; Ice
  Barrier and Elemental Mastery gained cast-time clauses (temporary / conditional) and are
  correctly skipped; the set of shipped cast rules is unchanged (compared with the previous file).
- Item (5): the level-17 pin does not hide a regression. At 17 every P is 1 (HT R1's start is 17,
  over = 0), so sections 1-5 keep testing the share and tick math alone, while section 6 covers P
  on a direct heal (HT R1), on ticks (Rejuvenation R1), its absence on damage (Wrath R1, ER R1),
  the floor (level 60) and the unknown level. The bookshapecheck section needs the bonus to move;
  at the stub's 64 HT R1 is legitimately 0. Not tested: P on a hybrid (Regrowth) -- the code
  multiplies the sum, so this is coverage, not a defect. Oracle added in fb57d25 (Regrowth R2 at 37).
- Item (4), Entangling Roots in TICK_MEASURED: 0.06 x 4 = 0.240 lies outside the measured
  0.244-0.255 and 0.06 x 4 x 1.05 = 0.252 inside; the 1.05 is confirmed independently by Wrath and
  Starfire, so the joint inference is sound. Acceptable (family-keyed like the others).
- Suites run: coefscheck 59 ok, talentscheck 33 ok, bookcheck 46 ok, bookshapecheck 10 ok
  (forever). Full gate not re-run (the implementer's log shows 105 runs passing).

## Major

**M1 -- `tools/buildtalents.py:78,130`: multiplier talents whose sentence does not start with
one of the four leads are neither shipped nor named, so the header's "23 multiplier talent(s)
skipped" list is silently incomplete.** `MULT_LEAD` only matches "Increases all damage you
deal / the damage done by your / the effect / the amount healed"; a talent whose desc fails it
is `continue`d before it can be named (line 130). On the 2026-10-22 export this silently drops,
among spell talents: **Druid Genesis** ("Increases the periodic damage and healing done by your
spells and abilities by 5%"), Druid Improved Moonfire, Priest Twin Disciplines, Improved Power
Word: Shield, Searing Light, Darkness, Warlock Shadow Mastery, Soul Siphon, Mage Improved Cone of
Cold (plus melee ones). The task (section 1) says "Recognised sentences only (anything else
skipped, named)" and the repo rule is "count and name what it skips, never guess".
Failure: the author (Resto druid) takes Genesis 5. Every unmeasured Rejuvenation / Regrowth HoT
/ Moonfire DoT estimate is 5% low and its words read "... (talentsforever)" or "(talentsforever,
predicted)" with no hint that a known multiplier was left out; the header claims a complete list,
so whoever reads it to see what is missing will not find Genesis. The TESTING step "one
heal-multiplier talent when taken" would then show an `unexplained x1.05` with nothing in the
file to explain it. Fix: widen the lead (e.g. any "Increases ... by N%" whose object is damage,
healing, an effect or an amount), keep the shapes as they are, so these are named as skipped.
**Fixed in fb57d25** (94 named; oracle in `tools/talentscheck.lua` section 10).

## Minor

**m1 -- `Spells/Coefficients.lua:266` (with `Spells/Book.lua:222`): "talents not read" is
factor 1 and never said**, unlike T129's cast rule, whose old path says "(talents not read)"
(`BaseCast`, Coefficients.lua:118). Item (2) follows the letter of section 3 ("factors equal to 1
are not said"), but section 2 deliberately gives the case its own words. Failure: at login the
trait walk answers nothing for the first scans (Book.lua:59-64); a Naturalist 5 druid's Wrath
shows "~43% estimated (42.9% (talentsforever))" -- not even "predicted" -- 5% low, indistinguishable
from a druid without the talent. Suggest saying ", talents not read" as the level does. **Fixed in fb57d25**.

**m2 -- `Spells/Coefficients.lua:225,248`: a heal rank with no learn level silently gets P 1.**
`SpellLevelLearned` answering nil or 0 (no number, or a spell the client gives no level) returns
`1, nil, nil`, and LevelWords says nothing, while an unknown *player* level says ", level
unknown". Failure: on a level-60 druid, if the client answers 0 for Rejuvenation R1, the card
says "80% (talentsforever)" where the rule gives 0, with no word that the penalty was not
applied. Only HT R1 is protected (MEASURED_START). Suggest ", learn level unknown" for kind heal. **Fixed in fb57d25**.

**m3 -- `Spells/Book.lua:1128-1130` with `Spells/Book.lua:243`: an either-or spell's damage
half can never take a damage multiplier.** Item (3): TalentMult runs once per book entry with the
entry's kind ("heal" for Holy Shock / Holy Nova), DamageHalf copies that `talentMult`, and
TalentWords drops it for kind "damage". No damage multiplier for paladin or priest is generated
today (Searing Light / Darkness are dropped, M1), so nothing is wrong on the current data; once
M1 is fixed and a "Holy damage" shape is recognised, Holy Nova's damage half would silently stay
x1. Either compute the damage half's factor in DamageHalf or note the limit in the seam comment.
**Fixed in fb57d25** (no code change, the lead's ruling: a known limit in `docs/DECISIONS.md`'s T133 entry).

## Not findings

- Item (1): the estimated words end "(talentsforever, predicted)" per section 3; the card mockup
  disagrees with section 3, and section 3 is the contract. Fine.
- Coefficient literals stay in `Spells/Coefficients.lua` and the generated files; no client call
  outside `Client/`; strings ASCII, no bare pipe; calibration untouched.
