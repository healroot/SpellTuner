# Lead handover -- WoW: Forever port

Rewritten by the lead after every commit and every hand-out. A successor continues from this file
alone. Worktree: `/home/penek/projects/addons/SpellTuner/.claude/worktrees/manademon-folder-continue-41eabc`,
branch `claude/manademon-folder-continue-41eabc`.

Last updated: 2026-09-28, lead run 2, at the T16a commit.

## Committed

| hash | what |
|---|---|
| (the commit carrying this revision) | T16a: Replay module carries engine/planner/solver/ReplayTrace/Tooltip/ReplayWindow + Commands_Forever.lua; ReplayWindow through MD.API; SM.RecordedHp; replayforever 10 (new). Lead: SP.Card `local kit = nil` (stray global, TBC unchanged) |
| 6887cdf | T14: Gates_Forever.lua -- SM:ValidateV3, eight gates on a v3 stream, gate 8 one-sided until SM.HEAL_AMOUNT is effective; gatecheck 8 (new suite). T16a/T16b gained a paint-time escape rule |
| 9f2488b | T13d: Replay module carries Scenario_Forever.lua -- v3 stream to scenario, heal attribution (ruling 2), max-HP estimate (ruling 1), reconstructed health; recorder aura `tgt`; tools/foreverfixture.lua; scenariocheck 9 (new suite). Two re-issues (recast cadence, recast chain) |
| 6624d58 | T13: Recorder module carries Recorder_Forever.lua, v3 stream into MD.cdb.recordings, /st rec; recordcheck 14 (new suite, in the TOOLS loop). One re-issue (cancel order, zone escape, aura scan in combat) |
| 9876615 | T15: Replay module carries Kit_Forever.lua + Engine/SimModel.lua; kit from MD.Book; MD.API.SpellName on both clients; kitcheck 7 (new suite, in the TOOLS loop). Lead fixes: Tranquility exclude, SpellKit only-if-nil |
| 797ef17 | T13a: apicheck rule 8 (handler argument used before IsSecret); Core_Forever ADDON_LOADED guarded; selftest 10 of 10 |
| 007d1d1 | T13e: probe asks whether a StatusBar hands a secret back (3 `bar` lines + `UnitHealthMissing(party1)`); probecheck 73. Lead added the `read skipped` guard |
| bdbc40a | T13c: module plumbing -- Module.lua proxy, Ready.lua handshake, root-resolved shared files in release/stub/apicheck; modulecheck 14, kitcheck 7, recordcheck 14, scenariocheck 9, gatecheck 8, replayforever 10, apicheck selftest 8 |
| 2ba2346 | docs: gate 8 one-sided until the HEAL amount is known (planner addendum, confirmed) |
| da7dff2 | docs: M2 re-check in roadmap/file table/tools/history; M3/M4 tasks written |
| 4303c71 | docs: TESTING §38 (next testing round), T13e written |
| 8a1f451 | alpha.4 bump. **NB:** it also carried T13c's module-TOC hunk (`Ready.lua` listed) before `Ready.lua` existed -- HEAD's release build is broken until T13c lands |
| b7e55b7 | T12b. **NB:** it also carried T13c's stub hunk (`ResolveModuleFile`, one table per addon load) |

## In the tree, not committed

Nothing.

## Next, in order

T16b -> T17 -> T18 -> T19.
Re-check each task's baselines against the suite run at the commit before handing it out.
Suite loop: `docs/TOOLS.md` §1 plus `apicheck`, `apicheck --selftest`, `refcheck --selftest`.

## Baselines (at the last commit)

TBC sixteen: reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56,
regencheck 27, simwindow 8, solvercheck 70, timeline 27, spelltip 48, practice 74, practiceui 49,
migrate 7, simcheck PASS. Forever: probecheck 73, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 14, scenariocheck 9, gatecheck 8, replayforever 10, parsecheck 11,
bookcheck 15, tipcheck 14, clockcheck 15, spellsui 15, measurecheck 18; adaptercheck 19/15,
corecheck 10/8, svcheck 6/1, consolecheck 11/1; apicheck 0 findings (39 files), selftest 10 of 10, refcheck ok.

## Open questions / hazards

- **Recorder follow-up (small, unassigned):** `Recorder_Forever.lua` stores a pre-pull aura's
  `remaining` as of the out-of-combat scan (up to 2 s before `t0`), not shifted to the pull. Fold
  into the next task that touches the recorder, or a one-item task: record the scan time and
  subtract `t0 - scanTime` when the pull starts; recordcheck assertion 10 checks it.

- **Version bump + TESTING section owed at the end of M3** (after T17): bump every Forever TOC to
  `1.0.0-alpha.5` (probecheck and consolecheck pin the version -- follow 8a1f451's pattern) and write
  TESTING §39 for the recorder, replay, validate and coach in game.
- **In-game checks owed for M3** (to go into a new `docs/TESTING.md` section with the next Forever
  build, once T16a makes a recording playable): `/st rec` lists a real pull; its CANCEL count
  matches the casts actually cancelled (STOP / SUCCEEDED order is UNKNOWN); the meter's own total
  after the pull. TESTING §38 is alpha.4 and does not carry the recorder.

- **The shared `.git` object store has 18 empty (corrupt) loose objects** (`git fsck`). They are
  reachable only from four old docs commits (fd6a540, ad94b2f, d35f41c, 47b9edf -- `git ls-tree -r`
  fails on them) and from branch `claude/combat-log-design-arch-ffb907`. HEAD's tree is readable.
  Not ours to repair (never touch `.git` internals); reported to the planner. Hazard: a new commit
  whose blob hash equals one of the empty objects would be silently corrupt, so after every commit
  run `git ls-tree -r HEAD` and `git archive HEAD` and check the export.
