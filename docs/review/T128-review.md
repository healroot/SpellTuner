# T128 review -- multiplicative trade score, rank tips explain themselves

Commit reviewed: 3655411 (diff vs 08ab7e4), against `docs/tasks/T128-trade-score-and-rank-tips.md`
with the lead's ruling that the 1010 oracle is best R6 (1.075 > R7 1.054). Reviewer: independent
(Opus 5.5, high). `make check` not run (a gate-runner owns this tree). Each finding was checked by
reading the code path. Two were also run: `bookshapecheck --print` scores for the moved goldens,
and a scratch harness run of Lifebloom's stack marks.

**Verdict: fail** -- 0 blockers, 1 major, 4 minors.

## Verified correct

- `RR.Score` (`Spells/RankRules.lua:89`) returns nil when any input is missing or when
  `me <= 0` / `ms <= 0`. It returns 1 by identity for max, so max always scores exactly 1. It
  returns nil for a negative rate. A rate of 0 gives 0 at k > 0, and `0^0 = 1` at k = 0, which
  leaves e/me (the k = 0 rule). A NaN input makes the score NaN, which never passes `> 1`, and
  `W.Score` prints `-`. `RR.Marks` starts `bestScore` at 1 and compares strictly, so a score of
  exactly 1 and every tie go to max or to the first of equals. Check 7 uses a score of exactly
  2 * 0.25^0.5 = 1.
- Oracles recomputed by hand. At 1010: R6 1.0745, R7 1.0544, R1 1.0224. R2 scores 0.959, R3
  0.969, and R4 and R5 are dominated by R6. At 460: R7 1.0364, R6 1.0331. Checks 16-19 can
  each fail.
- Goldens. Under the new rule, every moved best is the argmax over the non-dominated ranks that
  clear the floor:
  - Regrowth at L40 tree off goes to max R9. R4 scores 0.985 (it was +0.029 under the additive
    rule) and R3 is under the floor.
  - Healing Touch at L40 tree on goes to R12. R6 scores 0.9905 and R5 (1.004) is under the floor.
  - Renew goes to R8 (1.0022, R7 0.9987).
  - Flash of Light goes to R5 (1.0179, R4 1.0044, R1 under the floor).

  Since E * S^k <= 1 + (E-1) - k(1-S) for S <= 1, best can only move toward higher per sec, and
  all four moves do. The commit message lists every moved family.
- `RULE_VERSION` is 3, so an Advisor snapshot taken under rule 2 is re-seeded silently, and the
  pane signature and the Book_Model generation change too.
- Under What if, the GameTip rank-row hover passes `{ book, pool }` both through `SetView` (the
  hook path) and through `Lines(..., view)` (the fallback). The view is cleared on leave and on
  OnHide. `NowPool` and `CastsFromFull` read the view's pool. The tag-cell tips read
  `r.family`, which is the what-if family.
- Words: the card Marks line, the strip's full and short styles, MarkTip, SuggestedRule and the
  settings tips all say the score as a ratio. No additive score is left in code. Strings are
  ASCII with no bare `|`. The TRADE lines use the `text` and `label` tokens.

## Major

**M1 -- Lifebloom's own rank row gets the family's TRADE verdict, which contradicts its tag and
card.** Fixed in 7880c65. `UI/SpellsPane.lua:552` (`RankTradeTip(fam, e)`, defined at 657).
- Scenario: a TBC druid with Lifebloom, harness default book. Lifebloom R1 has perMana 6.69 and
  perSec 981. Rolled x3 has 7.11 and 1043, so `RR.MarkVariants` puts `bestOfStacks` on x3.
  `TagOf` tags the R1 row `beaten`, and the card's Marks line says best is rolled x3. Hovering
  R1 shows `TRADE / this rank is max`, `Score 1.000 vs max 1.000`, `Verdict holds best, max,
  eff`, because `fam.suggested`, `fam.maxRank` and `fam.effRank` are all R1 (one rank).
