# T56 -- Split `Verify.lua` into four files, a pure move (plan P12)

Status: **built** 2026-09-30 on branch `plan/P12` (base `fecaad4`), wave 4 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P12)

Review item A2 (`docs/review/2026-09-30-project-review.md`): `Verify.lua` (1435 lines) held five
concerns -- diagnostics, export, the regen instruments (the sole writer of `cdb.mp5`), the engine's
shipped self-tests and the coach commands -- so "what writes the measured mp5" was not findable and
the coach command could not be shared.

- Pure moves, names kept, no call changed: `Diagnostics_TBC.lua` (verify, snapshot, profile, export,
  calibrate), `Engine/RegenMeasure.lua` (fsrtest, regentest, spamtest, the `cdb.mp5` shape),
  `Engine/SimSelfTest.lua` (`RunSimRun`, the fixture replay), `Engine/ReviewCommands.lua`
  (`ValidationReport`, `RunCoach`, `RunCoachRun` -- their final home, TBC TOC only until P21).
- `RegenModel:MeasuredMp5` keeps its own bound and its once-only refusal message (untouched).
- TOC order preserved: the four lines replace `Verify.lua` (integrator).
- Tests: new `tools/verifycheck.lua` (tbc), a golden transcript captured on the parent before the
  first edit and equal after; equal counts for `simcheck`, `regencheck`, `reccheck`, `importcheck`,
  `restcheck`.

Owned files (section 4, wave 4): `Verify.lua` (deleted), `Diagnostics_TBC.lua`,
`Engine/RegenMeasure.lua`, `Engine/SimSelfTest.lua`, `Engine/ReviewCommands.lua`,
`tools/simcheck.lua`, `tools/regencheck.lua`, `tools/verifycheck.lua`. Nothing else was touched
(`tools/simcheck.lua` and `tools/regencheck.lua` needed no change: they call `MD:RunSimRun`,
`MD:RunSimReplay` and `MD:RunRegenTest` by name, and the names are kept).

## What was built

Two commits, in this order:

1. **`tools/verifycheck.lua`, the golden captured on `fecaad4`** with `Verify.lua` whole (13 ok there).
2. **The split.** `Verify.lua` deleted; its body cut at its three blank section separators
   (lines 478, 957, 1298) into:

