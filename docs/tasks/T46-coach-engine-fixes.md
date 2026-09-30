# T46 (P2) -- Simulation engine: Swiftmend's HoT end, the search key, the preempted decision, Swiftmend's price, the `others` store

Status: **built** 2026-09-30 on branch `plan/P2` (base d8a926f); **reworked** the same day after the
review's rejection (the B7 regression, below), awaiting review.

## The task (docs/PLAN-refactor-ux.md section 5, P2)

Review items (docs/review/2026-09-30-project-review.md): **B5, B6, B7, B8**, and the `others` drop
of **A18**.

- (a) B5: `LandCast`'s instant branch traces `HOT_END` for the HoT it consumes.
- (b) B6: one `SP.PARAMS` list (name, domain, default) deriving `NewPlan`'s defaults, `Params()`,
  `Key()` and the domains, in both `SP.Search` and `SP.SearchRun`, so `noDirect` is in the key by
  construction; the duplicate seed 3 replaced by a distinct point or dropped.
- (c) B7: when a fixed cast preempts, schedule a decision at the new `busyUntil`; the stale one falls
  to a decision-generation check; zero allocation and the heap's tie-break order kept.
- (d) B8: one `SM.SWIFTMEND_ORDER = { "Regrowth", "Rejuvenation" }` read by `LandCast` and the
  solver; the solver keeps its valuation in a local instead of writing `swiftmendAmount` onto the
  shared kit entry.
- (e) The `Scenario_Forever` and `Gates_Forever` wrappers forward `...`.

Owned files (section 4, wave 1): `Engine/SimModel.lua`, `Engine/SimPlanner.lua`,
`Engine/SimSolver.lua`, `Modules/SpellTuner_Replay/Scenario_Forever.lua`,
`Modules/SpellTuner_Replay/Gates_Forever.lua`, `tools/replaycheck.lua`, `tools/solvercheck.lua`,
`tools/coachforever.lua`, `tools/practice.lua`. Nothing else was edited.

## What was built

| file | change |
|---|---|
| `Engine/SimModel.lua` | **B8/B5:** `SM.SWIFTMEND_ORDER = { "Regrowth", "Rejuvenation" }`, `SM.SWIFTMEND_FIELD` (the kit entry's field for eating each: `swiftmendRegrowth`, `swiftmendRejuv`) and `SM.SwiftmendEats(e, row)` -> family, amount, HoT state (or nil), allocating nothing. `LandCast`'s instant branch goes through it and, after landing the heal and clearing the slot, **traces `TK.HOT_END` (tgt, hot index, 0)** at the Swiftmend. **B7:** a `decideGen` counter; every `E_DECIDE` carries the generation it was pushed under in its `a` slot, and the handler only runs `a == decideGen`. A fixed cast bumps the generation and pushes one decision at its `busyUntil` (t + GCD); the pending one (at a preempted cast's landing time, or anywhere) is dropped when it pops. Still one live chain; `HeapPush` writes into the same reused slots; `HeapLess` is untouched. **B7 follow-up (the review's rejection):** the live cast's landing is kept in four scalars (`landAt`, `landSpell`, `landTi`, `landCost`), set where `inFlight` is set, and `E_LAND` succeeds only when `inFlight` and the event's time is `landAt` (within 1e-9), with the committed spell, target and cost read from those scalars. A preempted cast's `E_LAND` still in the heap now falls through even after the plan has committed another cast; nothing is allocated. |
| `Engine/SimPlanner.lua` | **B6:** `SP.PARAMS` -- `{ name, domain, default [, seed] }` for `swiftmendBelow`, `directBelow`, `rollStacks`, `hotBelow`, `filler` and `noDirect` (`seed = true`: fixed by the seed, not stepped by the descent). `SP.DOMAINS` and `SP.PARAM_ORDER` are derived from it (same contents as before for the five searched ones). `SP.ParamKey(params)` is the key -- every entry of `SP.PARAMS` as the plan will hold it (nil = default), `noDirect` included. `SP.NewPlan` and `Plan:Params()` loop over `SP.PARAMS`. `SP.Search`'s `Key` is `SP.ParamKey`; `SP.SearchRun`'s is `SP.ParamKey(p) .. "|below|upTo"`. `SP.SearchSeeds()` returns the search's seeds: the default point, the HoTs-only point, **the low-threshold corner `{0.30, 0.35, 0, 0.60, false}` (SearchRun's third seed) in place of the byte copy of seed 1**, and the random point, re-drawn up to 8 times while it lands on a fixed seed (left out if it still does). |
| `Engine/SimSolver.lua` | **B8:** `Solver:Best` asks `SM.SwiftmendEats(e, S.hots[i])` -- the engine's own order -- and keeps the amount in a local `eats`; `SV.Deposits(e, st, out, eats)` takes it as a fourth argument instead of reading `e.swiftmendAmount`. Nothing is written onto the kit entry. |
| `Modules/SpellTuner_Replay/Scenario_Forever.lua` | **A18:** `SM.ScenarioFromRecording(rec, kit, ...)` forwards `...` to `SM.ScenarioV3` and to the v2 builder. |
| `Modules/SpellTuner_Replay/Gates_Forever.lua` | **A18:** `SM.Validate(self, rec, kit, ...)` forwards `...` on both roads. |
| `tools/replaycheck.lua` | +2 (80 -> 82), section 10: a scripted Regrowth at 1 s and Swiftmend at 4 s traces `HOT_END` for Regrowth at 4 s and `ReplayTrace`'s `Hot(1, Regrowth)` is nil at 6 s; nothing (Regrowth or Rejuvenation) is left in the row for the Swiftmend-ready dot. |
| `tools/solvercheck.lua` | +7 (77 -> 84), section 9: a `noDirect` plan is built during `SP.Search` (60 evaluations on the fake pull); `SP.SearchSeeds()` are distinct `SP.ParamKey`s; with both HoTs rolling the solver's Swiftmend is priced on Regrowth (entry worth 5000 on Rejuvenation, 1 on Regrowth: saved < 100); the kit entry has no `swiftmendAmount` after `Best`; B7: a plan asked at 0 for a 2.9 s cast, a fixed cast at 0.5 s, the next question at 2.0; **B7 follow-up (+2):** the same scenario with the plan answering Regrowth (2.0 s) at 2.0 -- the Regrowth's `CAST` is traced at 4.0, its own landing, and the preempted Healing Touch is never cast. |
| `tools/coachforever.lua` | +1 (18 -> 19): `SM.ScenarioFromRecording(coached, kit, { coached, sameLevel, otherLevel }).targets[2].dangerPrior` equals the value through `MD.cdb.recordings`, with `cdb` holding only the coached fight. |
| `tools/practice.lua` | +1 (80 -> 81): the session's trace carries `HOT_END` for the Rejuvenation the scripted Swiftmend ate (on MELEE), at the Swiftmend's time, and `Hot()` is nil a second later. |

