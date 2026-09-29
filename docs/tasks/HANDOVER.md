# Lead handover -- WoW: Forever port

Rewritten by the lead after every commit and every hand-out. A successor continues from this file
alone. Worktree: `/home/penek/projects/addons/SpellTuner/.claude/worktrees/manademon-folder-continue-41eabc`,
branch `claude/manademon-folder-continue-41eabc`.

Last updated: 2026-09-29, after T20 (review R6, the author's ruling "Fix both lines": the danger
line a plan decides on is causal). Every Forever TOC at `1.0.0-alpha.7`; the TBC TOC at 0.15.4 (the
author decides a TBC release separately). Next: T20b (hand out), then alpha.8, then T21.

## Committed (newest first)

| hash | what |
|---|---|
| (the commit carrying this revision) | T20 (R6): `SM.DangerLine` -- a plan decides on the biggest hit so far (prior / floor before the first), the score keeps the whole-fight line; `Solver:AtRisk` and rule 8 read it; synthetic scenarios unchanged; DECISIONS entry for the ruling; solvercheck 74, coachforever 17 |
| a7d604e | alpha.7: every Forever TOC + the probecheck / consolecheck pins; the review annotated `**Fixed** in <hash>` / `**Skipped**` per R-number; TOOLS suite counts; HISTORY entry; this handover |
| a12bcf6 | review-shared R5: a v3 replay's ticks called reconstructed (SimPlanner `rp.ticks.reconstructed`, ReplayWindow hover and checkbox); replayforever 11 |
| baaf6ef | review-shared R23: no `solver-corpus` strategy without `MD.IntuitionTBC`; coachforever |
| bdbd42e | review-shared R39, R40: Review's low mana `~N%` when modelled, Export hidden without `MD.RunExport`; reviewforever 10 |
| e6cc8cd | review-shared R4: Forever practice regen from `MD.API.ManaRegen()` when `MD.Regen` is absent; practiceforever 9 |
| a73d296 | review-spells R13 R31 R35 R36 R37 R38 R41 R42: non-mana costs free, `Book:CastsFor`, wards/reactive damage refused, clock starts in combat after a mid-fight login, stale values across rescans, crit `1.5x, unverified`; parse 12, book 17, tip 17, clock 17, spellsui 17 |
| 80054ab | review-core R15 R16 R21 R22: debug console Enable box on Forever, the stack line names the raising frame, the forward a tail call; consolecheck 14/1; stub `debugstack` from the real stack (`-- review-core`) |
| 3ad8cce | review-probe R2 R3 R17-R20: snapshot only in combat, SV type at load from the guard, pets, GUID mirrors, `no cost`, `SpellTuner_` modules' blocked actions; probecheck 82 |
| 4673fc8 | review-replay R28 R29 R30: Swiftmend ends the HoT it eats, pre-pull ticks by ceiling (with a scoped `Engine/SimModel.lua` `ticksLeft`/`firstTick` read TBC never sets), direct claims by size; scenariocheck 12 |
| 530cc08 | review-replay R27: an excluded target's line says `max estimated`; gatecheck 9 |
| 1463b9b | review-replay R12 R26: `/st coach N safe/health/cheap/regen` picks a strategy; the card keeps its colour codes; coachforever 16 (with baaf6ef) |
| ad3f5f4 | review-recorder R7-R11 R24 R25: dead at the pull, the opener and pre-cast HoTs, meter `none` when empty/partial/in combat again, the healer's death at the end, departed tokens; recordcheck 24 |
| 12ba325 | review-measure R1 R14 R32 R33 R34: deficit in combat only, casts named at another unit not judged (SENT target), HoT crit at 1.5x, lists escaped; measurecheck 26 |
| c725e91 | docs: CLAUDE.md rows for T17b/T17c/T19 and alpha.6 (applied by the planner); the independent Forever review |
| 63b0cf7 | alpha.6: every Forever TOC + the probecheck / consolecheck pins; TESTING §40 (practice and the imports on Forever); ROADMAP M3/M4 ticks; TOOLS rows (coachforever, adaptercheck, recordcheck, bindscheck + the loop); HISTORY entry from T18 on; this handover |
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

- `docs/tasks/T20b-danger-prior-from-others.md` -- written (the second half of R6: the danger prior
  from other recordings, leave-one-out). Handed out next.

