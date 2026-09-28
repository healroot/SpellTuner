# T17 — the coach and the solver on a Forever recording

Status: **accepted** 2026-09-28 (lead review at the end), after T16b. M3 (`docs/ROADMAP-FOREVER.md` M3, "T17 coach and the solver
re-measured on Forever recordings"), **as far as a synthetic Forever recording allows**: no real
Forever pull exists yet, so the re-measurement on real recordings is M5's; this task proves the path
end to end on the fixture and fixes what breaks on it.

## Goal

On a v3 recording the coach finds a plan, the card renders, the classifier labels the recorded
casts, the solver runs as a strategy, the causality invariant still holds, and the per-zone marks
are kept -- all on the Forever kit (T15) and gates (T14), with no plan binding a family the player
did not have. A solver-versus-rules line on the fixture is printed for the record, as the first
data point M5 will replace with real ones. For the author's first coached Forever pull.

## Facts

- `Engine/SimPlanner.lua`: `SP.Coach(rec, opts)` (1266), `SP.CoachAsync` (1656, frame-sliced on
  `debugprofilestop`), `SP.Classify` (826), `SP.Card` (987), `SP.Mark` / `SP.Progress` (1207-1232,
  `MD.cdb.coachMarks`), `SP.MaxRankBinds(rec.initial.known)` (90), `SP.STRATEGY_SET` / `SP.Strategy`
  (613), `SP.BINDABLE = { "Lifebloom", "Rejuvenation", "Regrowth", "HealingTouch", "Swiftmend" }`
  (49), `SP.HOT_RULE = { "Lifebloom", "Rejuvenation" }` (52). Forever has no Lifebloom (plan §1.1):
  every rule that names it must simply find nothing bound, never raise.
- The causality invariant is pasted at the top of `Engine/SimPlanner.lua` and tested by
  `tools/replaycheck.lua` 623 and `tools/solvercheck.lua` 184 ("a burst at 40s changes nothing ...
  before it") -- TBC fixtures.
- v3 recordings carry `initial.known` by engine family keys (T13) and no `incoming` / `threat`
  (secret by policy, plan §5); the foresight experiments stay off (plan §5).
- The fixture: `tools/foreverfixture.lua` (T13d), with its opts for a death and the meter.
- The solver's margin over the rules was measured on TBC recordings (44% less mana for the same
  deaths and floor seconds, `CLAUDE.md` SimSolver row); on Forever it is unmeasured.
- Anything that fails on the fixture and needs a change in a **shared** engine file is a minimal,
  guarded change that leaves every TBC suite at its count -- or a question, if it is not minimal.

## Files

| file | change | role |
|---|---|---|
| `tools/coachforever.lua` (new, forever) | the suite below | suite |
| `Engine/SimPlanner.lua`, `Engine/SimSolver.lua`, `Modules/SpellTuner_Replay/*_Forever.lua` | only what the suite shows broken on a v3 recording, each change named in the Report with its reason; none expected | fixes |

## Rules

- The causality invariant stays true and tested.
- TBC suites at their counts (solvercheck 70, replaycheck 80, simwindow 8, practice 74, ...).
- No client call outside `Client/`; apicheck 0. No new global; no library.
- Tests first: coachforever written and run first; paste what fails before any fix.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/coachforever.lua` ends `8 ok, 0 failed`. Names, verbatim:
   1. "the coach finds a plan for a clean v3 recording"
   2. "the plan binds only families the player had at that pull, and never Lifebloom"
   3. "the card renders, ASCII, with no bare pipe, naming the gates it rests on"
   4. "every recorded cast gets a label"
   5. "the solver runs as a strategy on the Forever kit"
   6. "a burst at 20 s changes nothing the plan does before it" (the invariant on a v3 scenario)
   7. "the zone's marks are kept and read back"
   8. "the asynchronous coach finishes and fills the replay window's suggested column"
2. The suite also prints, once, `solver vs rules on the fixture: mana <a> vs <b>, deaths <c> vs <d>,
   floor seconds <e> vs <f>` -- recorded in the Report, not asserted.
3. Every other suite at its count; apicheck 0; `--selftest` as before.
4. `luac -p` clean on every Lua file touched.
5. Paste into the Report: the first run; coachforever in full; the card as the suite printed it; the
   solver line; every fix with its reason; every other tail; apicheck; luac; `git status --short`.

## Out of scope

- Real Forever recordings (M5). Runs, `SP.CoachRun`. Intuition's shipped TBC prior. The foresight
  experiments (off, plan §5).
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

### Files

- `tools/coachforever.lua` (new) — the 8-assertion suite plus the one printed
  "solver vs rules" line, following `tools/replayforever.lua` (T16a) and
  `tools/reviewforever.lua` (T16b) for module loading, chat capture, and the
  ASCII/no-bare-pipe scan pattern. Uses `tools/foreverfixture.lua` for the
  clean recording (meter/mana curve made consistent with the engine's own
  replay, `tools/reviewforever.lua`'s own trick) and a hand-built v3
  recording for the causality check (assertion 6), where the fixture's own
  fixed event shape does not let a burst be inserted cleanly.
- No other file changed. Every rule and function the Facts named
  (`SP.Coach`, `SP.CoachAsync`, `SP.Classify`, `SP.Card`, `SP.Mark`/
  `SP.Progress`, `SP.MaxRankBinds`, `SP.BindsFromRecording`, `SP.STRATEGY_SET`/
  `SP.Strategy`/`SP.MakeStrategy`, `Engine/SimSolver.lua`'s `SV.NewPlan`/
  `Solver:Decide`) already guards every `Lifebloom`/`Regrowth`/`Swiftmend`
  bind with `self.binds[fam]` (nil on Forever, since the fixture's
  `initial.known` only ever carries `HealingTouch`/`Rejuvenation`) before
  indexing the kit, both in `Engine/SimPlanner.lua`'s `Plan:Decide` (rules 1,
  3, 4, 5, `BestHPM`, `Card`'s bind list) and in `Engine/SimSolver.lua`'s
  `Solver:Best`/`Solver:Decide` (`id and kit[id]`, `SV.FAMILIES` iterated
  unconditionally). `Modules/SpellTuner_Replay/*_Forever.lua` needed no
  change either: `SM.ScenarioFromRecording` already dispatches `rec.v == 3`
  to `SM.ScenarioV3`, and `SP.Replay` already falls back to
  `SM.RecordedHp` when `rec.hp` is absent. Nothing was broken on the fixture,
  so the "fixes" row of the Files table is empty, as the task expected.

### Tests first

First run of `tools/coachforever.lua` (before any fix — none turned out to
be needed to addon code; the two failures below were bugs in the suite
itself, fixed in the same file):

```
the coach finds a plan for a clean v3 recording                                                 ok - validation=true best=table: 0x5f0dd70695c0
the plan binds only families the player had at that pull, and never Lifebloom                   FAIL - badBind=Rejuvenation=774 lifebloom=nil
the card renders, ASCII, with no bare pipe, naming the gates it rests on                        ok
every recorded cast gets a label                                                                ok - labelled=4 ownCasts=4
the solver runs as a strategy on the Forever kit                                                ok - entry=table: 0x5f0dd6efaf20 okRun=true err=nil
a burst at 20 s changes nothing the plan does before it                                         ok - identical until the burst
the zone's marks are kept and read back                                                         FAIL - wrote=true stillHere=true otherHere=false progress=since your last card (3 fights): overheal 33% -> 12%
...
6 ok, 2 failed
  FAIL the plan binds only families the player had at that pull, and never Lifebloom - badBind=Rejuvenation=774 lifebloom=nil
  FAIL the zone's marks are kept and read back - wrote=true stillHere=true otherHere=false progress=since your last card (3 fights): overheal 33% -> 12%
```

Diagnosis of the two failures (both in the new suite, not the addon):

1. Assertion 2 compared a bound spell id against the exact id named in
   `rec.initial.known` (one id per family — the top rank the player had).
   The fixture's `known.Rejuvenation = 1058` (R2), but `SP.BindsFromRecording`
   correctly bound `774` (R1) because the recording casts each rank once and
   picks the first tie — a legitimate, lower rank of the *same* known family,
   not a spell the player never had. Fixed the check to compare family and
   `rank <= known rank` (`SD.spells[id].family == SD.spells[knownID].family
   and SD.spells[id].rank <= SD.spells[knownID].rank`) instead of exact id
   equality.
2. Assertion 7's "a mark for a different zone" recording was built with
   `buildFixture()`'s default (mismatched) meter, so `SP.Coach` (called
   without `force`) refused before ever reaching `SP.Classify`/`SP.Mark`,
   and `MD.cdb.coachMarks["Ramparts"]` was never written. Fixed by building
   that second recording the same consistent way as `recGood` (matching
   meter and mana curve against the engine's own replay), so it too passes
   every gate and `SP.Mark` runs.

After both fixes, `tools/coachforever.lua` passes `8 ok, 0 failed` with no
change to any engine or module file.

### coachforever.lua in full (final run)

```
|cff9966ffSpellTuner:|r Recorder: loaded
|cff9966ffSpellTuner:|r Replay: loaded
the coach finds a plan for a clean v3 recording                                                 ok - validation=true best=table: 0x648a138acb90
the plan binds only families the player had at that pull, and never Lifebloom                   ok - badBind=nil lifebloom=nil
the card renders, ASCII, with no bare pipe, naming the gates it rests on                        ok
every recorded cast gets a label                                                                ok - labelled=4 ownCasts=4
the solver runs as a strategy on the Forever kit                                                ok - entry=table: 0x648a1373d6f0 okRun=true err=nil
a burst at 20 s changes nothing the plan does before it                                         ok - identical until the burst
the zone's marks are kept and read back                                                         ok - wrote=true stillHere=true otherHere=true progress=since your last card (3 fights): overheal 33% -> 12%
|cff9966ffSpellTuner:|r coach: searching (this runs across frames; /md coach cancel stops it)...
|cff9966ffSpellTuner:|r Blood Furnace, 03:33 (0:30, 2 targets)   you 110   best 95   diff 15
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
the asynchronous coach finishes and fills the replay window's suggested column                  ok - frames=1 right=table: 0x648a13950900
solver vs rules on the fixture: mana 220 vs 220, deaths 0 vs 0, floor seconds 0.0 vs 0.0

8 ok, 0 failed
```

### The card, as SP.Coach printed it on the clean fixture (assertion 1/3/7's
recording, `force` via the async path — same card the sync `SP.Coach` call
in assertion 1 builds)

```
Blood Furnace, 03:33 (0:30, 2 targets)   you 110   best 95   diff 15
  Bind: Rejuvenation R1, Healing Touch R1
  2. Anyone under 45%: Healing Touch R1
  4. Anyone under 80%: the HoT whose whole heal fits the deficit (Rejuvenation R1)
  5. Otherwise wait - 77% of the fight, longest gap 10s
  you              110   lowest  42%   overheal 17%
  max rank         125   lowest  42%
  HoTs only        100   lowest  42%
  your binds        95   lowest  42%
  best (search)      95   lowest  42%
  best              95   lowest  42%   + 189 still owed
  strategies (one search, four ways of reading it)
    Safest = Highest health = Most mana left    284 mana   floor  42%    0.0s in danger   owes 114
    Least mana                            284 mana   floor  42%    0.0s in danger   owes 189
    |cff888888/md coach 1 safe / health / cheap / regen plays that one in the replay|r
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
```

Bind stops at `Rejuvenation R1, Healing Touch R1` — no Lifebloom, no
Regrowth, no Swiftmend line — because the fixture never gave the player
those families (`initial.known = { HealingTouch = 5185, Rejuvenation = 1058
}`), exactly what acceptance criterion 2 requires: nothing bound that the
player did not have, and Lifebloom in particular never appears (Forever has
none).

One pre-existing cosmetic oddity noticed but **not** in scope to fix: the
card prints `(warning: labelled 110 of 0 spent - the breakdown is
incomplete)` because `rec.spent` is a v2/TBC-only field the fixture (and, so
far, every v3 stream) never sets — the classifier's identity check compares
labelled mana against 0 instead of the fight's real spend. This does not
fail any of the eight assertions (the ASCII/pipe scan in assertion 3 does
not care about the number), so per the task's "minimal, guarded, or a
question" rule for shared-file changes I left it alone and am naming it here
rather than fixing it unasked.

### The solver line (acceptance 2, printed once, not asserted)

```
solver vs rules on the fixture: mana 220 vs 220, deaths 0 vs 0, floor seconds 0.0 vs 0.0
```

On this one short, light fixture (30 s, one tank hit for 500 at t=1, a
trickle of 300 afterwards) neither planner is ever pushed hard enough to
diverge — both spend the same 220 mana, no deaths, no time under the danger
line for either. This is expected on a fixture built to exercise the
attribution/cadence machinery (T13d), not to stress a healing decision; the
44%-less-mana margin CLAUDE.md records for the solver was measured on real,
longer TBC recordings, and M5's real Forever pulls are where that
re-measurement belongs, as the task's Goal and Out of scope both say.

### Every other suite at its count

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
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
coachforever  8 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc 15 ok, 0 failed
corecheck/forever 10 ok, 0 failed
corecheck/tbc 8 ok, 0 failed
svcheck/forever 6 ok, 0 failed
svcheck/tbc   1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc 1 ok, 0 failed
apicheck: 8 Forever TOCs, 40 files, 43 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok
```

All baselines from the task's Facts hold exactly (reviewforever 8,
replayforever 10, gatecheck 8, scenariocheck 9, recordcheck 14, kitcheck 7,
apicheck 0/40 files, `--selftest` 10/10, refcheck selftest ok, probecheck 73,
modulecheck 14, forevercheck 13, parsecheck 11, bookcheck 15, tipcheck 14,
clockcheck 15, spellsui 15, measurecheck 18, adaptercheck 19/15, corecheck
10/8, svcheck 6/1, consolecheck 11/1, and every TBC-flavour suite: simcheck
PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44,
navui 25, dashui 56, regencheck 27, simwindow 8, solvercheck 70, timeline 27,
spelltip 48, practice 74, practiceui 49, migrate 7).

### luac -p

```
$ tools/.lua/lua-5.1.5/src/luac -p tools/coachforever.lua
coachforever.lua: OK
```

No other file was touched, so no other file needed re-checking.

### git status --short

```
 M docs/tasks/HANDOVER.md
?? tools/coachforever.lua
```

`docs/tasks/HANDOVER.md` was already modified before this task started (per
the lead's note) and was never touched here; the only change made is the new
`tools/coachforever.lua`.

### What was skipped and why

- Real Forever recordings, `SP.CoachRun`, runs, and Intuition's shipped TBC
  prior — all named out of scope by the task.
- No fix was made to `Engine/SimPlanner.lua`, `Engine/SimSolver.lua` or
  `Modules/SpellTuner_Replay/*_Forever.lua`: the suite found nothing broken
  on the fixture (see "Tests first" above — both failures traced back to the
  test's own assumptions, not the addon), so the Files table's "fixes" cell
  is empty, matching its own "none expected".

### Questions

None — the fixture and existing code already satisfied every acceptance
item once the suite's own two bugs were fixed.

## Lead review (2026-09-28)

Accepted: every acceptance line holds and the lead reran every suite (coachforever 8, everything
else at its baseline; apicheck 0 over 40 files, `--selftest` 10 of 10, refcheck ok) and `luac -p`.

**Escalated to the planner -- the causality invariant does not hold on a real Forever recording.**
Assertion 6's fixture gives the tank a plain max (`maxSecret = false`). On Forever a party member's
max is always secret, and planner ruling 1's stand-in (`SM.EstimateMaxHP`: the largest deficit of
the **whole fight** plus its biggest hit) is computed from the future. The lead ran the same
assertion with the tank's max secret (`maxHP = -1, maxSecret = true`): `FAIL - diverged at 6.5s` --
the burst at 20 s raises the estimated max, which changes the fractions the rules read, which
changes a cast 13.5 s before the burst. The assertion is kept as delivered (it holds the planner
itself to the invariant given a known max); the leak is ruling 1's and goes back to the planner
with a recommendation (docs/tasks/HANDOVER.md, open questions).

Also noted: the card warns `labelled 110 of 0 spent` because a v3 stream has no `spent`; the Review
row's casts / spent / foreign-share columns read `ownCasts`, `spent`, `foreignShare`, which the v3
recorder does not stamp either. Follow-up task T13f.