## Tests first (the parent, d8a926f, with only the tests changed)

```
replaycheck
Swiftmend ends the Regrowth it eats (HOT_END at 4 s) FAIL - HOT_END at nil, Hot() at 6 s live
...and nothing is left for Swiftmend to eat after it FAIL - Regrowth true, Rejuvenation false
80 ok, 2 failed

solvercheck
a HoTs-only (noDirect) plan is built during the search FAIL - 28 plan(s) built, 0 HoTs-only
the search's seeds are distinct points         FAIL - no SP.SearchSeeds
with both HoTs rolling the solver's Swiftmend eats Regrowth, as the engine does FAIL - id=18562 saved=55000
the solver writes nothing onto the shared kit entry FAIL - swiftmendAmount=5000
after a fixed cast preempts a 2.9 s cast at 0.5 s, the plan is asked at 2.0 FAIL - asked at 0.00, 2.90, 5.80
77 ok, 5 failed

coachforever
the store passed as ScenarioFromRecording's third argument reaches the v3 builder FAIL - passed=nil via cdb=0.14
18 ok, 1 failed

practice
the practice trace ends the HoT Swiftmend ate, at the Swiftmend FAIL - Swiftmend at 12.05, HOT_END at nil
80 ok, 1 failed
```

After the change all four pass (82, 84, 19, 81).

**The B7 follow-up, failing first.** The new solvercheck on the rejected commit (d0877dc) -- the
review's repro, a Healing Touch charged and landed at 2.9 and the plan's Regrowth never landing:

```
a Regrowth committed at 2.0 after the preemption lands at 4.0, its own time FAIL - casts 0.50:8921, 2.90:26978
the preempted Healing Touch never succeeds (its stale landing is dropped) FAIL - casts 0.50:8921, 2.90:26978
82 ok, 2 failed
```

