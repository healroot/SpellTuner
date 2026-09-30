# T50 -- Parse, clock, export and the offline tools (plan P6)

Status: **built** 2026-09-30 on branch `plan/P6` (base `06f0969`), wave 2 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P6)

Review items (`docs/review/2026-09-30-project-review.md`): B4, B19, B20, B25, B26 (and the TBC half of
Q13, "importcheck covers the TBC export", taken with B25).

- **(a) B4.** `Spells/Parse.lua`'s single-damage catch-all (`DAMAGE_SINGLE`) read one tick of a
  periodic clause worded otherwise than the two recognised shapes as a direct hit (Hellfire 83,
  Volley 50), and Penance's "81 Holy damage to an enemy, or 184 healing to an ally, ... every 1 sec"
  as damage 81 with the heal dropped. It is refused now when the rest of the same sentence after the
  amount holds a period phrase (`every`, `each second`, `per second`, `Lasts`) or offers
  `or N healing`. The file's contract (refuse rather than guess) extended; no new shape guessed.
- **(b) B19.** The opener's `UNIT_SPELLCAST_SUCCEEDED` arrives before `PLAYER_REGEN_DISABLED`
  (review R8's window). The pool was right but `StartFight` zeroed `spent`, `casts` and `unpriced`,
  so the opener vanished from the spend rate, the warm-up lasted one cast longer and an unpriced
  opener left the hover's count.
- **(c) B20.** The Spells pane's Export wrote the character line's name and realm raw.
- **(d) B25.** `tools/import.lua` TBC `export N` wrote the header only (`^# recording %d` had no
  capture).
- **(e) B26.** `tools/refcheck.py` counted the probe's `\ddd` escapes as description numbers and
  never undid `\\`.

Owned files (section 4, wave 2): `Spells/Parse.lua`, `UI/Clock_Forever.lua`, `Engine/ManaModel.lua`,
`UI/SpellsPane_Forever.lua`, `tools/import.lua`, `tools/refcheck.py`, `tools/data/parse-fixture.lua`,
`tools/parsecheck.lua`, `tools/clockcheck.lua`, `tools/spellsui.lua`, `tools/importcheck.lua`.
Nothing else was touched.

## What was built

| file | change |
|---|---|
| `Spells/Parse.lua` | `PeriodicOrEitherAfter(text, e)`: the rest of the sentence after the amount (to the next `". "` or the end, lower-cased) holding `every` (word-bounded), `each second`, `per second`, `lasts` (word-bounded) or `or N healing`. `DAMAGE_SINGLE` reads its amount only when neither `NotCastDamage` (R35) nor this says no. Only the catch-all is guarded: the ranged, over-duration and combined shapes, the two tick shapes and every heal shape are untouched. |
| `Engine/ManaModel.lua` | `lastCast = { t, cost, priced }`, set by `Spend` / `Unpriced` when no fight is on (cleared by any cast in a fight). `ManaModel.OPENER_WINDOW = 0.5`. `StartFight(t)` folds a remembered cast with `0 <= t - lastCast.t <= 0.5` into the new fight -- a priced one into `spent` and `casts`, an unpriced one into `unpriced` -- once (the memory is cleared by `StartFight` either way). The pool itself is unchanged: the cost had already left it. `fight.start` stays the flag's time. |
| `UI/Clock_Forever.lua` | A comment at `PLAYER_REGEN_DISABLED` saying the model folds the opener. No behaviour change of its own. |
| `UI/SpellsPane_Forever.lua` | `Str` (the export's character-line helper) passes a string through `Esc`, as every other client string in the export already did. A missing value is still `?`. |
| `tools/import.lua` | `line:match("^# recording (%d+)")`: the number is captured, so a single fight's section matches `tostring(n)`; the run and run-pull branches read it only as a truth value, as before. |
| `tools/refcheck.py` | `unescape_client` undoes the probe's `Esc` in one left-to-right pass (`\\` a backslash, `\ddd` a byte, `\|\|` a pipe) and decodes the bytes as UTF-8, so a name with a curly apostrophe finds its reference key and a curly quote is one character before the numbers are counted. Every client value printed (the header's name and rank, the key, `desc: client`, cost, cast) goes through `ascii_escape`, so the output stays ASCII (a curly quote now prints as `’`, as the reference side always did). `--selftest` runs two cases and ends `selftest: 2 of 2 ok` (was `selftest: ok`): the bundled fixture against `expected.txt` (unchanged, byte for byte) and an in-memory export with an escaped curly apostrophe in a name, curly quotes in two descriptions and an escaped backslash. |
| `tools/data/parse-fixture.lua` | Penance's entry `loose` -> `refuse`; two new `refuse` entries marked `unverified` (review B4's own wordings, from memory, not a Forever client text): Hellfire and Volley. The header documents `refuse` and `unverified`. |
| `tools/parsecheck.lua` | Check 1 skips `refuse` entries; a new block 2b asserts each `refuse` entry reads `nil`, one check per entry (+3). Penance no longer prints in the `loose` report. |
| `tools/clockcheck.lua` | +2 (below), before the R36/R37 block. |
| `tools/spellsui.lua` | +1: item 8b (below). |
| `tools/importcheck.lua` | +1: item 13 (below). The TBC SavedVariables is written by `tools/svwrite.lua` from two hand-built v2 recordings, and the export runs in `tools/.lua/importcheck/tbcexport/` (it writes `.logs/recordings/<id>.txt` under the current directory, so nothing lands in the repository's `.logs/`). |

## Tests first (the parent's code, the new tests)

`tools/parsecheck.lua` with the parent's `Spells/Parse.lua`:

```
refused, not read as one direct hit: tf Priest|Penance|Rank 1            FAIL - heal nil damage {min=81, max=81, school=Holy} absorb nil
refused, not read as one direct hit: unverified Warlock|Hellfire         FAIL - heal nil damage {min=83, max=83, school=Fire} absorb nil
refused, not read as one direct hit: unverified Hunter|Volley            FAIL - heal nil damage {min=50, max=50, school=Arcane} absorb nil
12 ok, 3 failed
```

`tools/clockcheck.lua` with the parent's `Engine/ManaModel.lua`:

```
an opener 0.3 s before the combat flag counts in the fight's casts and spend FAIL - casts=0 spent=0 (want 1, 25)
an unpriced opener stays in the hover's unpriced count                   FAIL - unpriced=0 hover="SpellTuner mana clock (modelled) / ..."
21 ok, 2 failed
```

(The first also casts Rejuvenation 1.0 s before the flag, outside the window: `casts == 1` and
`spent == 25` hold only when that one is left out and the 0.3 s one is folded.)

`tools/spellsui.lua` with the parent's `UI/SpellsPane_Forever.lua` (the stub's player named
`Zo` + U+00EB + `|x`):

