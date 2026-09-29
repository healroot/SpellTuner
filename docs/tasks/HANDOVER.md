# Lead handover -- WoW: Forever port

Rewritten by the lead after every commit and every hand-out. A successor continues from this file
alone. Worktree: `/home/penek/projects/addons/SpellTuner/.claude/worktrees/manademon-folder-continue-41eabc`,
branch `claude/manademon-folder-continue-41eabc`.

Last updated: 2026-09-29, lead run 3 (the author: "ok continue working from where you have
stopped"). **The queue is done**: T17b, T17c, T19 committed, every Forever TOC at `1.0.0-alpha.6`
with TESTING §40. Nothing is running; nothing is handed out.

## Committed (newest first)

| hash | what |
|---|---|
| (the commit carrying this revision) | alpha.6: every Forever TOC + the probecheck / consolecheck pins; TESTING §40 (practice and the imports on Forever); ROADMAP M3/M4 ticks; TOOLS rows (coachforever, adaptercheck, recordcheck, bindscheck + the loop); HISTORY entry from T18 on; this handover |
| 9cbc043 | T19: `/st binds check` (`PR.BindsReport`), importers refuse an unknown shape naming what they expected and found; bindscheck 6 (new) |
| 3fc0623 | T17c: `MD.API.HealthMax` reads a party max through a hidden StatusBar behind `MD.API.BAR_READS_MAX = false`; the recorder records a plain read-back (`maxVia = "bar"`); adaptercheck 22/15, recordcheck 15 |
| a5e49e0 | T17b: party max from other recordings (leave-one-out, `SM.PartyMaxFromOthers`), else this fight's estimate with the plan flagged `foresees` and the card line "NOT causal - sees this fight"; coachforever 13 (assertion 6 on a secret max) |
| 34d3509 | docs: the planner's causality ruling, end-of-day handover |
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
docs/HISTORY.md's 2026-09-29 entry covers T18 onwards.

## In the tree, not committed

Nothing.

## Next, in order

1. **Nothing offline is queued.** M4 is built except for its in-game half (TESTING §40).
2. **Not done, needs the author (or the planner with the author's word):** the `CLAUDE.md` file-table
   rows for T17b / T17c / T19 and the alpha.6 status line. The lead did not edit `CLAUDE.md`: an
   agent's request is not the author's consent to change it. Proposed text is in the lead's report
   to the planner (2026-09-29): the `Client/API.lua` row gains `MD.API.HealthMax` behind
   `MD.API.BAR_READS_MAX = false` (T17c); the `Modules/<Name>/` row gains T17b's leave-one-out max
   (`SM.PartyMaxFromOthers`, `maxSource`, `maxForesees`, the card's `NOT causal` line), T17c's
   `maxVia = "bar"` in the recorder, and T19's `/st binds check`; the `Engine/Practice.lua` row gains
   `PR.BindsReport` and the importers' shape refusal; the `tools/` row's Forever suite list gains
   `coachforever` (13), `bindscheck` (6), `adaptercheck` 22 / 15, `recordcheck` 15, `practiceforever`
   (8); the "What this is" paragraph's "empty until M3/M4" becomes "M3 at alpha.5, M4's offline part
   at alpha.6".
3. **When the author's reports arrive:** §38.2 step 4 (gross or effective) -> `SM.HEAL_AMOUNT` and
   gate 8 two-sided; §38.3's `bar UnitHealthMax(party1): ...` line -> flip `MD.API.BAR_READS_MAX`
   (one word, `Client/API.lua` 333) if `read plain`, both out of combat and in the snapshot; §39 ->
   the recorder on real pulls (CANCEL count, meter vs attributed own healing); §40.1's
   `/st binds check` paste -> a task per importer that does not recognise the Forever shape (from
   the paste only); §40.2 -> practice on the beta.
4. Then M5 (launch client, 2026-11-04).

Suite loop: `docs/TOOLS.md` §1 (every suite, `bindscheck` included since alpha.6) plus
`python3 tools/apicheck.py`, `--selftest`, `python3 tools/refcheck.py --selftest`.

## Baselines (at the last commit)

TBC sixteen: simcheck PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44,
navui 25, dashui 56, regencheck 27, simwindow 8, solvercheck 70, timeline 27, spelltip 48, practice
74, practiceui 49, migrate 7. Forever: probecheck 73, forevercheck 13, modulecheck 14, kitcheck 7,
recordcheck 15, scenariocheck 9, gatecheck 8, replayforever 10, reviewforever 8, coachforever 13 (since T17b),
practiceforever 8, bindscheck 6, parsecheck 11, bookcheck 15, tipcheck 14, clockcheck 15, spellsui 15,
measurecheck 18. Both flavours: adaptercheck 22/15, corecheck 10/8, svcheck 6/1, consolecheck 11/1.
apicheck 0 findings over 44 files (45 distinct globals), selftest 10 of 10, refcheck selftest ok.

## Open questions / hazards

- **Resolved (planner's amendment, 2026-09-28; T17b a5e49e0 + T17c 3fc0623):** the causality leak of
  ruling 1's stand-in. Party max from other recordings (leave-one-out); else this fight's estimate,
  the plan flagged `foresees`, the card line "NOT causal - sees this fight"; the status-bar path
  ships off (`MD.API.BAR_READS_MAX = false`) -- **switch it on** (one word, `Client/API.lua` 333)
  only if the author's §38.3 report shows `bar UnitHealthMax(party1): set ok, read plain <n>`.
- **Waiting on the author:** TESTING §38 (alpha.4 items, notably §38.2 step 4 -- is a `UNIT_COMBAT`
  HEAL amount gross or effective; that sets `SM.HEAL_AMOUNT` and makes gate 8 two-sided -- and
  §38.3, the party probe with the `bar ...` lines), §39 (the recorder, validate, replay, coach and
  Review on real pulls; the CANCEL count against casts actually cancelled, since the STOP /
  SUCCEEDED order is UNKNOWN) and §40 (practice and the imports). All three install **alpha.6**
  (it carries everything §38/§39 need).
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
- **Nothing is installed past alpha.3** in the author's beta. Install alpha.6 (`./release.sh
  --install ...`) only when the author is ready to play §38-§40.
- 2026-09-29: the amendment is implemented (T17b, T17c); escalation 1 is closed.
