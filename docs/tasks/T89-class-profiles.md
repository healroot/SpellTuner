# T89 -- class profiles (S1 step 1)

Status: **built** 2026-10-01 on branch `next/T89` (base `e2b13f4`), wave N1 batch A, awaiting the
integrator. Spec: `docs/SPEC-next.md` 2.1 (the profile), section 3 (principles 1, 9, 10) and the
T89 row of section 11; research `docs/research/next/R-arch.md` section 3 and
`CRITIQUE-next.md` point 2 (the engine reads the kit's profile, never the logged-in player's).

**The branch needs its TOC lines (below) to load**: `Engine/SimPlanner.lua`,
`Engine/ManaCooldowns.lua`, `Engine/RegenModel.lua`, `Kit_Forever.lua` and `Stream_Forever.lua` now
derive their druid tables from `MD.Profiles` at file load. The TOCs are integrator-owned and were
**not** edited in the commit; every suite was run with the TOC lines applied in the working tree,
then the TOCs were restored (as T56, T63, T67, T84).

## What was built

- **`Spells/Profiles.lua`** (new; all three main TOCs, right after the flavour core; pure, no
  client call): `MD.Profiles` --
  - `P.FIELDS`, `P.FAMILY_FIELDS`, `P.PLANNER_FIELDS`, `P.COOLDOWN_FIELDS` (the shape, declared);
  - `P.Validate(p, types)` -> `true` or `false, problems` (Kit.Validate's style: undeclared fields,
    types, required fields, every `kit` a `Kit.TYPES` entry when `types` -- default `MD.Kit.TYPES`
    once loaded -- is known, `eats` naming HoT families, a name in one family only, `order` and
    `hotSlots` naming families (hot ones for slots), `planner.hotRule` inside `planner.bindable`,
    complete mana cooldowns, `regen.inFsrTalent` as `{ name, fraction }`);
  - `P.Register(class, p)` (a second registration for a class raises, as `MD:Provide`; a profile
    failing `Validate` raises naming its first problems), `P.Get(class)` (the registered one, else
    `P.generic`; never nil), `P.Require(class, who)` (raises when unregistered: what a file deriving
    a constant at load uses), `P.ForKit(kit)` (`Get(kit.profile)`, the druid's when absent),
    `P.Select(class)` (run at `CORE_LOGIN` from a callback this file registers);
  - methods on every profile (a metatable, so never fields): `:Can(cap)` -> `true` or
    `false, "class"`, `:Family(nameOrKey)` -> `key, def`, `:FamilyKeys()` (spellbook name -> key,
    built in name order), `:KitTypes()` (key -> kit type), `:HotIndex()` (key -> slot);
  - the generic profile (`caps = { clock }`) and `P.LineCaps(caps)` -- what a line grants every
    class, installed once by that line's profile file (Forever: `tooltip`, `rankTable`), so the
    flavour difference is a value the line installs (apicheck rule 10).
- **`Data/Profile_Druid_TBC.lua`** (new; TBC TOC after `Spells/Profiles.lua`): the six families of
  `Data/SpellData.lua` (names = SD's labels, kit = SD's `type`, SD's `exclude` marks), Swiftmend's
  `eats` and `cooldown = 15`, `order` = SD.familyOrder, `hotSlots` Rejuvenation / Regrowth /
  Lifebloom, the planner's three lists, Innervate as the mana cooldown (`value = "innervate"`),
  Intensity 0.10. Mirrors SpellData without reading it (it loads before it).
- **`Data/Profile_Druid_Forever.lua`** (new; both Forever main TOCs after `Spells/Profiles.lua`):
  `P.LineCaps({ tooltip, rankTable })`; five families (no Lifebloom), `order` = Kit_Forever's
  dashboard order, `hotSlots` Rejuvenation / Regrowth (SM.HOT_INDEX's slots 1 and 2), the
  planner's lists identical to TBC's (Lifebloom included: the rules skip a family the kit lacks,
  as always). No mana cooldowns or regen talent: nothing on the Forever TOCs reads them.
- **Derived at file load, by name** (`MD.Profiles.Require("DRUID")`, never the logged-in
  profile), each copied so the registered profile is never edited through them:
  - `Engine/SimPlanner.lua`: `SP.BINDABLE`, `SP.HOT_RULE` from `planner.bindable` / `hotRule`;
  - `Engine/ManaCooldowns.lua`: `MC.byClass.DRUID` from `manaCooldowns`, the named value model
    resolved through the new `MC.VALUES` (`innervate = InnervateValue`; an unknown name raises);
    the PRIEST / SHAMAN / PALADIN stubs unchanged;
  - `Engine/RegenModel.lua`: the DRUID row of `IN_FSR_TALENT` from `regen.inFsrTalent` (PRIEST,
    MAGE unchanged); the table is published as `MD.Regen.IN_FSR_TALENT` for the check;
  - `Modules/SpellTuner_Replay/Kit_Forever.lua`: `FAMILY_KEY` (`:FamilyKeys()`), `FAMILY_TYPE`
    (`:KitTypes()`), the excluded families (BuildIndex's `exclude` and `KitRestore`'s policy, were
    a literal `Tranquility`), the dashboard order (`SD.familyOrder`, a fresh copy per install as
    before), the crit school (`MD.API.SpellCritChance(4)`); `RankMath.FAMILY_KEY` /
    `RankMath.FAMILY_TYPE` published for the check;
  - `Modules/SpellTuner_Recorder/Stream_Forever.lua`: `MD.StreamV3.FAMILY_KEY`.
- **`tools/profilecheck.lua`** (new; forever and tbc) -- see below.

Not touched (other tasks' files): `SM.HOT_INDEX`, `SM.SPELL_CD`, `SM.SWIFTMEND_ORDER`
(`Engine/SimModel.lua`, T90 / T96), `SV.FAMILIES` (`Engine/SimSolver.lua`), SimPlanner's own
`local HOT_INDEX` (on Forever the profile's `HotIndex()` has no Lifebloom slot, so deriving it
would change Forever's table; it is T96's per-run `S.hotIndex`). The profile carries their values
and `profilecheck` holds them equal to the live constants, so T96 can derive them.

## Failing first

`tools/profilecheck.lua` run against an export of the parent `e2b13f4` (`git archive`): forever
**0 ok, 1 failed**, tbc **0 ok, 1 failed** (`MD.Profiles exists ...` FAIL; the suite stops there).

Mutation, in the branch: `Engine/SimPlanner.lua` deriving from
`(MD.ClassProfile or MD.Profiles.Require("DRUID", "x"))` -- tbc **40 ok, 3 failed**: `priest logged
in: SP.BINDABLE` / `SP.HOT_RULE equals the constant` (got `{"Renew"}`) and `no deriving file reads
MD.ClassProfile`. Restored.

## profilecheck (both flavours)

- the registry's functions; the druid profile registered; `Select` ran at `CORE_LOGIN`
  (`MD.ClassProfile` is the druid's); on tbc `MD:Profile()` is still the `/md profile` report;
- every registered profile validates against `Kit.TYPES`; every family's `kit` is a `Kit.TYPES`
  entry; `Validate` refuses an unknown kit type (naming the family), an undeclared field, a HoT
  slot that is not a HoT family;
- `:Family`, `:Can` (druid coaches; an ungranted cap is `false, "class"`);
- **the derived tables equal today's constants**, written out in the suite as they stood at
  `e2b13f4` and compared with the live published tables: `SP.BINDABLE`, `SP.HOT_RULE`; forever:
  Kit_Forever's `FAMILY_KEY` / `FAMILY_TYPE`, `MD.StreamV3.FAMILY_KEY`, the crit school read (4),
  `MD.SpellData.familyOrder`, only Tranquility excluded (in `SpellKit`'s index and through
  `KitRestore`), the five druid families reaching the index; tbc: `MC.byClass.DRUID` (six fields,
  `value == MC.VALUES.innervate`), the whole in-5SR talent table, the profile's families against
  `SD.families` (type, label, exclude) and `order` against `SD.familyOrder`; both: `planner.families`
  against the constant and `SV.FAMILIES`, `HotIndex()` keeping `SM.HOT_INDEX`'s slots,
  `SM.HOT_INDEX` and `SM.SWIFTMEND_ORDER` still the constants, Swiftmend's `eats` =
  `SM.SWIFTMEND_ORDER`, `cooldown` = `SM.SPELL_CD[18562]` = 15;
- `ForKit` of a kit with no profile (and of nil) is the druid's; of an unknown class the generic;
  a second registration raises; a profile failing `Validate` raises and registers nothing; the
  generic profile's caps (forever `clock rankTable tooltip`, tbc `clock`), `Can("coach")` false;
  `Get` never nil; `Require` raises;
- **a priest logs in** (`S.units.player.class = "PRIEST"`, `MD:DetectProfile()`, `CORE_LOGIN`):
  with no priest profile `MD.ClassProfile` is the generic one; a test priest profile whose lists
  differ from the druid's in every derived table is registered and selected; the deriving files
  are loaded again (forever: Stream_Forever, Kit_Forever, SimPlanner; tbc: RegenModel,
  ManaCooldowns, SimPlanner) and every derived table still equals the druid's constant; `ForKit({})`
  is still the druid's; a source scan finds no deriving file naming `MD.ClassProfile`;
- forever, with `tools/.cache/talentsforever.json`: the cache reads (a small JSON reader in the
  suite) and every druid `names` entry is in the talentsforever Druid spellbook. **Without the cache
  it prints `SKIP ...` and those two checks are not counted** (forever 46 instead of 48).

## Suites, before and after

`tools/check.sh` with the TOC lines applied: **74 run(s), all passed**; 69 counted against 67
expected (the two new `profilecheck` keys reported as NOTE). apicheck **0 findings** (62 files, was
60; 48 distinct globals, unchanged); textcheck **0 findings** (101 files, was 98); `luac -p` clean on
every changed file.

| suite | before | after |
|---|---|---|
| `profilecheck/forever` | -- (0 ok, 1 failed on the parent) | **46** (48 with the talentsforever cache) |
| `profilecheck/tbc` | -- (0 ok, 1 failed on the parent) | **44** |
| every other suite | as `expected-counts.json` | unchanged |

**Byte-identical:** every suite's output (`tools/.lua/check/*.out`) of the parent run and of this
run were compared after replacing table addresses: equal, except the file counts in `apicheck`,
`textcheck` and `releasecheck` (two / three new files), and the timing lines of `replayui` /
`reviewui` (`replay ... N ms`, the frame-sliced `search N evaluations` progress and `N frames`),
which differ between two runs of the parent itself (checked: two parent runs of `reviewui` differ
in the same lines). `slashcheck`, `verifycheck`, `solvercheck`, `restcheck`, `replaycheck`,
`practice`, `practiceui`, `coachforever`, `practiceforever`, `kitcheck`, `importcheck`, `simcheck`
equal. No `MD:RegisterDefaults` key: `defaultscheck` unchanged (forever 52, tbc 49).

## Integrator lines

**TOCs** (exactly what the runs used):

- `SpellTuner_TBC.toc`: after `Core_TBC.lua`, the two lines `Spells\Profiles.lua` and
  `Data\Profile_Druid_TBC.lua` (before `Data\SpellData.lua`).
- `SpellTuner_Mainline.toc` and `SpellTuner.toc` (identical): after `Core_Forever.lua`, the two
  lines `Spells\Profiles.lua` and `Data\Profile_Druid_Forever.lua` (before `Spells\Parse.lua`).
- No module TOC: the modules read `MD.Profiles` through their proxy (`Module.lua`).

**`tools/data/expected-counts.json`:** `"profilecheck/forever": 46,` and `"profilecheck/tbc": 44,`
(the cache-less counts; with the cache forever reports 48, a NOTE). `tools/check.sh` needs nothing:
the suite declares `HARNESS_FLAVOUR = { "forever", "tbc" }` and is found on its own.

**CLAUDE.md**, the repo-structure table, three new rows (after `Core_Forever.lua`'s):

> | `Spells/Profiles.lua` | **The class profile registry** (T89, `docs/SPEC-next.md` 2.1; all three main TOCs right after the flavour core; pure): `MD.Profiles` -- `Register(class, p)` (a second raises; a profile failing `Validate` raises), `Get(class)` (else the generic profile, never nil), `Require(class, who)`, `ForKit(kit)` (the kit's `profile`, the druid's when absent: what the engine reads), `Select(class)` at `CORE_LOGIN` -> **`MD.ClassProfile`**, the logged-in player's (not `MD.Profile`: TBC's `MD:Profile()` is the `/md profile` report); `Validate(p, types)` (declared fields, every `kit` a `Kit.TYPES` entry); methods `:Can(cap)` (`true` / `false, "class"`), `:Family`, `:FamilyKeys`, `:KitTypes`, `:HotIndex`; the generic profile (`clock`, plus what a line installs through `LineCaps`). **A module-level constant is derived at file load from `Require("DRUID")` by name, never from `MD.ClassProfile`** |
> | `Data/Profile_Druid_TBC.lua` | The druid's TBC profile (T89): `Data/SpellData.lua`'s six families mirrored (labels, types, exclude marks; `order` = `SD.familyOrder`), Swiftmend's `eats` / `cooldown`, `hotSlots` (SM.HOT_INDEX's order), the planner's lists, Innervate, Intensity. Names and rules only; SpellData stays the verified source. TBC TOC after `Spells/Profiles.lua` |
> | `Data/Profile_Druid_Forever.lua` | The druid's Forever profile (T89): `LineCaps({ tooltip, rankTable })` for every class on this line; five families by the spellbook's names (no Lifebloom), `hotSlots` Rejuvenation / Regrowth, the planner's lists (the TBC rules' own, Lifebloom included). No numbers. Forever main TOCs after `Spells/Profiles.lua` |

and append to the rows of the files that now derive:

> `Engine/SimPlanner.lua`: **T89:** `SP.BINDABLE` / `SP.HOT_RULE` derived at load from the druid profile's `planner` (copied)
>
> `Engine/ManaCooldowns.lua`: **T89:** `MC.byClass.DRUID` from the druid profile's `manaCooldowns`, its `value` a name resolved through `MC.VALUES`
>
> `Engine/RegenModel.lua`: **T89:** the DRUID in-5SR row from the druid profile's `regen.inFsrTalent`; `RM.IN_FSR_TALENT` published
>
> the `Modules/<Name>/` row: **T89:** `Kit_Forever.lua`'s `FAMILY_KEY` / `FAMILY_TYPE` / excluded families / dashboard order / crit school and `Stream_Forever.lua`'s `FAMILY_KEY` derived at load from the druid profile by name (`RankMath.FAMILY_KEY` / `FAMILY_TYPE` published for `tools/profilecheck.lua`)

and in the `tools/` row, after `tools/ttocheck.lua`'s sentence: **`tools/profilecheck.lua`** (T89,
forever / tbc): the profile registry, the derived tables against today's constants also with a
priest logged in, the talentsforever names (SKIP without the cache, not counted).

**docs/TOOLS.md**, section 1, a new row:

> | `profilecheck.lua` | **the class profiles** (T89; forever 46, tbc 44): every registered profile validates and names `Kit.TYPES` entries; the tables derived from the druid profile at file load equal today's constants (`SP.BINDABLE`, `SP.HOT_RULE`; forever Kit_Forever's and Stream_Forever's `FAMILY_KEY`, `FAMILY_TYPE`, the order, the exclusions, crit school 4; tbc `MC.byClass.DRUID`, the in-5SR table, `SD.families` / `familyOrder`), and the engine constants T89 left alone (`SM.HOT_INDEX`, `SM.SWIFTMEND_ORDER`, `SM.SPELL_CD`, `SV.FAMILIES`) equal the profile's values; **again after a priest logs in and the deriving files reload**; `ForKit`, a second registration, the generic profile's caps; with `tools/.cache/talentsforever.json` (`python3 tools/refcheck.py --fetch`) every Forever name is in that class's spellbook (+2; without the cache `SKIP`, not counted) |

**docs/SPEC-next.md** (the integrator's copy of the spec, for T96 / T99): `MD.Profile` reads
`MD.ClassProfile` (2.1's contract, 4.4's gate text and T99's row: `MD.ClassProfile:Can(cap)`).

**docs/HISTORY.md**: the integrator's wave entry. **docs/DECISIONS.md**, **docs/TESTING.md**: none
(no behaviour changes on either line).

## Deviations from the spec

1. **`MD.ClassProfile`, not `MD.Profile`.** TBC already has `MD:Profile()` (`Diagnostics_TBC.lua:206`,
   the `/md profile` copy box), and `Select` writing a table there broke `/md profile`
   (`verifycheck/tbc` raised "attempt to call method 'Profile' (a table value)" on the first run).
   The logged-in profile is `MD.ClassProfile`; everything else in 2.1 is as written. T99's gates
   read `MD.ClassProfile:Can(cap)`.
2. **The generic profile on TBC is `{ clock }`**, not `{ clock, tooltip }`: 2.1 says the generic
   profile is "exactly what a non-druid gets today", and on TBC a non-druid gets no spell tooltip
   (`UI/SpellTooltip.lua:57`) and no rank table. Forever's `tooltip` and `rankTable` are installed
   by `Data/Profile_Druid_Forever.lua` through `P.LineCaps` (a value the line installs, apicheck
   rule 10), since T89 owns no other Forever data file.
3. **No per-family `bindable` flag.** 2.1's sketch marks three families `bindable`, but
   `SP.BINDABLE` is five (Lifebloom and Swiftmend included) in a fixed order; the planner's lists
   are ordered lists in `planner` (`bindable`, `hotRule`, `families`), which is what derives
   `SP.BINDABLE` exactly. They are the same on both lines, Lifebloom included on Forever (the
   rules' own lists; a family the kit lacks is skipped as before), so `Validate` checks them as
   names, not against the line's families.
4. **Forever's `hotSlots` has no Lifebloom** (`R-arch` 3.1: "the HoT slots without Lifebloom"), so
   it names only HoT families of that line; it keeps SM.HOT_INDEX's slot numbers 1 and 2. 2.1's
   sketch lists three slots for a druid; the TBC profile does.
5. **`order`** is each line's own dashboard order (`SD.familyOrder` on TBC, Kit_Forever's on
   Forever), assertable against a constant, rather than 2.1's sample list.
6. **Mana cooldowns and the regen talent only in the TBC profile** (nothing on the Forever TOCs
   reads them; T105 brings Forever's mana sources from the spell text). Each cooldown entry
   carries `name` (MC's entries need it).
7. `P.Require` and `P.LineCaps` are additions (a load-order mistake raises by name instead of
   indexing nil; the line's caps). `RankMath.FAMILY_KEY` / `FAMILY_TYPE`, `MD.Regen.IN_FSR_TALENT`
   and `MC.VALUES` are published so the suite compares the live tables, not copies.
