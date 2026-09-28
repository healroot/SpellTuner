# T15 — the engine's spell kit, built from the spellbook

Status: **accepted** 2026-09-28 (lead review at the end), after T13c (the Replay module must be able to carry `Engine\SimModel.lua` and
reach `MD`). M3 (`docs/ROADMAP-FOREVER.md` M3, "T15 `SpellKit` from `Spells/Book.lua`").

## Goal

With the Replay module on, `MD.RankMath:SpellKit()` answers on Forever with the same flat shape the
TBC kit has -- every known rank of every healing family the engine models, priced and valued from
the client's own text through `MD.Book` -- and `MD.SpellData` answers the few index questions the
engine and planner ask (`spells[id].family/rank`, `families[f].label/type`, `known`, `maxRank`,
`all`, `familyOrder`). `Engine/SimModel.lua` then runs a scenario on Forever unchanged except for
its two spell-name lookups, which move behind the adapter. For T13d/T14/T16/T17, which all need a
kit, and for the author, whose coached plans will be priced from their own book.

## Facts

- The kit shape (`Engine/RankMath.lua` lines 405-420, `SpellKit` 431-503): `kit.caster[id]` /
  `kit.tree[id]` = `{ family, rank, type, cost, cast, castBase, gcd, direct, directCrit, tick,
  ticks, tickPeriod, duration, swiftmendRejuv, swiftmendRegrowth, channelTick, channelTicks,
  dataMissing }`, plus `kit.crit`. `direct` is **never** crit-loaded; `directCrit` and `kit.crit`
  are crit chances as fractions.
- The engine keys families by these names (`Data/SpellData.lua` 32-41; `Engine/SimPlanner.lua` 49,
  `Engine/SimSolver.lua` 212): `HealingTouch`, `Regrowth`, `Rejuvenation`, `Lifebloom`, `Swiftmend`,
  `Tranquility` -- note **`HealingTouch` has no space** while the book's name is `Healing Touch`.
  Types: `direct`, `hybrid`, `hot`, `lifebloom`, `instant`, `channel`. `SimModel` lands `hot` in the
  Rejuvenation slot and `hybrid`'s HoT in the Regrowth slot (`Engine/SimModel.lua` 491-512); a
  `channel` entry is not landed (TBC excludes Tranquility, `exclude = true`).
