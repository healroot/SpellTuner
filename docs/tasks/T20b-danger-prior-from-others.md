# T20b — before a target's first hit, its danger line from other recordings of it

Status: **accepted** 2026-09-29 (lead review at the end; T20 accepted in 1c76605). The second half of the author's
R6 ruling. Shared engine plus both scenario builders.

## Goal

A recorded scenario carries, per target, a **danger prior**: the biggest single hit that same person
took in **other** recordings (leave-one-out, exactly as T17b takes a party member's max: never the
recording being built), as a fraction of this scenario's max for them, times `db.simDangerHits`,
capped at 1. T20's `SM.DangerLine` already reads `tg.dangerPrior` before a target's first hit; this
task fills it on the TBC and the Forever builder, so a coached solver plan starts a fight with the
line that person's past pulls suggest rather than the flat 30%, and still sees nothing of the fight
being coached. For the author, whose ruling names this fallback, and for the causality invariant.

## Facts

- The ruling (planner's hand-out, 2026-09-29, the author's R6 choice): "falling back to db.simFloor
  before its first hit -- or, where a scenario has them, from other recordings of the same target
  (the leave-one-out rule T17b uses for max health; never the fight being coached)".
- T20 (`docs/tasks/T20-causal-danger-line.md`, its Report and the lead review; commit 1c76605): `SM:Run` copies
  `tg.dangerPrior` into `S.dangerPrior[i]`; `SM.DangerLine(S, ti)` returns, for a target whose
  `S.dangerMeasured[i]` is true, the biggest hit so far, else `S.dangerPrior[i]`, else `S.floor`;
  `S.dangerMeasured[i] = (tg.danger ~= nil)` (`Engine/SimModel.lua` 265). **A target never hit in the fight has `tg.danger ==
  nil`** and is therefore read as synthetic (the flat floor) -- with a prior it must be read as
  measured too, or a never-hit target would ignore its prior and a hit-at-all target would not,
  which would itself tell the plan whether the target is ever hit.
- The leave-one-out precedent: `SM.PartyMaxFromOthers(recs, excludeID, name, level)`
  (`Modules/SpellTuner_Replay/Scenario_Forever.lua` 427-456): raises when `excludeID` is nil, skips
  `r.id == excludeID`, matches `name` and, when both are numbers, `level`; `ChooseMaxes` (462) calls
  it only when `rec.id ~= nil` and defaults `others` to `MD.cdb and MD.cdb.recordings`.
- Both clients keep recordings in `MD.cdb.recordings`: TBC `Engine/FightRecorder.lua` 533 (ring of
  8, each with an `id`); Forever `Recorder_Forever.lua` (ring of 8, `v = 3`, `id`). A roster entry
  has `name` on both (TBC via `MD.Recorder.roster`; Forever `roster[i] = { name, guid, class, role,
  level, maxHP, maxSecret }`). The DMG event kind is **1** in both streams (`SM.K.DMG`,
  `Engine/SimModel.lua` 38; the v3 `V3.DMG`, Scenario_Forever.lua 15); `ev.tgt` is the roster index,
  `ev.amt` the amount, `rec.n` the count.
- The builders: TBC `SM.ScenarioFromRecording(rec, kit)` (`Engine/SimModel.lua` 1095-1140 at
  1c76605; the hits at 1108-1119, `targets[i]` at 1133-1139); Forever `SM.ScenarioV3(rec, kit, others)` (Scenario_Forever.lua
  556-724, `targets` at 603-618, `maxHP[i]` from `ChooseMaxes`). The Forever wrapper
  `SM.ScenarioFromRecording(rec, kit)` (732) sends v3 to `ScenarioV3(rec, kit)` and everything else
  to the TBC builder; it passes **no** third argument, so a Forever test sets the store through
  `MD.cdb.recordings` (as coachforever assertion 6 does, restored afterwards) or calls
  `SM.ScenarioV3(rec, kit, store)` directly.

## Files

