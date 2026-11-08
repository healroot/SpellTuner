# T138: What if Level, plans to 51, the plan the only talent override (Forever)

The author, 2026-11-08: "lets make it possible to distribute up to 51 talents within what if. Show some
small warning that player dont have that much talents yet, and he need X level to reach it. Also add a
level override in whatif so that player can consider downrank penalty for future. Remove direct talents
+- override, so that talent plan is the only place to override talents".

## Level

- A What if key `level` (`Spells/WhatIf_Forever.lua`): 1..60 (the live level when higher), live = the
  player's level.
- A heal rank's +healing share moves by LevelPenalty(typed) / LevelPenalty(live)
  (`Spells/Coefficients.lua`). The share was read or estimated under the live level's penalty, so the
  ratio holds for a measured share and an estimated one alike.
- The value moves by the share's change times the live bonus. It doesn't move when no bonus was read.
- A live share of 0 stays 0: what it was before the penalty is not known.
- Damage ranks don't move. Ranks learned later aren't in the book, and the sentence says so.

## The plan

- The sheet may spend up to 51 points.
- The info line judges the plan at `TP.Level()`: the typed Level, else the player's.
- Past that level's points the line shows the warning `you don't have that many yet: needs level N`
  (`TP.NeedLevel`, points + 9).

## The drawer

- No talent rows; the talent keys stay accepted, typed only by the plan.
- The rows are Level, plus Spirit where Bloom touches the family.
- The title is LEVEL AND TALENTS.
- The sentence says either "Talents from your plan: ..." or "Your own talents; Talent plan... tries a build".

## Acceptance

- `tools/talentwhatifcheck.lua` 41, `tools/talentplancheck.lua` 26, `tools/spellsui.lua`, `make check`.
- In game: `docs/TESTING.md` sections 56 and 59.