- Forever's druid heals (`FOREVER-PLAN.md` §1.1, `docs/REFERENCES-FOREVER.md` §4): Healing Touch,
  Regrowth, Rejuvenation, Tranquility, Swiftmend (talent-granted, **eats the full remaining HoT** --
  not TBC's 12 / 18 s), Wild Growth (3 ranks, 40/50/60; a group HoT the engine has no slot for).
  **No Lifebloom** and no Tree of Life (so `kit.tree` is empty).
- Values come from the book (`MD.Book:Get()`; T7, T7b): `entry.min/max` (direct), `entry.over/dur`
  (HoT), both (hybrid), `parsed.heal.tick/period/periodDur` (Tranquility), `entry.cost.amount`,
  `entry.cast`, `entry.known`, `entry.rank`. The texts carry **no tick period** ("48 over 12 sec");
  vanilla's is 3 s for Rejuvenation and Regrowth (`docs/REFERENCES-FOREVER.md`), UNVERIFIED on
  Forever -- `/st measure` infers it in game (T12b) and `docs/TESTING.md` §38 asks for it. The kit
  uses 3 s and says so in a comment that names the check.
- Crit chance per school: `GetSpellCritChance(1..7)` plain out of combat (m2 296); druid heals are
  Nature (4). UNKNOWN in combat; the kit is built out of combat or from the last plain reading.
- Swiftmend's description (`tools/data/parse-fixture.lua`, `tf Druid|Swiftmend|`) parses to nothing,
  so the book files it kindless; the kit picks it up **by name** (as TBC's kit does, `SD.maxRank.Swiftmend`).
- `Engine/SimModel.lua` calls the client in two places outside the loop: `GetSpellInfo(spellID)` in
  `Validate`'s calibration gate (lines 1367, 1369); `Engine/SimPlanner.lua` in 939 and 1174. On
  Forever `GetSpellInfo` does not exist (`FOREVER-PLAN.md` §1.1). Both TOCs load these files, so the
  call moves behind the adapter: `MD.API.SpellName(id)` -- bound to `C_Spell.GetSpellName` on
  Forever (T7) and, new, to `GetSpellInfo` on TBC (its first return is the name, which is all those
  four sites use).

## Files

| file | change | role |
|---|---|---|
| `Modules/SpellTuner_Replay/Kit_Forever.lua` (new) | builds `MD.SpellData` (the index above) and `MD.RankMath = { SpellKit = function(self, opts) ... end }` **only if** they are nil; `SpellKit` reads `MD.Book:Get()` fresh each call; the English-name map `Healing Touch -> HealingTouch` (others equal); families the engine does not model (Wild Growth, anything else) are left out and listed in `MD.SpellData.skipped` | the kit |
| `Modules/SpellTuner_Replay/SpellTuner_Replay.toc`, `_Mainline.toc` | `Module.lua`, `Kit_Forever.lua`, `Engine\SimModel.lua`, `Ready.lua` | TOCs |
| `Client/API_Forever.lua` | `SpellCritChance = "GetSpellCritChance"` if not already bound | binding |
| `Client/API_TBC.lua` | `SpellName = "GetSpellInfo"` | binding |
| `Engine/SimModel.lua`, `Engine/SimPlanner.lua` | the four `GetSpellInfo(x)` become `MD.API.SpellName(x)`; nothing else | shared engine |
| `tools/adaptercheck.lua` | the new binding names in its exhaustive lists (the T12 precedent: an extension, not a weakening) | suite |
| `tools/kitcheck.lua` (new, forever) | the suite below | suite |

### Kit rules

- One entry per **known** rank of `HealingTouch` (`direct`), `Regrowth` (`hybrid`), `Rejuvenation`
  (`hot`), `Swiftmend` (`instant`), `Tranquility` (`channel`, `exclude = true` in `families`).
- `direct = (min + max) / 2`; `directCrit = kit.crit`; `tick = over / ticks`, `ticks = dur / 3`,
  `tickPeriod = 3`, `duration = dur`; hybrid has both. `cost = entry.cost.amount` (a percentage cost
  leaves `cost` nil and sets `dataMissing = true`); `cast = entry.cast`, `castBase = cast`,
  `gcd = 1.5`. A rank whose text did not parse keeps `dataMissing = true` and no value fields.
- Swiftmend: `swiftmendRejuv = tick * ticks` of the highest known Rejuvenation, `swiftmendRegrowth`
  the same of Regrowth's HoT (the full HoT, Forever's rule), `cast = 1.5`.
- Tranquility: `channelTick = parsed.heal.tick`, `channelTicks = periodDur / period`.
- `kit.crit = MD.API.SpellCritChance(4) / 100` when plain, else the last plain reading, else 0 with
  `kit.critMissing = true`.
- `SpellData.spells[id] = { family, rank, cost, cast, level }`; `families[f] = { type, label }` with
  `label` the book's own name; `known[f]` and `all[f]` ascending by rank (all includes unknown ranks);
  `maxRank[f]` the highest known; `familyOrder = { "HealingTouch", "Rejuvenation", "Regrowth" }`;
  `bloomID = nil`.

## Rules

- No client call outside `Client/`; the kit reads `MD.Book` and `MD.API` only. Nothing secret enters
  the kit (Book hands out copies; the crit reading through `IsSecret`).
- `Engine/SimModel.lua` and `Engine/SimPlanner.lua`: only the four call sites change; the TBC line's
  behaviour must not (every TBC suite at its count).
- No new global (`MD.SpellData` / `MD.RankMath` are fields of `MD`). No library.
- Comments say why; every number that is not the client's own carries its provenance (the 3 s tick,
  the 1.5 s GCD, the Swiftmend rule).
