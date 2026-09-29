# T20 — the danger line a plan decides on is causal (R6, the author's ruling)

Status: **accepted** 2026-09-29 (lead review at the end). Review finding R6, ruled by the author ("Fix both lines").
Shared engine: lands on the TBC and the Forever line at once.

## Goal

When a plan decides at time t, the danger line it reads for a target is built only from what that
target has taken **so far in this fight**: the biggest hit already applied, times
`db.simDangerHits`, capped at 1; before its first hit, a prior the scenario carries (filled by
T20b from other recordings) or else the scenario's flat floor. The **score** keeps the whole-fight
line: `floorSeconds` in `SM:Run` and the card's measured line still use the biggest hit of the
whole fight, because scoring may look at everything and deciding may not. So a coached solver plan
(the replay window's "Solver: ..." strategies on both lines, `/st coach N <strategy>` on Forever)
can no longer be advised by a hit that has not landed. For the author, whose ruling this is, and
for the causality invariant every plan claims.

## Facts

- The ruling: the planner's hand-out of 2026-09-29, quoting the author's choice on
  `docs/review/2026-09-29-forever-review.md` R6 ("Fix both lines"): "At time t, a target's line is
  built from the biggest hit it has taken so far in this fight (times db.simDangerHits, capped as
  today), falling back to db.simFloor before its first hit -- or, where a scenario has them, from
  other recordings of the same target (the leave-one-out rule T17b uses for max health; never the
  fight being coached). The score after the fight (floorSeconds in SimModel's scoring, the card's
  measured line) keeps the whole-fight line ... Solver:AtRisk, rule 8, the reason records, and
  anything else Decide reads must use only the causal line."
- The leak, R6: `Engine/SimSolver.lua` `Solver:AtRisk` (331-358) reads `S.danger[i]` (334) on every
  `Decide`; rule 8's reason record reads it again (`below = S.danger[i]`, 416).
  `Engine/SimModel.lua` 256 sets `S.danger[i] = tg.danger or floor` once at the start of `SM:Run`.
  `tg.danger` is the whole fight's biggest hit: TBC `SM.ScenarioFromRecording` 1066-1105
  (`list[#list]` of the sorted whole-fight hits, 1099); Forever `SM.ScenarioV3`
  (`Modules/SpellTuner_Replay/Scenario_Forever.lua` 601-616). A skeptic reproduced it: 600 every
  2 s until 38 s, one 7000 hit at 40 s, max 10000 -- the solver's casts differ from about 4 s.
- Nothing else a plan decides on reads the danger line: `grep` of `S.danger` / `.danger` over
  `Engine/`, `UI/`, `Modules/` finds only SimSolver 334 and 416, SimModel 256 and 600 (the score)
  and `Engine/SimPlanner.lua` 1136 (the card, a score). The rules plans (`SP.NewPlan`) never read it
  (R6 skeptics 1 and 3), so **the rules coach (`SP.Search`, TBC's `/md coach`) does not change**.
- The engine already tracks what a target has taken so far, causally: the damage ring
  `S.dmg[ti]` gets `ring.biggest` updated on every applied DMG event (SimModel 394-407, "Everything
  here comes from events already applied, so the causality invariant holds"), reset per run at 263;
  `SM.SeenDamage(S, ti, t)` (1000) is the existing "What a plan may read" accessor over it.
- The score line: SimModel 600, `if frac < (S.danger[i] or floor) then floorSeconds = ...`.
- Synthetic scenarios (SimWindow presets, Practice sessions, the solvercheck/replaycheck hand-built
  scenarios) carry no `tg.danger` and get the flat `floor` for both the score and the decision
  (SimModel 249-256: "A synthetic scenario has no recorded damage and keeps the flat floor"). A
  constant sees no future. **Lead's call:** the causal line applies where the scenario carries a
  measured line (`tg.danger ~= nil`); a synthetic target keeps its flat floor for both, so Practice,
  SimWindow and every synthetic test decide exactly as today.
- Hand-built solver states in `tools/solvercheck.lua` (279-280, 474) set `danger = {}` and no ring,
  so `AtRisk` answers nil for them today; they must keep answering nil.
- The existing causality tests cannot see R6: solvercheck §4 (153-187) and replaycheck 9g build
  targets with no `danger` field (R6 skeptics). coachforever 6 (`tools/coachforever.lua` 175-254)
  runs the rules plan, not the solver.
- `db.simDangerHits` default 1 (`Core_TBC.lua` 39; `Modules/SpellTuner_Replay/Commands_Forever.lua`
  18); `db.simFloor` 0.30.

## Files

| file | change | role |
|---|---|---|
| `Engine/SimModel.lua` | (a) `NewSlot`: two more per-target tables, `dangerMeasured = {}` and `dangerPrior = {}`. (b) `SM:Run`'s target loop: keep `S.danger[i] = tg.danger or floor` (the score's line, unchanged); set `S.dangerMeasured[i] = (tg.danger ~= nil)` and `S.dangerPrior[i] = tg.dangerPrior` (a fraction or nil; nothing sets it until T20b); once per run `S.dangerHits = (MD.db and MD.db.simDangerHits) or 1` and `S.floor = floor`. (c) `SM.DangerLine(S, ti)` in the "What a plan may read" section beside `SM.SeenDamage`: when `S.dangerMeasured` is absent or false for `ti`, return `S.danger and S.danger[ti]` (today's value: the flat floor, or nil on a hand-built state); else, when the ring has a hit (`(ring.biggest or 0) > 0`) and `S.maxHP[ti] > 0`, `math.min(1, ring.biggest * (S.dangerHits or 1) / S.maxHP[ti])`; else `S.dangerPrior[ti]` if set, else `S.floor` (else 0.30). A comment saying why (R6: the score may look at the whole fight, a decision may not). (d) The two builders' comments (1070-1074 here) say `tg.danger` is the score's line. No change to line 600 | the causal line and the score's line, side by side |
| `Engine/SimSolver.lua` | `Solver:AtRisk`: the line is `(SM or MD.SimModel).DangerLine(S, i) or 0` times max; its comment (329-330) says "so far". Rule 8's reason record: `below = <the same DangerLine value>` (so `SV.ReasonText` prints the line the decision used). Nothing else | the solver reads only the causal line |
| `Engine/SimPlanner.lua` | the CAUSALITY header (4-10): one sentence adding the danger line as of t (`SM.DangerLine`) to what Decide may read, and that `S.danger` / `tg.danger` is the score's. Comment only | the invariant, written down |
| `Modules/SpellTuner_Replay/Scenario_Forever.lua` | the comment at 572 / 601: `danger` is the score's line (whole fight); a plan reads `SM.DangerLine`. Comment only | the Forever builder |
| `tools/solvercheck.lua` | new assertions (Acceptance 1) | TBC suite |
| `tools/coachforever.lua` | one new assertion (Acceptance 2) | Forever suite |

## Rules

- `CLAUDE.md`: no libraries; no new global (`SM.DangerLine` is a field of `MD.SimModel`); rendered
  strings ASCII only, no bare `|` (rule 8's sentence is unchanged in form); the **multi-return
  trap** -- `Solver:AtRisk` returns two values, `SM.SeenDamage` two: never inside `a and f() or b`;
  no client call and no `MD.API` in any of these files (they are pure engine code).
- **Decide may read only the causal line.** Nothing a plan's `Decide` reaches may read `S.danger`
  after this task; `S.danger` is read only by the score (SimModel 600) and nothing else.
- **The score does not change.** `floorSeconds`, `SP.Card`'s "danger line: N% of health on X - the
  biggest hit they took" and every builder's `tg.danger` keep the whole-fight line.
- A synthetic target (no `tg.danger`) keeps its flat floor for decisions: `SM.DangerLine` returns
  exactly what `S.danger[i]` held for it before. Practice, SimWindow, every synthetic scenario
  decide as today.
- **Tests first.** Write the new assertions, run them on the unchanged addon and paste the failing
  run (the causality assertions must FAIL on the old code; if one passes on the old code, make its
  burst larger -- still above every earlier hit -- until it fails, and say what you used).
- **TBC counts** may change only where an existing assertion asserted a decision made with the
  whole-fight line. If any existing assertion (any suite, either flavour) changes result: **stop and
  report** the assertion's name, file and line, its old and new detail text, and why you think it
  asserted the leak. Do not edit it.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this task's Report.

## Acceptance

1. `bash tools/run.sh tools/solvercheck.lua` ends `74 ok, 0 failed` (70 + 4). New names, verbatim, in a
   new section after §4 (the existing §4 assertions untouched):
   a. "the danger line a plan reads is the biggest hit so far" -- a measured scenario (targets carry
      `danger` computed exactly as the TBC builder would from the scenario's own hits: `math.min(1,
      biggest * simDangerHits / maxHP)`), max 10000, 600 every 2 s from 2 s to 38 s and one 7000 hit
      at 40 s; a plan whose `Decide` records `SM.DangerLine(S, 1)` at each call and casts nothing:
      before the first hit the value is the scenario's floor (0.30); after the 2 s hit and before the
      40 s one it is 0.06;
      after 40 s it is 0.70.
   b. "before the first hit the line is the scenario's prior when it has one" -- the same scenario
      with `targets[1].dangerPrior = 0.5`: 0.5 before 2 s, 0.06 from 2 s.
   c. "a hit bigger than any before it changes nothing the solver does before it" -- the solver
      (`SV.NewPlan(binds, { minValue = 0.5, horizon = 12 }, kit)`, as §4) on the measured scenario
      with and without the 7000 hit at 40 s (each scenario's `danger` from its own hits, as the
      builder would): casts identical until 39.9 s. **Must FAIL on the old code.**
   d. "the score still counts seconds under the whole-fight line" -- a scripted run with no casts:
      max 10000, `hp0 = 7500`, 100 every 2 s from 2 s to 38 s, one 8000 hit at 40 s, `danger` from
      the scenario's own hits (0.80): `result.floorSeconds >= 30` (the tank sits under 80% from the
      grace period to the hit, while the causal line before 40 s is 0.01).
2. `bash tools/run.sh tools/coachforever.lua` ends `17 ok, 0 failed`. New name, verbatim: "a burst
   above every earlier hit changes nothing the solver does before it" -- assertion 6's quiet and
   loud v3 recordings (same store arrangement: one other recording of Tank, neither the quiet nor
   the loud one; restored afterwards), through `SM.ScenarioFromRecording`, run with the
   `solver-blind` strategy (`SP.MakeStrategy(SP.Strategy("solver-blind"), binds, kit, {...})`):
   casts identical until 19.9 s. **Must FAIL on the old code** (if 1200 is not enough, raise the
   loud recording's burst for this assertion only and say so; assertion 6 keeps its recordings).
3. Every other suite at its count (the handover's baselines: TBC simcheck PASS, reccheck 54,
   replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27,
   simwindow 8, timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7; Forever probecheck
   82, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9,
   replayforever 11, reviewforever 10, practiceforever 9, bindscheck 6, parsecheck 12, bookcheck 17,
   tipcheck 17, clockcheck 17, spellsui 17, measurecheck 26; adaptercheck 22/15, corecheck 10/8,
   svcheck 6/1, consolecheck 14/1) -- or stopped and reported per Rules. `python3 tools/apicheck.py`
   0 findings, `--selftest` 10 of 10, `python3 tools/refcheck.py --selftest` ok.
4. `luac -p` clean on every Lua file touched (`tools/.lua/lua-5.1.5/src/luac` if `luac` is not on
   PATH).
5. Paste into the Report: the failing first run (solvercheck and coachforever tails with the FAIL
   lines); both suites in full after; every other suite's tail (the loop in `docs/TOOLS.md` §1);
   apicheck, its selftest, refcheck selftest; luac; `git status --short`; and `git diff --stat`.

## Out of scope

- Filling `dangerPrior` from other recordings (T20b, next). The builders' `danger` values.
- The rules plans, `SP.Search`, Intuition, Foresight, Practice, SimWindow.
- The replay window's painting, the card's wording, the gates.
- Every TOC version (the lead bumps). `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

(implementer, 2026-09-29)

**What was done, file by file**

- `Engine/SimModel.lua`: `NewSlot` gets `dangerMeasured = {}` and `dangerPrior = {}`; `SM:Run` keeps `S.danger[i] = tg.danger or floor` (the score's line, line 600 untouched), sets `S.dangerMeasured[i] = (tg.danger ~= nil)` and `S.dangerPrior[i] = tg.dangerPrior`, and once per run `S.dangerHits` and `S.floor`. New `SM.DangerLine(S, ti)` beside `SM.SeenDamage`, exactly as the task specifies (synthetic or hand-built target: `S.danger[ti]` as before, nil on a hand-built state; measured: `min(1, ring.biggest * dangerHits / maxHP)` once a hit is applied, else the prior, else the floor, else 0.30), one return value, with the R6 comment. The TBC builder's comment says `tg.danger` is the score's line.
- `Engine/SimSolver.lua`: `Solver:AtRisk` reads `(SM or MD.SimModel).DangerLine(S, i) or 0`; its comment says "so far"; rule 8's reason record `below` is the same `DangerLine` value. Nothing else.
- `Engine/SimPlanner.lua`: CAUSALITY header, one sentence (comment only).
- `Modules/SpellTuner_Replay/Scenario_Forever.lua`: comment above `dangerHits` (comment only).
- `tools/solvercheck.lua`: new section 4b after section 4 with the four names verbatim. `tools/coachforever.lua`: one new assertion in assertion 6's block, using the same store arrangement (one other Tank recording, restored afterwards) and `SP.MakeStrategy(SP.Strategy("solver-blind"), binds, kit, { scenario = sc, seed = 1 })`.

**Test detail worth knowing**

- Acceptance 1a/1b: the scenario as written (19 hits of 600 on a 10000 tank, nothing cast) kills the tank before the 40 s hit, and a dead target gets no hit applied, so "after 40 s it is 0.70" could not be observed. I added a foreign heal of 500 (`K.FHEAL`) at 3, 5, ... 39 s to the 1a/1b scenarios only (events sorted in time order, since the engine reads them by cursor). Danger, max, hit sizes and times are as specified. 1c uses the plain scenario (the solver heals there); 1d has no heals, as specified.
- Acceptance 1c "must FAIL on the old code": it failed with the 7000 hit as written ("31 and 28 casts, diverged at 4.0s"); no enlargement needed. The coachforever assertion also failed with assertion 6's own 1200 burst (diverged at 4.0 s); nothing raised.
- 1a and 1b fail on the old code because `SM.DangerLine` does not exist (the plan records nil); they are a specification of the new accessor, and 1c and the coachforever assertion are the ones that fail for the leak itself. 1d passes on the old code, as it should (the score is unchanged).
- The failing run below was taken with the engine files temporarily restored from `HEAD` (SimModel and SimSolver only) and then put back.

**Failing first run (old engine, new assertions)**

```
the danger line a plan reads is the biggest hit so far FAIL - before: no number in 1 reads; between: no number in 1 reads; after: no number in 1 reads
before the first hit the line is the scenario's prior when it has one FAIL - before: no number in 1 reads; from 2 s: no number in 1 reads
a hit bigger than any before it changes nothing the solver does before it FAIL - 31 and 28 casts, diverged at 4.0s
the score still counts seconds under the whole-fight line ok - danger 0.80, floorSeconds 34.0


71 ok, 3 failed
  FAIL the danger line a plan reads is the biggest hit so far - before: no number in 1 reads; between: no number in 1 reads; after: no number in 1 reads
  FAIL before the first hit the line is the scenario's prior when it has one - before: no number in 1 reads; from 2 s: no number in 1 reads
  FAIL a hit bigger than any before it changes nothing the solver does before it - 31 and 28 casts, diverged at 4.0s
```
```
a burst above every earlier hit changes nothing the solver does before it                       FAIL - 23 and 9 casts, diverged at 4.0s
  FAIL a burst above every earlier hit changes nothing the solver does before it - 23 and 9 casts, diverged at 4.0s


16 ok, 1 failed
  FAIL a burst above every earlier hit changes nothing the solver does before it - 23 and 9 casts, diverged at 4.0s
```

**Both suites after (the new assertions and tail)**

```
a burst at 40s changes nothing the solver does before it ok - diverged at 44.5s
the danger line a plan reads is the biggest hit so far ok - before: 4 reads, 0.300..0.300; between: 75 reads, 0.060..0.060; after: 38 reads, 0.700..0.700
before the first hit the line is the scenario's prior when it has one ok - before: 4 reads, 0.500..0.500; from 2 s: 75 reads, 0.060..0.060
a hit bigger than any before it changes nothing the solver does before it ok - 31 and 31 casts, diverged at 40.0s
the score still counts seconds under the whole-fight line ok - danger 0.80, floorSeconds 34.0
...
74 ok, 0 failed
```
```
a burst at 20 s changes nothing the plan does before it                                         ok - identical until the burst
a burst above every earlier hit changes nothing the solver does before it                       ok - 23 and 10 casts, diverged at 21.5s
a party member's max comes from other recordings of the same name and level, never the one coached ok - want=1800 burst=1800/others calm=1800/others
...

17 ok, 0 failed
```

**Every other suite, full loop of docs/TOOLS.md section 1, tails**

Every count equals the handover baseline except the two suites that gained an assertion; no existing assertion changed result (compared every suite's whole output before and after: only timing figures in three `[sim]`/`search finished` lines differ).

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
solvercheck   74 ok, 0 failed
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
coachforever  17 ok, 0 failed
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
```

```
apicheck: 8 Forever TOCs, 44 files, 45 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok
```

luac -p (`luac` on PATH or the built one): clean on Engine/SimModel.lua, Engine/SimSolver.lua, Engine/SimPlanner.lua, Modules/SpellTuner_Replay/Scenario_Forever.lua, tools/solvercheck.lua, tools/coachforever.lua.

```
git status --short
 M Engine/SimModel.lua
 M Engine/SimPlanner.lua
 M Engine/SimSolver.lua
 M Modules/SpellTuner_Replay/Scenario_Forever.lua
 M docs/tasks/HANDOVER.md
 M tools/coachforever.lua
 M tools/solvercheck.lua
?? docs/tasks/T20-causal-danger-line.md
?? docs/tasks/T20b-danger-prior-from-others.md
```
`git diff --stat` (before this Report was written): SimModel 36, SimPlanner 5, SimSolver 10, Scenario_Forever 2, coachforever 27, solvercheck 123, plus docs/tasks/HANDOVER.md 5, 201 insertions and 7 deletions over 7 files. `docs/tasks/HANDOVER.md` and T20b were already modified/untracked in the tree when I checked; I did not edit them.

**Skipped:** nothing. **Surprising:** the dead-tank problem above; one more thing for the lead: a plan that does not cast still gets `Decide` polled every 0.5 s, which is what the 1a/1b readings rely on. **Questions:** none.

## Lead review (2026-09-29)

Accepted, with one change by the lead (below). The lead read the diff, reran the whole loop of
`docs/TOOLS.md` §1 (solvercheck 74, coachforever 17, every other suite at the handover's baseline;
apicheck 0 findings over 44 files, 45 distinct globals, `--selftest` 10 of 10, refcheck ok) and
`luac -p` on the six files.

- **The deviation (foreign heals of 500 at 3, 5, ... 39 s in 1a/1b, events sorted) is accepted.**
  The scenario as the task wrote it kills the tank before 40 s, so "after 40 s it is 0.70" could not
  be read; that was the task's mistake. `K.FHEAL` never touches the damage ring (only an applied DMG
  updates `ring.biggest`), which the "between: 0.060..0.060" reading confirms. 1c and 1d keep the
  scenario as written.
- **Change by the lead, one line in each of the two new divergence assertions** (1c in
  `tools/solvercheck.lua`, the solver assertion in `tools/coachforever.lua`): the divergence time is
  now the EARLIER of the two casts at the first differing index, not the quiet run's. Taking the
  quiet run's time alone could report a late time when the loud run inserted an early cast, and
  pass a leak. Both still pass with the stricter time (40.0 s and 21.5 s, unchanged), and 1c fails
  on the old engine at 4.0 s either way. The two older assertions with the same pattern (solvercheck
  §4 "a burst at 40s ...", coachforever 6) were left as they are (out of this task's scope; noted in
  the handover).
- No `S.danger` read is left on a Decide path: `grep` finds `S.danger` only at SimModel 264 (set),
  610 (the score) and inside `SM.DangerLine` (the synthetic branch); `tg.danger` at SimPlanner 1139
  (the card, a score). `Solver:AtRisk` and rule 8's `below` read `SM.DangerLine`, one return value,
  never in an `and/or`.