| file | Verify.lua lines | what | header |
|---|---|---|---|
| `Diagnostics_TBC.lua` | 7-477 | `MD:RunVerify`, `MD:Snapshot`, `MD:Profile`, `MD:RunProfile`, `DumpRecording` (local), `MD:Export`, `MD:RunCalibrate`, `MD:RunExport` | the old file header (verify's part), plus where the rest went |
| `Engine/RegenMeasure.lua` | 479-956 | `/md fsrtest` (`MD:RunFSRTest` and its `UNIT_POWER_UPDATE` handler), `/md regentest` (`MD:ClearMeasuredMp5`, `StoreMeasuredMp5` -- the only writer of `cdb.mp5` and its shape --, `FinishRegenTest`, its power handler and `OnTick`, `MD:RunRegenTest`), `/md spamtest` (its two handlers, `OnTick`, `MD:RunSpamTest`) | names it the sole writer of `cdb.mp5`, and says `RegenModel:MeasuredMp5` keeps its own copy of the bound (section 6 of the plan) |
| `Engine/SimSelfTest.lua` | 958-1297 | `MD:RunSimRun` (with `SimTargets`, `Near`), `ReplayFixture` (local), `MD:RunSimReplay` | what `tools/simcheck.lua` reads back |
| `Engine/ReviewCommands.lua` | 1299-1435 | `MD:ValidationReport`, `MD:RunCoachRun`, `MD:RunCoach` | TBC only until P21 lists it on the Replay module |

Each file starts with its own header comment and `local _, MD = ...`, then the moved lines. Proof it
is a move and nothing else:

- **The bodies are byte-identical.** Verify.lua's lines 7-477, 479-956, 958-1297 and 1299-1435,
  concatenated, `cmp` equal to the four new files with their headers stripped, concatenated.
- **No local crossed a boundary.** `luac -l` on `Verify.lua` and on the four new files: the same 30
  globals read or written (`diff` empty). A helper used across a cut (`IsDrinking`, `Near`,
  `DumpRecording`, ...) would have shown up as a new global; none did.
- **Event registration order is kept.** The three `UNIT_POWER_UPDATE` handlers (fsrtest, regentest,
  spamtest), the spamtest `UNIT_SPELLCAST_SUCCEEDED` handler and the two `MD:OnTick` hooks register in
  the same relative order, at the same point in the TBC load (the four TOC lines sit where
  `Verify.lua` was, in the order above).
- `luac -p` passes on all four files.

### `tools/verifycheck.lua` (tbc, 13)

A scripted scene -- `tools/fakepull.lua`'s pull in the ring of 8, then a run of two pulls
(`RR:Start` / `RR:Stop`) -- and twelve commands through `SlashCmdList.SPELLTUNER`, each command's chat
output compared line for line with the golden embedded at the bottom of the file:

`verify` (32 lines), `profile` (46), `export` (258), `calibrate` (3), `fsrtest` (7, with a scripted
mana stream and the 15 s timer fired), `spamtest` (6, Rejuvenation chained to OOM with a Regrowth
mixed in), `simrun` (13), `simreplay fixture` (4), `simreplay 1` (19, the validation report),
`coach 1` (7, the refusal of a fight that does not replay), `coach 1 force` (33, a full card, the
frame-sliced search pumped to its end) and `coachrun 1` (12). One assertion per command plus one that
the golden has every command. The plan named six of these; the other six cover every function that
moved (the fsrtest and spamtest handlers had no test at all), so a file left out of the TOC fails
here by name (below).

What the suite sets so the golden holds on any machine, and nothing more: the stub's `date()` is read
in UTC (the export header and the coach card carry a time, and the stub's `date` uses the machine's
zone -- checked with `TZ=Asia/Tokyo`); `GetBuildInfo`, which the TBC stub lacks and `/md profile`'s
first line calls, answers a fixed build; `C_Timer.After` is replaced by a scheduler the suite fires on
the stub's clock (the stub's only collects callbacks, and P10 in this wave owns the stub's timers --
only calls through the global after the suite loads see it, which is fsrtest's). Before comparing, the
addon's version string is replaced by `{version}`, so a version bump is not a failure. The golden is
regenerated with `tools/run.sh tools/verifycheck.lua --golden` (paste the output over the table);
`--print` shows the transcript as chat would. Three consecutive runs and a run under another zone
gave the same transcript.

## Failing first

The suite is new and was captured on the parent, so "fails on the parent" is shown the other way
round -- it goes red on a change a user would see, and on a load list that loses a file:

```
(Diagnostics_TBC.lua: "vs live client" -> "vs the live client", reverted afterwards)
/md verify as on the parent                  FAIL - line 1 of 32 (golden 32):
      now:    "|cff9966ffSpellTuner:|r -- verify: static data vs the live client --"
      golden: "|cff9966ffSpellTuner:|r -- verify: static data vs live client --"
12 ok, 1 failed   (rc 1)

(SpellTuner_TBC.toc without its Engine\RegenMeasure.lua line)
/md fsrtest as on the parent                 FAIL - line 1 of 0 (golden 7):
/md spamtest as on the parent                FAIL - line 1 of 0 (golden 6):
11 ok, 2 failed   (rc 1)
```

And without the integrator's TOC lines the branch does not load on the TBC harness at all
(`load Verify.lua: cannot open`), which is the expected state until they land.

## Suites

Every suite in `docs/TOOLS.md` section 1, exit codes checked, on `fecaad4` + `verifycheck` (before) and
on this branch **with the four TOC lines below applied in the working tree** (after). Identical,
except textcheck's file count (one file became four):

| suite | before | after |
|---|---|---|
| `simcheck` | 13 | 13 |
| `regencheck` | 27 | 27 |
| `reccheck` | 63 | 63 |
| `importcheck` | 20 | 20 |
| `restcheck` | 51 | 51 |
| `verifycheck` (new) | 13 | 13 |
| `replaycheck` / `replayui` / `runcheck` / `reviewui` | 82 / 103 / 81 / 48 | same |
| `navui` / `dashui` / `simwindow` / `solvercheck` / `timeline` | 35 / 64 / 8 / 84 / 27 | same |
| `spelltip` / `costcheck` / `practice` / `practiceui` / `migrate` | 48 / 3 / 81 / 52 / 7 | same |
| `probecheck` / `forevercheck` / `modulecheck` / `kitcheck` / `recordcheck` | 87 / 16 / 14 / 7 / 29 | same |
| `scenariocheck` / `gatecheck` / `replayforever` / `reviewforever` / `coachforever` | 14 / 9 / 15 / 13 / 20 | same |
| `practiceforever` / `bindscheck` / `parsecheck` / `bookcheck` / `tipcheck` | 27 / 6 / 15 / 21 / 37 | same |
| `clockcheck` / `spellsui` / `measurecheck` / `releasecheck` | 23 / 48 / 30 / 16 | same |
| `themecheck` / `tabscheck` / `wincheck` | 23 / 24 / 55 | same |
| `adaptercheck` forever / tbc | 23 / 16 | same |
| `corecheck` forever / tbc | 13 / 13 | same |
| `svcheck` forever / tbc | 6 / 1 | same |
| `consolecheck` forever / tbc | 17 / 1 | same |
| `apicheck` / `--selftest` | 0 findings (8 Forever TOCs, 48 files, 46 globals) / 10 of 10 | same (no Forever TOC lists the new files) |
| `textcheck` / `--selftest` | 0 findings, 9 TOCs, 82 files / 2 of 2 | 0 findings, 9 TOCs, **85** files / 2 of 2 |
| `refcheck --selftest` | 2 of 2 | 2 of 2 |

Every suite exits 0 and ends `N ok, 0 failed`.

## Integrator lines

**`SpellTuner_TBC.toc`** -- the last line `Verify.lua` is replaced by these four, in this order, at
the same position (after `Integrations\ElvUIDatatext.lua`):

```
Diagnostics_TBC.lua
Engine\RegenMeasure.lua
Engine\SimSelfTest.lua
Engine\ReviewCommands.lua
```

No other TOC changes (no Forever TOC and no module TOC lists any of them; P21 adds
`Engine\ReviewCommands.lua` to the Replay module).

**CLAUDE.md**, the files table:

- Replace the `Verify.lua` row with four rows:
  - `| `Diagnostics_TBC.lua` | `MD:Snapshot()` (every model input, shared), `/md verify` (static data vs live client), `/md profile` (snapshot + costs + clock + settings into the copy popup), `/md export`, `/md calibrate`. TBC TOC only. **T56 (P12, review A2):** moved out of `Verify.lua` unchanged, with the next three |`
  - `| `Engine/RegenMeasure.lua` | The regen instruments: `/md fsrtest`, `/md regentest`, `/md spamtest`. **The only writer of `cdb.mp5`** (the measured leftover `RM:MeasuredMp5()` reads) and its shape; `RegenModel:MeasuredMp5` keeps its own copy of the "leftover <= reported" bound and its once-only refusal (sharing it is a later change, `docs/PLAN-refactor-ux.md` section 6). TBC TOC only (T56) |`
  - `| `Engine/SimSelfTest.lua` | The engine's shipped self-tests: `/md simrun` (`MD:RunSimRun`) and `/md simreplay` (the BF-1 fixture, or one recording's validation report); `tools/simcheck.lua` reads their verdicts back. TBC TOC only (T56) |`
  - `| `Engine/ReviewCommands.lua` | The review commands: `MD:ValidationReport`, `/md coach` (`MD:RunCoach`), `/md coachrun` (`MD:RunCoachRun`). TBC TOC only until P21 lists it on the Replay module (T56) |`
- `UI/Dashboard_Review.lua` row: `MD.RunExport` (TBC's `Verify.lua`) -> `MD.RunExport` (TBC's `Diagnostics_TBC.lua`).
- `tools/` row, after the `tools/replayui.lua` sentence: `**`tools/verifycheck.lua`** (T56, tbc) holds a golden transcript of twelve TBC commands (`verify`, `profile`, `export`, `calibrate`, `fsrtest`, `spamtest`, `simrun`, `simreplay fixture` / `1`, `coach 1` / `1 force`, `coachrun 1`) captured before `Verify.lua` was split; `--golden` regenerates it`.

**docs/TOOLS.md** section 1:

- New row after `costcheck.lua`: `| `verifycheck.lua` | **the TBC diagnostics, word for word** (T56, tbc, 13): a scripted pull in the ring of 8 and a two-pull run, then `/md verify`, `profile`, `export`, `calibrate`, `fsrtest` (a scripted mana stream, the 15 s timer fired), `spamtest` (chained to OOM, one other spell mixed in), `simrun`, `simreplay fixture`, `simreplay 1`, `coach 1`, `coach 1 force` and `coachrun 1`, each command's chat output equal line for line to the golden captured on `fecaad4` before `Verify.lua` was split (`date()` in UTC, a fixed `GetBuildInfo`, the version as `{version}`). `--print` shows the transcript, `--golden` prints a new golden to paste over the table |`
- The loop: add `verifycheck` after `costcheck` on the second line.

**tools/data/expected-counts.json** (when P13 creates it): `verifycheck` 13 (tbc). Every other count
unchanged.

**docs/TESTING.md** (after wave 4, TBC): one smoke line -- with the new TOC installed, `/md verify`,
`/md simrun`, `/md regentest` (it answers "you are at full mana" or starts) and `/md coach` each
answer in chat; a silent command means its file is missing from the TOC.

**docs/DECISIONS.md**: none (no behaviour changes). **docs/HISTORY.md**: the integrator's wave entry.

## Deviations

- **The branch does not load on the TBC harness until the TOC lines land.** The TOC is
  integrator-owned, so the committed `SpellTuner_TBC.toc` still lists the deleted `Verify.lua`; every
  TBC suite errors on `load Verify.lua` on this branch alone. The suites above were run with the four
  lines applied in the working tree and then reverted.
- **`verifycheck` runs twelve commands, not six**, and stubs three things (UTC `date`, `GetBuildInfo`,
  `C_Timer.After`) for itself -- above. It does not edit `tools/wowstub.lua` (P10's this wave).
- **A P10 interaction to watch.** If P10's stub changes what any of these commands print (its timers,
  geometry and focus knobs should not), `verifycheck` goes red after both are merged without P12 being
  at fault. To tell which: restore `Verify.lua` from `fecaad4` and its TOC line on the merged tree and
  run `tools/run.sh tools/verifycheck.lua --golden`; if that output equals the split's, the move is
  still pure and the golden is re-captured from it.
- **`tools/simcheck.lua` and `tools/regencheck.lua` are unchanged.** They were owned in case they
  named the file; they call the moved functions by name and needed nothing.
- **Comments elsewhere still say `Verify.lua`**, in files this task does not own:
  `Engine/RegenModel.lua` (lines 98 and 104, the regentest that stores the leftover -- now
  `Engine/RegenMeasure.lua`), `UI/Dashboard_Review.lua:576` (`MD:RunExport` -- now
  `Diagnostics_TBC.lua`), `Modules/SpellTuner_Replay/Commands_Forever.lua` (lines 3, 89, 122, 151, 175,
  which P21 rewrites) and `tools/reviewforever.lua:276`. Each can be updated by the next task that
  owns the file; the historical design docs keep the old name.
