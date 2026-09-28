# T15 — the engine's spell kit, built from the spellbook

Status: **open**, after T13c (the Replay module must be able to carry `Engine\SimModel.lua` and
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

(implementer)