| file | change | role |
|---|---|---|
| `Engine/SimModel.lua` | (a) `SM.DangerHitFromOthers(recs, excludeID, name, level)`: `error(...)` when `excludeID` is nil; returns nil unless `name` is a string and `recs` a table; for every table `r` in `recs` with `r.id ~= excludeID`, every roster index whose entry has that `name` (and, when both levels are numbers, the same `level`), the largest `r.ev.amt[j]` over `j = 1..r.n` with `r.ev.kind[j] == SM.K.DMG` and `r.ev.tgt[j] ==` that index; returns the largest over all of them and the number of recordings that contributed, or nil when none has a hit above 0. Plain numbers only (`type(...) == "number"` before any comparison). (b) The TBC builder: `SM.ScenarioFromRecording(rec, kit, others)`, `others` defaulting to `MD.cdb and MD.cdb.recordings`; when `rec.id ~= nil` and `SM.DangerHitFromOthers` answers for a target's name, `targets[i].dangerPrior = math.min(1, hit * dangerHits / maxHP)`. (c) `SM:Run`: `S.dangerMeasured[i] = (tg.danger ~= nil) or (tg.dangerPrior ~= nil)` | the prior, and the builder that sets it on TBC |
| `Modules/SpellTuner_Replay/Scenario_Forever.lua` | `SM.ScenarioV3`: the same `dangerPrior` on each target, from `others` (its existing parameter and default), divided by that target's `maxHP[i]` as chosen by `ChooseMaxes`; only when `rec.id ~= nil`. The wrapper passes nothing new | the Forever builder |
| `tools/solvercheck.lua` | three new assertions (Acceptance 1) | TBC suite |
| `tools/coachforever.lua` | one new assertion (Acceptance 2) | Forever suite |

## Rules

- `CLAUDE.md`: no libraries; no new global; the **multi-return trap** -- `SM.DangerHitFromOthers`
  returns two values: take them into locals with an `if`, never through `a and f() or b`; no client
  call and no `MD.API` in these files; no arithmetic on anything not checked to be a number (a
  stored `maxHP` of `-1` is a plain placeholder; divide only by a `maxHP > 0`).
- **The recording being built is never a source of its own prior**, by id; a recording with no `id`
  gets no prior.
- The score does not change (`tg.danger`, `floorSeconds`, the card).
- **Tests first**, failing run pasted.
- If an existing assertion (any suite, either flavour) changes result because a store now holds
  other recordings of the same names: **stop and report** its name, file, line, old and new detail.
  Do not edit it.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/solvercheck.lua` ends `77 ok, 0 failed` (T20's 74 + 3). New names,
   verbatim:
   a. "the danger prior is the biggest hit that person took in other recordings" -- a store holding
      the coached recording (id A: Tank takes a 5000 hit), another recording of Tank (id B, biggest
      hit 2000) and one of another name (a 9000 hit): `SM.DangerHitFromOthers(store, A, "Tank")`
      returns 2000 and 1.
   b. "the prior's exclusion is required" -- `pcall(SM.DangerHitFromOthers, store, nil, "Tank")` is
      false; the scenario built from a copy of recording A with `id = nil` has no `dangerPrior` on
      Tank.
   c. "before the first hit a plan reads the prior from other recordings" -- the scenario built by
      `SM.ScenarioFromRecording(A, kit, store)`: Tank's `dangerPrior` is `2000 / Tank's maxHP` (with
      `simDangerHits` 1) and a plan recording `SM.DangerLine(S, tank)` reads it before Tank's first
      hit and the biggest-hit-so-far after; removing A's 5000 hit changes neither the prior nor
      anything the plan read before that hit's time.