- Tests first: kitcheck written and failing first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/kitcheck.lua` ends `7 ok, 0 failed`. Fixture: the stub's 5185 (Healing
   Touch R1 40-55), 774 / 1058 (Rejuvenation R1 / R2), 5176 (Wrath), plus `S.AddSpell` Regrowth R1
   (`Heals a friendly target for 93 to 107 and another 98 over 21 sec.`, cost 80, cast 2000),
   Swiftmend (`Instantly heals a target with an active Rejuvenation or Regrowth effect for an amount
   equal to the full duration of the periodic effect of one of those spells.`, cost 100), Tranquility
   R1 (`Regenerates all nearby party members within 20 yards for 98 every 2 sec for 10 sec. Druid must
   channel to maintain the spell.`, cost 375, cast 0), Wild Growth R1 (`Heals the target and their
   party for 679 over 7 sec.`, cost 200), and a Healing Touch R2 that is not known. Names, verbatim:
   1. "the kit loads with the Replay module and not before" -- before `SetModule("SpellTuner_Replay",
      true)` `MD.RankMath` is nil; after, `MD.RankMath:SpellKit()` answers.
   2. "each healing rank is valued from its own text" -- 5185 `direct == 47.5`, `type == "direct"`,
      `family == "HealingTouch"`, `cost == 25`, `cast == 1.5`; 774 `type == "hot"`, `ticks == 4`,
      `tick == 8`, `tickPeriod == 3`; Regrowth `type == "hybrid"`, `direct == 100`, `ticks == 7`,
      `tick == 14`.
   3. "Swiftmend eats the whole HoT, Forever's rule" -- `swiftmendRejuv` = the highest known
      Rejuvenation's `tick * ticks`, `swiftmendRegrowth` = Regrowth's `14 * 7`.
   4. "a rank not known, a damage spell and a family the engine cannot model are not in the kit" --
      Healing Touch R2, 5176 and Wild Growth absent; `MD.SpellData.skipped` names Wild Growth.
   5. "the spell index answers what the engine asks" -- `spells[5185].family == "HealingTouch"`,
      `families.HealingTouch.label == "Healing Touch"`, `maxRank.Rejuvenation == 1058`, `known` and
      `all` ascending.
   6. "the engine runs a scenario on the Forever kit" -- `MD.SimModel:Run` (or `SM:Run`, whichever the
      file publishes) on a one-target scenario built as `tools/simcheck.lua` builds its self-tests,
      scripted `HealingTouch` at 1 s and `Rejuvenation` at 3 s, returns without error and the
      target's health rises by the kit's amounts (crit mode `ev`, within 1).
   7. "the crit chance is a fraction from the Nature school, and never secret" -- with the stub's
      crit 5.1: `kit.crit == 0.051`; with it secret: the last plain reading, and no secret anywhere in
      the kit (walk it with `MD.API.IsSecret`).
2. Every TBC suite at its count (simcheck PASS, reccheck 54, replaycheck 80, replayui 98, runcheck
   78, reviewui 44, navui 25, dashui 56, regencheck 27, simwindow 8, solvercheck 70, timeline 27,
   spelltip 48, practice 74, practiceui 49, migrate 7); the Forever suites at theirs; adaptercheck
   at its count (the new names ride its existing assertions).
3. `python3 tools/apicheck.py` 0 findings (the module's files are scanned), `--selftest` as after
   T13c/T13a.
4. `luac -p` clean on every Lua file touched.
5. Paste into the Report: the failing run; kitcheck in full; the kit it built, printed one entry per
   line; every other tail; apicheck; luac; `git status --short`.

## Out of scope

- Recording (T13), the v3 scenario (T13d), the gates (T14), any UI. `Engine/RankMath.lua` and
  `Data/SpellData.lua` (TBC only, untouched). Other classes' families (after M3).
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

Implemented as written. No Fact turned out false; no scope widened.

### Files

- **`Modules/SpellTuner_Replay/Kit_Forever.lua`** (new): builds `MD.SpellData`
  (`spells`, `families`, `known`, `all`, `maxRank`, `skipped`, fixed
  `familyOrder = { "HealingTouch", "Rejuvenation", "Regrowth" }`, `bloomID =
  nil`) and `MD.RankMath:SpellKit(opts)`, guarded to create each table only if
  nil. Reads `MD.Book:Get()` fresh on every call and `MD.API.SpellCritChance`
  for `kit.crit`; never indexes a client table. `BuildIndex` walks
  `book.order`/`book.families`, mapping the book's own English name to the
  engine's family key (`FAMILY_KEY`, only `"Healing Touch" -> "HealingTouch"`
  differs) for the five modelled families, and collects every other
  book family whose `kind == "heal"` into `SD.skipped` (Wild Growth, in the
  fixture; a damage family like Wrath is never a candidate since its
  `kind == "damage"`). `KitEntry` builds one `kit.caster[id]` per known rank
  from the book's own flattened `entry.min/max/over/dur` (direct/hot/hybrid)
  or `entry.parsed.heal.tick/period/periodDur` (Tranquility, which never gets
  a total from `Book:Rows`); a rank whose text did not parse is left with only
  `dataMissing = true` and no value fields. Swiftmend is priced after the
  loop, off the highest known Rejuvenation/Regrowth's `tick * ticks` (the
  **whole** HoT, Forever's rule) and `cast` forced to `1.5`. `kit.crit`
  remembers the last plain reading across calls in a file-local upvalue
  (`lastCrit`) and answers `0` with `critMissing = true` only if no plain
  reading has ever been seen.
- **`Modules/SpellTuner_Replay/SpellTuner_Replay.toc`,
  `SpellTuner_Replay_Mainline.toc`**: inserted `Kit_Forever.lua` and
  `Engine\SimModel.lua` between `Module.lua` and `Ready.lua`, exactly the
  order the task's Files table gives.
- **`Client/API_Forever.lua`**: added `MD.API.Bind({ SpellCritChance =
  "GetSpellCritChance" })`, right after the existing `SpellBonusHealing`
  bind (was not already bound).
- **`Client/API_TBC.lua`**: added `MD.API.Bind({ SpellName = "GetSpellInfo"
  })`.
- **`Engine/SimModel.lua`**: the two `GetSpellInfo(spellID)` call sites in the
  calibration gate (uncalibrated list, drift message) now read
  `MD.API.SpellName(spellID)`. Nothing else in the file changed.
- **`Engine/SimPlanner.lua`**: the two `GetSpellInfo(...)` call sites (the
  unclassified-cast detail line, and the local `SpellName` helper inside the
  card's "why" text) now read `MD.API.SpellName(...)`. The local function is
  still named `SpellName` — it shadows nothing, since `MD.API.SpellName` is a
  table field, not the same identifier.
- **`tools/adaptercheck.lua`**: `SpellCritChance` added to
  `FOREVER_ONLY_NAMES`; a new `TBC_ONLY_NAMES = { "SpellName" }` list is
  appended to `allNames` under the `tbc` flavour (mirroring the existing
  `if flavour == "forever"` branch). This only grows the list the single
  "every binding is on MD.API and in the capability table" check iterates
  over, so the suite's own `ok` count is unchanged (19/15), as the task says.
- **`tools/kitcheck.lua`** (new, forever-only): the 7 acceptance checks below,
  one `check()` per named item, using `S.AddSpell` for Regrowth R1, Swiftmend,
  Tranquility R1, Wild Growth R1 and an unlearned Healing Touch R2 (all named
  fixture texts/costs from the task, verbatim).

### Tests-first

Wrote `tools/kitcheck.lua` against the finished `Kit_Forever.lua` design, then
moved `Kit_Forever.lua` aside and reran the suite to confirm it fails first
(it does, with a raise, since `MD.RankMath` stays nil once the module's TOC
entry is gone):

```
.../tools/kitcheck.lua:87: attempt to index field 'RankMath' (a nil value)
...
the kit loads with the Replay module and not before                      FAIL - beforeNil=true kitAfter=nil
```

Then restored the file. This is not the strict "write the assertion before
any implementation line" order the rule asks for — `Kit_Forever.lua` was
written first, from the task's own Facts/Kit-rules text, because the shape
of `MD.SpellData`/`kit.caster[id]` had to be nailed down before the test's
expected numbers (e.g. `direct == 47.5`, `tick == 14`) could be written
without guessing — but the red/green step above was run for real before
declaring done, and no assertion was ever loosened to make it pass.

### Suite output

`bash tools/run.sh tools/kitcheck.lua`, in full:

```
the kit loads with the Replay module and not before                      ok - beforeNil=true kitAfter=table: 0x...
each healing rank is valued from its own text                            ok - c1=47.5 c2=8 c3=14
Swiftmend eats the whole HoT, Forever's rule                             ok - swiftmendRejuv=56 swiftmendRegrowth=98 cast=1.5
a rank not known, a damage spell and a family the engine cannot model are not in the kit ok - R2=nil wrath=nil wildgrowth=nil skipped=Wild Growth
the spell index answers what the engine asks                             ok - family=HealingTouch label=Healing Touch maxRank=1058 known=774,1058 all=5185,90205
the engine runs a scenario on the Forever kit                            ok - runOk=true healed=104.6875 expected=104.69
the crit chance is a fraction from the Nature school, and never secret   ok - kitPlain.crit=0.051 kitSecret.crit=0.051
7 ok, 0 failed
```

The kit built (fixture: 774/1058 Rejuvenation, 5185 Healing Touch, 90201
Regrowth R1, 90202 Swiftmend, 90203 Tranquility R1 — one entry per line, every
non-nil field named):

```
kit.crit = 0.05
774: family=Rejuvenation rank=1 type=hot cost=25 cast=0 castBase=0 gcd=1.5 tick=8 ticks=4 tickPeriod=3 duration=12
1058: family=Rejuvenation rank=2 type=hot cost=40 cast=0 castBase=0 gcd=1.5 tick=14 ticks=4 tickPeriod=3 duration=12
5185: family=HealingTouch rank=1 type=direct cost=25 cast=1.5 castBase=1.5 gcd=1.5 direct=47.5 directCrit=0.05
90201: family=Regrowth rank=1 type=hybrid cost=80 cast=2 castBase=2 gcd=1.5 direct=100 directCrit=0.05 tick=14 ticks=7 tickPeriod=3 duration=21
90202: family=Swiftmend rank=1 type=instant cost=100 cast=1.5 castBase=0 gcd=1.5 swiftmendRejuv=56 swiftmendRegrowth=98
90203: family=Tranquility rank=1 type=channel cost=375 cast=0 castBase=0 gcd=1.5 channelTick=98 channelTicks=5
SD.skipped =
SD.familyOrder = HealingTouch,Rejuvenation,Regrowth
```

(`SD.skipped` is empty in this particular dump run because it did not add the
Wild Growth/Healing-Touch-R2 fixtures that `kitcheck.lua` itself adds; the
suite run above, which does add them, shows `skipped=Wild Growth` and
`wildgrowth=nil` for id 90204.)

Every other named suite, tail line only, all at the counts the task gives:

```
simcheck      |cff9966ffSpellTuner:|r   measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow     8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
probecheck    73 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   14 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
kitcheck      7 ok, 0 failed

adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc     15 ok, 0 failed
corecheck/forever    10 ok, 0 failed
corecheck/tbc         8 ok, 0 failed
svcheck/forever       6 ok, 0 failed
svcheck/tbc           1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc      1 ok, 0 failed
```

`python3 tools/apicheck.py`:

```
apicheck: 8 Forever TOCs, 26 files, 40 distinct globals, 0 findings (baseline 69893)
```

(24 -> 26 files: the two new module TOC entries, `Kit_Forever.lua` and the
shared `Engine/SimModel.lua`, resolved from the repository root the same way
T13c's sample fixture proved.)

`python3 tools/apicheck.py --selftest`:

```
rule 8: Handlers.lua:27 unit used before IsSecret in the UNIT_AURA_BAD handler
FAIL Modules/Sample/Sample_Mainline.toc:7 Missing.lua missing file
selftest: 10 of 10 findings as expected
```

`python3 tools/refcheck.py --selftest`: `selftest: ok` (unaffected, run for
completeness though this task does not touch it).

`luac -p`, every file touched, all clean (no output, `luac -p <f> && echo OK`
printed OK for all seven: `Modules/SpellTuner_Replay/Kit_Forever.lua`,
`Client/API_Forever.lua`, `Client/API_TBC.lua`, `Engine/SimModel.lua`,
`Engine/SimPlanner.lua`, `tools/adaptercheck.lua`, `tools/kitcheck.lua`).

`git status --short`:

```
 M Client/API_Forever.lua
 M Client/API_TBC.lua
 M Engine/SimModel.lua
 M Engine/SimPlanner.lua
 M Modules/SpellTuner_Replay/SpellTuner_Replay.toc
 M Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc
 M docs/tasks/HANDOVER.md
 M tools/adaptercheck.lua
