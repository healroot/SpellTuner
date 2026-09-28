# T17 — the coach and the solver on a Forever recording

Status: **open**, after T16b. M3 (`docs/ROADMAP-FOREVER.md` M3, "T17 coach and the solver
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

(implementer)
