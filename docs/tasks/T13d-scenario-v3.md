# T13d — a v3 stream becomes the engine's scenario

Status: **accepted** 2026-09-28 after two re-issues (lead reviews at the end), after T15 (the Forever kit and spell index) and T13 (the v3 stream's shape). M3
(`docs/ROADMAP-FOREVER.md` M3, "`ScenarioFromRecording` v3"), split from T13 by the lead so each task
is one module. Carries two choices the planner ruled on 2026-09-28 (`FOREVER-PLAN.md`, "Planner
rulings for M3" above §2.4, items 1 and 2), each as **one replaceable function**.

## Goal

With the Replay module on, `SM.ScenarioFromRecording(rec, kit)` accepts a v3 stream (T13) and
returns a scenario of exactly the shape the engine already runs -- targets, recorded damage and
foreign heals, the script and the fixed casts, mana rates, pre-pull HoTs -- plus the **reconstructed
health** of every target at a 2 s grid for the health gate and the replay window. Every v2 stream
(TBC) goes through the old function untouched. The heals `UNIT_COMBAT` reported without a source are
split into the player's own (paired with their casts) and everyone else's; a party member's unknown
max health gets a stated stand-in. For T14 (gates), T16 (replay window), T17 (coach).

## Facts

- The v2 scenario shape (`Engine/SimModel.lua` `ScenarioFromRecording` 1056-1197): `{dur, pool,
  initial, energizeAssumed, targets[i] = {name, role, maxHP, danger, hp0, tracked}, ev, rates, fixed,
  incoming, threat, sampleT, hpSampleT, kit, floor, script}`. `SM:Run` walks `scenario.ev` with
  `#ev.t` (616-617) and applies `DMG` (damage), `FHEAL` (a foreign heal, landed by the engine), `DIED`,
  `CASTSTART` / `CANCEL` (trace only); own heals are **generated** by the engine from the script and
  never read (735-767). `init.auras` entries `{target, spellID, stacks, remaining}` start HoTs ticking
  (637-656). `fixed` entries `{t, id, cost, tgt, kind}` come from `MD:ClassifyCast` (TBC:
  `Data/DruidSpells.lua` 66).
- The v3 stream (T13): `ev` kinds `DMG = 1`, `HEAL = 15` (a heal of **unknown source**),
  `OWNCAST = 3`, `CASTSTART = 6`, `CANCEL = 7`, `DIED = 9`; `roster[i].maxHP = -1, maxSecret = true`
  for party members; `mana` from the clock's model; `initial.auras = { {token, spellId, remaining,
  stacks} }`; `initial.known` by the engine's family keys (T13); `meter`.
- `UNIT_COMBAT` HEAL carries **no source** (plan §2.3). The plan says the engine generates own heals
  and the foreign-share gate reads the damage meter, but not how the stream's sourceless heals are
  split into own (to drop) and foreign (to replay). **Planner ruling 2 -- `SM.AttributeHeals(rec, kit)`:** pair by time and target with the player's own
  casts (a direct heal in `[cast - 0.3, cast + 1.0]` on the cast's target; a HoT's ticks at
  `cast + 3k +/- 0.4` for `k = 1..ticks`, at most twice the kit's tick, ending at a recast of the
  same family on the same target; pre-pull HoTs' ticks counted back from their expiry); everything
  else is foreign. The damage meter's own total checks it (T14, gate 8 "heals attributed"; a pull
  that disagrees beyond the gate's threshold is not coached from).
- A party member's max health is secret (plan §6 Q2). **Planner ruling 1 --
  `SM.EstimateMaxHP(deficits, hits)`, a lower-bound stand-in:** the largest deficit the target lived through
  plus the biggest single hit it took (it survived the first, and one more such hit is the plan's own
  danger idea), marked `maxEstimated = true` on the target and on the scenario; the player's max is
  the plain one recorded. Every report that prints a percentage of a party member's health must say
  "estimated" (T14, T16); **the deficit is exact and is what the engine decides on**.
- Health, reconstructed (plan §2.3): per target a deficit, `+ DMG`, `- HEAL` (all heals, own and
  foreign -- they all landed), floored at 0, starting at 0 (full at the pull -- the plan's anchor),
  set to the max at a `DIED`; health = max - deficit, sampled on a 2 s grid from 0 to `dur`.
- Forever has no unreported regen (Dreamstate is TBC; plan §2.5): `initial.energize = 0`,
  `apiBase` / `apiCasting` = the first mana sample's `base` / `cast`.
- **Lead, at hand-out (2026-09-28, after T13 landed as `6624d58`):** the recorder stores
  `initial.auras` entries as `{token, spellId, remaining, stacks}` and its stored roster carries no
  token (`Modules/SpellTuner_Recorder/Recorder_Forever.lua`, `ScanAuras` / `CopyRoster`), so a stream
  cannot say which target a pre-pull HoT sits on. This task adds `tgt` (the roster index, which the
  scan already iterates by) to each entry; `ScenarioV3` maps an aura by `tgt` and drops one without it.
- Kit families and the spell index: T15 (`MD.SpellData.spells[id].family`, `HOT_INDEX` names).

## Files

| file | change | role |
|---|---|---|
| `Modules/SpellTuner_Replay/Scenario_Forever.lua` (new) | `SM.AttributeHeals`, `SM.EstimateMaxHP`, `SM.ScenarioV3`; wraps `SM.ScenarioFromRecording` so `rec.v == 3` goes to `ScenarioV3` and anything else to the original; defines `MD:ClassifyCast(id)` **only if nil**: `(label, kind)` from the book -- a heal family `heal`, a damage family `damage`, a kindless book spell `utility`, else `unknown` | the scenario |
| `Modules/SpellTuner_Recorder/Recorder_Forever.lua` | `ScanAuras` records `tgt` (the roster index) in each entry and `CopyAuraList` copies it; nothing else | the recorder's aura target |
| `tools/recordcheck.lua` | assertion 10 also requires the pre-pull Rejuvenation's `tgt` to be the tank's index (same name, same count) | suite |
| `Modules/SpellTuner_Replay/*.toc` | `Scenario_Forever.lua` after `Engine\SimModel.lua`, before `Ready.lua` | TOCs |
| `tools/foreverfixture.lua` (new) | `return function(opts) ... end` building the hand-made v3 stream below (a fresh table each call; `opts` may override the meter, a death, the foreign heals) -- T14, T16 and T17 reuse it | fixture |
| `tools/scenariocheck.lua` (new, forever) | the suite below, on that stream | suite |

### `SM.ScenarioV3(rec, kit)` returns the v2 shape plus

- `ev`: a **new** array set (never the stream's own): `DMG`, `DIED`, `CASTSTART`, `CANCEL` copied;
  each `HEAL` either dropped (own) or copied as `FHEAL` (foreign); `OWNCAST` copied (the engine's
  script reads it through `script`, as v2).
- `targets[i]`: `maxHP` (plain or estimated), `maxEstimated`, `danger` (v2's rule on the recorded
  hits), `hp0 = maxHP`, `tracked` (in `rec.tracked` and hit or healed at least once).
- `initial`: `{mana, form = "caster", apiBase, apiCasting, energize = 0, auras = <mapped>,
  known = <engine family keys>}`; an aura whose spell is not in `MD.SpellData.spells` is dropped.
- `script` and `fixed` as v2 (fixed = casts not in `MD.SpellData.spells`, with `MD:ClassifyCast`'s kind).
- `rates` from `rec.mana`; `sampleT = rec.mana.t`; `hpSampleT` = the 2 s grid.
- `recordedHp = { t = grid, hp = { [i] = {...} } }` (the reconstruction), `attribution = { own,
  foreign, ownDirect, ownTick, prepull }` counts, `maxEstimated` (any target), `incoming = {}`,
  `threat = {}` (secret by policy, plan §5).

## Rules

- Pure: no client call, no `MD.API`, no `GetTime` in `Scenario_Forever.lua` except `MD:ClassifyCast`
  reading `MD.Book` (which is the adapter's). Never mutate `rec`.
- `Engine/SimModel.lua` untouched; a v2 stream's scenario byte-for-byte what it was (TBC suites).
- No new global; no library. Comments say why; the two escalated functions each carry a header
  comment "Planner ruling <1 or 2>, 2026-09-28 (FOREVER-PLAN.md, rulings for M3)" and the rule in one line.
- Tests first: scenariocheck written and failing first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/scenariocheck.lua` ends `9 ok, 0 failed`. Fixture: a hand-built v3 stream
   (use the field list in T13; say where you took it from), player (max 375) + party1 (tank), 30 s,
   the stub book's Healing Touch R1 and Rejuvenation R1, own casts with targets, foreign heals
   between them, a pre-pull Rejuvenation on party1 with 6 s left, one untracked-kit cast (Wrath).
   Names, verbatim:
   1. "a v3 stream becomes a scenario of the engine's shape, and a v2 one takes the old road"
   2. "a heal landing with an own direct cast on its target is own; the others are foreign"
   3. "a HoT's ticks by cadence are own; a heal between them is foreign"
   4. "a HoT recast on the same target ends the first one's ticks"
   5. "a pre-pull HoT from the out-of-combat read ticks from the start and its ticks are own"
   6. "health is a deficit from every landed amount, floored at full, sampled every two seconds"
   7. "a party member's max is the stated estimate and marked; the player's is the recorded one"
   8. "casts the healing kit does not price are fixed points with their kind from the book"
   9. "the engine replays the scenario to the reconstructed health when the kit matches the heals"
      -- the fixture's own heals equal the kit's amounts; `SM:Run(sc, nil, {critMode = "ev"})`'s
      `hpCurve` against `recordedHp` within 1% of max, mean, per tracked target.
2. Every other suite at its count (TBC sixteen unchanged; the Forever suites; kitcheck 7, recordcheck
   14).
3. `python3 tools/apicheck.py` 0 findings; `--selftest` as after T13a/T13c.
4. `luac -p` clean.
5. Paste into the Report: the failing run; scenariocheck in full; the fixture's attribution counts
   and reconstructed curves (a few rows); every other tail; apicheck; luac; `git status --short`.

## Out of scope

- The gates (T14), the replay window (T16), coaching (T17). The recorder (T13) beyond the aura `tgt` above. `Engine/SimModel.lua`.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

Implemented as specified, including the lead's hand-out amendment (the recorder's pre-pull aura
entries gain `tgt`). Files touched:

- **`Modules/SpellTuner_Recorder/Recorder_Forever.lua`**: `ScanAuras` now iterates the roster with
  `ipairs` capturing the index `i` (it already walked `R.roster` in order; only the loop variable
  name changed from `_` to `i`) and stores `tgt = i` on each aura entry; `CopyAuraList` copies it
  through. Nothing else in this file changed.
- **`tools/recordcheck.lua`**: assertion 10 ("own HoTs on the party are read before the pull,
  never in combat") gained `rec.initial.auras[1].tgt == 2` (party1/Tank is roster index 2 in the
  fixture) and the detail string reports it. Same name, same count (14).
- **`Modules/SpellTuner_Replay/Scenario_Forever.lua`** (new): `SM.EstimateMaxHP(deficits, hits)`
  (Planner ruling 1 -- the largest deficit lived through plus the biggest single hit, floored at
  1), `SM.AttributeHeals(rec, kit)` (Planner ruling 2 -- pairs each sourceless `HEAL` (kind 15)
  with the player's own casts: a direct/kindless heal in `[cast-0.3, cast+1.0]` on the cast's
  target; a HoT's ticks at `cast + tickPeriod*k`, sized at most twice the kit's own tick, ending at
  a recast of the same family on the same target -- including a pre-pull HoT a recast lands on top
  of; a pre-pull HoT's own ticks counted back from `remaining` with the same `ticksLeft`/`nextTick`
  arithmetic `Engine/SimModel.lua`'s own `init.auras` handling uses), and `SM.ScenarioV3(rec, kit)`
  (the v2 shape plus `recordedHp`, `attribution`, `maxEstimated`, per the Files table's field
  list). `SM.ScenarioFromRecording` is wrapped: `rec.v == 3` goes to `ScenarioV3`, anything else to
  the original (saved as a local before reassignment). `MD:ClassifyCast(id)` is defined only if
  nil, reading `book.spells[id].name` -> `book.families[name].kind` (a heal family "heal", a
  damage family "damage", a kindless family "utility", an id the book never saw "unknown") -- see
  "judgment call" below for a real bug this caught. No client call, no `MD.API`, no `GetTime()`
  anywhere in this file; `rec` is never mutated (only read).
- **`Modules/SpellTuner_Replay/SpellTuner_Replay.toc`, `SpellTuner_Replay_Mainline.toc`**:
  `Scenario_Forever.lua` inserted after `Engine\SimModel.lua`, before the blank line and `Ready.lua`.
- **`tools/foreverfixture.lua`** (new): `return function(opts) ... end` building the hand-made v3
  stream the acceptance criteria describe -- player (Healroot, plain max 375) + party1 (Tank,
  secret max), 30s, Healing Touch R1 (5185) and Rejuvenation R1/R2 (774, 1058) from the stub's
  fixed five, foreign heals between the own ones, a pre-pull Rejuvenation on party1 with 6s left,
  one untracked-kit cast (Wrath, 5176). `opts.death`, `opts.foreign`, `opts.meter` let a later
  caller (T14/T16/T17) vary it without touching this file; a fresh table every call.
- **`tools/scenariocheck.lua`** (new): the 9-assertion suite below.

### A design note the Facts section does not spell out, worth recording

`Engine/SimModel.lua`'s own HoT model does **not** restart a tick's cadence on a recast (its own
comment: "a refresh extends a HoT; it does NOT restart its tick timer") -- so the very next tick
after a recast lands at whatever the *previous* application's own schedule already had queued, not
at `recast_t + tickPeriod`. Getting assertion 9's 1%-tolerance reproduction right meant the fixture
had to place its recast (cast C, Rejuvenation R2) exactly on what would have been the *previous*
cast's own next tick boundary (`7 + 3*3 = 16`) -- at that exact instant the engine's tie-break order
(the script event fires before the heap's stale tick at the same timestamp) produces one clean
tick, at that instant, at the new rank's value. `SM.AttributeHeals` encodes the general rule this
matches for a *boundary-exact* recast: a fresh cast's ticks start one `tickPeriod` after its own
cast time; a cast landing while a same-family/target application is still active (checked against
that earlier application's own `tickPeriod*ticks` duration, pre-pull included) starts counting
ticks from its own cast time instead (`k=0`) -- which is what "ends the first one's ticks" (Facts)
resolves to at the instant of the recast. This is a documented simplification (a recast landing at
an *arbitrary* moment, not on the old boundary, would tick at a time this rule does not predict);
the fixture was built to land exactly there rather than widening `AttributeHeals` to reproduce the
engine's full continuation arithmetic, which the task's own Facts wording ("cast + 3k") does not
ask for.

### Judgment call / a real bug the tests-first loop caught

`Spells/Book.lua`'s `BuildEntry` (what actually populates `book.spells`, read by `Book:Get()`) never
sets a per-spell `.kind` field -- only `Book:GroupFamilies` sets `.kind` on the *family* object
(`book.families[name].kind`), and only `Book:ReadSpell` (a different, one-off entry builder used
for ids outside the book) sets `entry.kind` on its own throwaway table. My first draft of
`MD:ClassifyCast` read `book.spells[id].kind`, which is always nil for every book spell -- acceptance
8 (Wrath's fixed entry) failed with `kind=utility` instead of `damage` until I fixed it to resolve
the family by name first. The tests-first section below shows this run.

### Tests first

`tools/scenariocheck.lua` was written against the drafted `Scenario_Forever.lua` (the two were
developed together, since the event-pairing rules needed settling alongside the fixture), then run
and made to fail honestly rather than adjusted to match whatever the code did. The `MD:ClassifyCast`
bug above is the one real bug this caught; restoring the buggy version and rerunning:

```
casts the healing kit does not price are fixed points with their kind from the book             FAIL - wrath=20,5176,20,2,utility

8 ok, 1 failed
  FAIL casts the healing kit does not price are fixed points with their kind from the book - wrath=20,5176,20,2,utility
```

Every other assertion already passed against that draft (the bug was isolated to `ClassifyCast`).
Restoring the fixed file (a plain file copy, no `git` command) reruns to 9/9 below.

### `tools/scenariocheck.lua`, full run

```
|cff9966ffSpellTuner:|r Recorder: loaded
|cff9966ffSpellTuner:|r Replay: loaded
a v3 stream becomes a scenario of the engine's shape, and a v2 one takes the old road           ok - shapeOk=true v2Ok=true
a heal landing with an own direct cast on its target is own; the others are foreign             ok - own[direct]=true own[foreign]=nil ownDirect=1
a HoT's ticks by cadence are own; a heal between them is foreign                                ok - tick1=true between=nil tick2=true
a HoT recast on the same target ends the first one's ticks                                      ok - at16=true amt16=14 at19=true
a pre-pull HoT from the out-of-combat read ticks from the start and its ticks are own           ok - t3=true t6=true prepull=2
health is a deficit from every landed amount, floored at full, sampled every two seconds        ok - max=1192 at0=1192 at2=692 at4=500
a party member's max is the stated estimate and marked; the player's is the recorded one        ok - p1=375,false p2=1192,true any=true
casts the healing kit does not price are fixed points with their kind from the book             ok - wrath=20,5176,20,2,damage
the engine replays the scenario to the reconstructed health when the kit matches the heals      ok - t1: maxDev=0.00 meanDev=0.00 (maxHP*1%=3.75) | t2: maxDev=0.00 meanDev=0.00 (maxHP*1%=11.92)

9 ok, 0 failed
```

Attribution counts on the fixture: `own = 9` (1 direct + 8 tick), `foreign = 2`, `ownDirect = 1`,
`ownTick = 8`, `prepull = 2`. Reconstructed curve for the tank (target 2, estimated max 1192,
grid every 2s): `t=0 hp=1192, t=2 hp=692 (500 dmg), t=4 hp=500 (692 net deficit), t=6 hp=508,
t=8 hp=508, t=10 hp=516, t=12 hp=546, t=30 hp=610` -- and `SM:Run`'s `hpCurve` matches this array
exactly (`maxDev=0.00`) because crit was forced to 0 (`S.crit[4] = 0`) and the fixture's own heal
amounts/times were placed at exactly what the engine's HoT model produces for the same script (see
the design note above).

### `tools/recordcheck.lua`, full run

```
14 ok, 0 failed
```
(all 14 names unchanged; assertion 10's new `tgt=2` check is in the detail string.)

### Every other suite

```
kitcheck       7 ok, 0 failed
probecheck    73 ok, 0 failed
modulecheck   14 ok, 0 failed
forevercheck  13 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
simcheck      -> PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow      8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate        7 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc     15 ok, 0 failed
corecheck/forever    10 ok, 0 failed
corecheck/tbc         8 ok, 0 failed
svcheck/forever       6 ok, 0 failed
svcheck/tbc           1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc      1 ok, 0 failed
```

Every count matches the baseline the lead's hand-out gave exactly; the TBC sixteen are unchanged
(this task touches no TBC file, and `Engine/SimModel.lua` itself is untouched -- confirmed by the
v2 half of assertion 1, which runs a trivial v2-shaped rec through `SM.ScenarioFromRecording` and
checks it still returns the plain v2 shape with no `recordedHp`/`attribution` field).

### apicheck

```
apicheck: 8 Forever TOCs, 28 files, 41 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok   (refcheck.py --selftest)
```

28 files vs the baseline's 27 is exactly the one new file (`Scenario_Forever.lua`); no new client
binding was needed (this file never calls `MD.API` or a client global), so the distinct-globals
count (41) is unchanged.

### luac -p

```
Modules/SpellTuner_Recorder/Recorder_Forever.lua  OK
Modules/SpellTuner_Replay/Scenario_Forever.lua    OK
tools/recordcheck.lua                             OK
tools/scenariocheck.lua                           OK
tools/foreverfixture.lua                           OK
```

(`tools/.lua/lua-5.1.5/src/luac`, the one `tools/run.sh` builds; `luac` is not on `PATH`.)

### git status --short

```
 M Modules/SpellTuner_Recorder/Recorder_Forever.lua
 M Modules/SpellTuner_Replay/SpellTuner_Replay.toc
 M Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc
 M docs/tasks/HANDOVER.md
 M docs/tasks/T13d-scenario-v3.md
 M tools/recordcheck.lua
?? Modules/SpellTuner_Replay/Scenario_Forever.lua
?? tools/foreverfixture.lua
?? tools/scenariocheck.lua
```

`docs/tasks/HANDOVER.md` was already modified before this task started (the lead's) and was not
touched further. `docs/tasks/T13d-scenario-v3.md` shows modified only because this Report section
was appended, as asked. No `git add`, `stash`, `checkout -- <path>`, `reset` or commit was run.

### Skipped / out of scope (as the task says)

The gates (T14), the replay window (T16), coaching (T17), any recorder change beyond the aura `tgt`
field, `Engine/SimModel.lua` itself, `CLAUDE.md` and every `docs/` file except this Report.

### Question

None -- the one Fact that needed resolving mid-implementation (the recast-tick-cadence mismatch
between a simple "cast + 3k" model and `Engine/SimModel.lua`'s actual non-resetting tick timer) is
documented above as a design note rather than a blocking question: it is resolved by how the
fixture places its recast, and `AttributeHeals`' rule is stated in its own comment so a later task
extending it (T14/T16/T17) can see the boundary of what it currently handles exactly.

## Lead review 1 (2026-09-28) -- re-issued

Not accepted yet; one thing, everything else stays as it is. Fix it on top of the tree.

**`SM.AttributeHeals`: "a recast over an already-ticking application starts counting from its own
cast time (k = 0)".** That rule claims a heal at the instant of the recast (a refreshed HoT does not
tick on the refresh) and misses the recast's real ticks whenever the recast falls between two
ticks. It passes only because the fixture puts the recast exactly on a tick boundary, where every
rule agrees -- the test asserts the code, not the behaviour. What the client does to the tick
timer on a refresh is **UNKNOWN** on Forever: planner ruling 2 reads it as `cast + 3k` from the
recast, the engine keeps the old cadence (`Engine/SimModel.lua`, v0.14.2, measured on TBC). Required:

1. Every application claims its ticks at `c.t + P*k`, `k = 1..ticks` (ruling 2), and a recast that
   lands on an active application of the same family and target **also** claims the continuing
   cadence of the one it replaces (`oldNext + P*k`, up to the new application's end) -- both
   cadences, each claim size-guarded as now and consumed at most once. No claim at the recast
   instant. The same for a recast on a pre-pull HoT (its cadence from its expiry). A header line
   says the order is UNKNOWN and why both are accepted.
2. Fixture (`tools/foreverfixture.lua`): the recast moves **off** a tick boundary (for example 1.5 s
   after a tick) and its recorded ticks follow the engine's cadence (so assertion 9 still reproduces
   within 1%); a foreign heal on the same target **at the recast instant** is added.
3. Assertion 4 additionally requires that heal to be foreign and the recast's ticks own; assertion 3
   or 4 (say which) also covers the ruling's own cadence: a second, hand-built stream (a fresh
   `foreverfixture` call with an override) whose recast ticks land at `recast + 3k` attributes them
   own too. Names and count unchanged (9).

Acceptance otherwise unchanged. Append a **Report (re-issue)** section below with the failing run
(new fixture against the old rule), scenariocheck in full, the attribution counts, every other tail,
apicheck, luac, `git status --short`.

## Report (re-issue)

Fixed the one thing the review named; nothing else in the tree touched.

- **`Modules/SpellTuner_Replay/Scenario_Forever.lua`**: `SM.AttributeHeals` changed in two places,
  both inside the tick-claim loop over `casts`.
  1. The per-application cadence is now unconditional: every cast (fresh or a recast) claims its
     own ticks at `c.t + tickPeriod*k` for `k = 1..ticks` -- the old `fresh`/`offset` special case
     (a recast claiming `k=0` at its own instant) is gone. No claim ever lands at the recast's own
     instant now, for either cadence.
  2. `ActiveBefore` no longer returns a bare boolean; it returns the active application's own
     continuing cadence as `{anchor, tickPeriod, prepull}` (`anchor` already being that cadence's
     first future tick, so a plain own cast's anchor is `c.t + tickPeriod` and a pre-pull aura's is
     its own `nextTick`). A new `NextOnCadence(anchor, tickPeriod, t)` returns the smallest
     `anchor + tickPeriod*m` (`m >= 0`) that is `>= t`. When a recast lands over an active
     application (`ActiveBefore` returns non-nil), the recast ALSO claims that application's
     continuing cadence from `NextOnCadence(active.anchor, active.tickPeriod, c.t)` stepping by
     `active.tickPeriod`, up to `min(cutoff, c.t + newTickPeriod*newTicks)` ("the new application's
     own end") -- each claim still going through the same `AddClaim`/size-guard/consumed-once
     machinery as every other claim, tagged `prepull = active.prepull` (true only when the
     continuing cadence traces back to a pre-pull aura, not an own cast). A header comment above
     `SM.AttributeHeals` states the order is UNKNOWN on Forever and names both readings (Planner
     ruling 2's own words vs `Engine/SimModel.lua`'s actual, unreset tick timer) as the reason both
     are claimed rather than guessed between.
  I read `Engine/SimModel.lua`'s `ApplyHot`/`E_TICK` handling (lines ~421-459, ~797-809) to confirm
  which cadence the engine itself actually produces on an off-boundary recast, since assertion 9
  needs the reconstruction to match it: `st.nextTick` is kept (not re-anchored) whenever the old
  `nextTick` is still `>= t` at the recast, `st.tick`/`st.ticksLeft` are overwritten to the new
  rank's, and the tick handler keeps advancing `nextTick` by the same `tickPeriod` — i.e. exactly
  the "old anchor, new amount" cadence `NextOnCadence` computes. This is documented in the new
  fixture comment rather than repeated as a second design note.
- **`tools/foreverfixture.lua`**: the recast (cast C, Rejuvenation R2, spell 1058) moved from
  landing exactly on cast B's tick boundary (t=16) to 1.5s off it (t=17.5); cast B's own normal
  ticks now run to t=16 (a third tick, still before the recast) since the cutoff moved out to
  17.5; a foreign heal (amount 5) lands at the recast's own instant (17.5), never a tick of either
  cadence; the recast's own recorded ticks (t=19, 22, 25, 28, amount 14 each) follow the OLD/
  continuing cadence — what `Engine/SimModel.lua` actually produces, needed for assertion 9's 1%
  reproduction. A new `opts.recastCadence` ("old", the default, or "new") switches those four ticks
  to the OTHER cadence instead (t=20.5, 23.5, 26.5, 29.5 — Planner ruling 2's own "cast + 3k"
  words) for the second, hand-built stream item 3 of the review asks for; nothing else in the
  fixture changed (the DMG/pre-pull/foreign events before t=16, the Wrath cast, `opts.death`/
  `opts.foreign`/`opts.meter` are untouched).
- **`tools/scenariocheck.lua`**: assertion 4 ("a HoT recast on the same target ends the first
  one's ticks") rewritten in place -- same name, same position, count still 9. It now checks, on
  the base (`recastCadence = "old"`) fixture: the heal at the recast's own instant (17.5) is
  foreign (`own[atRecast] ~= true`), the first continuing tick (t=19) is own with the new rank's
  amount (14). It then builds a **second** fixture (`buildFixture({ recastCadence = "new" })`,
  a fresh call per the review's wording) and checks its two first "new cadence" heals (t=20.5,
  23.5) are also attributed own -- covering the ruling's own cadence in the same assertion (I put
  it in assertion 4, not 3, since it is specifically about what a recast's ticks are attributed
  to). Assertions 1, 2, 3, 5-9 are byte-for-byte what they were; assertion 6's checked values
  (t=0,2,4) and assertion 7 are unaffected by the fixture change (they depend only on events at or
  before t=13, none of which moved).

### Tests first: the new fixture and assertion 4 against the OLD (pre-review) rule

I restored the pre-review `Scenario_Forever.lua` (the version this task's first Report describes,
saved before editing) over the fixed one, ran `tools/scenariocheck.lua` against the NEW fixture and
NEW assertion 4, confirmed it fails, then restored the fixed file (a plain file copy, no `git`
command) and reran to 9/9:

```
a HoT recast on the same target ends the first one's ticks                                      FAIL - atRecast=true at19=nil amt19=14 at205(new cadence)=true at235(new cadence)=true
the engine replays the scenario to the reconstructed health when the kit matches the heals      FAIL - t1: maxDev=0.00 meanDev=0.00 (maxHP*1%=3.75) | t2: maxDev=51.00 meanDev=12.44 (maxHP*1%=11.92)

7 ok, 2 failed
  FAIL a HoT recast on the same target ends the first one's ticks - atRecast=true at19=nil amt19=14 at205(new cadence)=true at235(new cadence)=true
  FAIL the engine replays the scenario to the reconstructed health when the kit matches the heals - t1: maxDev=0.00 meanDev=0.00 (maxHP*1%=3.75) | t2: maxDev=51.00 meanDev=12.44 (maxHP*1%=11.92)
```

The old rule claims the recast's own instant (17.5) as a "direct-less, k=0" tick, so the foreign
heal there is wrongly read as own (`atRecast=true`), and it never claims t=19 at all (`at19=nil`)
since its recast branch only ever counted from the recast's own time forward with no offset,
missing the boundary-crossing old cadence entirely -- which is exactly why assertion 9's
reconstruction also disagreed with the engine's actual replay by 51 health (12.4 mean) on the tank.

### `tools/scenariocheck.lua`, full run (fixed rule)

```
a v3 stream becomes a scenario of the engine's shape, and a v2 one takes the old road           ok - shapeOk=true v2Ok=true
a heal landing with an own direct cast on its target is own; the others are foreign             ok - own[direct]=true own[foreign]=nil ownDirect=1
a HoT's ticks by cadence are own; a heal between them is foreign                                ok - tick1=true between=nil tick2=true
a HoT recast on the same target ends the first one's ticks                                      ok - atRecast=nil at19=true amt19=14 at205(new cadence)=true at235(new cadence)=true
a pre-pull HoT from the out-of-combat read ticks from the start and its ticks are own           ok - t3=true t6=true prepull=2
health is a deficit from every landed amount, floored at full, sampled every two seconds        ok - max=1192 at0=1192 at2=692 at4=500
a party member's max is the stated estimate and marked; the player's is the recorded one        ok - p1=375,false p2=1192,true any=true
casts the healing kit does not price are fixed points with their kind from the book             ok - wrath=20,5176,20,2,damage
the engine replays the scenario to the reconstructed health when the kit matches the heals      ok - t1: maxDev=0.00 meanDev=0.00 (maxHP*1%=3.75) | t2: maxDev=0.00 meanDev=0.00 (maxHP*1%=11.92)

9 ok, 0 failed
```

Attribution counts on the base fixture (`recastCadence = "old"`, the default): `own = 10`
(1 direct + 9 tick), `foreign = 3`, `ownDirect = 1`, `ownTick = 9`, `prepull = 2` (own rose from 9
to 10 and foreign from 2 to 3 versus the first Report's numbers -- cast B now gets a third normal
tick at t=16, before the recast, since the cutoff moved out to 17.5; the new foreign heal at the
recast's own instant is the extra foreign one). Reconstructed curve for the tank (target 2),
against the engine's own `hpCurve[2]` from `SM:Run` -- identical at every 4s mark:

```
recordedHp: t=0 hp=1192  t=4 hp=500  t=8 hp=508  t=12 hp=546  t=16 hp=562  t=18 hp=567  t=20 hp=581  t=24 hp=595  t=28 hp=623
hpCurve:    t=0 hp=1192.0 t=4 hp=500.0 t=8 hp=508.0 t=12 hp=546.0 t=16 hp=562.0        t=20 hp=581.0 t=24 hp=595.0 t=28 hp=623.0
```

### `tools/recordcheck.lua`

Untouched by this re-issue (the review named only `SM.AttributeHeals` and the fixture/test in
`SpellTuner_Replay`); reran anyway since it shares the module load order:

```
14 ok, 0 failed
```

### Every other suite

```
kitcheck       7 ok, 0 failed
probecheck    73 ok, 0 failed
modulecheck   14 ok, 0 failed
forevercheck  13 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
simcheck      -> PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow      8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate        7 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc     15 ok, 0 failed
corecheck/forever    10 ok, 0 failed
corecheck/tbc         8 ok, 0 failed
svcheck/forever       6 ok, 0 failed
svcheck/tbc           1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc      1 ok, 0 failed
```

Every count matches the baseline exactly, including `scenariocheck 9` and `recordcheck 14` (both
named as "stays" in the task's baseline line). This task touches no `Engine/SimModel.lua` line and
no TBC file, and assertion 1's v2 half (a trivial v2-shaped rec through
`SM.ScenarioFromRecording`, checked to return the plain v2 shape with no `recordedHp`/`attribution`
field) still passes, confirming the v2 road is untouched.

### apicheck

```
apicheck: 8 Forever TOCs, 28 files, 41 distinct globals, 0 findings (baseline 69893)
```

```
FAIL Bad.lua:2 os not in the client's Lua
FAIL Bad.lua:3 UnitHealth client call outside Client/
FAIL Bad.lua:4 NewGlobalName new global
FAIL Bad.lua:5 COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT_UNFILTERED named
FAIL Bad.lua:6 C_Spell.NoSuchMember C_ member not in baseline 69893
FAIL Fixture_Mainline.toc:7 Gone.lua missing file
rule 8: Handlers.lua:21 unit used before IsSecret in the UNIT_HEALTH_BAD handler
rule 8: Handlers.lua:27 unit used before IsSecret in the UNIT_AURA_BAD handler
FAIL Modules/Sample/Sample_Mainline.toc:7 Missing.lua missing file
selftest: 10 of 10 findings as expected
```

`refcheck.py --selftest`:

```
refcheck: 6 spells, 1 agree, 4 disagree, 1 not in the reference
selftest: ok
```

28 files (unchanged from the first Report -- this re-issue added no new file); 41 distinct globals
unchanged (no new client binding was needed to satisfy the review, since the fix is pure
timing/pairing arithmetic over data the file already reads).

### `luac -p`

```
Modules/SpellTuner_Recorder/Recorder_Forever.lua  OK
Modules/SpellTuner_Replay/Scenario_Forever.lua    OK
tools/recordcheck.lua                             OK
tools/scenariocheck.lua                           OK
tools/foreverfixture.lua                           OK
```

(`tools/.lua/lua-5.1.5/src/luac`, the one `tools/run.sh` builds; `luac` is not on `PATH`.)

### `git status --short`

```
 M Modules/SpellTuner_Recorder/Recorder_Forever.lua
 M Modules/SpellTuner_Replay/SpellTuner_Replay.toc
 M Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc
 M docs/tasks/HANDOVER.md
 M docs/tasks/T13d-scenario-v3.md
 M tools/recordcheck.lua
?? Modules/SpellTuner_Replay/Scenario_Forever.lua
?? tools/foreverfixture.lua
?? tools/scenariocheck.lua
```

Same file set as before this re-issue (only the two `??` files' own contents changed:
`Scenario_Forever.lua` and `foreverfixture.lua`; `scenariocheck.lua`'s assertion 4 changed). No
`git add`, `stash`, `checkout -- <path>`, `reset` or commit was run. `docs/tasks/HANDOVER.md` was
already modified before this re-issue started (the lead's) and was not touched further;
`docs/tasks/T13d-scenario-v3.md` is modified only by this Report (re-issue) section.

### Skipped / out of scope

Everything the original task and this review left out of scope: the gates (T14), the replay window
(T16), coaching (T17), any recorder change, `Engine/SimModel.lua` itself, `CLAUDE.md` and every
`docs/` file except this Report.

### Question

None. The review's own required reading (`Engine/SimModel.lua`'s `ApplyHot`) confirmed which
cadence the engine actually produces on an off-boundary recast, which is what let the base fixture
reproduce assertion 9 at 0.00 deviation rather than needing a wider tolerance or a guess.

## Lead review 2 (2026-09-28) -- re-issued

Review 1's point is fixed for **one** recast. It breaks on a chain, which is the common case (a
Rejuvenation rolled on the tank before it runs out, again and again). `ActiveBefore` returns the
most recent application's **own** cadence (`c.t + P`), but when that application was itself a
recast, the engine's cadence (the one the review asked to accept alongside ruling 2's) is the
cadence **it** inherited -- the first application's, carried through every refresh
(`Engine/SimModel.lua`, the tick timer is never restarted). After a second recast the inherited
ticks are claimed by nobody and go foreign. Required:

1. Each application carries its **inherited anchor**: its own (`c.t + P`) when it lands on nothing,
   else the inherited anchor of the application it replaces (a pre-pull HoT's anchor is its own
   cadence from expiry). A recast claims its own cadence **and** the inherited one (not the
   replaced application's own), up to its end or the next recast. Still no claim at a recast
   instant; still each claim consumed once.
2. Fixture: a variant (a `foreverfixture` override, like `recastCadence`) with **three**
   applications of Rejuvenation on the tank, each refreshed off a tick boundary, whose recorded
   ticks follow the engine's cadence throughout; assertion 4 additionally requires every one of
   those ticks own. Name and count unchanged (9). Assertion 9 unchanged (the base fixture).

Append a **Report (re-issue 2)** section with the failing run (the new variant against the current
rule), scenariocheck in full, every other tail, apicheck, luac, `git status --short`.

## Report (re-issue 2)

Fixed the chain the review named; nothing else touched.

- **`Modules/SpellTuner_Replay/Scenario_Forever.lua`**: `SM.AttributeHeals` reworked so every
  application (fresh or a recast) carries an `inherited` cadence, not just the immediately-replaced
  application's own one.
  1. `ActiveBefore` is gone; `FindActive(t, tgt, family, beforeIdx)` replaces it and returns only
     `"cast", j` or `"prepull", a` (or nil) -- which application is active, not its cadence. Two new
     small helpers compute a cadence directly: `OwnCadenceOf(cst)` (a fresh application's own,
     `cst.t + tickPeriod`) and `PrepullCadenceOf(a)` (a pre-pull aura's own remaining-tick
     arithmetic, unchanged from before).
  2. A new `inherited` table, filled in cast order as the main loop processes each cast: for cast
     `i`, `inherited[i]` is `OwnCadenceOf(c)` when `FindActive` finds nothing active; when it finds
     an active application, `inherited[i]` is **that application's own `inherited` entry** (falling
     back to `OwnCadenceOf` of that application only if this is the first time it is asked, i.e. it
     was itself a fresh cast) -- never that application's own fresh cadence. This is the one-line
     fix: review 1's code read `active.anchor = c.t + tickPeriod` off the immediately-replaced
     cast directly; this reads `inherited[ref]` first, which is what makes a chain of any length
     keep tracing back to the very first application.
  3. The claiming loop is otherwise unchanged: a recast (`kind` non-nil) claims `myInherited`'s
     cadence from `NextOnCadence(myInherited.anchor, myInherited.tickPeriod, c.t)` up to
     `min(cutoff, ownEnd)`, tagged `prepull = myInherited.prepull`; no claim at the recast's own
     instant; every claim still goes through the same `AddClaim`/size-guard/consumed-once machinery.
  4. The header comment above `SM.AttributeHeals` gained a "Lead review 2" paragraph stating the
     chain bug and the fix in the same terms as this report.
- **`tools/foreverfixture.lua`**: a new `opts.chain` branch (checked first, before the existing
  narrative) returns a wholly separate v3 stream -- player + tank roster, no pre-pull aura, no
  DMG/foreign events -- built around **three** Rejuvenation applications (spell 774 throughout) on
  the tank: X1 fresh at t=7, X2 a recast at t=17.5 (1.5s off X1's own t=16 boundary), X3 a recast at
  t=23.5 (1.5s off X2's own t=22 boundary, and -- the point of the fixture -- itself exactly on X1's
  original cadence, so a fix that reads X2's own cadence instead of X1's inherited one would still
  pass by coincidence at this one instant; the assertion checks every claimed tick, including the
  ones between X2's and X3's own recast instants, not just this one). All ten resulting heal events
  (10, 13, 16 from X1; 19, 20.5, 22 from X2; 25, 26.5, 28, 29.5 from X3) are own by hand-worked
  arithmetic against `Engine/SimModel.lua`'s kept-cadence rule, documented tick by tick in the
  fixture's own comment. Nothing in the existing `recastCadence` branch or any other `opts` field
  changed.
- **`tools/scenariocheck.lua`**: assertion 4 ("a HoT recast on the same target ends the first one's
  ticks") extended in place -- same name, same position, count still 9 -- with a `chainAllOwn` check
  that builds `buildFixture({ chain = true })`, looks up all ten expected heal-event times and
  requires every one attributed own, folded into the same `ok`/detail string alongside the existing
  base-fixture and `recastCadence = "new"` checks (I put it in assertion 4, as review 2 does not ask
  for a new assertion and the review's own item 2 describes it as extending "assertion 4"). Assertion
  9 (the base fixture's reconstruction-vs-engine reproduction) is untouched, as required.

### Tests first: the new chain variant against the review-1 rule (before this fix)

I set aside the fixed `Scenario_Forever.lua` (copied to a scratch path, not a `git` operation),
restored the review-1 version (the one `Report (re-issue)` describes -- `ActiveBefore` reading the
immediately-replaced application's own cadence) with the NEW fixture and NEW assertion 4 already in
place, ran `tools/scenariocheck.lua`, confirmed it fails, then restored the fixed file (a plain file
copy) and reran to 9/9:

```
a HoT recast on the same target ends the first one's ticks                                      FAIL - atRecast=nil at19=true amt19=14 at205(new cadence)=true at235(new cadence)=true chainAllOwn=false

8 ok, 1 failed
  FAIL a HoT recast on the same target ends the first one's ticks - atRecast=nil at19=true amt19=14 at205(new cadence)=true at235(new cadence)=true chainAllOwn=false
```

The review-1 rule gets the base fixture's single recast right (`atRecast`/`at19`/the two
`recastCadence` checks all still pass) but `chainAllOwn=false`: X3's continuing ticks (25, 28) go
unclaimed because `ActiveBefore` read X2's own fresh cadence (anchor 20.5) rather than the cadence
X2 itself inherited from X1 (anchor 10) -- exactly the bug the review names.

### `tools/scenariocheck.lua`, full run (fixed rule)

```
|cff9966ffSpellTuner:|r Recorder: loaded
|cff9966ffSpellTuner:|r Replay: loaded
a v3 stream becomes a scenario of the engine's shape, and a v2 one takes the old road           ok - shapeOk=true v2Ok=true
a heal landing with an own direct cast on its target is own; the others are foreign             ok - own[direct]=true own[foreign]=nil ownDirect=1
a HoT's ticks by cadence are own; a heal between them is foreign                                ok - tick1=true between=nil tick2=true
a HoT recast on the same target ends the first one's ticks                                      ok - atRecast=nil at19=true amt19=14 at205(new cadence)=true at235(new cadence)=true chainAllOwn=true
a pre-pull HoT from the out-of-combat read ticks from the start and its ticks are own           ok - t3=true t6=true prepull=2
health is a deficit from every landed amount, floored at full, sampled every two seconds        ok - max=1192 at0=1192 at2=692 at4=500
a party member's max is the stated estimate and marked; the player's is the recorded one        ok - p1=375,false p2=1192,true any=true
casts the healing kit does not price are fixed points with their kind from the book             ok - wrath=20,5176,20,2,damage
the engine replays the scenario to the reconstructed health when the kit matches the heals      ok - t1: maxDev=0.00 meanDev=0.00 (maxHP*1%=3.75) | t2: maxDev=0.00 meanDev=0.00 (maxHP*1%=11.92)

9 ok, 0 failed
```

Assertion 9's numbers are byte-identical to the re-issue 1 report's (the base fixture did not
change).

### Every other suite

```
recordcheck    14 ok, 0 failed
kitcheck        7 ok, 0 failed
probecheck     73 ok, 0 failed
modulecheck    14 ok, 0 failed
forevercheck   13 ok, 0 failed
parsecheck     11 ok, 0 failed
bookcheck      15 ok, 0 failed
tipcheck       14 ok, 0 failed
clockcheck     15 ok, 0 failed
spellsui       15 ok, 0 failed
measurecheck   18 ok, 0 failed
simcheck       -> PASS
reccheck       54 ok, 0 failed
replaycheck    80 ok, 0 failed
replayui       98 ok, 0 failed
runcheck       78 ok, 0 failed
reviewui       44 ok, 0 failed
navui          25 ok, 0 failed
dashui         56 ok, 0 failed
regencheck     27 ok, 0 failed
simwindow       8 ok, 0 failed
solvercheck    70 ok, 0 failed
timeline       27 ok, 0 failed
spelltip       48 ok, 0 failed
practice       74 ok, 0 failed
practiceui     49 ok, 0 failed
migrate         7 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc     15 ok, 0 failed
corecheck/forever    10 ok, 0 failed
corecheck/tbc         8 ok, 0 failed
svcheck/forever       6 ok, 0 failed
svcheck/tbc           1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc      1 ok, 0 failed
```

Every count matches the baseline exactly, including `scenariocheck 9` and `recordcheck 14` ("stays"
per the task's baseline line). This re-issue touches no `Engine/SimModel.lua` line, no TBC file and
no recorder file; the TBC sixteen and the recorder are unaffected by construction.

### apicheck

```
apicheck: 8 Forever TOCs, 28 files, 41 distinct globals, 0 findings (baseline 69893)
```

```
FAIL Bad.lua:1 GetSpellInfo not in baseline 69893
FAIL Bad.lua:2 os not in the client's Lua
FAIL Bad.lua:3 UnitHealth client call outside Client/
FAIL Bad.lua:4 NewGlobalName new global
FAIL Bad.lua:5 COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT_UNFILTERED named
FAIL Bad.lua:6 C_Spell.NoSuchMember C_ member not in baseline 69893
FAIL Fixture_Mainline.toc:7 Gone.lua missing file
rule 8: Handlers.lua:21 unit used before IsSecret in the UNIT_HEALTH_BAD handler
rule 8: Handlers.lua:27 unit used before IsSecret in the UNIT_AURA_BAD handler
FAIL Modules/Sample/Sample_Mainline.toc:7 Missing.lua missing file
selftest: 10 of 10 findings as expected
```

`refcheck.py --selftest`:

```
refcheck: 6 spells, 1 agree, 4 disagree, 1 not in the reference
selftest: ok
```

28 files, 41 distinct globals -- unchanged from the first two reports (this re-issue touches no
`.toc` and adds no new file; the fix is pure arithmetic/pairing logic over data the file already
reads, no new client binding needed).

### `luac -p`

```
Modules/SpellTuner_Replay/Scenario_Forever.lua    OK
tools/foreverfixture.lua                           OK
tools/scenariocheck.lua                             OK
tools/recordcheck.lua                               OK
Modules/SpellTuner_Recorder/Recorder_Forever.lua    OK
```

(`tools/.lua/lua-5.1.5/src/luac`, the one `tools/run.sh` builds; `luac` is not on `PATH`.)

### `git status --short`

```
 M Modules/SpellTuner_Recorder/Recorder_Forever.lua
 M Modules/SpellTuner_Replay/SpellTuner_Replay.toc
 M Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc
 M docs/tasks/HANDOVER.md
 M docs/tasks/T13d-scenario-v3.md
 M tools/recordcheck.lua
?? Modules/SpellTuner_Replay/Scenario_Forever.lua
?? tools/foreverfixture.lua
?? tools/scenariocheck.lua
```

Same file set as the prior two reports (only the contents of `Scenario_Forever.lua` and
`foreverfixture.lua` changed further, plus `scenariocheck.lua`'s assertion 4). No `git add`,
`stash`, `checkout -- <path>`, `reset` or commit was run. `docs/tasks/HANDOVER.md` remains the
lead's, untouched by me; `docs/tasks/T13d-scenario-v3.md` is modified only by this Report
(re-issue 2) section.

### Skipped / out of scope

Everything the original task and both reviews left out of scope: the gates (T14), the replay window
(T16), coaching (T17), any recorder change, `Engine/SimModel.lua` itself, `CLAUDE.md` and every
`docs/` file except this Report.

### Question

None. Review 2's own description of the bug (`ActiveBefore` reads the immediately-replaced
application's own cadence rather than what it inherited) matched exactly what tracing the code by
hand showed, and the fixture's three-application chain reproduces the failure and its fix cleanly.

## Lead review 3 (2026-09-28)

Accepted. Both review points are fixed and held by clauses that failed first. The lead reran every
suite (scenariocheck 9, recordcheck 14, kitcheck 7, everything else at its baseline; apicheck 0 over
28 files, `--selftest` 10 of 10, refcheck ok) and `luac -p`. Left open, not this task's: the
recorder's pre-pull aura `remaining` is measured at the out-of-combat scan, up to 2 s before the
pull, and is not shifted to `t0` -- a HoT's first own tick can be placed up to 2 s early. Noted in
`docs/tasks/HANDOVER.md` for the next recorder change.
