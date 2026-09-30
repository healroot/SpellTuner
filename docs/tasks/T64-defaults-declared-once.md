# T64 -- Defaults declared once (plan P20)

Status: **built** 2026-09-30 on branch `plan/P20` (base `3261856`), wave 8 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. No TOC line is needed: no shipped file is new.

## The task (docs/PLAN-refactor-ux.md section 5, P20)

Review item (`docs/review/2026-09-30-project-review.md`): **A3** (the consumers; P11/T55 built the
mechanism, `MD:RegisterDefaults` and `MD:Setting` in `Core.lua`) -- "settings defaults live in three or
four places; a LoadOnDemand module cannot declare its own": `Core_TBC.lua`'s `DEFAULTS`,
`Commands_Forever.lua`'s `REPLAY_DEFAULTS` copy, `SM.GATES[...].default`, inline `MD.db.simFullHp or
0.85` / `simFloor or 0.30` / `replaySpeed or 1` in the options pane, the replay window and the engine,
two gate defaults that exist only in `Gates_Forever`, and "`Core_Forever.lua` DEFAULTS lacks keys
shared files read".

- `Engine/SimModel.lua` registers every key it, the planner and the replay window read; `SM.GATES`
  keeps the setting name and its `default` reads the registry. `Gates_Forever.lua` registers its two.
- The inline literals go (`SimModel.lua:228, 229, 306, 1398, 1670`, `SimPlanner.lua:891, 1007, 1838`,
  `ReplayWindow.lua:1367, 1693`, `Options_General.lua:289-290` in the plan's numbering), all through
  `MD:Setting(key)`.
- `Core_TBC.lua`'s `DEFAULTS` loses the registered keys (values identical); `Core_Forever.lua` needs no
  hand-copied keys. `REPLAY_DEFAULTS` moves in P21 (it owns `Commands_Forever.lua` this wave).
- Tests: new `tools/defaultscheck.lua`, both flavours. Equal counts: `simcheck`, `solvercheck`,
  `coachforever`, `gatecheck`, `replayui`, `simwindow`.
- TBC: no behaviour change (same values, one place).

Owned files (section 4, wave 8): `Core_TBC.lua`, `Core_Forever.lua`, `Engine/SimModel.lua`,
`Engine/SimPlanner.lua`, `Replay/Gates_Forever.lua`, `UI/ReplayWindow.lua`, `UI/Options_General.lua`,
new `tools/defaultscheck.lua`. **Plus one data file outside the table**, `tools/data/import-forever-sv.lua`
(see Deviations).

## What was built

| file | change |
|---|---|
| `Engine/SimModel.lua` | At the top, `MD:RegisterDefaults{ simFullHp = 0.85, simFloor = 0.30, simDangerHits = 1, simReaction = 0.5, simMinActivity = 0, simAllowRebinds = false, simBigHit = 0.15, replaySpeed = 1, replayTicks = true, replayNextPull = true, replayAutoCoach = true }`, each with the provenance comment it had in `Core_TBC.lua`. Beside the gates, `MD:RegisterDefaults{ simGateManaMean = 0.02, simGateManaMax = 0.05, simGateHpMean = 0.05, simGateHpMax = 0.15, simForeignShare = 0.25 }`. **`SM.Gate(setting, why)`** builds a gate: `{ setting, why }` with a metatable whose `default` reads `MD.DEFAULTS[setting]` (which `RegisterDefaults` fills on both lines) -- no stored copy. `Threshold` is `MD:Setting(g.setting), g.why`. The seven reads (`floor`, `fullAt`, `S.dangerHits`, `reaction`, `dangerHits`, the scenario's `floor`, `lowLine`) are `MD:Setting(key)`. |
| `Engine/SimPlanner.lua` | `fullHp`, `reaction`, the big-hit threshold and `simAllowRebinds` read `MD:Setting`. |
| `Modules/SpellTuner_Replay/Gates_Forever.lua` | `MD:RegisterDefaults{ simGateMeter = 0.10, simGateAttrib = 0.10 }`; `meterOwn` / `attributed` built with `SM.Gate` (same setting names and `why` texts); `Threshold` is `MD:Setting`. |
| `UI/ReplayWindow.lua` | The big-hit marker (`simBigHit`) and the opening speed (`replaySpeed`) read `MD:Setting`. |
| `UI/Options_General.lua` | The two sliders' `SetValue` read `MD:Setting("simFullHp")` / `("simFloor")`; the pane's comment names where the defaults now live. |
| `Core_TBC.lua` | `DEFAULTS` loses the 16 keys (the gate block with its heading, `simAllowRebinds`, the four `replay*`, `simBigHit`, and `simFullHp` .. `simMinActivity`), replaced by a three-line comment pointing at `Engine/SimModel.lua`. `simUtilityPerFight = nil` stays (derived, owned by `Data/SimPresets.lua`; a nil default registers nothing). |
| `Core_Forever.lua` | A comment over `DEFAULTS`: a module's settings are registered by the file that reads them, so no key is hand-copied. **Two keys added**, `muted = false` and `effectiveMode = false`: the new suite's source scan found them read on the Forever TOC with no default (`Core.lua`'s `MD:Alert`, shared `UI/Dashboard_Rows.lua`'s Effective mode) -- A3's "`Core_Forever.lua` DEFAULTS lacks keys shared files read". Both read `false` as they read `nil` before. |
| `tools/defaultscheck.lua` | New, `HARNESS_FLAVOUR = { "tbc", "forever" }`, on `tools/lib/t.lua`. Below. |
| `tools/data/import-forever-sv.lua` | Rebuilt with `tools/run.sh tools/importfixture.lua`: four lines added, `effectiveMode = false`, `muted = false`, `simGateAttrib = 0.1`, `simGateMeter = 0.1` (the Forever `SpellTunerDB` now carries them). Nothing else moved. |

### What a player sees

Nothing on TBC: the same keys with the same values reach `SpellTunerDB` (the registry back-fills them
at `InitDB`, where `Core_TBC.lua`'s table did), and every reader answers the same number. On Forever,
`SpellTunerDB` gains `simGateMeter`, `simGateAttrib`, `muted` and `effectiveMode` with the values the
code already used.

### `tools/defaultscheck.lua` (tbc 48, forever 52)

Loads everything first: on tbc every `UI/` file of `SpellTuner_TBC.toc` the harness skips
(`Integrations/` apart, it needs ElvUI), with `UI.CreateSlider` watched so the options' sliders can be
read; on forever the three modules (`MD:SetModule("SpellTuner_Practice", true)`).

1. **Every registered default equals the literal it replaced** -- the table `OLD` (copied from
   `3261856`: `Core_TBC.lua`'s `DEFAULTS`, `REPLAY_DEFAULTS`, the inline fallbacks, the gates'
   defaults), per key: `MD.DEFAULTS[key]`, the harness's fresh `MD.db[key]` and `MD:Setting(key)` with
   the key removed from the db. Plus: a second default for `simFullHp` (0.9) is refused, the same one
   again is accepted. (tbc 16 keys, forever 18.)
2. **The gates read their defaults from the registry** -- each gate's `setting`, `default`, `why`, and
   `rawget(g, "default") == nil`; `manaMean.default` follows a change to `MD.DEFAULTS.simGateManaMean`.
3. **Each key is declared once, by its owner** -- a scan of every file on the flavour's TOCs (a module
   entry resolved to the module folder, else the repository, as T13c does) for `key = ...` table fields:
   each key in `Engine/SimModel.lua` only (`simGateMeter` / `simGateAttrib` in `Gates_Forever.lua`);
   tbc: `Core_TBC.lua` carries none; forever: `Commands_Forever.lua`'s `REPLAY_DEFAULTS` is counted as
   declared, never as an owner, and may only repeat registered values (until P21 moves it).
4. **Every setting read has a default after all modules load** -- the same files scanned for
   `MD.db.<key>` (not the target of an assignment), `MD.db["<key>"]`, `MD:Setting("<key>")`,
   `SM.Gate("<key>"` and `setting = "<key>"`: each must answer `MD:Setting` with the db key removed, or be
   in `REPLAY_DEFAULTS`, or in `NO_DEFAULT` with its reason (`replayPos` -- the pre-T31 window position,
   adopted once; `healAmountGross` -- latched from the combat log; `simUtilityPerFight` -- derived from
   the summaries; `uiPath` -- nil opens on the first group; `modules` -- TBC declares no module, the
   registry reads it behind a guard). tbc reads 43 keys, forever 28. Plus: the scan finds a reader for
   every registered key (`simMinActivity` excepted: declared, shown by `/md profile`, read by no rule), and
   no `MD.db.<key> or <number>` is left in the seven files this task owns.
5. **The Options sliders** (tbc) -- on the fresh db they show 85 and 30; with the two keys removed from
   the db, still 85 and 30; with 0.9 / 0.25 stored, 90 and 25. Forever: `UI/Options_General.lua` is on
   no Forever TOC.

## Tests first

`tools/defaultscheck.lua` run on the parent `3261856` (a copy of the tree from `git archive`, the new
suite dropped in):

```
tbc:      24 ok, 24 failed   exit 1
  gate foreign/hpMax/hpMean/manaMax/manaMean: ... no second copy  FAIL - stored copy 0.25 / 0.15 / 0.05 / 0.05 / 0.02
  gate manaMean's default is the registry's value                 FAIL
  <each of the 16 keys> is declared in Engine/SimModel.lua only   FAIL - declared in Core_TBC.lua
  Core_TBC.lua's DEFAULTS carries none of them                    FAIL
  no `MD.db.<key> or <literal>` left in ...                       FAIL - Engine/SimModel.lua:249 simFloor; ... UI/Options_General.lua:290 simFloor (14 sites)
forever:  4 ok, 48 failed    exit 1
  <each of the 18 keys> = <old> (registered, fresh db, MD:Setting) FAIL - registered nil ... (simGateMeter / simGateAttrib: fresh db nil too)
  a second default for simFullHp (0.9) is refused                 FAIL
  gate <all seven> ... no second copy                             FAIL
  <each of the 18 keys> is declared in <owner> only               FAIL - declared nowhere
  Commands_Forever.lua's REPLAY_DEFAULTS repeats only registered values  FAIL - 16 keys, differing: ...
  every setting read on the forever TOCs has a default (28 read)  FAIL - effectiveMode (UI/Dashboard_Rows.lua:441), muted (Core.lua:263), simGateAttrib (Gates_Forever.lua)
  no `MD.db.<key> or <literal>` left in ...                       FAIL
```

After: `48 ok, 0 failed` (tbc) / `52 ok, 0 failed` (forever), exit 0.

**Mutations on the finished branch** (one replacement each, defaultscheck under the flavour named,
reverted):

| mutation | result |
|---|---|
| `SimModel`: `simFloor = 0.31` | tbc 44 ok, 4 failed (section 1 twice, the two slider checks show 31) |
| `SimPlanner`: `fullHp` back to `(MD.db and MD.db.simFullHp) or 0.85` | tbc 47 / 1 (`SimPlanner.lua:913 simFullHp`) |
| `Core_TBC`: `simFullHp = 0.85` back in `DEFAULTS` | tbc 46 / 2 (declared in `Core_TBC.lua, Engine/SimModel.lua`) |
| `Gates_Forever`: `meterOwn` with its own `default = 0.10` | forever 51 / 1 (stored copy 0.1) |
| `Gates_Forever`: `simGateAttrib` not registered | forever 48 / 4 |
| `Core_Forever`: `muted` removed | forever 51 / 1 (`muted (Core.lua:263)`) |
| `Options_General`: the slider back on `MD.db.simFullHp or 0.80` | tbc 46 / 2 |

## Suites (`make check` = `tools/check.sh`, exit codes and footers checked)

| suite | before (`3261856`) | after |
|---|---|---|
| `defaultscheck` (tbc / forever) | -- | **48 / 52** |
| `simcheck` (tbc) | 13 | 13 |
| `solvercheck` (tbc) | 84 | 84 |
| `coachforever` | 20 | 20 |
| `gatecheck` | 9 | 9 |
| `replayui` (tbc) | 103 | 103 |
| `simwindow` (tbc) | 8 | 8 |
| `importcheck` | 21 | 21 (red until the fixture was rebuilt, see Deviations) |
| every other suite | adaptercheck 23 / 16, bindscheck 6, bookcheck 21, clockcheck 23, consolecheck 20 / 1, corecheck 24 / 24, costcheck 3, dashui 64, forevercheck 16, kitcheck 11 / 3, measurecheck 30, migrate 7, modulecheck 19, navui 35, parsecheck 15, practice 84, practiceforever 28, practiceui 52, probecheck 88, reccheck 63, recordcheck 31, recordingscheck 32 / 32, regencheck 27, releasecheck 21, replaycheck 82, replayforever 15, restcheck 51, reviewforever 13, reviewui 49, runcheck 81, scenariocheck 14, slashcheck 8, spellsui 48, spelltip 48, svcheck 6 / 1, tabscheck 24, themecheck 23, timeline 27, tipcheck 37, ttocheck 45, verifycheck 13, wincheck 55, lib/t 12 | all equal, all passing |
| harness-skip, reproduce-smoke, strategies-smoke | ok | ok |
| `apicheck.py` / `--selftest` | 0 findings, 50 files / 13 | 0 findings, 50 files / 13 |
| `textcheck.py` / `--selftest` | 0 findings, 87 files / 2 | 0 findings, 87 files / 2 |
| `refcheck.py --selftest` | 2 | 2 |

`tools/check.sh`: 66 runs, all passed, exit 0; its only notes are `defaultscheck/tbc: 48` and
`defaultscheck/forever: 52` "not in the expected counts". Every suite's saved output
(`tools/.lua/check/*.out`) was compared with the parent's, with table addresses and millisecond timings
normalised: **equal** -- the TBC suites (`slashcheck`, `verifycheck` with its golden transcripts,
`solvercheck`, `simcheck`, `replaycheck`, `reccheck`, `practice`, `restcheck` ...) and the coach cards
in `coachforever` / `replayforever` included -- except `releasecheck` (the worktree's path in its
"Built ..." lines) and the frame-sliced search's debug counts (`[sim] search N evaluations` in `replayui`
/ `reviewui`, `N frames` in `simwindow` / `runcheck`), which differ between two runs of the same tree
(the search is sliced on `debugprofilestop()`, as T63 recorded). `luac -p` passes on every changed file.

## TBC

No behaviour change and no DECISIONS entry. The 16 keys reach `MD.DEFAULTS` from `Engine/SimModel.lua`
at file load (before login, after `Core_TBC.lua` assigned the table), so `InitDB` fills the db exactly as
before; `MD:Setting(key)` answers the db value first, and the registered value is the old literal. The
settings dump of `/md profile` sorts its keys, so its text is unchanged (the golden in `verifycheck` is
equal).

## Integrator lines

- **TOCs:** none.
- **`tools/data/expected-counts.json`** -- two entries (alphabetical, after `"dashui/tbc": 64,`):
  ```
  "defaultscheck/forever": 52,
  "defaultscheck/tbc": 48,
  ```
- **`docs/TOOLS.md` section 1** -- a row after `dashui.lua`:
  ```
  | `defaultscheck.lua` | **defaults declared once** (T64, P20, review A3; tbc 48, forever 52): every registered default equals the literal it replaced (in `MD.DEFAULTS`, a fresh db and `MD:Setting` with the key absent) and a second, different default is refused; `SM.GATES` keep their setting and provenance and read `default` from the registry (no stored copy); each sim* / replay* / gate key is declared in `Engine/SimModel.lua` only (`simGateMeter` / `simGateAttrib` in `Gates_Forever.lua`), `REPLAY_DEFAULTS` counted as declared until P21; every setting a file on the flavour's TOCs reads (`MD.db.<key>`, `MD.db["<key>"]`, `MD:Setting`, a gate's setting, found by scanning the sources) has a default once every module is loaded, the few without one by design listed with their reason; no `MD.db.<key> or <number>` left in the engine, planner, replay window, gates or options; on tbc the Options sliders show 85 and 30 on a fresh db and with the keys absent |
  ```
- **`CLAUDE.md`** -- the repo-structure table:
  - `Engine/SimModel.lua` row, append: `**T64 (P20, review A3):** declares the settings it, the planner and the replay window read (sim*, replay*, the five v2 gate thresholds) with `MD:RegisterDefaults`, their provenance comments moved from `Core_TBC.lua`; `SM.Gate(setting, why)` builds a gate whose `default` reads the registry; every reader asks `MD:Setting(key)`, no inline `or 0.85` left`
  - `Core_TBC.lua` row, append: `**T64:** `DEFAULTS` no longer carries the engine's keys (`Engine/SimModel.lua` registers them, same values)`
  - `Core_Forever.lua` row, append: `**T64:** a module's settings are registered by the file that reads them (no hand-copied keys); `muted` and `effectiveMode` declared, read on this TOC by `Core.lua` and `UI/Dashboard_Rows.lua``
  - `Modules/<Name>/` row, in the T14 sentence after "`SM.HEAL_AMOUNT`": `; since T64 its two thresholds (`simGateMeter`, `simGateAttrib`) are registered there with `MD:RegisterDefaults`, built with `SM.Gate``
- **`docs/HISTORY.md`** -- the wave's entry: "T64 (P20): the engine's settings declared once (review A3):
  `Engine/SimModel.lua` and `Gates_Forever.lua` register their defaults, `SM.GATES` reads the registry,
  every reader asks `MD:Setting`; `Core_TBC.lua`'s `DEFAULTS` loses 16 keys, `Core_Forever.lua` gains
  `muted` / `effectiveMode`; new `tools/defaultscheck.lua` (tbc 48, forever 52); the Forever import
  fixture rebuilt (four new keys). TBC unchanged."
- **`docs/TESTING.md`** -- nothing new to test in game (a regression check at most: Settings -> General
  still shows 85 / 30 on a profile that never moved the sliders).
- **`docs/DECISIONS.md`** -- none (no TBC behaviour change).
- **With P21 (same wave):** `REPLAY_DEFAULTS` in `Commands_Forever.lua` holds only keys `Engine/SimModel.lua`
  now registers with the same values, so P21 can simply delete it (the Replay module loads `SimModel.lua`
  before `Commands_Forever.lua`). If P21 instead registers some of them from `Commands_Forever.lua`, the
  values must stay equal (a different one raises) -- better not to: `SimModel.lua` is their one owner.
  Once `REPLAY_DEFAULTS` is gone, `tools/defaultscheck.lua`'s `REPLAY_DEFAULTS_FILE` exemption (section 3's
  `replayDeclared`, section 4's "or in `REPLAY_DEFAULTS`") can be dropped; the suite passes either way.

## Deviations

1. **`tools/data/import-forever-sv.lua` edited, a file outside P20's row.** Registering
   `simGateMeter` / `simGateAttrib` (the plan's "`Gates_Forever.lua` registers its two gate defaults")
   and declaring `muted` / `effectiveMode` back-fill the Forever `SpellTunerDB`, and `importcheck`'s first
   assertion holds that the committed fixture is what `tools/importfixture.lua` writes today -- red until
   it is rebuilt. Rebuilt with `tools/run.sh tools/importfixture.lua`: four added lines, nothing else. No
   other task of wave 8 touches the fixture (P21 does not change what `SpellTunerDB` holds if it deletes
   `REPLAY_DEFAULTS`; if its registration changed the db, the integrator rebuilds the fixture once more
   after the merge with the same command).
2. **The replay window's four settings (`replaySpeed`, `replayTicks`, `replayNextPull`,
   `replayAutoCoach`) are registered by `Engine/SimModel.lua`, not by `UI/ReplayWindow.lua`.** The plan's
   own example puts `replaySpeed = 1` in SimModel's call; the window loads after `SimModel.lua` on both
   lines, and the offline TBC harness does not load `UI/`, so registering them in the window would have
   dropped them from the TBC suites' databases (and moved the `/md` settings transcripts).
3. **`Core_Forever.lua` gains two keys** (`muted`, `effectiveMode`) that the plan did not list -- the
   plan's own test ("every `MD.db.<key>` read ... has a default after all modules load") found them, and
   A3 names the gap. Both read `false` where they read `nil`.
4. The `ReplayWindow.lua` reads with no inline literal (`replayTicks`, `replayNextPull ~= false`,
   `replayAutoCoach == false`) and the `Options_General.lua` reads of other keys (`halfLife or 15`,
   `oomConfidence or 0.7`) were left as they are: the plan lists the lines to change, and those keys
   have their defaults (`Engine/SimModel.lua`'s registry, `Core_TBC.lua`'s `DEFAULTS`).
