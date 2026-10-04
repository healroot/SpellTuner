# T127 review -- rank marks eff / max / best

Commit reviewed: e9a7012 (diff vs 8aac028), against `docs/tasks/T127-rank-marks.md` and
`docs/mockups/rank-marks.html`. Reviewer: independent (Opus 5.5, high). `make check` not run
(a gate-runner owns this tree); every finding below was verified by reading the code path.

**Verdict: fail** -- 0 blockers, 1 major, 7 minors, 1 nit.

## Verified correct

- `RR.Score` / `RR.TradeK` (`Spells/RankRules.lua`): nil on any missing input, nil when
  `me <= 0` or `ms <= 0`, so no division by zero or NaN; k outside 0..1 or not a number falls
  back to `ST.Rules`. k = 0 picks the most per mana among non-dominated rows; k = 1 scores at
  most 0 for any slower rank, so best = max. Ties take the first of equals. With score <= 0 for
  every row, best = max.
- The 40% floor applies to `kind == "heal"` only; damage call sites (Book_Model `DamageFamilies`,
  WhatIf) pass `"damage"`. `tools/whatifcheck.lua`'s re-based "trade against max no longer pays"
  expectation is the honest result: damage has no floor.
- Forever gaps / stale entries: Book's `RULE_FIELDS.eligible` needs `known and perMana and perSec`,
  so a gap or stale entry never reaches `Score`. TBC rows are always numeric.
- Planner, sim and `SpellKit` never read `suggested`, so nothing changes there.
- Goldens: HT / Regrowth / Rejuvenation now suggesting max at heal k 0.15 is the rule's honest
  result (e.g. HT at L40: R6 scores -0.0188, R5 is under the floor, so max R12). The oracle in
  `tools/bookcheck.lua` follows the new rule; it was not bent to hide a bug.
- `tools/rankmarkscheck.lua`: 11 cases checked by hand, all sound, and each can fail.
- Lifebloom: `RR.MarkVariants` runs on the rolled rows; `bestOfStacks` drives the tag.
- Settings persist to `ST.db` with registered defaults; `RANK_RULES_CHANGED` marks the Forever
  book dirty and rebuilds the TBC book; the What if book recomputes the marks on both lines
  (`WI:Book()` is not cached).
- Colours: `good` is a token in `UI/Style.lua:125` and `UI/Theme_Flat.lua:87`, with a
  `UI/SpellTip.lua` FALLBACK. New strings are ASCII, no bare `|`.

## Findings

### M1 (major) -- Advisor gear toast compares against a snapshot taken under the old rule

**Fixed in 2d63ed9.**

`UI/Advisor.lua:57-77` (with `:86-90` and `Engine/RankMath.lua:681`).

`CheckRankShift` compares `RankMath:SuggestedRanks()` (now the best mark) with the persisted
`ST.cdb.suggestedRanks`. `MD_READY` re-seeds the snapshot only when it is absent, and nothing
re-seeds it on `RANK_RULES_CHANGED`.

- Upgrade: a druid who had `suggestedRanks = { HT = 6, Rejuv = ... }` saved under 0.17.1's old rule
  upgrades. On the first `PLAYER_EQUIPMENT_CHANGED` (any gear swap) they get
  `gear change - Healing Touch R12 is now your efficient rank (was R6). Rebind?`, and the same
  for Rejuvenation and Regrowth. Gear did not cause it, and nothing should be rebound.
- Settings: moving Review -> MODEL -> Trade-off (heals) changes best for several spells while the
  snapshot stays put. The next gear change attributes all of those shifts to gear.
