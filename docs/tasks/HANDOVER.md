# Lead handover -- WoW: Forever port

Rewritten by the lead after every commit and every hand-out. A successor continues from this file
alone. Worktree: `/home/penek/projects/addons/SpellTuner/.claude/worktrees/manademon-folder-continue-41eabc`,
branch `claude/manademon-folder-continue-41eabc`.

Last updated: 2026-09-28, lead run 2, at the T13e commit.

## Committed

| hash | what |
|---|---|
| (the commit carrying this revision) | T13e: probe asks whether a StatusBar hands a secret back (3 `bar` lines + `UnitHealthMissing(party1)`); probecheck 73. Lead added the `read skipped` guard |
| bdbc40a | T13c: module plumbing -- Module.lua proxy, Ready.lua handshake, root-resolved shared files in release/stub/apicheck; modulecheck 14, apicheck selftest 8 |
| 2ba2346 | docs: gate 8 one-sided until the HEAL amount is known (planner addendum, confirmed) |
| da7dff2 | docs: M2 re-check in roadmap/file table/tools/history; M3/M4 tasks written |
| 4303c71 | docs: TESTING §38 (next testing round), T13e written |
| 8a1f451 | alpha.4 bump. **NB:** it also carried T13c's module-TOC hunk (`Ready.lua` listed) before `Ready.lua` existed -- HEAD's release build is broken until T13c lands |
| b7e55b7 | T12b. **NB:** it also carried T13c's stub hunk (`ResolveModuleFile`, one table per addon load) |

## In the tree, not committed

Nothing.

## Next, in order

T13a -> T15 -> T13 -> T13d -> T14 -> T16a -> T16b -> T17 -> T18 -> T19.
Re-check each task's baselines against the suite run at the commit before handing it out.
Suite loop: `docs/TOOLS.md` §1 plus `apicheck`, `apicheck --selftest`, `refcheck --selftest`.

## Baselines (at the last commit)

TBC sixteen: reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56,
regencheck 27, simwindow 8, solvercheck 70, timeline 27, spelltip 48, practice 74, practiceui 49,
migrate 7, simcheck PASS. Forever: probecheck 73, forevercheck 13, modulecheck 14, parsecheck 11,
bookcheck 15, tipcheck 14, clockcheck 15, spellsui 15, measurecheck 18; adaptercheck 19/15,
corecheck 10/8, svcheck 6/1, consolecheck 11/1; apicheck 0 findings, selftest 8 of 8, refcheck ok.

## Open questions / hazards

- **The shared `.git` object store has 18 empty (corrupt) loose objects** (`git fsck`). They are
  reachable only from four old docs commits (fd6a540, ad94b2f, d35f41c, 47b9edf -- `git ls-tree -r`
  fails on them) and from branch `claude/combat-log-design-arch-ffb907`. HEAD's tree is readable.
  Not ours to repair (never touch `.git` internals); reported to the planner. Hazard: a new commit
  whose blob hash equals one of the empty objects would be silently corrupt, so after every commit
  run `git ls-tree -r HEAD` and `git archive HEAD` and check the export.
