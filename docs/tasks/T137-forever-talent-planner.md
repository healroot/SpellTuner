# T137: the talent planner (Forever)

The author, 2026-11-07: "Would it be hard to make a small copy of actual talents tree where player can
plan a build and so we calculate like he has those talents from the build". Mockup approved the same
day (claude.ai artifact "SpellTuner talent planner"): "sheet with real icons, keep the spinners too".

## Data

`tools/buildtalents.py` also writes `Data/TalentTree_Forever.lua` (GENERATED): every class's three
trees as the export lays them out -- name, row, col, max, req, icon, the top rank's sentence (ASCII).
Layout and words only: what a talent does to a number stays `Data/Talents_Forever.lua`'s.

## Rules (`Spells/TalentPlan.lua`, pure)

- Points: level - 9, 0..51 (assumed: one a level from 10; VERIFY), never under the live build's total.
- A talent opens when its tree has (row - 1) x 5 points above it, and its requirement is at full rank.
- A point never comes off when a talent of a later tier would lose its tier or a dependant has points.

## The bridge

- `TP:Current()`: a modelled talent's typed rank (the What if), else the kept plan's, else live. The kept
  plan is forgotten once the What if was cleared after the plan was applied.
- `TP:Apply(plan)`: every modelled talent typed in one change (`WI:SetMany`, one `WHATIF_CHANGED`),
  one equal to live cleared; the whole plan kept (unmodelled talents move no number but keep their tiers).
- The per-spell rank rows stay: they and the plan write the same What if keys.

## The sheet (`UI/TalentPlanner.lua`)

What if drawer -> "Talent plan..." beside TALENTS (shown when the line installs a planner and the live
ranks were read). An 840 x 520 sheet over the main window: info line, My talents / Clear / Use in What
if; three trees of 34-px cells with the talent's own icon (`Interface\Icons\<icon>`, the question mark
when the client refuses one), rank badge, blue dot for a talent the What if models, edge colour by state
(full accent, some good, open label, locked disabled and desaturated); the right panel: the hovered
talent, why it cannot take a point, its sentence, whether it moves numbers, every change from live.
Left-click adds, right-click removes. Use applies and closes; x / ESC discard. Never opens in combat;
closes with its window; never saved.

## Acceptance

`tools/talentplancheck.lua` (forever), `make check`; in game `docs/TESTING.md` section 58.
