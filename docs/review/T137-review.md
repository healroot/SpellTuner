# T137 review -- the talent planner (and T136, durations in the What if)

Reviewer: independent adversarial review (Opus 5.5), 2026-11-07.
Diff: T136 is commit `62c0fa5`. T137 is uncommitted: `git diff` plus `Spells/TalentPlan.lua`,
`UI/TalentPlanner.lua`, `tools/talentplancheck.lua` and `docs/tasks/T137-forever-talent-planner.md`.
Verdict: **fail, on one major**: no blocker, 1 major, 9 minors. The rules are right. The way the plan
is kept is not: a reopened plan brings back talents the player took out. The rest are UI edges, two
in-game steps that cannot pass as written, and tests that still pass when the code they guard is
broken.

Scenarios were run with scratch scripts (`/tmp/t137r/probe*.lua`) against the real worktree under the
harness. Mutations were made only in a scratch copy (`/tmp/t137r/copy`). `tools/check.sh` was not run
(the brief forbids it). Suites run: `talentplancheck` 17/17 and `talentwhatifcheck` 39/39 (forever),
`restylecheck` 45/45, `themecheck` 38/38, `apicheck` 0 findings, `textcheck` 0 findings.

## What was verified

- **Tier and requirement rules** (`Spells/TalentPlan.lua` CanAdd / CanRemove). A tier opens at
  (row - 1) x 5 points in the rows above it. A requirement must be at full rank. A removal is refused
  when any talent in a later row of the same tree, two or more tiers up included, would drop under its
  threshold, or when a dependant has points; a chain A -> B -> C is held at every link. For plans that
  follow the rules, counting only the rows above gives the same answer as the game's whole-tree count,
  because the removal rule keeps every occupied row's threshold true. Same-row requirements (Paladin
  Boundless Light, Priest Improved Mind Flay) work.
- **Data agreement** (probe2): every class has three trees. Every talent the What if models is in the
  tree under the same name, and its max there equals the What if row's max. So `Clean` never clamps a
  value that Apply writes.
- **Points**: level - 9, clamped to 0..51, never under the live total of names the tree knows.
- **`WI:SetMany`**: refused values are skipped, nil clears, and `WHATIF_CHANGED` fires once. The suite
  asserts the serial (+2 across Set plus Apply).
- **T136**: `parse_duration` refuses any text after the seconds, so a second clause or "seconds" gets
  the talent named and skipped. Channels are excluded, and the live book is untouched (suite section 6).
  Moonfire's damage hybrid lengthens only its over part. Insect Swarm (+2 s) and Improved SW:P (+3 / +6)
  use the parsed `dur`. Typed down from live, the part shortens.
- `UI/TalentPlanner.lua` calls no client global outside the kit (`CreateFrame` only, as other UI files
  do), and apicheck agrees.

## Major