2. `bash tools/run.sh tools/coachforever.lua` ends `18 ok, 0 failed` (T20's 17 + 1). New name,
   verbatim: "a Forever target's danger prior comes from other recordings of the same name and
   level" -- a v3 store with the coached recording, another of Tank at the same level (biggest hit
   H) and one of Tank at another level (a bigger hit): the coached scenario's Tank `dangerPrior ==
   math.min(1, H / Tank's maxHP)`, and a recording with no `id` gets none.
3. Every other suite at its count after T20 (the counts in T20's lead review), or stopped and
   reported per Rules. apicheck 0 findings, selftest 10 of 10, refcheck selftest ok.
4. `luac -p` clean on every Lua file touched.
5. Paste into the Report: the failing first run; both suites in full after; every other suite's
   tail (`docs/TOOLS.md` §1 loop); apicheck, selftest, refcheck selftest; luac; `git status
   --short`; `git diff --stat`.

## Out of scope

- A prior from a run's other pulls (`MD.cdb.runs`) or from practice fights: the store is
  `MD.cdb.recordings` only.
- `SM.DangerLine`'s rule after the first hit (T20). The rules plans, Intuition, Foresight.
- Every TOC version. `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

(implementer, 2026-09-29)

**What was done, file by file**

- `Engine/SimModel.lua`: (a) new `SM.DangerHitFromOthers(recs, excludeID, name, level)` above the replay section: `error(...)` on a nil `excludeID`; nil unless `name` is a string and `recs` a table; skips `r.id == excludeID` and any entry that is not a table with a roster and `ev`/`n`; matches roster entries by name and, when both levels are numbers, level; the largest plain-number `ev.amt[j] > 0` over `SM.K.DMG` events on those indices; returns that and the number of recordings with a hit, else nil. (b) `SM.ScenarioFromRecording(rec, kit, others)`: `others` defaults to `MD.cdb and MD.cdb.recordings`; for each target, when `rec.id ~= nil` and `maxHP > 0`, `dangerPrior = math.min(1, hit * dangerHits / maxHP)` from the helper (two returns taken with an `if`). (c) `SM:Run`: `S.dangerMeasured[i] = (tg.danger ~= nil) or (tg.dangerPrior ~= nil)`, with a comment. Line 610 (the score) untouched.
- `Modules/SpellTuner_Replay/Scenario_Forever.lua`: `SM.ScenarioV3` sets `dangerPrior` the same way from its own `others` (nil defaults to `MD.cdb.recordings`, held in a local `priorStore`), by name and level, divided by that target's `maxHP[i]` from `ChooseMaxes`, only when `rec.id ~= nil` and `maxHP[i] > 0`. The wrapper is unchanged.
- `tools/solvercheck.lua`: new section 4c (after 4b, before section 5) with the three names verbatim. `tools/coachforever.lua`: one new assertion in the T17b block (after "the exclusion is required", before the store is restored), name verbatim.

**Test detail worth knowing**

- 1a/1b/1c use hand-made TBC recordings (roster Healroot + Tank of max 10000). Store: A (Tank 300 at 4 s, 5000 at 20 s), B (Tank 2000 at 5 s, 700 at 9 s), C (Bob 9000 at 6 s). 1c reads `SM.DangerLine(S, 2)` under a plan that casts nothing: 0.200 before 4 s (the prior), 0.030 from 4 s to 20 s, 0.500 after; then the same recording without the 5000 hit gives the same prior and identical readings (time and value) before 20 s.
- The coachforever assertion uses the T17b `tankRec` helper: a coached Tank (secret max, hits 300 and a 9000 burst), Tank level 64 with plain max 5000 and hits of 700 (H), Tank level 60 with a 2000 hit; prior 0.14 = 700/5000; a copy with no id gets nil.
- On the old engine "the prior's exclusion is required" passes (`SM.DangerHitFromOthers` does not exist, so the pcall is false, and no prior exists to appear). It is a specification of the guard; the other two solvercheck assertions and the coachforever one fail on the old code. Nothing needed changing to make any assertion pass.
- `tools/run.sh tools/reviewui.lua` prints `[sim] search N evaluations`, a time-sliced count (19, 21, 15, 16, 28 in different runs); it varies the same way on a HEAD copy of the tree (19 x6, 21 x2 over eight runs), so it is not a change. No assertion in any suite changed result: I ran the whole loop on a `git archive HEAD` copy and on this tree and diffed every suite's whole output (pointers and timings masked): the only differences are the new assertion lines and the two totals.

**Failing first run (new assertions, unchanged engine)**

```
75 ok, 2 failed
  FAIL the danger prior is the biggest hit that person took in other recordings - hit=nil recordings=nil
  FAIL before the first hit a plan reads the prior from other recordings - prior=nil want=0.2 before=0.300/0.300/8 between=0.030/31 after=0.500/78 identical-before-20s=true

17 ok, 1 failed
  FAIL a Forever target's danger prior comes from other recordings of the same name and level - prior=nil want=0.14 (maxHP 5000) noId=nil
```
(solvercheck and coachforever tails; "the prior's exclusion is required" passed, see above.)

**Both suites after (new assertions and tail)**

```
the danger prior is the biggest hit that person took in other recordings ok - hit=2000 recordings=1
the prior's exclusion is required              ok - pcall=false prior=nil
before the first hit a plan reads the prior from other recordings ok - prior=0.2 want=0.2 before=0.200/0.200/8 between=0.030/31 after=0.500/78 identical-before-20s=true
...
77 ok, 0 failed
```
```
a Forever target's danger prior comes from other recordings of the same name and level          ok - prior=0.14 want=0.14 (maxHP 5000) noId=nil
...
18 ok, 0 failed
```

**Every other suite (docs/TOOLS.md section 1 loop)**

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
solvercheck   77 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
probecheck    82 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   14 ok, 0 failed
kitcheck      7 ok, 0 failed
recordcheck   24 ok, 0 failed
scenariocheck 12 ok, 0 failed
gatecheck     9 ok, 0 failed
replayforever 11 ok, 0 failed
reviewforever 10 ok, 0 failed
coachforever  18 ok, 0 failed
practiceforever 9 ok, 0 failed
bindscheck    6 ok, 0 failed
parsecheck    12 ok, 0 failed
bookcheck     17 ok, 0 failed
tipcheck      17 ok, 0 failed
clockcheck    17 ok, 0 failed
spellsui      17 ok, 0 failed
measurecheck  26 ok, 0 failed
adaptercheck/forever 22 ok, 0 failed
adaptercheck/tbc 15 ok, 0 failed
corecheck/forever 10 ok, 0 failed
corecheck/tbc 8 ok, 0 failed
svcheck/forever 6 ok, 0 failed
svcheck/tbc   1 ok, 0 failed
consolecheck/forever 14 ok, 0 failed
consolecheck/tbc 1 ok, 0 failed
apicheck: 8 Forever TOCs, 44 files, 45 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok
```

luac -p: clean on Engine/SimModel.lua, Modules/SpellTuner_Replay/Scenario_Forever.lua, tools/solvercheck.lua, tools/coachforever.lua.

```
git status --short
 M CLAUDE.md
 M Engine/SimModel.lua
 M Modules/SpellTuner_Replay/Scenario_Forever.lua
 M docs/tasks/HANDOVER.md
 M tools/coachforever.lua
 M tools/solvercheck.lua
?? docs/tasks/T20b-danger-prior-from-others.md
git diff --stat (before this Report)
 CLAUDE.md                                      | 22 +++---
 Engine/SimModel.lua                            | 63 +++++++++++++++++-
 Modules/SpellTuner_Replay/Scenario_Forever.lua | 12 +++-
 docs/tasks/HANDOVER.md                         | 10 +--
 tools/coachforever.lua                         | 19 ++++++
 tools/solvercheck.lua                          | 92 ++++++++++++++++++++++++++
 6 files changed, 199 insertions(+), 19 deletions(-)
```
`CLAUDE.md` and `docs/tasks/HANDOVER.md` show as modified; I did not touch either (CLAUDE.md was clean in the status at the start of the task, so someone else edited it during it).

**Skipped:** nothing. **Questions:** none. **Noted, not changed:** the Forever wrapper `SM.ScenarioFromRecording(rec, kit)` still hands a v2 recording to the TBC builder without a store, so that builder reads `MD.cdb.recordings` by default, as the task intends.

## Lead review (2026-09-29)

Accepted, no change by the lead. The lead read the diff, reran the whole loop of `docs/TOOLS.md` §1
(solvercheck 77, coachforever 18; every other suite line identical to the T20 export run; apicheck 0
findings over 44 files, 45 distinct globals, `--selftest` 10 of 10, refcheck ok) and `luac -p` on the
four files.

- The exclusion is by id and required; a recording with no id gets no prior on both builders; the
  two returns of `SM.DangerHitFromOthers` are taken with an `if` on both; only plain numbers are
  compared (`type(a) == "number"` before `a > 0`), and the divisor is a `maxHP > 0`.
- "the prior's exclusion is required" passes on the old engine (the function did not exist, so the
  pcall was false and no prior could appear): accepted as a guard on the new function; the other two
  solvercheck assertions and the coachforever one fail on the old engine, as the Report shows.
- The coachforever assertion separates all three sources: the coached recording's own 9000 burst
  (excluded by id) would give 1.0, the other-level Tank's 2000 would give 0.4, the same-level Tank's
  700 over the chosen 5000 max gives the 0.14 asserted.
- The `CLAUDE.md` modification the implementer saw is the lead's (T21 drafting), not theirs.

