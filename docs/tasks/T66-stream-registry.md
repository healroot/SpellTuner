# T66 -- Stream registry and v3 constants (plan P22)

Status: **built** 2026-09-30 on branch `plan/P22` (base `46c09d9`), wave 9 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. **The branch needs its two TOC lines (below)**:
`Recorder_Forever.lua` now reads `MD.StreamV3`, which the new `Stream_Forever.lua` publishes, so
without the lines the Recorder module fails to load and every Forever suite that switches a module on
fails (13 runs: `coachforever`, `defaultscheck/forever`, `gatecheck`, `importcheck`, `modulecheck`,
`practiceforever`, `recordcheck`, `recordingscheck/forever`, `replayforever`, `reviewforever`,
`scenariocheck`, `svcheck/forever`, `wincheck`) -- checked on the committed tree. Every TBC suite
loads and passes without them. The TOC lines were applied in the working tree only, to run the suites,
and reverted before the commit (the T56 / T63 / T65 pattern).

## The task (docs/PLAN-refactor-ux.md section 5, P22)

Review item (`docs/review/2026-09-30-project-review.md`): **A18** (the rest; T46 took the dropped
`others` argument) -- "the v2/v3 pipeline is wired by monkey-patching": `Scenario_Forever.lua` and
`Gates_Forever.lua` replaced `SM.ScenarioFromRecording` / `SM.Validate` with wrappers dispatching on
`rec.v == 3`; gates 1, 2, 4, 7 and `Threshold` / `MeanMax` were copied (~120 lines); `ReconstructHp`'s
grid loop was duplicated inside `ScenarioV3`; `AttributeHeals` ran twice per validation (scenario and
gate 8); the v3 kind `HEAL = 15` and `FAMILY_KEY` were hand-copied into four or five module files with
nothing asserting `HEAL` never collides with `SM.K`; SimPlanner and ReplayWindow tested `rec.v == 3` by
name.

- `SM.scenarioBuilders[v]` / `SM.validators[v]` in SimModel (v2 its own; an unknown version raises);
  `Scenario_Forever` and `Gates_Forever` register v3 instead of wrapping.
- `SM.Threshold` / `SM.MeanMax` exported, Gates' copies deleted; gates 1, 2, 4, 7 shared as primitives.
- One `ReconstructHp` (the copy inside `ScenarioV3` goes); the attribution carried on the scenario so
  gate 8 does not attribute twice.
- `Modules/SpellTuner_Recorder/Stream_Forever.lua` publishes `MD.StreamV3 = { K, FAMILY_KEY }`, used by
  the recorder, the scenario, the gates and `ReviewCommands`' casts-and-mana count; the Replay module
  asserts at load that no `SM.K` value equals `StreamV3.K.HEAL`.
- SimPlanner and ReplayWindow stop testing `rec.v == 3` (a scenario flag instead).
- Tests: equal counts and outputs `gatecheck`, `scenariocheck`, `simcheck`, `replayforever`,
  `coachforever`, `importcheck`, `recordcheck`; new: a recording with `v = 9` raises a named error
  (`gatecheck` +1).
- TBC: SimModel is shared; dispatch by table with the v2 default; byte-identical outputs.

Owned files (section 4, wave 9): `Engine/SimModel.lua`, `Replay/Scenario_Forever.lua`,
`Replay/Gates_Forever.lua`, new `Recorder/Stream_Forever.lua`, `Recorder/Recorder_Forever.lua`,
`Engine/ReviewCommands.lua`, `Engine/SimPlanner.lua`, `UI/ReplayWindow.lua`, `tools/gatecheck.lua`,
`tools/scenariocheck.lua`, `tools/recordcheck.lua`. Committed: all but the last two, which pass
unchanged (same counts, same output), plus this file.

## What was built