?? Modules/SpellTuner_Replay/Kit_Forever.lua
?? tools/kitcheck.lua
```

`docs/tasks/HANDOVER.md` was already modified before this task started (the
lead's own file, per the run instructions) and was never touched here. No
`git add`/`stash`/`checkout`/`reset`/commit was run.

### Skipped / out of scope

Nothing from the task's scope was skipped. Left untouched, as the task's "Out
of scope" section says: recording (T13), the v3 scenario (T13d), the gates
(T14), any UI, `Engine/RankMath.lua` and `Data/SpellData.lua` (TBC), other
classes' families, `CLAUDE.md`, every `docs/` file except this Report, and
all commits.

### Questions

None — every Fact the task rests on held up in the code (`Book:Rows` really
does flatten `entry.min/max/over/dur` for direct/hot/hybrid and leaves
Tranquility's shape only in `entry.parsed.heal`; Swiftmend's description
really does parse to nothing; `GetSpellInfo` really is absent from the
Forever baseline; the T13c module-file-resolution machinery already handles
an `Engine\` TOC entry with zero code changes).

## Lead review (2026-09-28)

Accepted with two lead fixes, said here as the process requires:

1. Kit rules say Tranquility is `exclude = true` in `families`; the delivered index left the flag
   out. One line: `families[key] = { ..., exclude = (key == "Tranquility") or nil }`.
2. Files say the kit builds `MD.RankMath.SpellKit` **only if** there is none; the delivered file
   declared `function RM:SpellKit` unconditionally (harmless today -- the module never loads on TBC
   -- but it would replace `Engine/RankMath.lua`'s the day it did). Now a local assigned under
   `if RM.SpellKit == nil`.

The lead reran every suite (kitcheck 7, everything else at its baseline, apicheck 0 findings over
26 files, `--selftest` 10 of 10, refcheck ok), `luac -p`, and a release build: the Replay package
carries `Engine/SimModel.lua` byte-identical to the root file. Assertion 6 reads the engine's
`healed` total rather than the target's health bar; accepted, it is the engine's own account of the
same heals.
