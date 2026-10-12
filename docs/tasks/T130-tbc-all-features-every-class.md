# T130: every feature for every TBC class -- coach, simulate, advisor

Author's ruling (2026-10-12): "now lets make all features avaliable for all classes".
This overrides decision 8 (b) (`docs/DECISIONS.md` "TBC other classes read their bases
from the tooltip", and the 2026-10-11 practice entry that kept "the coach, the simulator
and the advisor" the druid's). Add a dated `docs/DECISIONS.md` entry saying so.

**Scope.** The TBC line only: `Data/Profile_{Priest,Shaman,Paladin}_TBC.lua` grant
`coach`, `simulate` and `advisor`, and each feature works on the class's own book.
Forever is unchanged: every Forever class already has `coach` and `practice`, and
Simulate (`UI/SimWindow.lua`) and the advisor (`UI/Advisor.lua`) are on the TBC TOC only.
The druid's behaviour must not change (its suites stay green with unchanged counts,
except new checks you add).

What already exists (branch `tbc-priest-fixes`, commits b4c0eca, 0a6d68e, ff7e599):
- `ST.Kit.Index()` (Engine/Kit.lua) is the spell index for sim / practice / recorder /
  replay: the TBC class book via `RankMath:Source()` when `RankMath:IsClassBook()`,
  else `ST.SpellData`. Never read `ST.SpellData` directly on these paths.
- `RankMath:SpellKit` returns `RankMath.ClassKit` for a class book.
- Practice works for TBC classes (`PR.Policy()` -> `TBC_CLASS_POLICY`, `kitIsLive`).
- The recorder records every class; `tools/tbcclasscheck.lua` already runs a priest
  practice session through the eight gates.

## 1. Coach (the pattern is Forever's, T106)

- Forever classes coach **solver only**: their profile names a `planner = { families = {...} }`
  and no `rules` (the threshold rules are the druid's tactics; `docs/SPEC-next.md` 4.2 P2),
  and `Engine/SimPlanner.lua` compares the solver's causal strategies for a kit whose profile
  names no threshold rules. Give each TBC class profile a `planner` the same way (families in
  candidate order, from the families the TBC profile already has; copy the Forever profile's
  order where the families match). `hotSlots` already exist.
- Grant `coach`. Every gate asking `Can("coach")` (UI/Dashboard_Review.lua,
  UI/ReplayWindow.lua, Engine/ReviewCommands.lua) must then work: `/st coach`, Review ->
  Coach, the replay's SUGGESTED column. Find and fix any TBC path that assumes the druid
  (`ST.SpellData`, druid families, `RC.policy`, SimPlanner's TBC rule lists, card text).
- Unmodelled spells and the group assumption are named on the card as on Forever.

## 2. Simulate (`UI/SimWindow.lua`, Data/SimPresets.lua)

- Grant `simulate`. The window builds a fight from presets and runs the engine: make it
  run on the class's kit (`Kit.Index`, `SpellKit`) and plans (solver-only for a class with
  no `rules`). Any druid-only choice (a default plan naming Lifebloom, a preset binding)
  must come from the profile or be skipped for a class without it -- never a druid spell
  offered to a priest.

## 3. Advisor (`UI/Advisor.lua`, `Engine/ManaCooldowns.lua`)

- Grant `advisor`. Its parts:
  - mana sources: Innervate is the druid's spell; ManaCooldowns is per class -- a class
    gets what ManaCooldowns has for it plus carried potions; no Innervate alert for a
    class that cannot cast it (Innervate from another druid is not modelled here).
  - "efficient rank shifted" (gear) toast: today `ST.RankMath:SuggestedRanks()` and
    `ST.SpellData.families[family].label` -- make it read the class book (`RankMath:Source()`
    / the book's family labels) so a priest gets a toast about Greater Heal, never a druid
    family.
  - drink reminder: class-neutral already; confirm.

## 4. Tests

- Extend `tools/tbcclasscheck.lua` (TBC flavour) in the manner of `tools/classcoach.lua`:
  for each of Priest, Shaman, Paladin: granted coach / simulate / advisor; a synthetic
  five-man fight with the class's heals recorded and validated through the gates; the
  solver coaches it (casts the class's heals, nobody dies, card names the unmodelled spells);
  the causality test (a late burst changes nothing cast before it) at least for the priest;
  the simulator runs one preset for the class and its plan casts only the class's spells;
  the advisor's rank toast names only the class's families. Remove the existing checks that
  assert coach / simulate / advisor are refused.
- Update `tools/capscheck.lua` / `tools/profilecheck.lua` if they assert the old grants.
- `tools/data/expected-counts.json` for every changed suite.

## 5. Docs

- Profile file headers (they say "no coach, simulate or advisor ... no planner").
- `CLAUDE.md` row for the TBC class profiles ("Coach, simulate and advisor stay the druid's").
- `docs/DECISIONS.md` dated entry; `docs/HISTORY.md` entry appended after the 2026-10-12
  "blooms" paragraph; `docs/TESTING.md` §52 a step 6 (coach a priest fight, Simulate on the
  priest, the advisor's potion alert).

## Acceptance

- `make check` green (`tools/check.sh`), counts updated.
- No druid suite's existing check changed in meaning.
- Every new class path reads the class's own book; no druid family name reaches a
  non-druid's UI.
- Commit on the branch with a message ending in the attribution line given to you.