**M1 -- `Spells/TalentPlan.lua:141-142` with `UI/TalentPlanner.lua:136` and `Spells/TalentPlan.lua:161-163`:
a reopened plan brings back every unmodelled talent the plan took to 0.** `Change` stores rank 0 as
`plan[name] = nil`. Apply copies the plan as it is, so the kept plan has no entry for that talent.
`Current` then reads `TP.kept[name]` as nil and falls through to `live[name]`. Run: live Nature's
Focus 5, Naturalist 5, Gift of Nature 2. Apply `{ Heart of the Wild 5, Naturalist 5, Gift of Nature 2 }`
(Nature's Focus moved into Heart of the Wild). The next `Current()` has Nature's Focus 5 and Heart of the
Wild 5, 17 spent, where the plan spent 12. A respec that uses every point (all 17 at level 26) reopens
at 22 spent of 17. The sheet then refuses every add as "no points left", and Use re-applies the talent
the player removed. No number moves today, because the talent is unmodelled, but the sheet shows a
build the player did not make, and it breaks the tier rules. The fix: keep explicit zeros in the kept
plan (or keep `live` with the plan and diff against it), and add a suite case that removes an
unmodelled live talent.

## Minor

**m1 -- `Spells/TalentPlan.lua:135` with `Spells/WhatIf.lua:162-163`: after a plan of only unmodelled
talents, Clear does not forget the plan.** Apply types nothing, so the What if stays empty. The drawer's
Clear then answers false and does not bump the serial, so `serial == keptAt` and the plan stays kept.
Run: Apply `{ Nature's Focus 3, ..., Heart of the Wild 2 }`, then `WI:Clear()` -> false, and the next
plan still has Nature's Focus 3 and Heart of the Wild 2. `docs/TESTING.md` 58.5 ("Clear the What if:
the next Talent plan... starts from your live build again") fails for such a plan. Only a `/reload`, or
My talents followed by Use, gets back to live.

**m2 -- `UI/TalentPlanner.lua:194,277` with `UI/SpellsPane.lua:1592,1643-1646`: the mask does not
cover the What if drawer, and its "Talent plan..." button throws away the plan in progress.** The
sheet's mask is `SetAllPoints(win)`. The drawer is a child of `win`, anchored outside it
(`TOPLEFT` to `win`'s `TOPRIGHT`), so its spinners, Clear and "Talent plan..." can all still be clicked.
Run: Open, add Bloom, then Open again -> Bloom gone, because `plan = TP:Current()`. A spinner changed
while the sheet is open does not repaint the sheet (it does not listen to `WHATIF_CHANGED`), and Use
then silently overwrites it. Either mask the drawer as well, or keep the plan when the sheet is already
shown.

**m3 -- `UI/SpellsPane.lua:1737-1749,1782`: the planner's button appears only on a spell some modelled
talent touches.** The button sits in the `classRows` branch. A family with no talent row, which gets
the "No talent moves this spell" note, hides it. A Hunter has 0 modelled rows (probe2: Hunter, Rogue
and Warrior all 0) and so never sees the button, even though the trees exist. A Mage (2 rows) sees it
on two spells only. The task says the button shows "when the line installs a planner and the live ranks
were read".

**m4 -- `UI/TalentPlanner.lua:221-232`: the right panel uses fixed y offsets with nothing measured.**
`selDesc` starts at y 104 and `selModel` at 196, leaving 92 px for the description: about 7 lines of
FONT_SMALL (11 px) at 218 px width, roughly 280 characters. Ten sentences in the tree are longer.
Moonkin Form's (about 460 characters, about 12 lines, about 156 px) runs over `selModel`, the "Changes"
header (236) and the changes list (256). The changes list is unbounded as well. A level-60 plan far from
live gives 15 or more lines, many wrapped at 218 px, which run into the legend at y 458 and past the
sheet's bottom. `fontOffset` +2 makes both worse. `selInfo` (62 to 104) holds three lines; with a wrapped
requirement plus a reason it needs four.

**m5 -- `UI/TalentPlanner.lua:45-48,204-207,215` and `Spells/TalentPlan.lua:149`: illegal plans are
painted as legal and applied.** The spinners still write the same keys, so Bloom 1 typed on a build with
5 Restoration points opens as "maxed", with an accent edge and no warning. Nature's Focus then cannot
come off ("Bloom would lose its tier"), and Use applies the plan unchecked. The info line shows more
spent than the points available in the ordinary label colour. My talents copies live ranks without
clamping them: live Nature's Focus 7 against a tree max of 5 gives `7/5`, while `Current()` clamps the
same talent to 5.

**m6 -- `Spells/WhatIf_Forever.lua:364-371` (T136): a lengthened hybrid's +healing share is scaled by
the ratio of the whole value, not by the over-time part alone.** Regrowth R2 with Nature's Splendor:
live share 0.783 (0.286 + 0.071 x 7). The copy gets 0.887. The over-time share alone gives
0.286 + 0.497 x 27/21 = 0.925, so the copy is 4% low, and with +150 Healing typed the heal comes out
about 6 low. T134 accepted this same approximation for Genesis in writing. `docs/DECISIONS.md`'s
"Durations in the What if" never mentions the share.

**m7 -- `docs/TESTING.md:2526-2527` (56.5) and `docs/DECISIONS.md:1680-1681`: "Heal x15/12 ... Per sec
unchanged" is false at that point in section 56.** Step 2 types Bloom, and nothing clears it before step
6. Run with Bloom typed: Rejuvenation 472 -> 495 (x1.049, not x1.25), per second 39.3 -> 33.0 (x0.84).
Bloom is added to the value but not stretched with the duration. A druid who really has Bloom sees the
same thing. The step needs "clear Bloom first", or the expected numbers with Bloom.

**m8 -- `docs/TESTING.md` 58.3 and CHANGELOG `## Next`: this step needs level 31.** Bloom is in row 3
and needs 10 Restoration points. Nature's Splendor is in row 3 and needs 10 Balance points including
Nature's Majesty 2/2. With the 2 talents themselves that is 22 points, that is level 31. At the author's
last known level (25 or 26, 16 or 17 points) the step cannot be done. The CHANGELOG's "every spell's
numbers follow the planned talents" holds only for the modelled (blue-dot) talents.

**m9 -- `tools/talentplancheck.lua:197-264`: tests that pass with the code broken.**
- With `CellState`'s locked check removed (`UI/TalentPlanner.lua:53`), the suite still passes 17/17:
  nothing asserts the edge state or the desaturation.
- With both the `win` OnHide hook (`:240`) and the ESC push (`:283`) removed, it still passes 17/17,
  although the task's acceptance names both "closes with its window" and "ESC discard".
- "4 Use in What if" builds `rj = book.spells[1430]` and asserts nothing about it. In this suite's stub,
  1430 is nil (the detail prints `nil`), so section 58.3's "Rejuvenation's Heal and Per mana move" is
  not tested from the sheet's side.

## Not findings

- The `Layout` cache keyed on the `trees` table, and the cells left over when it rebuilds: the class
  cannot change without a `/reload`, so the cache never goes stale.
- `live` is captured once at Open (`:272`), so a respec at a trainer while the sheet is open makes
  Changes and My talents stale. Apply reads live afresh, and the plan is absolute. This was read in the
  code, not run.
- ESC with `db.ui.escStack = false`: the sheet has no name, so ESC closes the window, which then closes
  the sheet. Every unnamed sheet shares this.
- Fired within `SetMany` before `keptAt` is set, a handler that called `Current()` would forget the plan.
  No handler does today.
- `SetTexture` returning false on an unknown icon cannot be checked outside the client. The fallback is
  correct as written.
- This is a first review; it contradicts no other review.

## Fixed (2026-11-07, before the first commit of T137)

- **M1** `TP:Apply` keeps every tree talent's rank, 0 included; `Current` reads it. Test "3 review M1".
- **m1** `WI:Clear` counts every clear (`WI.clears`), empty or not; the kept plan is forgotten when the count moved since Apply. Test "3 review m1".
- **m2** A second press on Talent plan... keeps the plan in progress; a spinner moved while the sheet is open re-syncs the modelled talents in the plan and repaints. Test "4 review m2".
- **m3** The drawer shows Talent plan... for a family with no talent rows too (the note moves down). Test "4 review m3".
- **m4** The right panel chains each line under the one before; the changes list stops at 10 with "and N more".
- **m5** `TP.Problems(plan, trees, points)`: a plan past the rules (tier, requirement, points) is said on the info line in red, the cell's edge red; My talents clamps to each talent's top. Tests "3 review m5", "4 review m5".
- **m6** Accepted, written in `docs/DECISIONS.md` (Regrowth's share ~4% low under Nature's Splendor, as Genesis in T134).
- **m7 / m8** `docs/TESTING.md` 56.5 says Clear first; 58.3 plans Bloom only (fits level 25/26), 58.6 the rules check; CHANGELOG says the numbers follow the talents SpellTuner models.
- **m9** Tests: locked edge = disabled, the sheet on the ESC stack, the window's hide hides it; the empty rj read dropped. Suite 17 -> 24.