- Wording: "efficient rank" is now wrong, because best is not eff (T127's whole point).

Fix: register `RANK_RULES_CHANGED` in Advisor to re-seed `ST.cdb.suggestedRanks` silently; stamp
the snapshot with a rule version plus both k values and, on a stamp mismatch at `MD_READY` or in
`CheckRankShift`, replace it instead of comparing; say "best rank". Add a harness case: seed an
old snapshot, fire an equipment change, expect no toast.

### m1 (minor) -- "Suggested" wording survives beside "Best"

**Fixed in 2d63ed9.**

`UI/SpellsPane.lua:2192` (My spells column "Suggested", tip "The rank SpellTuner suggests."),
`UI/SpellsPane.lua:2742` (Overview tip "Suggested  Rank N of M known"), `Spells/WhatIf.lua:315`,
`:322`, `:341` ("Suggested: Rank X -> Rank Y", "No change to the suggestion."),
`Spells/Words.lua:745`.

Scenario: the chip says BEST and the tooltip says "Best", while the My spells column and the What
if footer say "Suggested" for the same rank. Mockup Q5 recommended renaming the column to Best.
Fix: rename to Best across these surfaces and re-base the goldens.

### m2 (minor) -- Lifebloom: the suggested fill sits on R1 while the best tag is on x3

**Fixed in 2d63ed9.**

`UI/SpellsPane.lua:869` (`suggested = e.suggested`) with `UI/Dashboard_Rows.lua` PaintFill.

Scenario: Lifebloom with x3 as `bestOfStacks`. The accent fill and the mark bar paint the R1 base
row (it carries `suggested`); the "best" tag paints the x3 rolled row. Mockup M4 puts the fill on
x3 and tags R1 and x2 "beaten"; the implementation leaves them untagged unless `dominated`.
Fix: give the rolled row holding `bestOfStacks` the `suggested` flag for the fill, and tag the
non-best rolled rows as M4 shows.

### m3 (minor) -- Dead callout string with a task tag and the old wording

**Fixed in 2d63ed9.**

`Engine/RankMath.lua:661`: `"Max rank (R%d) is also the best trade (T127: no lower rank saves..."`.
No UI reads `callout`, only the goldens. A task id inside a user-style string leaks if anything
ever shows it. Fix: drop the "(T127: ...)" from the string (keep it as a comment) or remove
`callout` if nothing will read it.

### m4 (minor) -- bookshapecheck re-base comment understates what moved

**Fixed in 2d63ed9.**

`tools/bookshapecheck.lua:526-533` says only the druid's HT, Regrowth and Rejuvenation moved.
The class golden also moved: Priest Renew, Flash Heal, Circle of Healing, Greater Heal; Shaman
Chain Heal, Lesser Healing Wave; Paladin Flash of Light. The results follow the rule; the comment
does not. Fix: list every moved family so the next reviewer can audit the re-base.

### m5 (minor) -- Settings duplicate the rule constants as literals

**Fixed in 2d63ed9.**

`UI/Settings.lua:523`, `:529`: defaults 0.25 / 0.15 and the "40%" in the tips are typed in, not
read from `ST.Rules.TRADE_K_DAMAGE` / `TRADE_K_HEAL` / `SUGGESTED_FLOOR`. Scenario: a later change
of `ST.Rules.TRADE_K_HEAL` to 0.2 leaves the slider's default and the tip saying 0.15 and 40%.
Fix: read the constants (format the floor as a percentage).

### m6 (minor) -- RANK_RULES_CHANGED fires on every drag step

**Fixed in 2d63ed9.**

`UI/Settings.lua:520` with `UI/Style.lua:3217` (`onValueChangedFn` on each `userChanged` step).
Scenario: dragging the heal slider from 0 to 100 at step 5 fires up to 20 events, and on TBC each
one runs a full `Book_Model` Rebuild (RankMath Compute across every family). Fix: fire from the
slider's after-value-changed / mouse-up callback, or coalesce to one fire per frame.

### m7 (minor) -- Words disagree with RR.Marks in edge cases

**Fixed in 2d63ed9.**

`Spells/Words.lua`:
- `UnderFloor` checks only `fam.maxKnown.value`; `RR.Marks` falls back to `max.value` when top
  has no value. On Forever, when the highest known rank has no value (a gap), the rule applies
  the floor against max and the reason says nothing, or the reverse.
- `Compare` heads "(max)" even when the strip passes the `maxKnown` fallback
  (`fam.maxRank or fam.maxKnown`).
- `CompareSame` still says "Your highest rank is also the best per mana."
- `SuggestedRule` calls max "the fastest rank": max is the most per second, not the shortest
  cast (the rankmarkscheck "shorter-cast max" case shows they differ).
Fix: mirror the rule's fallback in `UnderFloor`; label the fallback "(highest)"; reword the two
sentences.

### n1 (nit) -- TBC: ratio text stale after a k change that does not move best

**Fixed in 2d63ed9.**

`UI/SpellsPane.lua` `Signature` does not include k, and on TBC `Book_Model` Refresh fires
`BOOK_CHANGED` only when its signature (which holds `suggested`, not k, effRank or maxRank)
changes. Scenario: the Spells view is open, the heal slider moves from 0.15 to 0.20, best does not
move: the strip and card keep "at 6.7:1" until the view is navigated away and back. Fix: add the
two k values (and effRank / maxRank) to either signature.

## Must fix before merge

- M1: re-seed and version-stamp the Advisor's `suggestedRanks` snapshot on `RANK_RULES_CHANGED` and
  on upgrade, and say "best rank" in the toast.
