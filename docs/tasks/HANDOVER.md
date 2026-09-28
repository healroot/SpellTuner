# Lead handover -- WoW: Forever port

Rewritten by the lead after every commit and every hand-out. A successor continues from this file
alone. Worktree: `/home/penek/projects/addons/SpellTuner/.claude/worktrees/manademon-folder-continue-41eabc`,
branch `claude/manademon-folder-continue-41eabc`.

Last updated: 2026-09-28, lead run 2, at the alpha.5 bump commit.

## Committed

| hash | what |
|---|---|
| (the commit carrying this revision) | Every Forever TOC at 1.0.0-alpha.5 (probecheck/consolecheck pins follow, counts unchanged); TESTING §39 (M3 in game); HISTORY entry |
| c3fb09b | T13f: recorder stamps ownCasts/spent/foreignShare; pre-pull aura remaining aged to t0; recordcheck 14 (assertions 2 and 10 extended). TESTING §39 drafted (uncommitted until the alpha.5 bump) |
| 46ebdd9 | T17: coach/solver/card/classifier/marks on a v3 recording, no engine change; coachforever 8 (new). Causality leak via the max estimate escalated |
| 4ae77d8 | T16c: paint-time Esc narrowed to the pipe (names painted as given; TBC as before T16a); lead fix: Esc returns one value |
| 243256c | T16b: Forever window Reports -> Review (shared Dashboard_Review.lua through the adapter, placeholder when Replay is off), MD:RunCoach / MD:ValidationReport on Forever; reviewforever 8 (new) |
| a8ba234 | T16a: Replay module carries engine/planner/solver/ReplayTrace/Tooltip/ReplayWindow + Commands_Forever.lua; ReplayWindow through MD.API; SM.RecordedHp; replayforever 10 (new). Lead: SP.Card `local kit = nil` (stray global, TBC unchanged) |
| 6887cdf | T14: Gates_Forever.lua -- SM:ValidateV3, eight gates on a v3 stream, gate 8 one-sided until SM.HEAL_AMOUNT is effective; gatecheck 8 (new suite). T16a/T16b gained a paint-time escape rule |
| 9f2488b | T13d: Replay module carries Scenario_Forever.lua -- v3 stream to scenario, heal attribution (ruling 2), max-HP estimate (ruling 1), reconstructed health; recorder aura `tgt`; tools/foreverfixture.lua; scenariocheck 9 (new suite). Two re-issues (recast cadence, recast chain) |
| 6624d58 | T13: Recorder module carries Recorder_Forever.lua, v3 stream into MD.cdb.recordings, /st rec; recordcheck 14 (new suite, in the TOOLS loop). One re-issue (cancel order, zone escape, aura scan in combat) |
| 9876615 | T15: Replay module carries Kit_Forever.lua + Engine/SimModel.lua; kit from MD.Book; MD.API.SpellName on both clients; kitcheck 7 (new suite, in the TOOLS loop). Lead fixes: Tranquility exclude, SpellKit only-if-nil |
| 797ef17 | T13a: apicheck rule 8 (handler argument used before IsSecret); Core_Forever ADDON_LOADED guarded; selftest 10 of 10 |
| 007d1d1 | T13e: probe asks whether a StatusBar hands a secret back (3 `bar` lines + `UnitHealthMissing(party1)`); probecheck 73. Lead added the `read skipped` guard |
| bdbc40a | T13c: module plumbing -- Module.lua proxy, Ready.lua handshake, root-resolved shared files in release/stub/apicheck; modulecheck 14, kitcheck 7, recordcheck 14, scenariocheck 9, gatecheck 8, replayforever 10, reviewforever 8, coachforever 8, apicheck selftest 8 |
| 2ba2346 | docs: gate 8 one-sided until the HEAL amount is known (planner addendum, confirmed) |
| da7dff2 | docs: M2 re-check in roadmap/file table/tools/history; M3/M4 tasks written |
| 4303c71 | docs: TESTING §38 (next testing round), T13e written |
| 8a1f451 | alpha.4 bump. **NB:** it also carried T13c's module-TOC hunk (`Ready.lua` listed) before `Ready.lua` existed -- HEAD's release build is broken until T13c lands |
| b7e55b7 | T12b. **NB:** it also carried T13c's stub hunk (`ResolveModuleFile`, one table per addon load) |

## In the tree, not committed

Nothing.

## Next, in order

T18 -> T19.
Re-check each task's baselines against the suite run at the commit before handing it out.
Suite loop: `docs/TOOLS.md` §1 plus `apicheck`, `apicheck --selftest`, `refcheck --selftest`.

## Baselines (at the last commit)

TBC sixteen: reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56,
regencheck 27, simwindow 8, solvercheck 70, timeline 27, spelltip 48, practice 74, practiceui 49,
migrate 7, simcheck PASS. Forever: probecheck 73, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 14, scenariocheck 9, gatecheck 8, replayforever 10, reviewforever 8, coachforever 8, parsecheck 11,
bookcheck 15, tipcheck 14, clockcheck 15, spellsui 15, measurecheck 18; adaptercheck 19/15,
corecheck 10/8, svcheck 6/1, consolecheck 11/1; apicheck 0 findings (40 files), selftest 10 of 10, refcheck ok.

## Open questions / hazards

- **ESCALATED to the planner (2026-09-28, T17 review): ruling 1 breaks the causality invariant.**
  `SM.EstimateMaxHP` uses the whole fight's largest deficit + biggest hit, so a v3 scenario's party
  max depends on the future; with the tank's max secret, coachforever assertion 6's burst at 20 s
  changes a cast at 6.5 s (`FAIL - diverged at 6.5s`, lead's run). Recommendation: (1) take a party
  member's max from **other** recordings of the same name (leave-one-out, Intuition's rule: a fight
  is never in its own prior), falling back to this fight's estimate with the plan flagged
  `foresees` and the card saying "max from this fight" as Foresight does; (2) if T13e's probe shows
  a status bar reads a secret max back plain, record the real max and drop the stand-in. Not
  blocking T18/T19.


- **In-game M3 checks** are TESTING §39 (alpha.5): `/st rec` on real pulls, CANCEL count vs casts
  actually cancelled (STOP / SUCCEEDED order UNKNOWN), meter totals, validate / replay / coach /
  Review. The next bump is the lead's own commit (follow 8a1f451 / this run's alpha.5 commit:
  every Forever TOC's `## Version:`, and the pins in probecheck.lua and consolecheck.lua).

- **The shared `.git` object store has 18 empty (corrupt) loose objects** (`git fsck`). They are
  reachable only from four old docs commits (fd6a540, ad94b2f, d35f41c, 47b9edf -- `git ls-tree -r`
  fails on them) and from branch `claude/combat-log-design-arch-ffb907`. HEAD's tree is readable.
  Not ours to repair (never touch `.git` internals); reported to the planner. Hazard: a new commit
  whose blob hash equals one of the empty objects would be silently corrupt, so after every commit
  run `git ls-tree -r HEAD` and `git archive HEAD` and check the export.