```
a non-ASCII character name exports escaped, ASCII with no bare pipe      FAIL - non-ascii; line="character: Zo\195\171|x Anniversary DRUID level 64"
47 ok, 1 failed
```

After: `character: Zo\195\171||x Anniversary DRUID level 64` (the probe's own escapes).

`tools/importcheck.lua` with the parent's `tools/import.lua`:

```
TBC export N writes that recording's section, not the header alone                           FAIL - recording sections=0; wrote .logs/recordings/1790000002.txt (8 of 44 lines: the header plus recording 1)
19 ok, 1 failed
```

After: the file holds `# recording 1`, `1790000002`, `Slave Pens` (tab-separated) with its roster, initial, precasts,
`# ev`, `# hp` and `# mana`, and not the other recording.

`tools/refcheck.py --selftest` with the parent's `unescape_client` (rc 1):

```
700 Nature\226\128\153s Touch Rank 1  [not in the reference: Druid|Nature\226\128\153s Touch|Rank 1]
701 Quoted Touch Rank 1  [Druid|Quoted Touch|Rank 1, s=beta, src=selftest]
  desc numbers: client 8, reference 2
  desc: client "Heals for 20 to 24. \226\128\156Quoted\226\128\157."
  desc: reference "Heals for 20 to 24. “Quoted”."
refcheck: 2 spells, 0 agree, 1 disagree, 1 not in the reference
selftest: 1 of 2 ok
```

After: `refcheck: 2 spells, 2 agree, 0 disagree, 0 not in the reference`, `selftest: 2 of 2 ok`, rc 0.

## Suites (exit codes checked; the loop in docs/TOOLS.md section 1)

Before: a `git archive 06f0969` copy of the parent (with `tools/.lua`). After: this branch.

| suite | before (06f0969) | after |
|---|---|---|
| `parsecheck` | 12 | **15** |
| `clockcheck` | 21 | **23** |
| `spellsui` | 47 | **48** |
| `importcheck` | 19 | **20** |
| `refcheck.py --selftest` | `selftest: ok` | **`selftest: 2 of 2 ok`** |
| `bookcheck` / `tabscheck` / `tipcheck` (druid texts untouched) | 21 / 24 / 37 | 21 / 24 / 37 |
| `simcheck` | 13 | 13 |
| every other suite | reccheck 54, replaycheck 82, replayui 98, runcheck 78, reviewui 44, navui 35, dashui 63, regencheck 27, simwindow 8, solvercheck 84, restcheck 51, timeline 27, spelltip 48, costcheck 3, practice 81, practiceui 50, migrate 7, probecheck 87, forevercheck 16, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 15, reviewforever 11, coachforever 19, practiceforever 25, bindscheck 6, measurecheck 30, releasecheck 16, themecheck 23, wincheck 53, adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1, consolecheck 17 / 1 | all equal, all rc 0 |
| `apicheck.py` / `--selftest` | 0 findings / 10 of 10 | same |
| `textcheck.py` / `--selftest` | 0 findings / 2 of 2 | same |

(`releasecheck` fails in an archive copy by construction -- it builds from `git ls-files` -- so its
"before" is the 16 the parent's TOOLS.md records; on this branch it is 16, rc 0.)

`luac -p` passes on every changed `.lua`.

## TBC

No. `Spells/Parse.lua`, `Engine/ManaModel.lua`, `UI/Clock_Forever.lua` and `UI/SpellsPane_Forever.lua`
are on the Forever TOCs only; the tools are tools (`tools/import.lua`'s TBC export now writes what it
always said it wrote). No DECISIONS entry.

## Integrator lines

**docs/TOOLS.md section 1** (append to each row's text):

- `parsecheck.lua`: ` Since **T50** (15): one tick of an unrecognised periodic clause and an amount offered "or N healing" refused, not read as one direct hit -- Penance, and Hellfire and Volley as UNVERIFIED wordings (B4)`
- `clockcheck.lua`: ` Since **T50** (23): an opener up to 0.5 s before the combat flag counts in the fight's casts and spend, and an unpriced one stays in the hover's count (B19)`
- `spellsui.lua`: ` Since **T50** (48): a non-ASCII character name exports escaped (B20)`
- `importcheck.lua`: replace `(no harness of its own; it runs tools/import.lua as the planner does, 19)` with `(no harness of its own; it runs tools/import.lua as the planner does, 20)` and append ` Since **T50**: TBC `export N` on a `svwrite`-built file writes that recording's section, not the header alone (B25)`

**docs/TOOLS.md, the `refcheck.py` paragraph** (after "`--selftest` runs the fixture in `tools/data/refcheck-fixture/`."):

> Since **T50** (B26) the probe's escapes are undone before a name is looked up or a number counted
> (`\\`, `\ddd`, `||`, one pass), every client value is printed through the same ASCII escape as the
> reference's, and `--selftest` runs two cases (the fixture, and an escaped curly quote agreeing with
> its reference), ending `selftest: 2 of 2 ok`.

**tools/data/expected-counts.json** (when it exists): `parsecheck` 15, `clockcheck` 23, `spellsui` 48,
`importcheck` 20, `refcheck --selftest` 2.

**CLAUDE.md**, append to the rows:

- `Spells/Parse.lua`: ` **T50** (review B4, 2026-09-30): the single-damage catch-all also refuses an amount whose sentence goes on with a period phrase (`every`, `each second`, `per second`, `Lasts`) or offers `or N healing` (Penance) -- one tick of a periodic clause it has no shape for is not one direct hit`
- `Engine/ManaModel.lua`: ` **T50** (review B19): an own cast up to 0.5 s before `StartFight` (the opener, R8's window) is folded into the fight's spend, casts or unpriced count`
- `UI/SpellsPane_Forever.lua`: ` **T50** (review B20): the Export's character line escaped like the rest`
- the `tools/` row, after "`python3 tools/refcheck.py`** (T8b) ... never judging it.": ` Since **T50** (B26) it undoes the probe's escapes before counting; `tools/import.lua`'s TBC `export N` writes its recording (B25).`

**docs/DECISIONS.md**, **docs/TESTING.md**, TOCs: nothing.

## Deviations

- **refcheck's selftest fixture.** The plan asks `refcheck.py --selftest` for +1; the fixture folder
  `tools/data/refcheck-fixture/` is not in P6's owned files, so the second case is built in memory in
  `tools/refcheck.py` itself (written to a temporary file, since `parse_dump` reads a path). The
  bundled fixture and its `expected.txt` are untouched and still compared byte for byte.
- **The TBC SavedVariables for importcheck** is built inline in `tools/importcheck.lua` with
  `tools/svwrite.lua` from two hand-made v2 recordings, not by a TBC mode of `tools/importfixture.lua`
  (Q13's longer-term shape): `importfixture.lua` is P10's file (wave 4), not P6's. The recordings
  carry only what `MD:Export` dumps; nothing validates or replays them.
- **The realm half of B20** is fixed (`Str` escapes both) but not asserted: the stub's
  `GetRealmName` is a constant and `MD.API` caches the bound function, so the suite changes the
  player's name only. `tools/wowstub.lua` is not P6's file.
- **refcheck's output** for an ASCII dump is byte-identical; for a client value with non-ASCII bytes
  it now prints `\uXXXX` (the reference side's existing escape) instead of the probe's `\ddd`.