On the parent (d8a926f) the landing assertion fails too (`casts 0.50:8921, 4.90:9858`: the plan is
asked only at the cancelled cast's landing time, 2.9, so the Regrowth lands at 4.9); the parent's
whole solvercheck is 78 ok, 6 failed. With the fix, 84 ok: `casts 0.50:8921, 4.00:9858`.

## Suites (exit codes checked; the loop of docs/TOOLS.md section 1)

Every suite exited 0 before and after. Counts before -> after:

| suite | before | after |
|---|---|---|
| replaycheck | 80 | **82** |
| solvercheck | 77 | **84** |
| coachforever | 18 | **19** |
| practice | 80 | **81** |
| simcheck | PASS, 0 FAIL lines | PASS, 0 FAIL lines |
| reccheck 54, replayui 98, runcheck 78, reviewui 44, navui 35, dashui 63, regencheck 27, simwindow 8, restcheck 51, timeline 27, spelltip 48, practiceui 50, migrate 7, probecheck 87, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 15, reviewforever 11, practiceforever 25, bindscheck 6, parsecheck 12, bookcheck 21, tipcheck 37, clockcheck 20, spellsui 47, measurecheck 30, releasecheck 13, importcheck 19, themecheck 23, tabscheck 24, wincheck 53 | same | same |
| adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1, consolecheck 17 / 1 (forever / tbc) | same | same |

`python3 tools/apicheck.py`: 0 findings (48 files). `--selftest`: 10 of 10. `refcheck.py --selftest`:
ok. `luac -p` on every changed file: ok.

**Invariant.** The causality tests stay green: `coachforever` ("a burst above every earlier hit
changes nothing the solver does before it", the v3 causality assertion) and `solvercheck` (sections
4 and 4b, "a burst at 40s changes nothing the solver does before it"). The score (`SP.Score`,
`SP.ChainScore`, `SP.Better`) is untouched.

**Proves no other change:** `simcheck` (0 FAIL lines, the BF-1 fixture PASS), `restcheck` 51,
`gatecheck` 9, `scenariocheck` 12, `replayforever` 15 all unchanged; the author's practice fight
(`tools/data/practice/1790701698.lua`) through `tools/import.lua --fixture ... report p1` is
**byte-identical** before and after (the replay row: spent 480, regen 137, used 354, end 21, owed
223, lowest 43%, 9 casts; gates PASS; every strategy row the same).

## The coach card, before and after (the author's practice fight)

`bash tools/run.sh tools/import.lua --fixture tools/data/practice/1790701698.lua coach p1`, on the
parent and on this branch. The whole card is identical but its last line:

```
before:   search: 26 plans evaluated
after:    search: 56 plans evaluated
```

The search now also descends from the HoTs-only seed and from the new third seed (and the random
one), and still returns the same winner here (`best (search) 202 used (285 spent) lowest 27%`), so the
rules, the rows and the reasons are unchanged. The same holds for the two other fixtures tried: the
v3 pull in `tools/data/import-forever-sv.lua` (`coach 1 force`: 25 -> 41 plans, same card) and the
TBC scripted pull of `tools/fakepull.lua` through `SP.CoachAsync` (28 -> 44 plans, same card:
`best (search) 1.6k used (2.4k spent) lowest 25%`, rules Swiftmend < 30%, Regrowth R9 < 55%,
Lifebloom x1, HoT < 60%). A card changes where the HoTs-only subspace, a preempted long cast or a
Swiftmend on a target with both HoTs rolling decides the winner; none of these three fixtures has one
that does.

## Integrator lines

**docs/DECISIONS.md** -- a new section after "One kit record and one report tool (2026-09-30)":

```
## Coach fixes (2026-09-30)

The whole-project review (`docs/review/2026-09-30-project-review.md` B5-B8, A18) found four engine
bugs that change what the coach suggests on both lines; T46 (`docs/tasks/T46-coach-engine-fixes.md`)
fixes them. The author accepted that coach cards change (plan section 8, question 2).

1. **A Swiftmend ends the HoT it eats, in the trace** (B5). The replay, the Swiftmend-ready dot and
   the practice window stop drawing an eaten Regrowth or Rejuvenation to its nominal expiry.
2. **The search's key is every plan parameter** (B6). One `SP.PARAMS` list derives the defaults,
   `Plan:Params()`, the key and the domains; `noDirect` is in the key, so the HoTs-only seed is
   evaluated (it collided with the default seed and was never run) in `SP.Search` and
   `SP.SearchRun`. `noDirect` is fixed per seed, not stepped by the descent. The third seed, a copy
   of the first, is now the low-threshold corner (Swiftmend 30%, direct 35%, no roll, HoT 60%) that
   the run search already used; the random seed is re-drawn when it lands on a fixed one.
3. **A preempted plan is asked again when it is free** (B7). A fixed cast (damage, control, a
   shift) that cancels a plan's long cast frees the healer at its own global cooldown; the plan is
   asked then, instead of at the cancelled cast's landing time, so the suggested column no longer
   idles, and is no longer charged for idling, after a Moonfire. The cancelled cast's landing
   event, still queued, lands nothing: only the live cast lands, at its own time.
4. **Swiftmend is priced on the HoT it will eat** (B8). `SM.SWIFTMEND_ORDER` (Regrowth, then
   Rejuvenation: TBC's rule) is read by the engine and the solver; the solver priced Rejuvenation
   first and wrote `swiftmendAmount` onto the shared kit entry (copied into practice recordings'
   kits by `SM.KitSnapshot`). It writes nothing now.
5. **The `others` store reaches the v3 builder** (A18, the dropped argument): the Replay module's
   wrappers of `SM.ScenarioFromRecording` and `SM.Validate` forward every argument.

The lexicographic score and the causality invariant are unchanged. On the three fixtures tried the
winner is the same and only the evaluation count grows (the author's practice fight: 26 -> 56).
```

**docs/TOOLS.md** section 1 table -- append to the rows:

- `replaycheck.lua`: ` Since **T46** (82): a Swiftmend ends the HoT it eats in the trace (B5)`
- `solvercheck.lua`: ` Since **T46** (84): the HoTs-only seed evaluated, the seeds distinct, the solver's Swiftmend priced on Regrowth first and writing nothing on the kit, a preempted plan asked again at the fixed cast's global cooldown, its next cast landing at its own time and the cancelled one never (B6, B7, B8)`
- `coachforever.lua`: ` Since **T46** (19): the store passed as the third argument reaches the v3 builder (A18)`
- `practice.lua`: ` Since **T46** (81): the practice trace ends the HoT Swiftmend ate`

**CLAUDE.md** -- append to the rows:

- `Engine/SimModel.lua`: ` **T46 (P2, 2026-09-30):** `SM.SWIFTMEND_ORDER` / `SM.SwiftmendEats` (Regrowth, then Rejuvenation) for the engine and the solver, a Swiftmend traces `HOT_END` for the HoT it eats, a fixed cast starts a new decision generation at its global cooldown (the stale decision dropped), and a plan cast lands only at its own landing time (`landAt`; a preempted cast's queued landing lands nothing) (B5, B7, B8)`
- `Engine/SimPlanner.lua`: ` **T46 (P2):** `SP.PARAMS` (name, domain, default) derives `NewPlan`, `Plan:Params()`, `SP.ParamKey`, `SP.DOMAINS` and `SP.PARAM_ORDER`; `noDirect` is in both searches' keys; `SP.SearchSeeds()` four distinct starts (B6)`
- `Engine/SimSolver.lua`: ` **T46 (P2):** Swiftmend priced on the HoT the engine eats, the amount passed to `SV.Deposits` rather than written onto the kit entry (B8)`
- `Modules/<Name>/` row, after the Replay review notes: ` **T46:** the Replay module's `ScenarioFromRecording` / `Validate` wrappers forward every argument (A18)`

**TOCs:** none. **docs/TESTING.md:** none (no in-game check is needed; the change is engine-only
and the coach card is checked offline). **tools/data/expected-counts.json:** it does not exist at
this base; when P13 creates it: replaycheck 82, solvercheck 84, coachforever 19, practice 81.

## Deviations

- **`reproduce` on the practice fixture was not run as named.** `tools/reproduce.lua` reads a
  SavedVariables file (`SpellTunerDB`), not a `{ rec, kit }` fixture, and fails on
  `tools/data/practice/1790701698.lua` at this base (line 22, `realDB` nil); the Malchezaar control
  (`.logs/wcl-holdout.lua`) is not in this checkout. In its place: `import.lua --fixture ... report
  p1` -- the fight's own casts through the engine beside every strategy -- is byte-identical before
  and after, and `restcheck` (which asserts the same fight's replay and gates) is unchanged at 51.
- **`noDirect` is a seed parameter, not a searched coordinate** (`seed = true` in `SP.PARAMS`): it
  is in the key, the defaults and `Params()`, and the descent keeps each seed's value. Stepping it
  as a sixth coordinate would also work but spends more of the 300 evaluations; the HoTs-only
  subspace is reached from its own seed.
- **The duplicate seed was replaced, not dropped**, with SearchRun's third seed; the random seed is
  re-drawn when it collides with a fixed one (so "the seeds are distinct keys" holds every run).
- **B7 bumps the generation on every fixed cast while a plan decides**, not only when one preempts a
  cast in flight. Without a cast in flight the pending decision is always at or before the new
  `busyUntil` and would have hit the busy guard and been re-pushed there, so the timing is the same;
  one path is simpler to hold.
- `Scenario_Forever.lua`'s own Swiftmend attribution (which recorded heal a recorded Swiftmend ate,
  lines 218-221) keeps its local Regrowth-then-Rejuvenation test rather than reading
  `SM.SWIFTMEND_ORDER`: it attributes a recording, it does not land a cast, and its order already
  agrees.
- The fixture cards do not change their winner (see above); the before/after shown is the one line
  that differs. After the B7 follow-up the three fixtures' cards and `report p1` are identical to the
  rejected commit's (none of them has a plan cast committed between a preemption and the cancelled
  cast's landing time); only the stub's frame count in the `(the search ran across N stub frames)`
  footnote varies, because the search slices on elapsed time.