| file | change |
|---|---|
| `Engine/SimModel.lua` | The v2 builder and validator become locals (`ScenarioV2`, `ValidateV2`), registered in **`SM.scenarioBuilders`** and **`SM.validators`** under 1 and 2 (a recording with no `v` reads as 2, so every TBC recording -- v1 like the BF-1 fixture, v2, practice -- takes the road it always took). `SM.ScenarioFromRecording(rec, kit, ...)` and `SM:Validate(rec, kit, ...)` pick the function for `SM.StreamVersion(rec)` and forward every argument; a version nobody registered raises `SimModel: no scenario builder for a v9 recording (known: 1, 2, 3)` / `SimModel: no validator for ...`, at the caller. A third registry, **`SM.healthReconstructors[v]`**, answers **`SM.RecordedHealth(rec)`**: `rec.hp`, else the version's reconstruction, else nil. **`SM.Threshold`**, **`SM.MeanMax`** exported. The shared gates as primitives: **`SM.NewValidation(rec, sc)`** (the table and its `Gate` adder; energize read from the scenario, which a v3 scenario carries as 0 / not assumed), **`SM.GateMana(Gate, r, rec, note)`** (gates 1+2, `note` appended to each text), **`SM.GateDeath(Gate, rec)`**, **`SM.OwnSpend(rec, ownCast)`**, **`SM.GateSpend(Gate, rec, sc, kit, spend, why)`**. `ValidateV2` calls them in the same order with the same texts and provenance. |
| `Modules/SpellTuner_Recorder/Stream_Forever.lua` (new) | `MD.StreamV3 = { V = 3, K = { DMG = 1, OWNCAST = 3, CASTSTART = 6, CANCEL = 7, DIED = 9, HEAL = 15 }, FAMILY_KEY = { ... } }` -- the numbers and names that were hand-copied. Pure. |
| `Modules/SpellTuner_Recorder/Recorder_Forever.lua` | `K`, `FAMILY_KEY` and the stream's `v` from `MD.StreamV3`; its two copies and their "not guaranteed loaded" notes gone. |
| `Modules/SpellTuner_Replay/Scenario_Forever.lua` | `V3 = MD.StreamV3.K`, with two load-time assertions: no `SM.K` value equals `HEAL` (named error `StreamV3.K.HEAL (15) collides with SM.K.<name>`), and the five kinds a v3 stream shares with `SM.K` keep its numbers (`SM.DangerHitFromOthers` reads a v3 stream's damage by `SM.K.DMG`). `ReconstructHp` is the one grid: `ScenarioV3` reads its max, grid and sizing (`hits`, `hitOrHealed` now come back with it) instead of computing `SizeRec` + `ChooseMaxes` + a second grid loop. The scenario carries **`ownHeals`** (the attribution's own set, beside `attribution`), **`reconstructed = true`**, and `recordedHp.max` (so it is `rec.hp`'s shape). `PartyMaxFromOthers` reads `StreamV3.V`. The wrapper is gone: `SM.scenarioBuilders[3]` and `SM.healthReconstructors[3]` (`SM.RecordedHp`) are registered. |
| `Modules/SpellTuner_Replay/Gates_Forever.lua` | 327 -> 237 lines. Its `V3_HEAL`, `Threshold`, `MeanMax` copies gone (`SM.Threshold`, `SM.MeanMax`); gates 1+2 `SM.GateMana(Gate, r, rec, " (modelled pool)")`, 4 `SM.GateDeath`, 7 `SM.OwnSpend(rec, V3.OWNCAST)` + `SM.GateSpend(..., "book classification (Forever)")`; gate 3 counts damage by `V3.DMG`; gate 8 reads `sc.ownHeals` / `sc.attribution` instead of calling `SM.AttributeHeals` again. `SM.ValidateV3(rec, kit)` (a plain function now; nothing called it as a method but the wrapper) is `SM.validators[3]`; the wrapper is gone. |
| `Engine/ReviewCommands.lua` | `CastsAndMana` counts a v3 stream's casts by `MD.StreamV3.K.OWNCAST` when the stream's `v` is `MD.StreamV3.V`, read at call time (absent on TBC, where no v3 stream exists: a v2 stream without the counters reads 0 as before). |
| `Engine/SimPlanner.lua` | `SP.Replay`: the ticks come from `scenario.recordedHp` when the scenario says `reconstructed` (it used to rebuild them with `SM.RecordedHp(rec)` after testing `rec.v == 3`; the same numbers -- same recording, same `others`); `ticks.reconstructed` from the same flag. `SP.FromRecordings` (no scenario there) reads `SM.RecordedHealth(rec)`. |
| `UI/ReplayWindow.lua` | The "health reconstructed from UNIT_COMBAT" line shows when `rp.scenario.reconstructed`, not when `rec.v == 3`. |
| `tools/gatecheck.lua` | forever 9 -> **11**: `v = 9` raises a named error through `SM.ScenarioFromRecording` and `SM:Validate`; one validation calls `SM.AttributeHeals` once and gate 8 still reads it. |

`rec.v == 3` / `V3_*` / a literal `15` for a kind no longer appear in any owned file. `Kit_Forever.lua`
keeps its own `FAMILY_KEY` (not owned in wave 9; see Deviations).

## Tests first

On the parent (`46c09d9`) with only the two new assertions added:

```
tools/run.sh tools/gatecheck.lua
a recording of an unknown version (v = 9) raises a named error (T66)          FAIL - scenario: true table: 0x56efca511850 ; validate: true table: 0x56efca5141b0
one validation attributes the heals once, and gate 8 still reads them (T66)   FAIL - calls=2 gate=own 10 heals paired with your casts, foreign 3; paired total 144 vs meter 400 (64% off, limit 10%); only a shortfall is checked until a heal amount is known to be effective
9 ok, 2 failed
```

(The parent read a `v = 9` recording as a v2 stream and returned a scenario and a validation.)

On the branch (TOC lines applied): `gatecheck` 11 ok, 0 failed:

```
a recording of an unknown version (v = 9) raises a named error (T66)   ok - scenario: false SimModel: no scenario builder for a v9 recording (known: 1, 2, 3) ; validate: false SimModel: no validator for a v9 recording (known: 1, 2, 3)
one validation attributes the heals once, and gate 8 still reads them (T66)   ok - calls=1 ...
```

**Mutations** (each applied alone, then restored):

- gate 8 calling `SM.AttributeHeals(rec, kit)` again instead of reading the scenario's: `gatecheck`
  10 ok, 1 failed (`calls=2`).
- `Road` falling back to the v2 road for an unknown version (`registry[v] or registry[2]`):
  `gatecheck` 10 ok, 1 failed (`scenario: true table ...`).

## Suites (`make check` = `tools/check.sh`, exit codes and footers checked)

Before: `46c09d9`, 66 runs, all passed. After: this branch with the two TOC lines applied in the working
tree, 66 runs, all passed. Every count equal except `gatecheck`:

| suite | before | after |
|---|---|---|
| `gatecheck/forever` | 9 | **11** |
| `scenariocheck/forever` / `recordcheck/forever` / `replayforever/forever` / `coachforever/forever` / `reviewforever/forever` | 14 / 31 / 15 / 21 / 13 | same |
| `importcheck` / `kitcheck/forever` / `modulecheck/forever` / `defaultscheck/forever` / `practiceforever/forever` | 21 / 11 / 19 / 52 / 28 | same |
| `simcheck/tbc` / `replaycheck/tbc` / `replayui/tbc` / `reviewui/tbc` / `solvercheck/tbc` / `restcheck/tbc` / `reccheck/tbc` / `runcheck/tbc` / `verifycheck/tbc` / `defaultscheck/tbc` | 13 / 82 / 103 / 49 / 84 / 51 / 63 / 81 / 14 / 48 | same |
| every other suite in `tools/data/expected-counts.json` | as expected | same |
| `apicheck` | 0 findings, 8 Forever TOCs, **51** files, 47 globals | 0 findings, 8 Forever TOCs, **52** files, 47 globals |
| `textcheck` | 0 findings, 9 TOCs, **87** files | 0 findings, 9 TOCs, **88** files |
| selftests (`lib/t`, apicheck, textcheck, refcheck), harness skip, reproduce / strategies smoke | pass | pass |

**Outputs.** Every suite's saved output (`tools/.lua/check/*.out`) before and after, compared with
table addresses, milliseconds and frame counts normalised: identical except `gatecheck`'s two new
lines and footer, the file counts above, and the `[sim] search N evaluations` debug lines in
`replayui` / `reviewui`, which are frame-sliced on `debugprofilestop()` and differ between two runs of
the same tree (checked: two runs of `replayui` on this branch print 17/17/35/35/44/44 and
19/16/37/37/44/44). `simcheck`, `importcheck`, `scenariocheck`, `recordcheck`, `replayforever`,
`coachforever` byte-identical after that normalisation.

## TBC

No behaviour change. Every TBC recording is v1, v2 or carries no `v`, and all three take the v2 road,
whose builder and validator are the same code with the shared gates factored out (same order, same
texts, same provenance); `replayui`, `reviewui`, `simcheck`, `replaycheck`, `solvercheck`, `restcheck`,
`reccheck`, `runcheck`, `verifycheck`, `dashui` outputs unchanged. The one new behaviour -- a recording
of a version nobody registered is refused by name rather than read as a v2 stream -- cannot be reached
by a TBC recording.

## Integrator lines

**`Modules/SpellTuner_Recorder/SpellTuner_Recorder_Mainline.toc`** and
**`Modules/SpellTuner_Recorder/SpellTuner_Recorder.toc`** (identical) -- one new line right before
`Recorder_Forever.lua`, after `Module.lua` and its blank line:

```
Module.lua

Stream_Forever.lua
Recorder_Forever.lua

Ready.lua
```

(After `Module.lua`, which points the module's table at SpellTuner's `MD`; before `Recorder_Forever.lua`,
which reads `MD.StreamV3` at load. The Replay module needs no line: it depends on the Recorder module,
so `MD.StreamV3` is published before `Scenario_Forever.lua` runs.) No other TOC changes.

**CLAUDE.md**, the files table:

- `Engine/SimModel.lua` row, append: ` **T66 (P22, review A18):** the roads are registries keyed by the stream's version -- `SM.scenarioBuilders[v]`, `SM.validators[v]`, `SM.healthReconstructors[v]` (behind `SM.RecordedHealth(rec)`); v1, v2 and a recording with no `v` take the v2 road, the Replay module registers v3, and a version nobody registered raises a named error. `SM.Threshold`, `SM.MeanMax` and the gates both roads share (`SM.NewValidation`, `SM.GateMana`, `SM.GateDeath`, `SM.OwnSpend`, `SM.GateSpend`) are exported for `Gates_Forever.lua``
- `Modules/<Name>/` row: replace ` **T46:** the Replay module's `ScenarioFromRecording` / `Validate` wrappers forward every argument (A18)` with ` **T46:** every argument after `kit` reaches the v3 road (A18). **T66 (P22):** `SpellTuner_Recorder` lists `Stream_Forever.lua` first -- `MD.StreamV3` (`V`, the v3 kinds `K`, `FAMILY_KEY`), the one copy the recorder, `Scenario_Forever.lua`, `Gates_Forever.lua` and `Engine/ReviewCommands.lua` read; `Scenario_Forever.lua` asserts at load that `K.HEAL` equals no `SM.K` value and that the shared kinds keep `SM.K`'s numbers, registers the v3 builder instead of wrapping, reads its health grid from its one `ReconstructHp`, and marks its scenario `reconstructed` with `ownHeals` beside `attribution`; `Gates_Forever.lua` registers `SM.ValidateV3` and reads gates 1, 2, 4, 7 from `Engine/SimModel.lua`, gate 8 from the scenario's attribution`
- In the same row, `**T14:** and `Gates_Forever.lua` -- `SM:ValidateV3`, the eight gates` -> `**T14:** and `Gates_Forever.lua` -- `SM.ValidateV3`, the eight gates`.

**docs/TOOLS.md** section 1:

- `gatecheck.lua` row: `Since **the 2026-09-29 review** (9): an excluded target's line says `max estimated` (R27)` -> append: ` Since **T66** (11): a recording of an unknown version (`v = 9`) raises a named error through `SM.ScenarioFromRecording` and `SM:Validate`; one validation attributes the heals once (gate 8 reads the scenario's)`.

**tools/data/expected-counts.json**: `"gatecheck/forever": 11`. Every other count unchanged.

**docs/DECISIONS.md** (one paragraph, under the refactor's entries):

> ## A stream's version picks its road (2026-09-30, T66)
>
> **A recording is replayed and validated by the road registered for its version (T66, P22, review
> A18).** `Engine/SimModel.lua` keeps one registry per question (`SM.scenarioBuilders`,
> `SM.validators`, `SM.healthReconstructors`); v1, v2 and a recording without a version take the v2
> road, the Replay module registers v3. A version nobody registered is refused with a named error
> instead of being read as a v2 stream, because the same numbers mean other things in another version
> (a v3 heal is kind 15, which the engine's own kinds do not have). The v3 constants live once, in the
> Recorder module's `Stream_Forever.lua`, and the Replay module refuses to load if a v3 heal would
> collide with an engine kind. No TBC recording changes road; nothing TBC prints moved.

## Deviations

1. **`gatecheck` +2, not +1.** The plan's one new assertion (`v = 9` raises) is there; the second pins
   the attribution-once change (a validation calls `SM.AttributeHeals` once, gate 8 still reads it) so
   that part of A18 can go red too (the first mutation above). `expected-counts.json` needs 11.
2. **A third registry, `SM.healthReconstructors` behind `SM.RecordedHealth(rec)`.** `SP.FromRecordings`
   tests `rec.v == 3` on a recording it has no scenario for (it buckets damage from the raw stream), so
   "a scenario flag instead" cannot reach it without building a scenario per recording. It asks the
   registry instead; `SP.Replay` and the replay window do read the scenario's `reconstructed` flag.
3. **`StreamV3.V`** is published beside `K` and `FAMILY_KEY` (the plan names two fields) so the recorder
   stamps and the readers test the version from the same place.
4. **The load-time assertion also checks the five shared kinds** (`DMG`, `OWNCAST`, `CASTSTART`,
   `CANCEL`, `DIED`) equal `SM.K`'s, not only that `HEAL` collides with none: `SM.DangerHitFromOthers`
   and gate 3 used to read a v3 stream by `SM.K`'s numbers, and a renumbered v3 kind would have broken
   them silently.
5. **`Kit_Forever.lua` keeps its own `FAMILY_KEY`.** It is P15/P19's file and not in wave 9's table;
   switching it to `MD.StreamV3.FAMILY_KEY` is a one-line follow-up for the next task that owns it (the
   Replay module always has `MD.StreamV3`).
6. **`SM:ValidateV3` is now `SM.ValidateV3(rec, kit)`**, a plain function (the registry calls
   `fn(rec, kit, ...)`); nothing but the removed wrapper called it. `sc.recordedHp` gains `max` (the
   reconstruction already computed it) so `SP.Replay` reads it in `rec.hp`'s shape.
7. **`tools/scenariocheck.lua` and `tools/recordcheck.lua` are unedited**: both pass with equal counts
   and output ("v2 takes the old road" still holds: a v2 scenario has no `recordedHp`, no
   `attribution`, and now no `reconstructed` or `ownHeals`).
