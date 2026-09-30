# T47 -- Launch safety, one text rule, simcheck's exit (plan P3)

Status: **built** 2026-09-30 on branch `plan/P3` (base `d8a926f`), wave 1 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P3)

Review items: A31 / A10 (the interface bands coded four times; Forever's interface leaving 16xxx at
launch breaks the addon in four places), B3 (em and en dashes in chat strings), B11 (TTO half: a bare
pipe in the debug line), U31 (the U+00D7 close glyph), Q3 (`tools/simcheck.lua` exits 0 whatever the
engine's self-tests say).

- **(a) The client from the TOC, not the interface.** `MD.API.client` from `SPELLTUNER_TOC`, the band
  only a fallback, one band table (`tools/data/flavours.txt`) that `Client/API.lua`, `release.sh`,
  `tools/apicheck.py` and `tools/releasecheck.lua` all agree with.
- **(b) One text rule.** New `tools/textcheck.py`: no byte above 127 in any string constant of a
  shipped file (every TOC, TBC included), read from `luac`'s listing; `--selftest` on a fixture. The
  tree's eleven sites fixed; `Engine/TTO.lua:443` doubles its pipes.
- **(c) Q3.** `RunSimRun` / `RunSimReplay` return their verdicts; `simcheck` exits 1 on a failure and
  prints the standard footer.

Owned files (section 4, wave 1): `Client/API.lua`, `release.sh`, `tools/releasecheck.lua`,
`tools/apicheck.py`, new `tools/data/flavours.txt`, `tools/forevercheck.lua`, new `tools/textcheck.py`
+ `tools/data/textcheck-fixture.lua`, `Core_TBC.lua`, `Verify.lua`, `UI/Style.lua`, `UI/Advisor.lua`,
`Engine/TTO.lua`, `tools/simcheck.lua`. Nothing else was touched.

## What was built

| file | change |
|---|---|
| `tools/data/flavours.txt` | New. One line per flavour: name, marker files (comma-separated, as a TOC lists them), band. `tbc  Client/TOC_TBC.lua  20000-29999`; `forever  Client/TOC_Mainline.lua,Client/TOC_Plain.lua  16000-19999`. The header states the rule: marker decides, a TOC under `Modules/` is forever, the band only for a TOC with neither and a warning when a TOC is outside its flavour's band. |
| `Client/API.lua` | `MD.API.MARKERS = { TBC = "tbc", Mainline = "forever", Plain = "forever" }`, `MD.API.BANDS = { tbc = { 20000, 29999 }, forever = { 16000, 19999 } }`. `MD.API.client` is `MARKERS[SPELLTUNER_TOC]` (our own global, set by the first file of every main TOC; `rawget`, type-checked); only when the marker is absent or unknown does the old `GetBuildInfo` interface read decide, now by walking `BANDS`. The interface outside every band with a marker present changes nothing. |
| `release.sh` | Reads the table (`$SRC/tools/data/flavours.txt`, else the script's own). A TOC is the flavour whose marker file it lists (entries normalised: CR, backslashes, whitespace); else a TOC under `Modules/` is forever; else its interface band; a TOC with neither is refused: `ERROR: <toc> has no marker file and interface <n> is in no band of tools/data/flavours.txt`. A marked (or module) TOC whose interface is outside its flavour's band builds, with `WARNING: <toc> has interface <n>, outside forever's band 16000-19999 (tools/data/flavours.txt); packaged as forever by its marker file` (or `by its Modules/ folder`) on stderr. A TOC listing the markers of two flavours is refused. The header comment says so; the two `no ... TOC (interface ...)` messages lost their hard-coded bands. |
| `tools/apicheck.py` | `load_flavours()` / `toc_flavour()`: a Forever TOC is one the table calls forever by the same three steps (the band only as the fallback). The selftest fixture (`Fixture_Mainline.toc`, `Modules/Sample/...`) is still classified forever (fallback band and module folder). |
| `tools/textcheck.py` | New. Every `.lua` any TOC under the root loads (all nine TOCs; a module's `Engine/ Spells/ Data/ UI/` entry resolved at the root as release.sh does), `luac -l -l -p`'s constant tables decoded (luac's `\ddd`, `\"`, `\\` escapes), each constant with a byte > 127 reported at the line of every instruction that uses it: `FAIL <file>:<line> "<constant, high bytes as \ddd>"`, footer `textcheck: 9 TOCs, 82 files, N findings`, exit 1 on a finding (2 without luac). A comment is never a finding; a source escape `"\226\128\148"` is. The bare-pipe half of the rule stays a reading question (`\|c`, `\|r`, `\|T` are legitimate) and the docstring says so. `--selftest` (2 assertions) on the fixture. |
| `tools/data/textcheck-fixture.lua` | New. An em dash in a call (line 4), a multiplication sign (U+00D7) in a table store (5), a source escape (6), an e-acute in a comparison (8), an en dash in a long string (9) -- the five findings -- plus a comment with an em dash (2) and an ASCII line with an escaped backslash `\\226` (7) that must not be. |
| `Core_TBC.lua` | 243, 325, 369: `first run - ...`, `widget unlocked - ...`, `usage: /md window N (5-60 seconds)`. |
| `Verify.lua` | 10, 93: `-- verify: static data vs live client --`, `-- input snapshot --`; 24, 65, 68, 500: the em dash became ` - `. Q3: `RunSimRun` returns `#out, fails` (`0, 1` when the engine is not loaded); `ReplayFixture` returns `lines, spendExact and fit`; `RunSimReplay("fixture")` returns that verdict (`false` when the engine or fixture is missing; the recording branch returns nothing, as before). Nothing prints differently. |
| `UI/Advisor.lua` | 68: the gear-change toast `gear change - %s R%d ...`. |
| `UI/Style.lua` | 248: the header's close button text `x` (was U+00D7). |
| `Engine/TTO.lua` | 443 (now 444): the tto debug summary's five ` \| ` separators doubled to ` \|\| ` (one pipe drawn by the console), with a one-line comment. |
| `tools/forevercheck.lua` | +3 (13 -> 16), below. |
| `tools/releasecheck.lua` | +3 (13 -> 16), below; check 4 ("no TOC of the other flavour is in either package") now classifies each packaged TOC by the table (marker, module folder, band) instead of the two hard-coded bands. |
| `tools/simcheck.lua` | Reads both verdicts; after `--curve` (if asked) prints `\n<ok> ok, <failed> failed` -- each simrun line one assertion (12), the fixture one more -- then a `FAIL:` line per failing part, and `os.exit(1)` on any failure or when no self-test ran. |

## Tests first (on the parent's code, only the tests changed)

`tools/forevercheck.lua` with the parent's `Client/API.lua`:

```
the Mainline marker at interface 120105 answers forever                  FAIL - Mainline unknown, Plain unknown
the TBC marker at 20506 answers tbc; no marker falls back to the band    ok - TBC tbc, none/20506 tbc, none/120105 unknown
MD.API.BANDS and MD.API.MARKERS equal tools/data/flavours.txt            FAIL - flavours.txt lines 0, BANDS nil, MARKERS nil
14 ok, 2 failed
```

(The TBC assertion passes on the parent by design: 20506 is inside the old band. It pins that the
new marker path did not break TBC and that the fallback still answers `unknown` outside every band.)

`tools/releasecheck.lua` with the parent's `release.sh`:

```
a Forever TOC at interface 120105 is packaged as forever (its marker), with a warning FAIL - rc=1 ERROR: SpellTuner_Mainline.toc has interface 120105: neither tbc nor forever
a module TOC at interface 120105 is packaged as forever (its folder), with a warning FAIL - rc=1 ERROR: SpellTuner_Mainline.toc has interface 120105: neither tbc nor forever
a TOC with no marker file and an interface in no band is refused, by name            FAIL - rc=1 ERROR: SpellTuner_Odd.toc has interface 120105: neither tbc nor forever
13 ok, 3 failed
```

(The third: the parent refused that TOC too, by name, but refused every TOC at 120105 the same way;
the assertion asks for the new reason, `no marker file`, so it fails there.)

`tools/textcheck.py` on the tree before the fix (the eleven sites, and nothing else):

```
FAIL UI/Style.lua:248 "\195\151"
FAIL Core_TBC.lua:243 "first run \226\128\148 the widget is unlocked for 60s so you can dr..."
FAIL Core_TBC.lua:325 "widget unlocked \226\128\148 drag it, then /md lock."
FAIL Core_TBC.lua:369 "usage: /md window N (5\226\128\14760 seconds)"
FAIL UI/Advisor.lua:68 "gear change \226\128\148 %s R%d is now your efficient rank (was R%d..."
FAIL Verify.lua:10 "\226\128\148 verify: static data vs live client \226\128\148"
FAIL Verify.lua:24 " \226\128\148 spellID unknown to this client"
FAIL Verify.lua:65 "|cffffaa33GetSpellPowerCost unavailable|r \226\128\148 the static t..."
FAIL Verify.lua:68 "checked %d cast times, %d costs \226\128\148 %d mismatch(es)."
FAIL Verify.lua:93 "\226\128\148 input snapshot \226\128\148"
FAIL Verify.lua:500 "fsrtest: logging mana changes for 15s \226\128\148 cast one spell now."
textcheck: 9 TOCs, 82 files, 11 findings
```

After: `textcheck: 9 TOCs, 82 files, 0 findings`, rc 0. `--selftest`: `selftest: 2 of 2 ok` (the
tool is new, so it does not exist on the parent).

**simcheck, checked once by hand.** `Near` in `Verify.lua` broken (`<= tol - 1e9`):

- parent `tools/simcheck.lua`: the simrun block says `4 FAILED`, the last line is the fixture's
  `-> PASS`, **rc=0**;
- new `tools/simcheck.lua`: `9 ok, 4 failed` / `FAIL: 4 engine self-test(s)`, **rc=1**.

`Near` restored afterwards (`git diff` shows no change on that line).

## Suites (exit codes checked; the loop in docs/TOOLS.md section 1 plus textcheck)

| suite | before (d8a926f) | after |
|---|---|---|
| `simcheck` | rc 0, no footer (`-> PASS`) | rc 0, `13 ok, 0 failed` |
| `forevercheck` | 13 | **16** |
| `releasecheck` | 13 | **16** |
| `textcheck.py` / `--selftest` | -- | 0 findings / 2 of 2 |
| `apicheck.py` / `--selftest` | 0 findings (8 TOCs, 48 files, 46 globals) / 10 of 10 | same |
| `refcheck.py --selftest` | ok | ok |
| every other suite | reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 35, dashui 63, regencheck 27, simwindow 8, solvercheck 77, restcheck 51, timeline 27, spelltip 48, practice 80, practiceui 50, migrate 7, probecheck 87, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 15, reviewforever 11, coachforever 18, practiceforever 25, bindscheck 6, parsecheck 12, bookcheck 21, tipcheck 37, clockcheck 20, spellsui 47, measurecheck 30, importcheck 19, themecheck 23, tabscheck 24, wincheck 53, adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1, consolecheck 17 / 1 | all equal, all rc 0 |

`luac -p` passes on every changed `.lua`; `bash -n release.sh` passes.

**Byte comparison of full outputs** (parent tree from `git archive d8a926f` against this branch):
`importcheck`, `modulecheck`, and the forever runs of `adaptercheck`, `consolecheck`, `corecheck`,
`svcheck` are byte-identical. Every other TBC-harness output differs only in:

- the first-run chat line (`first run - the widget ...`, this task's text change), one line each;
- time-dependent lines that differ between two runs of the parent too (`replay 1 opened ... N ms`,
  `search N evaluations` -- the search is sliced on `debugprofilestop`; `solvercheck`'s printed table
  addresses);
- `practice`: `...and the client, level and version  ok - tbc / 64 / 0.16.3` (was `unknown / ...`).
  The TBC stub has no `GetBuildInfo`, so the parent's `MD.API.client` was `unknown` under the TBC
  harness; the TBC marker now says `tbc`. The assertion only asks for a value. In the real TBC client
  `GetBuildInfo` answers 20505, inside the band, so `client` was and is `tbc` there.

## TBC

Text only: the ten chat strings (the first-run line, `/md unlock`, `/md window` usage, six
`/md verify` / `/md fsrtest` lines, the gear-change toast) read ASCII, and the TBC window's close
button reads `x`. `MD.API.client` is `tbc` on the TBC client before and after. The debug console's tto
summary draws `|` where it drew nothing (a bare pipe was an escape). No look, layout or model change.

## Integrator lines

**docs/DECISIONS.md** (new section, after "One kit record and one report tool (2026-09-30)"):

> ## The client is the TOC's, the interface is a fallback (2026-09-30, T47)
>
> `MD.API.client` comes from the TOC the client loaded: its first file, `Client/TOC_<X>.lua`, sets
> `SPELLTUNER_TOC = "<X>"`, and `TBC` is `tbc`, `Mainline` and `Plain` are `forever`
> (`MD.API.MARKERS`). The interface band (`MD.API.BANDS`: tbc 20000-29999, forever 16000-19999)
> decides only when that marker is absent. Why: WoW: Forever runs the retail engine, and its launch
> interface is not promised to stay in 16xxx; the band alone would turn the addon into an "unknown
> client" (and Practice's `OnForever()` false, undoing T24) the day it moves, and `release.sh` would
> refuse to build. `release.sh` classifies a TOC by the marker file it lists (a TOC under `Modules/`
> is forever), warns when the interface is outside its flavour's band and refuses only a TOC with
> neither. One table, `tools/data/flavours.txt`, is what `release.sh`, `tools/apicheck.py` and
> `tools/releasecheck.lua` read; `tools/forevercheck.lua` asserts `Client/API.lua`'s two tables
> equal it. On TBC nothing changes: its interface is inside the band and its marker says `tbc`.
> The same task made the ten TBC chat strings with an em or en dash and the window's U+00D7 close
> glyph ASCII (`tools/textcheck.py`, B3, U31) -- text only.

**CLAUDE.md**, table rows:

- `Client/API.lua` row: replace `` `MD.API.client` (`"forever"` on interface >= 16000 and < 20000, else `"tbc"`) `` with `` `MD.API.client` from the TOC's marker `SPELLTUNER_TOC` (`TBC` -> `"tbc"`, `Mainline` / `Plain` -> `"forever"`, `MD.API.MARKERS`), the interface band (`MD.API.BANDS`, equal to `tools/data/flavours.txt`) only when the marker is absent (T47) ``.
- `release.sh` / `Makefile` row: replace `a TOC's flavour is its interface (20000-29999 tbc, 16000-19999 forever)` with `a TOC's flavour is the marker file it lists (`tools/data/flavours.txt`; a TOC under `Modules/` is forever), the interface band only when it has neither -- a TOC outside its flavour's band builds with a WARNING, one with no marker and no band is refused by name (T47)`.
- `tools/` row: after the `apicheck.py` sentence add `**`python3 tools/textcheck.py`** (T47) reads every string constant of every file any TOC loads (TBC included) out of `luac -l -l` and fails on a byte above 127 (`--selftest` on `tools/data/textcheck-fixture.lua`)`.
- "Verifying changes", point 3: after `python3 tools/apicheck.py` (0 findings) add `and `python3 tools/textcheck.py` (0 findings) for any shipped file`.

**docs/TOOLS.md** section 1:

- `simcheck.lua` row, append: `Since **T47** (13): exits 1 on any failure and ends with the standard footer (12 self-test lines + the BF-1 replay)`.
- `forevercheck.lua` row, append: `Since **T47** (16): `Client/API.lua` re-run with the Mainline or Plain marker at interface 120105 answers `forever`, the TBC marker at 20506 `tbc`, no marker falls back to the band (`unknown` outside every band), and `MD.API.BANDS` / `MD.API.MARKERS` equal `tools/data/flavours.txt``.
- `releasecheck.lua` row, append: `Since **T47** (16): the flavour from `tools/data/flavours.txt` -- on the scratch copy a Forever TOC at interface 120105 packaged as forever by its marker with a WARNING, a module TOC at 120105 by its folder, a TOC with no marker file and an interface in no band refused by name; the "other flavour" check classifies by the table`.
- New row: `| `textcheck.py` | **one text rule** (T47, python, no harness): no byte above 127 in any string constant of any file a TOC loads (all nine TOCs, TBC included), from `luac -l -l`'s constant tables, reported at the line that uses it; `--selftest` (2) on `tools/data/textcheck-fixture.lua` -- five sites found, a comment and an escaped backslash not |`.
- The loop: after the `apicheck.py` line add `python3 tools/textcheck.py | tail -1; python3 tools/textcheck.py --selftest | tail -1`.

**docs/TESTING.md** section 44: items 3 (Text, B3) and 15 (Client, P3) of the plan's section 9, as
written there.

**tools/data/expected-counts.json** (when P13 creates it): `forevercheck` 16, `releasecheck` 16,
`simcheck` 13, `textcheck --selftest` 2.

No TOC changes.

## Deviations

- `flavours.txt`'s forever line carries **two** marker files (`Mainline` and `Plain`), comma-separated
  ("one line per flavour" kept). `Client/API.lua` exposes `MD.API.MARKERS` next to `MD.API.BANDS`, and
  forevercheck's third assertion checks both (and that each `Client/TOC_<X>.lua` sets exactly `<X>`).
- `release.sh` also refuses a TOC that lists the markers of two flavours, and a flavour the table
  names that `release.sh` has no package for (neither can happen with today's table).
- releasecheck's existing check 4 was moved from the hard-coded bands to the table (the plan's
  "`releasecheck.lua:225-230` read the same table"); its name and count are unchanged.
- `Verify.lua`'s two header lines became `-- verify: ... --` / `-- input snapshot --` rather than
  ` - `, to stay headers.
- The failing-first `releasecheck` refusal assertion fails on the parent on its message (the parent
  refused the TOC too, as it refused every TOC at 120105); stated above.
- Under the TBC harness a practice record's `client` reads `tbc` instead of `unknown` (see the byte
  comparison); the real TBC client is unchanged.