- The task says "Lifebloom stack rows likewise", and `StackTradeTip` already names the parent
  (`"Rank 1 one cast"`), but the parent row never reaches it. No test hovers the rank row; the
  spellsui case hovers only the first rolled row.
- Related wording: on the x3 row (the stack's max), `Words.lua:642` says "this rank is max" for
  a rolled row.
- Fix: in `GameTip` / `RankTradeTip`, when `e.variants` is a table, build the block with
  `StackTradeTip(e, e)`, so the verdict is "beaten by rolled x3" against the stack. Have
  `TradeLines` take a `selfWord` such as "this row is max" from the context. Add a spellsui case
  that hovers the Lifebloom rank row and asserts its verdict agrees with `TagOf`.

## Minor

**m1 -- With After overheal on, the TRADE block's percentages do not match the row's cells.** Fixed in 7880c65.
`UI/SpellsPane.lua:657-664`, `Spells/Words.lua:644-646`.
- Scenario: After overheal on, TBC Healing Touch with measured overheal. The Per mana and Per
  sec cells show `Shown(e, after)` (effHpm / effHps). The TRADE `Per mana +x%` / `Per sec -y%`
  and the score use raw `e.perMana` / `e.perSec`, the numbers the marks are computed from. The
  task asks for "the numbers from the same book the row shows". The old TagTip has the same gap.
- Fix: when `AfterOn()`, add a muted line "before overheal (the marks' numbers)" to the block.
  Alternatively, mark on effective numbers, but that is a rule change.

**m2 -- A kindless spell's row tooltip still counts Casts to OOM from the live pool under What
if.** Fixed in 7880c65. `UI/SpellTip.lua:510` (`OtherLines` uses `Book:DefaultPool()` and ignores `activeView`).
- Scenario: What if with a typed Mana of 20000, then hover a mana-cost utility row in the OTHER
  table (Mark of the Wild). GameTip passes the view, but the block says `Casts to OOM` against
  the live max. The task says to fix it "for every column tip".
- Fix: use the same `activeView.pool` branch as `CastsFromFull` (a full pool of the view's max
  and regenCasting).

**m3 -- Leftover "worth what it loses" sentences state the old rule without "at the margin", and
contradict the marks shown.** Fixed in 7880c65.
- Where:
  - `UI/SpellsPane.lua:2290`, the Overview `Best` column tip.
  - `Spells/Words.lua:568-569`, MarkTip best = max: "(heals: 1% per mana for 6.7% per second)".
  - `Spells/Words.lua:797-798`, the CompareBestIsMax full sentence "(heals, 6.7:1)".
  - The stale comment at `Words.lua:504` ("worth it for damage at 4:1").
- Scenario: Regrowth at L40 live. R4 is +11% per mana for -56% per sec. At the stated 6.7:1,
  +11% buys 74% per sec, so a reader concludes R4 should be best. Under the new rule it scores
  0.985 and best is max. The appended `, score 0.948`-style tail does not explain the gap.
- Fix: add "at the margin" to both parentheticals, as `SuggestedRule` and the settings tips now
  do. Reword the Overview tip to "the rank that scores highest against max (per mana x per sec^k)".

**m4 -- The strip fit test cannot catch a wrong room, only "no style fits".** Fixed in 7880c65.
`tools/spellsui.lua` (T128 strip case).
- The check wraps with the same 8 px function the code is given, against `st.compareW`, the width
  the code computed itself. If `compareW` were wrong (the task's own hypothesis: room measured for
  the other chip), the code and the test would agree and pass.
- The commit's root cause (CompareFit painted its last style when none fit) is plausible, and the
  new `brief` / `least` styles address it. The room itself is still unchecked.
- Fix: also assert `st.compareW` against the geometry: the strip width minus the chip, the gap
  and the inset of the What if button and side column. The stub's `S.Geometry` can resolve
  `compare:GetWidth()` from its two anchors. Run it in both chip states (BEST and WHAT IF with
  `live: Rn`).
