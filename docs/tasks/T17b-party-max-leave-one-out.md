# T17b — a party member's max from other recordings, never the fight being coached

Status: **accepted** 2026-09-29 (lead review at the end), the first task of the day (planner's amendment to ruling 1). M3 fix.

## Goal

On a Forever recording, the max health the scenario gives a party member whose max is secret comes
from **other recordings of the same name and level** (leave-one-out: the recording being built is
never its own source), so a burst late in the fight cannot change what the plan does before it. When
no other recording has that person, this fight's own estimate is used as today, and the coached plan
is flagged `foresees` and its card says in one line that it is not causal and why. For the author,
whose coached Forever pulls must not be advised by the future; and for the planner, whose causality
invariant must hold with the max secret, as it always is on Forever.

## Facts

- The ruling: `docs/FOREVER-PLAN.md`, "Planner rulings for M3", the amendment dated 2026-09-28 (end
  of day): "a party member's max for coaching comes from other recordings of the same name, never
  from the fight being coached; where there are none, this fight's estimate is used with the plan
  flagged `foresees` and the card saying so (the same honesty rule as `Engine/Foresight.lua`) ...
  The coach's causality assertion must run with the max secret".
- The leak (lead's T17 review, `docs/tasks/T17-coach-forever.md` "Lead review"): with
  `maxHP = -1, maxSecret = true` on the tank, coachforever assertion 6 printed `FAIL - diverged at
  6.5s`, because `SM.EstimateMaxHP` reads the whole fight.
- `Modules/SpellTuner_Replay/Scenario_Forever.lua`: `SM.EstimateMaxHP(deficits, hits)` (25) takes
  **lists** and adds the largest of each; the stand-in is chosen in two places that must agree --
  `ReconstructHp` (288, the max selection at 307-317; behind `SM.RecordedHp`, 364, which
  `Engine/SimPlanner.lua` 1385 and 1741 call as `SM.RecordedHp(rec)`) and `SM.ScenarioV3` (374, the
  selection at 425-437, `targets` at 440-455, the return at 530-543). The wrapper
  `SM.ScenarioFromRecording` (551) sends `rec.v == 3` to `SM.ScenarioV3(rec, kit)`.
- The sizing arithmetic (`sizingMax` = the largest running deficit, DMG adding, HEAL subtracting,
  floored at 0; `hits` = every DMG amount) is the same loop in both places.
- Recordings live in `MD.cdb.recordings` (`Modules/SpellTuner_Recorder/Recorder_Forever.lua` 607,
  ring of 8); each has `id`, `v = 3`, and `roster[i] = { name, guid, class, role, level, maxHP,
  maxSecret }` where a party member's max is `maxHP = -1, maxSecret = true` and the player's is plain
  (Recorder_Forever.lua 86-107). `name` and `level` are plain (a string / a number, or nil).
- The leave-one-out precedent: `Engine/Intuition.lua` `IN:Build(recs, excludeID)` (114) takes the
  exclusion as an argument; `CLAUDE.md` Intuition row: "a fight is never in its own prior".
- `foresees`: set on solver plans by `Engine/SimSolver.lua` 234 (`foresees = params.foresight ~=
  nil`); rules plans (`SP.NewPlan`, `Engine/SimPlanner.lua` 104) never set it; nothing in
  `SP.Card` (987) reads it today. On TBC every plan that reaches `SP.Card` is a rules plan
  (`SP.Baselines` 794, "your binds" 1295, the search's `SP.NewPlan` 1500), so a card line keyed on
  `best.foresees` never prints on TBC.
- `SP.Coach` (1270) builds `scenario` (1285), picks `best` among the candidates (1303-1315), calls
  `SP.Card` (1318) and caches `SP.plans[rec.id] = best`; `SP.CoachAsync` (1663) ends in `SP.Coach`
  with the search's plan in `extra`, so a flag set in `SP.Coach` covers both paths.
- coachforever assertion 6 (`tools/coachforever.lua` 155-221) builds two hand-made v3 recordings
  (ids 9000000001 quiet, 9000000002 loud) with the Tank's max **plain** (10000).

## Files

| file | change | role |
|---|---|---|
| `Modules/SpellTuner_Replay/Scenario_Forever.lua` | (a) `SM.PartyMaxFromOthers(recs, excludeID, name, level)`: raises (`error`) when `excludeID` is nil; walks `recs`, skipping the entry whose `id == excludeID` and anything not `v == 3`; takes every roster entry with the same `name` (and, when both levels are numbers, the same `level`); if any of them is plain (`maxSecret == false`, `maxHP > 0`) returns the largest plain value, `"recorded"`, count; else returns `SM.EstimateMaxHP(<that recording's sizingMax for the entry, one per recording>, <all their hits, concatenated>)`, `"others"`, count; with none, returns nil. (b) one local chooser used by **both** `ReconstructHp` and `SM.ScenarioV3`: plain in this recording -> that; else, if `rec.id` is not nil and `SM.PartyMaxFromOthers` answers -> that; else this fight's `SM.EstimateMaxHP` as today. Each target carries `maxSource` = `"recorded"` / `"others"` / `"this fight"`; `maxEstimated` stays true for the last two. (c) `SM.ScenarioV3(rec, kit, others)` and `SM.RecordedHp(rec, kit, others)`: `others` defaults to `MD.cdb and MD.cdb.recordings` when nil (pass `{}` for none); the scenario also returns `maxForesees` = the list of names (`"?"` for a nameless one) of **tracked** targets whose `maxSource == "this fight"`, or nil when the list is empty. One sizing loop, factored, rather than a third copy | the scenario |
| `Engine/SimPlanner.lua` | in `SP.Coach`, after `best` is chosen: when `scenario.maxForesees` is a non-empty list, `best.foresees = true` and `best.foreseesWhy = "max health of <names joined with ', '> estimated from this fight (no other recording of them)"`. In `SP.Card`, directly after the header line: when `best and best.foresees`, one line `"  NOT causal - sees this fight: " .. (best.foreseesWhy or "a view of this fight")`. Nothing else | the flag and the card line |
| `tools/coachforever.lua` | assertion 6 run with the Tank's max secret; five new assertions (Acceptance) | suite |

## Rules

- `CLAUDE.md`: no libraries; no new global (`SM.PartyMaxFromOthers` is a field of `MD.SimModel`);
  rendered strings **ASCII only, no bare `|`** (the card line; a name is printed as given, as every
  other card line prints it, T16c); the **multi-return trap** -- `SM.PartyMaxFromOthers` returns
  three values: take them into locals with an `if`, never through `a and f() or b`; no client call
  and no `MD.API` in `Scenario_Forever.lua` (it is pure; `MD.cdb` is a plain table); no arithmetic on
  a secret -- a stored `maxHP` of `-1` is a plain placeholder, and the chooser only ever does
  arithmetic on values it has checked with `type(...) == "number"`.
- The recording being built is **never** a source of its own max, by id. A recording with no `id`
  gets no others (it cannot be excluded, so it is not trusted).
- `Engine/SimPlanner.lua` is shared with TBC: the two hunks are keyed on fields a TBC scenario and a
  TBC plan never carry (`scenario.maxForesees`, `best.foresees`); every TBC suite at its count.
- Tests first: write the modified assertion 6 and the five new ones, run them, and paste the failing
  run before touching the addon.
- If an existing Forever suite (scenariocheck, gatecheck, replayforever, reviewforever,
  practiceforever) changes its result because its fixtures now find each other in
  `MD.cdb.recordings`: **stop and report** the failing line; do not edit its assertions.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/coachforever.lua` ends `13 ok, 0 failed`. Assertion 6 keeps its name,
   "a burst at 20 s changes nothing the plan does before it", and now runs with the Tank's roster
   entry `maxHP = -1, maxSecret = true` in both the quiet and the loud recording, with
   `MD.cdb.recordings` holding **one other** recording of Tank (same level, a different id, no
   burst) and **neither** the quiet nor the loud one (they are two versions of one fight); the store
   is restored afterwards. New names, verbatim:
   9. "a party member's max comes from other recordings of the same name and level, never the one
      coached" -- a store holding the coached recording (with a burst), one other recording of Tank
      at the same level, one of Tank at another level and one of another name: the coached
      scenario's Tank `maxHP` equals `SM.EstimateMaxHP` over the same-level other recording's
      sizing only, `maxSource == "others"`; removing the coached recording's burst leaves it equal.
   10. "a plain max in another recording is taken as it is" -- another recording with Tank
      `maxSecret = false, maxHP = 5000`: the scenario's Tank `maxHP == 5000`, `maxSource ==
      "recorded"`.
   11. "the exclusion is required" -- `pcall(SM.PartyMaxFromOthers, recs, nil, "Tank", 64)` is
      false; a recording with no `id` gets `maxSource == "this fight"`.
   12. "with no other recording of them, the plan is flagged foresees and its card says so" --
      `SP.Coach` on the clean fixture with the store holding only itself: `best.foresees == true`
      and exactly one card line starts `  NOT causal - sees this fight:` and contains `Tank`.
   13. "with another recording of them, the plan is not flagged and the card says nothing" -- the
      same fixture with another recording of Tank in the store: `best.foresees` is not true and no
      card line contains `NOT causal`.
2. Every other suite at its count (the handover's baselines: TBC sixteen as listed, probecheck 73,
   scenariocheck 9, gatecheck 8, replayforever 10, reviewforever 8, practiceforever 8, ...);
   `python3 tools/apicheck.py` 0 findings, `--selftest` 10 of 10, `refcheck.py --selftest` ok.
3. `luac -p` clean on every Lua file touched.
4. Paste into the Report: the failing first run; coachforever in full; the card from assertion 12
   as printed; every other suite's tail (the loop in `docs/TOOLS.md` §1); apicheck and its
   selftest; refcheck selftest; luac; `git status --short`.

## Out of scope

- The status-bar readback path (T17c, next). The recorder. `Client/`.
- The replay window's and the gates' wording of "max estimated" (they keep saying "estimated",
  which stays true for a max from other recordings).
- `SP.CoachRun`, runs, Intuition, Foresight.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

Implementer: Claude (Sonnet 5.5), 2026-09-29. Not committed.

### What was done

- `tools/coachforever.lua` (first, tests before code). Assertion 6 keeps its name and now builds the
  Tank with `maxHP = -1, maxSecret = true` in both the quiet and the loud recording; the store holds
  one other Tank (level 64, id 9000000003, no burst) and neither of the two, and is restored after.
  New 9 to 13 with the names verbatim: 9, 10, 11 run on small hand-built v3 recordings (`tankRec`),
  12 and 13 on the clean fixture through `SP.Coach` (13 forces the coach, see Surprising). 13 assertions.
- `Modules/SpellTuner_Replay/Scenario_Forever.lua`: `SizeRec(rec)` (the one sizing loop: hits,
  sizingMax, hitOrHealed), `SM.PartyMaxFromOthers(recs, excludeID, name, level)` (errors on a nil
  `excludeID`), `ChooseMaxes(rec, others, hits, sizingMax)` used by both `ReconstructHp` and
  `SM.ScenarioV3`; `SM.ScenarioV3(rec, kit, others)` and `SM.RecordedHp(rec, kit, others)` with
  `others` defaulting to `MD.cdb.recordings`; each target carries `maxSource`; the scenario carries
  `maxForesees` (names of tracked targets on `"this fight"`, nil when none). `ReconstructHp` also
  returns `maxSource`. The multi-return is taken with `local v1, src1 = ...` and an `if`.
- `Engine/SimPlanner.lua`: `SP.Coach` sets `best.foresees` and `best.foreseesWhy` from
  `scenario.maxForesees` before the classifier and the card; `SP.Card` adds the one line after the
  header. Both keyed on fields a TBC scenario and plan never carry.

### Surprising / decisions the task did not spell out

- `PartyMaxFromOthers` skips a matching roster entry that took no damage in its recording: it carries
  no sizing, and `SM.EstimateMaxHP` would have floored that person's max at 1 for the coached fight.
  With no other usable source the answer is nil and the fight falls back to "this fight", flagged.
  A one-line change to drop if the planner wants the literal reading.
- A `nil` name (a nameless roster entry) cannot match anyone, so it gets nil from `PartyMaxFromOthers`.
- Assertion 13 is run with `force = true`: with a second recording of Tank in the store the recGood
  validation is not the point of the assertion. (It also passes without; not needed to decide.)
- The stub has no `luac` on PATH; `tools/.lua/lua-5.1.5/src/luac` was used for `luac -p`.
- No existing suite changed its count or result; coachforever went from 8 to 13.

### The failing first run (after writing the tests, before touching the addon), tail

```
the asynchronous coach finishes and fills the replay window's suggested column                  ok - frames=1 right=table: 0x62db412e1e20
with no other recording of them, the plan is flagged foresees and its card says so              FAIL - foresees=nil lines=0
with another recording of them, the plan is not flagged and the card says nothing               ok - foresees=nil lines=0
solver vs rules on the fixture: mana 220 vs 220, deaths 0 vs 0, floor seconds 0.0 vs 0.0

8 ok, 5 failed
  FAIL a burst at 20 s changes nothing the plan does before it - diverged at 6.5s
  FAIL a party member's max comes from other recordings of the same name and level, never the one coached - want=1800 burst=19500/nil calm=1800/nil
  FAIL a plain max in another recording is taken as it is - maxHP=1800 source=nil
  FAIL the exclusion is required - pcall=false source=nil
  FAIL with no other recording of them, the plan is flagged foresees and its card says so - foresees=nil lines=0
```

### coachforever, in full (after the change)

Assertion 12's card as printed is the block under "--- the card, store holding only the coached
recording:" (line 2 of it is the new one).

```
|cff9966ffSpellTuner:|r Recorder: loaded
|cff9966ffSpellTuner:|r Replay: loaded
the coach finds a plan for a clean v3 recording                                                 ok - validation=true best=table: 0x5b2ac993e970
the plan binds only families the player had at that pull, and never Lifebloom                   ok - badBind=nil lifebloom=nil
the card renders, ASCII, with no bare pipe, naming the gates it rests on                        ok
every recorded cast gets a label                                                                ok - labelled=4 ownCasts=4
the solver runs as a strategy on the Forever kit                                                ok - entry=table: 0x5b2ac97408a0 okRun=true err=nil
a burst at 20 s changes nothing the plan does before it                                         ok - identical until the burst
a party member's max comes from other recordings of the same name and level, never the one coached ok - want=1800 burst=1800/others calm=1800/others
a plain max in another recording is taken as it is                                              ok - maxHP=5000 source=recorded
the exclusion is required                                                                       ok - pcall=false source=this fight
the zone's marks are kept and read back                                                         ok - wrote=true stillHere=true otherHere=true progress=since your last card (3 fights): overheal 33% -> 12%
|cff9966ffSpellTuner:|r coach: searching (this runs across frames; /md coach cancel stops it)...
|cff9966ffSpellTuner:|r Blood Furnace, 03:33 (0:30, 2 targets)   you 110   best 95   diff 15
|cff9966ffSpellTuner:|r   NOT causal - sees this fight: max health of Tank estimated from this fight (no other recording of them)
|cff9966ffSpellTuner:|r   Bind: Rejuvenation R1, Healing Touch R1
|cff9966ffSpellTuner:|r   2. Anyone under 45%: Healing Touch R1
|cff9966ffSpellTuner:|r   4. Anyone under 80%: the HoT whose whole heal fits the deficit (Rejuvenation R1)
|cff9966ffSpellTuner:|r   5. Otherwise wait - 77% of the fight, longest gap 10s
|cff9966ffSpellTuner:|r   you              110   lowest  42%   overheal 17%
|cff9966ffSpellTuner:|r   max rank         125   lowest  42%
|cff9966ffSpellTuner:|r   HoTs only        100   lowest  42%
|cff9966ffSpellTuner:|r   your binds        95   lowest  42%
|cff9966ffSpellTuner:|r   best (search)      95   lowest  42%
|cff9966ffSpellTuner:|r   best              95   lowest  42%   + 189 still owed
|cff9966ffSpellTuner:|r   strategies (one search, four ways of reading it)
|cff9966ffSpellTuner:|r     Safest = Highest health = Most mana left    284 mana   floor  42%    0.0s in danger   owes 114
|cff9966ffSpellTuner:|r     Least mana                            284 mana   floor  42%    0.0s in danger   owes 189
|cff9966ffSpellTuner:|r     ||cff888888/md coach 1 safe / health / cheap / regen plays that one in the replay||r
|cff9966ffSpellTuner:|r   damage casts: 1 for 20 mana + 0 lost to the five-second rule = 0
|cff9966ffSpellTuner:|r   (the fight would not have been the same fight without them - the mob lives longer.
|cff9966ffSpellTuner:|r   This is what pressing them cost your mana, not whether to press them.)
|cff9966ffSpellTuner:|r   danger line: 42% of health on Tank - the biggest hit they took. Seconds below it are
|cff9966ffSpellTuner:|r   what a plan is scored on first, ahead of mana.
|cff9966ffSpellTuner:|r   overheal     1 casts 25   HealingTouch 1 above 85%
|cff9966ffSpellTuner:|r   spell        1 casts 25
|cff9966ffSpellTuner:|r   late         1 casts 40
|cff9966ffSpellTuner:|r   utility 20  shifts 0  (outside the healing denominator)
|cff9966ffSpellTuner:|r   (warning: labelled 110 of 0 spent - the breakdown is incomplete)
|cff9966ffSpellTuner:|r   why, at 2s - the first cast the plan would not have made:
|cff9966ffSpellTuner:|r     you    HealingTouch R1 -> Healroot
|cff9966ffSpellTuner:|r            ||cff888888overheal: target was at 100% (0 missing) and HealingTouch heals 48: 48 wasted||r
|cff9966ffSpellTuner:|r     plan   wait
|cff9966ffSpellTuner:|r            ||cff888888waiting: every bound HoT is already rolling there, the efficient one frees in 4.0s||r
|cff9966ffSpellTuner:|r   caveat: EV crit; other healers as recorded; threat and kill speed not modelled; all gates passed; late and idle come from running the plan alone, the rest from lockstep
|cff9966ffSpellTuner:|r   since your last card (3 fights): overheal 33% -> 12%
|cff9966ffSpellTuner:|r   search: 20 plans evaluated
the asynchronous coach finishes and fills the replay window's suggested column                  ok - frames=1 right=table: 0x5b2ac97cada0
--- the card, store holding only the coached recording:
    Blood Furnace, 03:33 (0:30, 2 targets)   you 110   best 95   diff 15
      NOT causal - sees this fight: max health of Tank estimated from this fight (no other recording of them)
      Bind: Rejuvenation R1, Healing Touch R1
      2. Anyone under 45%: Healing Touch R1
      4. Anyone under 80%: the HoT whose whole heal fits the deficit (Rejuvenation R1)
      5. Otherwise wait - 77% of the fight, longest gap 10s
      you              110   lowest  42%   overheal 17%
      max rank         125   lowest  42%
      HoTs only        100   lowest  42%
      your binds        95   lowest  42%
      best              95   lowest  42%   + 189 still owed
      damage casts: 1 for 20 mana + 0 lost to the five-second rule = 0
      (the fight would not have been the same fight without them - the mob lives longer.
      This is what pressing them cost your mana, not whether to press them.)
      danger line: 42% of health on Tank - the biggest hit they took. Seconds below it are
      what a plan is scored on first, ahead of mana.
      overheal     1 casts 25   HealingTouch 1 above 85%
      spell        1 casts 25
      late         1 casts 40
      utility 20  shifts 0  (outside the healing denominator)
      (warning: labelled 110 of 0 spent - the breakdown is incomplete)
      why, at 2s - the first cast the plan would not have made:
        you    HealingTouch R1 -> Healroot
               |cff888888overheal: target was at 100% (0 missing) and HealingTouch heals 48: 48 wasted|r
        plan   wait
               |cff888888waiting: every bound HoT is already rolling there, the efficient one frees in 4.0s|r
      caveat: EV crit; other healers as recorded; threat and kill speed not modelled; all gates passed; late and idle come from running the plan alone, the rest from lockstep
      since your last card (3 fights): overheal 33% -> 12%
with no other recording of them, the plan is flagged foresees and its card says so              ok - foresees=true lines=1
with another recording of them, the plan is not flagged and the card says nothing               ok - foresees=nil lines=0
solver vs rules on the fixture: mana 220 vs 220, deaths 0 vs 0, floor seconds 0.0 vs 0.0

13 ok, 0 failed
```

### The suite loop (docs/TOOLS.md section 1), after the change

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
kitcheck      7 ok, 0 failed
recordcheck   14 ok, 0 failed
scenariocheck 9 ok, 0 failed
gatecheck     8 ok, 0 failed
replayforever 10 ok, 0 failed
reviewforever 8 ok, 0 failed
coachforever  13 ok, 0 failed
practiceforever 8 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc 15 ok, 0 failed
corecheck/forever 10 ok, 0 failed
corecheck/tbc 8 ok, 0 failed
svcheck/forever 6 ok, 0 failed
svcheck/tbc   1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc 1 ok, 0 failed
apicheck: 8 Forever TOCs, 44 files, 44 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok
```

### luac -p

```
luac -p ok Modules/SpellTuner_Replay/Scenario_Forever.lua
luac -p ok Engine/SimPlanner.lua
luac -p ok tools/coachforever.lua
```

### git status --short

```
 M Engine/SimPlanner.lua
 M Modules/SpellTuner_Replay/Scenario_Forever.lua
 M docs/tasks/HANDOVER.md
 M tools/coachforever.lua
?? docs/tasks/T17b-party-max-leave-one-out.md
```

(`docs/tasks/HANDOVER.md` was already modified before this task; this task also modifies this file's Report.)

### Question

None blocking. The planner may want to confirm the "skip an entry with no damage" choice above.

## Lead review (2026-09-29)

Accepted, no change by the lead. The lead read the diff, reran every suite (coachforever 13, every
other suite at the handover's baseline; apicheck 0 findings over 44 files -- 44 distinct globals
instead of 43, the new one `error`, a Lua builtin -- `--selftest` 10 of 10, refcheck ok) and
`luac -p` on the three files.

- Assertion 6 is not vacuous: printed from a scratch copy, the quiet and the loud run share four
  casts before the burst (`6.50:1058 16.00:5185 17.50:5185 19.00:5185`) and part only at 20.5 s;
  without the other recording (the failing first run) it diverged at 6.5 s, as the T17 review found.
- The implementer's question -- a matching roster entry that took no damage is skipped: **confirmed**.
  Such an entry carries no evidence about the max (its sizing is 0 and it has no hits); counting it
  would floor the person at 1 when it is the only source, which is worse than the flagged fallback.
- Both `Engine/SimPlanner.lua` hunks are keyed on `scenario.maxForesees` / `best.foresees`, which no
  TBC scenario or rules plan carries; the TBC sixteen are unchanged.
- Noted, not in scope: `SM.ScenarioV3` still carries its own copy of the health reconstruction loop
  beside `ReconstructHp` (pre-existing since T16a); both now read the same `ChooseMaxes`, so they
  cannot disagree on the max.
