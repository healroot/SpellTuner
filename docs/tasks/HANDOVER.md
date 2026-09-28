# Lead handover -- WoW: Forever port

Rewritten by the lead after every commit and every hand-out. A successor continues from this file
alone. Worktree: `/home/penek/projects/addons/SpellTuner/.claude/worktrees/manademon-folder-continue-41eabc`,
branch `claude/manademon-folder-continue-41eabc`.

Last updated: 2026-09-28, lead run 2, **wrapped up for the day at the author's request**, after the
T18 commit. Nothing is running; nothing was dispatched after T18.

## Committed (newest first)

| hash | what |
|---|---|
| (the commit carrying this revision) | docs: this handover, end of day |
| a25d878 | T18: Practice module carries Engine/Practice.lua, UI/PracticePanel.lua, UI/BindingsWindow.lua (shared, through MD.API) + Commands_Forever.lua; Simulate -> Practice in the Forever window; PR.EnsureKit; practiceforever 8 (new) |
| b95ef03 | Every Forever TOC at 1.0.0-alpha.5 (probecheck/consolecheck pins follow); TESTING §39 (M3 in game); HISTORY entry |
| c3fb09b | T13f: recorder stamps ownCasts/spent/foreignShare; pre-pull aura remaining aged to t0 |
| 46ebdd9 | T17: coach/solver/card/classifier/marks on a v3 recording, no engine change; coachforever 8. Causality leak escalated (below) |
| 4ae77d8 | T16c: paint-time Esc narrowed to the pipe (names painted as given; TBC as before T16a) |
| 243256c | T16b: Forever window Reports -> Review; MD:RunCoach / MD:ValidationReport on Forever; reviewforever 8 |
| a8ba234 | T16a: Replay module carries engine/planner/solver/ReplayTrace/Tooltip/ReplayWindow + Commands_Forever.lua; SM.RecordedHp; replayforever 10; SP.Card `local kit = nil` |
| 6887cdf | T14: Gates_Forever.lua, SM:ValidateV3, gate 8 one-sided until SM.HEAL_AMOUNT is effective; gatecheck 8 |
| 9f2488b | T13d: Scenario_Forever.lua (SM.ScenarioV3, AttributeHeals on both HoT cadences, EstimateMaxHP, reconstructed health); tools/foreverfixture.lua; scenariocheck 9 |
| 6624d58 | T13: Recorder_Forever.lua, v3 stream, /st rec; recordcheck 14 |
| 9876615 | T15: Kit_Forever.lua (kit + spell index from MD.Book), MD.API.SpellName; kitcheck 7 |
| 797ef17 | T13a: apicheck rule 8 (event argument used before IsSecret); selftest 10 of 10 |
| 007d1d1 | T13e: probe asks whether a StatusBar hands a secret back; probecheck 73 |
| bdbc40a | T13c: module plumbing (Module.lua proxy, Ready.lua, root-resolved shared files); modulecheck 14 |
| 2ba2346 and earlier | previous lead run (see docs/HISTORY.md) |

Every accepted task file carries a "Lead review" section saying what the lead changed, if anything.
The T18 row is not yet in docs/HISTORY.md (the b95ef03 entry covers up to T13f) -- add it with T19.

## In the tree, not committed

Nothing.

## Next, in order

1. **T19** (`docs/tasks/T19-binds-import-check.md`, written, not yet handed out) -- re-check its
   baselines against the table below first (it was written before M3 landed).
2. Then M4 is done except for the in-game checks: bump to `1.0.0-alpha.6` (every Forever TOC's
   `## Version:` plus the pins in `tools/probecheck.lua` and `tools/consolecheck.lua`, as b95ef03 did)
   and add a TESTING section for practice on Forever.
3. Whatever the planner answers on the escalation below.

Suite loop: `docs/TOOLS.md` §1 (it lists every suite, the new Forever ones included) plus
`python3 tools/apicheck.py`, `--selftest`, `python3 tools/refcheck.py --selftest`.

## Baselines (at the last commit)

TBC sixteen: simcheck PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44,
navui 25, dashui 56, regencheck 27, simwindow 8, solvercheck 70, timeline 27, spelltip 48, practice
74, practiceui 49, migrate 7. Forever: probecheck 73, forevercheck 13, modulecheck 14, kitcheck 7,
recordcheck 14, scenariocheck 9, gatecheck 8, replayforever 10, reviewforever 8, coachforever 8,
practiceforever 8, parsecheck 11, bookcheck 15, tipcheck 14, clockcheck 15, spellsui 15,
measurecheck 18. Both flavours: adaptercheck 19/15, corecheck 10/8, svcheck 6/1, consolecheck 11/1.
apicheck 0 findings over 44 files, selftest 10 of 10, refcheck selftest ok.

## Open questions / hazards

- **ESCALATED to the planner (T17 review): ruling 1 breaks the causality invariant.**
  `SM.EstimateMaxHP` uses the whole fight's largest deficit + biggest hit, so a v3 scenario's party
  max depends on the future; with the tank's max secret, coachforever assertion 6's burst at 20 s
  changes a cast at 6.5 s (`FAIL - diverged at 6.5s`, lead's run; the committed assertion uses a
  plain max and passes). Recommendation: (1) take a party member's max from **other** recordings of
  the same name (leave-one-out, Intuition's rule), falling back to this fight's estimate with the
  plan flagged `foresees` and the card saying "max from this fight"; (2) if T13e's probe shows a
  status bar reads a secret max back plain, record the real max and drop the stand-in.
- **Waiting on the author:** TESTING §38 (alpha.4 items, notably §38.2 step 4 -- is a `UNIT_COMBAT`
  HEAL amount gross or effective; that sets `SM.HEAL_AMOUNT` and makes gate 8 two-sided) and §39
  (alpha.5: the recorder, validate, replay, coach and Review on real pulls; the CANCEL count against
  casts actually cancelled, since the STOP / SUCCEEDED order is UNKNOWN).
- **Lesson -- check before you dispatch.** T13c was dispatched twice, and two implementers were
  writing in the same tree at once (the previous run's alpha.4 commit also swept in T13c's TOC hunk,
  and T12b's commit its stub hunk). Before handing a task out or re-issuing it: read the task's
  Report section, `git status --short` and `git diff` for its files; if another implementer may
  still be writing, wait until the tree settles (file mtimes stable for a few minutes) rather than
  starting a second one. Stage only the task's own paths; never `git add -A`.
- **The shared `.git` object store has 18 empty (corrupt) loose objects** (`git fsck`). They are
  reachable only from four old docs commits (fd6a540, ad94b2f, d35f41c, 47b9edf -- `git ls-tree -r`
  fails on them) and from branch `claude/combat-log-design-arch-ffb907`. HEAD's tree is readable.
  Not ours to repair (never touch `.git` internals); reported to the planner. Hazard: a new commit
  whose blob hash equals one of the empty objects would be silently corrupt, so after every commit
  run `git ls-tree -r HEAD` and export HEAD with `git archive` and run the suites there.

## Planner, end of 2026-09-28

- **Escalation 1 ruled** (docs/FOREVER-PLAN.md, the amendment under ruling 1): party max for
  coaching from other recordings of the same name; else this fight's estimate with `foresees` set
  and said on the card; drop the stand-in if the T13e readback shows a plain max. Write it as the
  **first task tomorrow** (before T19), with coachforever's causality assertion run on a secret max.
- **Escalation 2 (the 18 empty git objects)** stays with the author -- no agent touches `.git`.
- **Nothing is installed past alpha.3** in the author's beta. Install alpha.5+ (`./release.sh
  --install ...`) only when the author is ready to play §38/§39.
