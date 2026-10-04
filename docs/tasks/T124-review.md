# T124 review (first independent review)

Reviewer: Opus, adversarial. Diff `cc43c4e..HEAD` (a017677 tests, 8a65b71 code, 0dfe218 report).
Branch worktree-agent-a226519d3821b3238. No other review of this unit has been seen, so nothing here contradicts one.

(Written to the scratchpad: a hook refused the write into the agent worktree. Copy it to `docs/tasks/T124-review.md` there if wanted.)

## Verdict: approve (pass with minors). 0 blockers, 0 majors, 7 minors.

I ran these suites myself (not make check):
- whatifcheck: tbc 10/10, forever 9/9
- spellsui: tbc 16/16, forever 58/58
- bookshapecheck: tbc 18/18 (golden digests unchanged), forever 10/10
- bookcheck/forever: 33/33
- adaptercheck/forever: 26/26

All match the report's proposed counts.

## The acceptance criteria, as checked

**The footer (`WI.Changes`).** Every printed number comes from `whatFam`. The live family is read only for `suggested.id` and `rank`.
- The beaten reason uses `dominatedBy`, looked up in `whatFam`.
- The floor reason uses `MD.Rules.SUGGESTED_FLOOR` and `whatFam.maxKnown`.
- Both are consistent with `RankRules.Suggested` / `DominatedBy`. When the new rank has less per mana, the rule picked it either because the old rank was beaten or because the old rank fell under the floor. The order the footer checks them in (beaten first) matches.
- whatifcheck 8 gives the live families per-mana digits unlike the what-if ones and scans every footer for them. That test can fail.

**`DM.Compute`.**
- The new `opts.bonusDelta` is passed only by `Book:Build(true)` (`WhatIfDamage`).
- `DM.Compute` never reads `MD.sim`.
- The live digests did not move.

**`MD.sim`.** It is written only in `Spells/WhatIf_TBC.lua`. `Book_Model` reads it.

**Forever's `SpellBonusDamage`.**
- A secret answer goes through `MD.API.Call` and is unreadable.
- `DamageBonus` mirrors the heal branch: plain, stale in combat, secret -> last, nil before any reading, school names accepted.
- bookcheck T124 covers all five cases.

**The generation signature.** `EntrySig` still skips `bonus.amount` / `of`.

**No client calls outside `Client/` are added.** `Engine/DamageMath.lua:195` reads the global directly, but that line predates this diff and the file is TBC-only.

**ASCII.** All new strings are ASCII, with no bare pipe.

**The two changed assertions are legitimate.**
- bookshapecheck check 6 encoded the old missing binding.
- The removed spellsui T122-2 clause (`footer ~= "No change..."`) never proved that the suggestion moved. Under T122 a no-move footer also differed from the bare sentence. It cannot hold under the new rule. See m6 for the gap this leaves.

## Findings (all non-blocking)

**m1 (minor): `Spells/WhatIf_Forever.lua:120-121`.** `bonus.of = typed` and `bonus.amount = counts * typed` are set on every damage family. The family's value moved by `counts * (typed - live of the on-screen school)`.
- Failure scenario: Nature +100, Arcane +130, Wrath on screen, type 200 (delta +100).
  - Moonfire's value moves to Arcane 230, which is correct.
  - But its card says `of 200` and an amount of `counts x 200`, when it should say `of 230`.
- Shown today only if a Moonfire card is open while the what-if values came from Wrath. The provider rebuilds per screen, so this is latent.
- Fix: `nb.of = (b.of or live) + delta`, and amount = `counts * nb.of`.

**m2 (minor): `Spells/WhatIf_Forever.lua:138` (deviation 6).** With no live reading, `delta = 0` and nothing moves, yet `bonus.of` names the typed value. The heal path already behaves this way.
- Fix: leave `of` alone when the delta is 0.

**m3 (minor): joined-statement edit artifacts.** Two statements sit on one line with a run of spaces between them.
- Locations: `Spells/WhatIf.lua:280`, `Spells/WhatIf.lua:297`, `UI/SpellsPane.lua:1297`.
- The SpellsPane.lua line is outside the needed change: a pure reformat of two existing lines.
- The code is valid Lua and behaves the same. Readability only.
- Fix: split each back onto two lines.

**m4 (minor, layering): `Spells/WhatIf.lua:279`.** `WI.DamageSchool` reads UI state, `MD.SpellsPane.family` and its `IsShown()`. That makes the live +Spell damage, and so the delta, depend on which family view is open.
- The spec asks for exactly this ("the family on screen"), so it is noted, not wrong.
- `IsShown()` can be true while the main window is hidden.

**m5 (minor): report, Spells/WhatIf.lua.** The task asked the implementer to check that the strip, the chip, the cells and the RANKS note do not mix the two books, and to say so. The report does not state the outcome of that check.
- On reading the code, they each use the what-if book (the RANKS note is gated on `WI:Get(fam.kind)`).
- Fix: one line in the report.

**m6 (minor, test gap): `tools/spellsui.lua` T122-2 tbc and T124 forever.** No UI test paints the moved footer sentence. The only remaining pane clause is `footer == WI.Changes(liveFam, whatFam)`, which is close to tautological.
- The words are proven in whatifcheck 8 only.
- Fix: in T122-2, assert that the footer starts with `Suggested:` exactly when the two suggested ids differ, and is exactly `No change to the suggestion.` otherwise.
- Also: there is no WHAT IF fit test on Forever. The TBC T122-5 test iterates every row, including the new one.

**m7 (minor, test hygiene): `tools/spellsui.lua` T124 forever.**
- `ph == Num(phLive)` compares the placeholder with the same `WI:Live()` that painted it, so that clause is circular. `wrathLive == 120` carries the real assertion.
- The comment says "first damage family's school, Wrath's Nature" and then "Moonfire, Arcane, before Wrath". These contradict each other. Keep the second.

## Deviations judged
- 1 (BonusLine shows the typed stat by family kind): accepted.
- 2: accepted with m4.
- 3 (alt out of scope): accepted, as the spec says.
- 4 (MeasureBonus heal-only): accepted, as the spec says.
- 5 (no TBC stale handling): accepted. TBC's read is static and its tooltips are static.
- 6: see m2.
- 7: accepted.
- 8 (test setup changed after the tests-first commit): accepted. The original setup could not paint the pane, and the commit history is honest about it.
