# T124 report -- What if compares like with like, +Spell damage on both lines

Branch `worktree-agent-a226519d3821b3238` (from cc43c4e). Commits:
- a017677 -- tests first (whatifcheck, spellsui, bookcheck, adaptercheck); they failed before the code.
- 8a65b71 -- the code, plus the two obsolete assertions and the T124 test's setup fix (see Deviations).
- this report.

## What changed, by file

- `Spells/Words.lua`: new `W.SuggestionMoved(old, new, beatenBy, top, kind)`. It returns
  `Suggested: Rank X -> Rank Y. With these stats Rank Y gives P per mana, Rank X Q (+n%).`
  When P < Q it adds the reason: ` Rank X is beaten by Rank N.`, or else
  ` Rank X is under 40% of Rank M's heal|damage.`
- `Spells/WhatIf.lua`:
  - The STATS row `+Spell damage` (step 25, big step 100), placed after `+Healing`, and its summary word `spell damage`.
  - `WI.DamageSchool(book)`: the school of the damage family on screen (`MD.SpellsPane.family`, a preview included). Otherwise the school of the book's first damage family in its order.
  - `WI.LiveDamage(Book)`: `Book:Bonus("damage", school)`.
  - `WI.Changes`: both numbers come from the what-if book. The live family supplies only which rank was suggested. Missing input, or the same suggestion, reads `No change to the suggestion.`
- `Spells/WhatIf_TBC.lua`: `damage` is added to the keys, and `Live().damage` is set.
- `Engine/DamageMath.lua`: `DM.Compute(spellID, family, base, class, opts)`. `opts.bonusDelta` moves the bonus, never below 0. DamageMath never reads `MD.sim`.
- `Spells/Book_Model.lua`: `WhatIfDamage()` returns `{ bonusDelta = MD.sim.damage - live }`. It is passed only when building the what-if book (`DamageFamilies(..., dmgOpts)`).
- `Client/API_Forever.lua`: `MD.API.Bind({ SpellBonusDamage = "GetSpellBonusDamage" })`.
- `Spells/Book.lua`:
  - `Book:Bonus("damage", school)` takes a school name or an id from 1 to 7.
    - Out of combat it answers the plain value, `false`, and keeps it in `Book._lastDamage[id]`.
    - In combat, or when the read fails, it answers the last plain value and `true`. Before any reading it answers nil.
  - The scan's bonus cache is keyed by kind and school.
  - A damage entry's `bonus.of` / `amount` are now its school's reading.
  - `fam.school` is the first rank's parsed damage school.
- `Spells/WhatIf_Forever.lua`:
  - `Live().damage` is set.
  - Each family moves with its own stat: heal ranks with +Healing, damage ranks with +Spell damage. A damage rank moves by `bonus.counts x delta` on `parsed.damage`, then `Book.Numbers(w, "damage")` and the rank rules run again.
  - `ranksNote` appears for a heal or damage family only while that family's own stat is typed.
- `UI/SpellsPane.lua` (BonusLine only): the typed stat follows the family's kind. A heal shows `+N healing`. A damage family shows `+N <School> damage`, in the accent, with a muted ` what if`.

## Suite counts (run on their own; each flavour run separately)

| Suite | tbc before | tbc after | forever before | forever after |
|---|---|---|---|---|
| whatifcheck | 8 | 10 | 7 | 9 |
| spellsui | 16 | 16 | 57 | 58 |
| bookcheck | 2 | 2 | 32 | 33 |
| bookshapecheck | 18 | 18 | 10 | 10 |
| adaptercheck | 19 | 19 | 26 | 26 |
| tipcheck (sanity) | skip (forever only) | skip | 53 | 53 |

All of them now pass with 0 failed. `apicheck` reports 0 findings and `textcheck` reports 0 findings. `luac -p` passes on every touched file.

**make check: not run** (the lead's instruction).

## Deviations

1. **`UI/SpellsPane.lua` BonusLine.** Before this change the typed value always read `+N healing`. A damage family now shows its own stat.
2. **The WhatIf files read `MD.SpellsPane.family`** to find the school on screen.
   - With a heal family on screen, the live +Spell damage is the school of the book's first damage family.
   - One delta (typed minus the live value of that school) moves every school.
   - Spell-damage gear adds to every school alike, so this matches the gear.
3. **Out of scope:** either-or families (`altKind` / `entry.alt`) are not moved by +Spell damage.
4. **`Book:MeasureBonus` stays heal-only.** Damage ranks always move by the estimated coefficient.
5. **TBC** reads raw `GetSpellBonusDamage` through `DM.Bonus` (the existing path). No stale handling on TBC.
6. **When nothing has been read:** with no live reading, Forever's `Move` gives `{ delta = 0, typed }`. Nothing moves, but `bonus.of` names the typed value.
7. **Two existing assertions no longer matched the spec.** Each was changed to the T124 behaviour; neither was weakened.
   - `tools/bookshapecheck.lua` check 6 asserted that `Book:Bonus("damage", "Nature")` is nil, which held only because Forever had no binding. T124 adds that binding. The check now asserts the stub's Nature reading with `stale == false`.
   - `tools/spellsui.lua` T122-2 (tbc) asserted that the footer was not `No change to the suggestion.` In T124 a suggestion that did not move reads exactly that. The clause `footer == WI.Changes(liveFam, whatFam)` still stands.
8. **My own T124 spellsui/forever test had a wrong setup.** It changed after the tests-first commit.
   - The stub's Wrath has one rank, so it has no strip and no What if pane. The pane opened on Wrath was never painted.
   - The test now opens the pane on Nourish. It asserts:
     - the `+Spell damage` placeholder equals `WI:Live().damage`;
     - with Wrath on screen, `WI:Live().damage == 120`;
     - Wrath's header shows `+200 Nature damage what if`;
     - Nourish's footer is `No change to the suggestion.`
   - The original `ph == "120"` could not hold for a heal on screen, because this suite's Moonfire (Arcane) comes before Wrath in the book's order.

## Proposed expected-counts changes

- whatifcheck: tbc 8 -> 10, forever 7 -> 9
- spellsui: forever 57 -> 58
- bookcheck: forever 32 -> 33

## Proposed TESTING line (section 49 or new 50)

- Spells -> a family with several ranks -> What if...:
  - Type +Healing so that the suggestion moves. The footer reads `Suggested: Rank X -> Rank Y. With these stats Rank Y gives P per mana, Rank X Q (+n%).` Both numbers should match the per-mana cells shown in the table.
  - Type a value that leaves the suggestion where it is. The footer reads `No change to the suggestion.`
  - Open Wrath (TBC: any damage spell). Type +Spell damage. The header reads `+N Nature damage what if` in the accent, and the Value / Per mana cells move.
  - On Forever, check that the header's live `+N Nature damage` matches the character sheet's spell damage.

## Proposed CHANGELOG line

- What if: the footer now compares the old and new suggested rank with the same stats, and says why when the new one gives less per mana. New `+Spell damage` row, on both TBC and Forever; Forever now reads your spell damage per school.