## Next, in order

1. **The review's groups not accepted: none.** All seven fix branches (`fix/review-measure`,
   `-recorder`, `-replay`, `-probe`, `-core`, `-spells`, `-shared`) were accepted and are in HEAD;
   there is no review group left to redo.
2. **R6** (ruled "Fix both lines", DECISIONS "Forever review R6"): T20 committed (the causal line);
   T20b (the prior from other recordings) next; then **alpha.8** (every Forever TOC + the
   probecheck / consolecheck pins, R6 marked Fixed in `docs/review/2026-09-29-forever-review.md`,
   TOOLS counts, HISTORY entry), then **T21** docs (CLAUDE.md file table, TESTING §38-§40,
   ROADMAP-FOREVER up to alpha.8 and the review fixes 12ba325..a12bcf6; TESTING steps changed only
   where a fix changed what the author sees).
3. **When the author's reports arrive:** §38.2 step 4 (gross or effective) -> `SM.HEAL_AMOUNT` and
   gate 8 two-sided; §38.3's `bar UnitHealthMax(party1): ...` line -> flip `MD.API.BAR_READS_MAX`
   (one word, `Client/API.lua` 333) if `read plain`, both out of combat and in the snapshot; §39 ->
   the recorder on real pulls (CANCEL count, meter vs attributed own healing); §40.1's
   `/st binds check` paste -> a task per importer that does not recognise the Forever shape (from
   the paste only); §40.2 -> practice on the beta. Install **alpha.7** for all of them (it carries
   every review fix; nothing in §38-§40 changes).
4. Then M5 (launch client, 2026-11-04).

Suite loop: `docs/TOOLS.md` §1 (every suite, `bindscheck` included since alpha.6) plus
`python3 tools/apicheck.py`, `--selftest`, `python3 tools/refcheck.py --selftest`.

## Baselines (at the last commit)

TBC sixteen (unchanged by the review): simcheck PASS, reccheck 54, replaycheck 80, replayui 98,
runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27, simwindow 8, solvercheck 74, timeline
27, spelltip 48, practice 74, practiceui 49, migrate 7. Forever: probecheck 82, forevercheck 13,
modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 11,
reviewforever 10, coachforever 17, practiceforever 9, bindscheck 6, parsecheck 12, bookcheck 17,
tipcheck 17, clockcheck 17, spellsui 17, measurecheck 26. Both flavours: adaptercheck 22/15,
corecheck 10/8, svcheck 6/1, consolecheck 14/1. apicheck 0 findings over 44 files (45 distinct
globals), selftest 10 of 10, refcheck selftest ok. The same counts in a `git archive HEAD` export.

## Open questions / hazards

- **Resolved (planner's amendment, 2026-09-28; T17b a5e49e0 + T17c 3fc0623):** the causality leak of
  ruling 1's stand-in. Party max from other recordings (leave-one-out); else this fight's estimate,
  the plan flagged `foresees`, the card line "NOT causal - sees this fight"; the status-bar path
  ships off (`MD.API.BAR_READS_MAX = false`) -- **switch it on** (one word, `Client/API.lua` 333)
  only if the author's §38.3 report shows `bar UnitHealthMax(party1): set ok, read plain <n>`.
- **Ruled and fixed (T20):** review R6. Follow-up worth a one-line task some day: the two OLDER
  divergence assertions (solvercheck §4 "a burst at 40s ...", coachforever 6) time a divergence by
  the quiet run's cast only, which could report late when the loud run inserts an early cast; T20's
  two new ones take the earlier of the two (lead's one-line change). Both older ones still pass
  with the stricter time.
- **Waiting on the author:** TESTING §38 (alpha.4 items, notably §38.2 step 4 -- is a `UNIT_COMBAT`
  HEAL amount gross or effective; that sets `SM.HEAL_AMOUNT` and makes gate 8 two-sided -- and
  §38.3, the party probe with the `bar ...` lines), §39 (the recorder, validate, replay, coach and
  Review on real pulls; the CANCEL count against casts actually cancelled, since the STOP /
  SUCCEEDED order is UNKNOWN) and §40 (practice and the imports). All three install **alpha.7**
  (it carries everything §38/§39 need, plus the review fixes).
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
