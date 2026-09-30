# T57 -- One honest command: `make check` (plan P13)

Status: **built** 2026-09-30 on branch `plan/P13` (base `a185bfb`), wave 5 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P13)

Review items (`docs/review/2026-09-30-project-review.md`) Q2 (aliases, `RegisterEvent`), Q4, Q5, Q7,
Q9 (library only), Q15 (checksum, usage lines, smoke runs, reviewui's wait) and A10 (identity checks):

- (a) apicheck rule 8 follows `local NAME = <param>` aliases; a rule forbids `RegisterEvent(` outside
  `Client/` and `Core.lua`, and the one offender -- `UI/ReplayWindow.lua`'s raw
  `PLAYER_REGEN_DISABLED` frame -- moves onto `MD:On` (no allow-list).
- (b) Q4: the harness's skip exits 3 instead of 0; `HARNESS_FLAVOUR` stays as it is (no suite edited
  for it); probecheck adapted.
- (c) Q5: `tools/check.sh` / `make check`: every suite under each declared flavour, rc and footer
  required, a `FAIL` or a skip under a requested flavour is a failure, apicheck, textcheck and the
  python selftests, counts compared with `tools/data/expected-counts.json` (a decrease fails);
  `make release` and `make install` depend on it (`NO_CHECK=1` overrides).
- (d) Q7: releasecheck asserts its scratch copy first, falls back to `find`, splits the folded check
  into four; the twin TOCs asserted identical but for the marker line; modulecheck asserts the three
  `Module.lua` / `Ready.lua` and each module's two TOCs identical.
- (e) `tools/lib/t.lua` (`check`, `section`, `done`, `Ascii`, `Strip`, `CapturedChat`) for new suites;
  no mass migration.
- (f) Q15: `run.sh` pins the Lua 5.1.5 SHA-256; `strategies`, `solvercmp`, `wclcheckkit`, `reproduce`,
  `healcheck` print a usage line when their default file is absent; `check.sh` smoke-runs `reproduce`
  and `strategies` on `tools/data/practice/1790701698.lua`; reviewui asserts `MD.coachSearch == nil`
  right after the click.

Owned files (section 4, wave 5): `tools/harness.lua`, `tools/run.sh`, `tools/check.sh` (new),
`tools/lib/t.lua` (new), `Makefile`, `tools/apicheck.py`, `tools/releasecheck.lua`,
`tools/modulecheck.lua`, `tools/reviewui.lua`, `tools/probecheck.lua`, `tools/strategies.lua`,
`tools/solvercmp.lua`, `tools/wclcheckkit.lua`, `tools/reproduce.lua`, `tools/healcheck.lua`,
`UI/ReplayWindow.lua` (the raw event frame only). Plus apicheck's own selftest fixture,
`tools/data/apicheck-fixture/` (see Deviations).

## What was built

Three commits:

1. **apicheck rule 8 aliases and rule 9; the replay's combat hook on `MD:On`.**
   - Rule 8 (`tools/apicheck.py`): for each handler parameter, every `local NAME = <param>` in the
     handler body (the right-hand side the parameter alone) is the same value: its risky uses count
     from the `local` on, and an `IsSecret` check on either name before the use covers it. An alias
     of an alias is not followed (said in the docstring).
   - Rule 9: `:RegisterEvent` / `:RegisterUnitEvent` / `:RegisterAllEvents` (after `.` or `:`, so the
     `pcall(frame.RegisterEvent, frame, e)` spelling counts too), comments and strings blanked,
     outside `Client/` and `Core.lua` -- reported as
     `FAIL <file>:<line> RegisterEvent outside MD:On (only Client/ and Core.lua register events)`.
     Like every apicheck rule it covers the files the Forever TOCs load (`UI/SpellTooltip.lua`'s
     watcher frame is TBC-only and out of its scope).
   - Selftest fixture: `Handlers.lua` gains an alias handler that checks the alias (no finding) and
     one that does not (`Handlers.lua:45 sid`); `Bad.lua:12` registers on a raw frame (a finding, its
     comment mentioning `RegisterEvent(` is not one); `Client/Ok.lua` registers on its own frame (no
     finding). Selftest 10 -> **12**.
   - `UI/ReplayWindow.lua`: the `do local guard = CreateFrame("Frame") ... end` block is now
     `MD:On("PLAYER_REGEN_DISABLED", function() ... end)` with the same body. The handler now runs
     inside the kernel's dispatch (after the handlers registered before it, under P11's `xpcall`).
     Nothing else in the file changed.
2. **`tools/check.sh`, `make check`, the skip code, the checksum, `tools/lib/t.lua`.**
   - `tools/harness.lua`: the skip prints the same `skip: <tool> runs under <flavours> only` and
     exits **3**. New: `HARNESS_FORCE` (set by a tool, consumed by the harness) loads `declared[1]`
     whatever `ST_FLAVOUR` says -- probecheck's steps 12 and 14 load Forever inside a tbc run, which
     used to be a mid-suite `os.exit(0)` under `--flavour tbc`. probecheck is the only user.
   - `tools/check.sh` (header comment is its manual):
     - suites = every `tools/*.lua` except the helpers and research tools in its `NOT_SUITES` line
       (a new file not listed is run as a suite and fails if it has no footer); each run under every
       flavour its first `HARNESS_FLAVOUR = ...` line names (`tools/run.sh --flavour F`), or plainly
       when it names none; `ST_FLAVOUR` always scrubbed (`env -u`); plus `tools/lib/t.lua`'s
       self-test;
     - a run passes on exit 0 AND a `<n> ok, 0 failed` footer with n > 0 AND no line marked FAIL
       (`<name> FAIL`, `<name> FAIL - detail`, or a footer's `FAIL ...` list line -- the gate
       reports' `FAIL no damage meter ...` inside ok lines do not match); exit 3 is reported as
       "skipped under a flavour it was asked for" and fails;
     - `harness-skip`: costcheck (tbc only) under `--flavour forever` must exit 3 and print its
       `skip:` line;
     - smoke runs: `reproduce.lua --fixture` and `strategies.lua --fixture` on
       `tools/data/practice/1790701698.lua` (exit 0 and their table printed);
     - python: `apicheck.py` (0 findings), `textcheck.py`, and the `--selftest` of apicheck,
       textcheck and refcheck;
     - counts: `{"suite/flavour": n}` (plain suites and the selftests by name) against
       `tools/data/expected-counts.json` -- fewer than expected fails, an expected run that did not
       happen fails (a declaration that lost a flavour), more or new is a NOTE; no file -> a NOTE and
       no comparison; `--write-counts` writes the file after a green run; `--counts FILE` compares
       with another file; `--only a,b` runs a subset (an expected key is then missed only if its suite
       was named);
     - `--tree NAME|DIR` execs that source's own `tools/check.sh` (a worktree name as
       `./release.sh --list` prints it, or a directory; refused with a message when that tree has
       none), `--pick` shows `./release.sh --list`, reads a choice and prints the source's path;
     - every run's output is kept in `tools/.lua/check/<suite>.<flavour>.out` (gitignored).
   - `Makefile`: `make check`; `make release` / `make install` take the source (SRC, else the same
     menu through `tools/check.sh --pick`), run **that source's** check (`--tree`) and build nothing if
     it fails; `NO_CHECK=1` builds unchecked and says so. release.sh is then called with
     `--src <path>` (it accepts a directory). The `RELEASE` variable is unchanged, so
     `make release SRC=. NO_CHECK=1 RELEASE=echo` shows what would run.
   - `tools/run.sh`: the tarball is checked against
     `2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333` (lua.org's SHA-256 for
     lua-5.1.5.tar.gz, and what the existing `tools/.lua/lua.tar.gz` hashes to) before unpacking; a
     mismatch deletes it and exits 1. `sha256sum`, else `shasum -a 256`.
   - `tools/lib/t.lua`: `check` (the house format, `%-72s ok|FAIL[ - detail]`), `section`, `counts`,
     `done` (the footer `check.sh` reads, `  FAIL <name>` lines, exit 0/1), `Strip` (colour codes out,
     `||` kept), `Ascii(s, opts)` (printable ASCII, no bare pipe; colour codes and `||` allowed;
     `opts.newlines` allows `\n`, `opts.noColour` refuses colour codes; answers ok and why),
     `CapturedChat(body)` (restores the frame even when body raises), `Has`. Run as a script it tests
     itself (12 checks); check.sh runs it as `lib/t`. No existing suite was migrated.
3. **Identity checks, usage lines, reviewui's wait.**
   - `tools/releasecheck.lua` (16 -> **21**): the scratch copy is `git ls-files -co --exclude-standard`
     inside a repository, else `find` minus `.git`, `tools/.lua`, `dist`, `.claude`, `.logs`,
     `tools/.cache`, `__pycache__`; a new check "the scratch copy of the tree holds release.sh and
     every TOC (git|find)" comes before anything reads it; the folded `--set-version` check is four:
     refuses a bad version and changes nothing / rewrites every TOC's version line and only that line
     / changes no file but the TOCs / keeps a CRLF TOC's every CR; and "SpellTuner.toc and
     SpellTuner_Mainline.toc differ only in their marker line" (`Client\TOC_Plain.lua` /
     `Client\TOC_Mainline.lua`).
   - `tools/modulecheck.lua` (14 -> **19**): the three `Module.lua` are one file, the three
     `Ready.lua` are one file, and each module's `<Name>.toc` equals its `<Name>_Mainline.toc` (three
     checks).
   - Research tools: `strategies`, `solvercmp`, `wclcheckkit` (both default files), `reproduce` and
     `healcheck` check their file before `dofile` and print a usage line with exit 2 instead of a
     traceback. `reproduce.lua --fixture <path>` and `strategies.lua --fixture <path>` read
     `{ rec, kit }` as `tools/import.lua --fixture` does and use the fixture's own kit (strategies
     binds the fight's own known ranks, `rec.initial.known`, and copies the kit per run since
     `--calibrate` scales it in place). Without `--fixture` both behave as before.
   - `tools/reviewui.lua` (48 -> **49**): the 200-frame wait after a plain click on a rejected fight
     is gone; "a plain click starts no coach search" asserts `MD.coachSearch == nil` and no
     `coach: searching` line right after the click. One frame (`S.Tick(0.016)`) then runs before the
     shift-click: the plain click also cancelled the replay window's automatic coach of the pull
     opened earlier in the suite, and a cancelled search's callback clears `MD.coachSearch` on its
     next frame whatever it holds by then (finding 1 below). Without that frame the shift-click's
     search handle was cleared after one frame and the suite read "no plan".

## Failing first

- **apicheck** -- the parent's `apicheck.py` on the new fixture finds 10 (not
  `Handlers.lua:45 sid`, not `Bad.lua:12 RegisterEvent`), so the new selftest's 12 expected fail on
  the parent's detection; on the tree the parent reports 0 findings while the new one reports
  `FAIL UI/ReplayWindow.lua:2055 RegisterEvent outside MD:On ...` until the move (then 0). Q2's own
  mutation -- the recorder's `IsSecret(sid) or` removed at both sites -- is caught now:

  ```
  rule 8: Modules/SpellTuner_Recorder/Recorder_Forever.lua:515 sid used before IsSecret in the UNIT_SPELLCAST_START handler
  rule 8: Modules/SpellTuner_Recorder/Recorder_Forever.lua:528 sid used before IsSecret in the UNIT_SPELLCAST_SUCCEEDED handler
  ```
- **The skip** -- `tools/run.sh --flavour forever tools/costcheck.lua` under the parent's harness:
  `skip: costcheck.lua runs under tbc only`, **rc 0**; now rc **3** (and check.sh's `harness-skip`
  holds it). probecheck under the parent's harness with `--flavour tbc` would exit mid-suite at
  step 12; now it runs whole (88 ok) and under `--flavour forever` exits 3 at its first load.
- **check.sh, a deliberately failing suite** -- a temporary `tools/zzdemo.lua` (tbc) printing an
  assertion marked FAIL, then `1 ok, 0 failed`, exit 0 (the old simcheck's shape); full run:

  ```
    FAIL  zzdemo/tbc                 1 ok, 0 failed
            an assertion that failed                 FAIL
            output: tools/.lua/check/zzdemo.tbc.out
  check: 60 run(s), 1 failed: zzdemo/tbc          (rc 1)
  ```
- **check.sh, a suite mis-declared as tbc-only** -- `adaptercheck.lua`'s declaration changed to
  `HARNESS_FLAVOUR = "tbc"`, full run against the counts this branch writes:

  ```
    ok    adaptercheck/tbc           16
    FAIL adaptercheck/forever: expected 23 assertion(s), and it did not run (or did not pass)
    counted 53 run(s) against 54 expected
  check: 58 run(s), 1 failed: counts          (rc 1)
  ```
  (Without an expected-counts file a lost flavour is only a missing line; the file is what makes it
  a failure -- hence the integrator line below.)
- **releasecheck outside a repository** -- the tree copied without `.git` into a scratch folder: the
  parent's releasecheck `11 ok, 5 failed`, among them Q7's symptom
  `--set-version rewrites every TOC's version line and nothing else FAIL - SpellTuner_TBC.toc lost its CRLF: 0 of 0`
  and `the build refuses when two TOCs disagree on the version FAIL - rc=0`; the new one
  `21 ok, 0 failed` with `the scratch copy of the tree holds release.sh and every TOC (find) ok`.
  In the same copy, `## Notes:` changed in `SpellTuner.toc` only: `SpellTuner.toc and
  SpellTuner_Mainline.toc differ only in their marker line FAIL - 2 differing line(s): ...`.
- **modulecheck** -- a line appended to `SpellTuner_Replay/Ready.lua` and a blank line added to
  `SpellTuner_Practice.toc` in the scratch copy:
  `the three modules' Ready.lua are the same file FAIL - SpellTuner_Replay/Ready.lua differs from SpellTuner_Recorder's`,
  `SpellTuner_Practice: its two TOCs are identical FAIL`.
- **reviewui** -- the plain click made a shift-click (`S.shift = true`): `a plain click starts no coach
  search FAIL` (47 ok, 2 failed).
- **The research tools** -- the parent's `strategies`, `solvercmp`, `wclcheckkit` with no data file:
  a `dofile` traceback, rc 1; `reproduce --fixture ...`: traceback (it took `--fixture` for a file
  name). Now each prints `<tool>: no <file>` and its usage line, rc 2; `reproduce --fixture` reports
  the author's fight at 888 / 888 (100%), 9 of 9 casts; `strategies --fixture` prints the control and
  eight strategies (0.06 s).
- **run.sh** -- a scratch copy with the expected hash changed: `tools/run.sh: lua-5.1.5.tar.gz has
  SHA-256 2640fc56..., expected 0000fc56... - not unpacked`, rc 1, nothing unpacked; with the real
  hash a fresh copy downloads, verifies, builds and runs.
- **The replay's combat hook** is held by `practiceui`'s `entering combat ends practice`: with the
  `MD:On` line disabled it fails (51 ok, 1 failed); `replayui` does not cover it.

## Suites

Before = every suite of `docs/TOOLS.md` section 1 on `a185bfb`, exit codes checked; after =
`tools/check.sh` on this branch (all rc 0, `check: 59 run(s), all passed`).

| suite | before | after |
|---|---|---|
| `releasecheck` | 16 | **21** (+1 copy, +3 split, +1 twin TOCs) |
| `modulecheck` | 14 | **19** (+2 Module/Ready, +3 module TOC pairs) |
| `reviewui` | 48 | **49** (no search after a plain click) |
| `apicheck --selftest` | 10 of 10 | **12 of 12** |
| `lib/t` (new) | -- | 12 |
| `replayui` / `practiceui` | 103 / 52 | 103 / 52 (the combat hook on `MD:On`) |
| `probecheck` | 88 | 88 (now run under tbc by check.sh) |
| `simcheck` / `reccheck` / `replaycheck` / `runcheck` | 13 / 63 / 82 / 81 | same |
| `navui` / `dashui` / `regencheck` / `simwindow` / `solvercheck` | 35 / 64 / 27 / 8 / 84 | same |
| `restcheck` / `timeline` / `spelltip` / `costcheck` / `verifycheck` | 51 / 27 / 48 / 3 / 13 | same |
| `practice` / `migrate` / `forevercheck` / `kitcheck` / `recordcheck` | 81 / 7 / 16 / 7 / 31 | same |
| `scenariocheck` / `gatecheck` / `replayforever` / `reviewforever` / `coachforever` | 14 / 9 / 15 / 13 / 20 | same |
| `practiceforever` / `bindscheck` / `parsecheck` / `bookcheck` / `tipcheck` | 28 / 6 / 15 / 21 / 37 | same |
| `clockcheck` / `spellsui` / `measurecheck` / `importcheck` | 23 / 48 / 30 / 21 | same |
| `themecheck` / `tabscheck` / `wincheck` | 23 / 24 / 55 | same |
| `adaptercheck` forever / tbc | 23 / 16 | same |
| `corecheck` forever / tbc | 22 / 22 | same |
| `svcheck` forever / tbc | 6 / 1 | same |
| `consolecheck` forever / tbc | 20 / 1 | same |
| `apicheck` | 0 findings (8 TOCs, 48 files, 47 globals) | same |
| `textcheck` / `--selftest` | 0 findings (9 TOCs, 85 files) / 2 of 2 | same |
| `refcheck --selftest` | 2 of 2 | same |

**TBC suites byte-identical**: every suite's output on this branch was compared with its output on
`a185bfb`. Identical except (a) the four suites that gained assertions (releasecheck, modulecheck,
reviewui and the selftest) and (b) lines that differ between any two runs of the same commit: table
addresses in ok-line details (`coachforever`, `recordcheck`, `kitcheck`, `practiceforever`,
`replayforever`, `solvercheck`) and the counts of the wall-clock-sliced coach search (`replayui`'s
`[sim] search N evaluations`, `simwindow`'s `5 frames` / `6 frames`). No assertion line changed.

## Integrator lines

**`tools/data/expected-counts.json`** -- generated once at the end of wave 5 (after P14 lands, on the
merged tree): `tools/check.sh --write-counts`. For reference, this branch alone writes 54 keys:
`adaptercheck/forever 23, adaptercheck/tbc 16, apicheck-selftest 12, bindscheck/forever 6,
bookcheck/forever 21, clockcheck/forever 23, coachforever/forever 20, consolecheck/forever 20,
consolecheck/tbc 1, corecheck/forever 22, corecheck/tbc 22, costcheck/tbc 3, dashui/tbc 64,
forevercheck/forever 16, gatecheck/forever 9, importcheck 21, kitcheck/forever 7, lib/t 12,
measurecheck/forever 30, migrate/tbc 7, modulecheck/forever 19, navui/tbc 35, parsecheck/forever 15,
practice/tbc 81, practiceforever/forever 28, practiceui/tbc 52, probecheck/tbc 88, reccheck/tbc 63,
recordcheck/forever 31, refcheck-selftest 2, regencheck/tbc 27, releasecheck 21, replaycheck/tbc 82,
replayforever/forever 15, replayui/tbc 103, restcheck/tbc 51, reviewforever/forever 13,
reviewui/tbc 49, runcheck/tbc 81, scenariocheck/forever 14, simcheck/tbc 13, simwindow/tbc 8,
solvercheck/tbc 84, spellsui/forever 48, spelltip/tbc 48, svcheck/forever 6, svcheck/tbc 1,
tabscheck/forever 24, textcheck-selftest 2, themecheck/forever 23, timeline/tbc 27,
tipcheck/forever 37, verifycheck/tbc 13, wincheck/forever 55` (P14 adds `ttocheck/<flavour>`).

**`docs/TOOLS.md` section 1** -- the paragraph under the heading and the whole `bash` block at the end
of the section are replaced by:

````
Run all of them with one command before committing anything:

```bash
make check                 # = tools/check.sh
tools/check.sh --only reccheck,replayui     # a subset while working
```

`tools/check.sh` runs every suite under each flavour its `HARNESS_FLAVOUR` line declares, plus
`tools/lib/t.lua`'s self-test, the harness's skip, a smoke run of `reproduce.lua` and
`strategies.lua` on `tools/data/practice/1790701698.lua`, `apicheck.py`, `textcheck.py` and the
three python `--selftest`s. A run passes on exit 0 with the footer `<n> ok, 0 failed` and no line
marked FAIL; a skip (exit 3) under a flavour it asked for is a failure. The assertion counts are
compared with `tools/data/expected-counts.json`: fewer, or a run the file expects that did not
happen, fails. After adding assertions: `tools/check.sh --write-counts`. Each run's output is in
`tools/.lua/check/`. `make release` and `make install` run the built source's own check first
(`NO_CHECK=1` skips it). A new helper under `tools/` that is not a suite goes on check.sh's
`NOT_SUITES` line. New suites take `check` / `section` / `done` / `Ascii` / `Strip` /
`CapturedChat` from `tools/lib/t.lua` (see its header).
````

and these table rows change (text appended to the existing cells):

- `releasecheck.lua`: `Since **T57** (21): the scratch copy asserted first (git's file list, else find), --set-version's one check is four (a bad version refused, every version line and only it, no other file, a CRLF TOC's CRs), SpellTuner.toc / SpellTuner_Mainline.toc differ only in the marker line`
- `modulecheck.lua`: `Since **T57** (19): the three Module.lua and the three Ready.lua are one file each, each module's two TOCs identical`
- `reviewui.lua`: `Since **T57** (49): a plain click on a rejected fight starts no coach search, asserted right after the click`
- `probecheck.lua`: `Since **T57**: its Forever loads set HARNESS_FORCE, so it runs whole under --flavour tbc (check.sh's run)`
- new row after `textcheck.py`: `| lib/t.lua | **the suite library** (T57, no harness, 12): check / section / done (the footer check.sh reads) / Ascii / Strip / CapturedChat, run as a script it tests itself |`
- the apicheck line wherever TOOLS.md describes it: `rule 8 follows local aliases of a handler's argument; rule 9: no RegisterEvent outside Client/ and Core.lua (T57); --selftest 12`

and in the section on the research tools (section 2/3), one line each where they are described:
`reproduce.lua --fixture <tools/data/practice/<id>.lua>` and `strategies.lua --fixture <...>`
replay one practice fight with its own kit; with no data file every research tool prints its usage.

**`CLAUDE.md`** -- "Verifying changes" step 3: replace from "**for anything the engine or the
recorder touches, both harnesses still pass**:" to the end of the step with
`**make check** (tools/check.sh) is green: every suite under its flavours, apicheck 0 findings,
textcheck, the selftests and the expected counts (docs/TOOLS.md section 1).` and drop the hand-kept
assertion counts elsewhere in CLAUDE.md -- the counts live in `tools/data/expected-counts.json`.
Found by grepping for `assertions` and for a suite name followed by a number: the `tools/` row's
`(25 assertions: ...)` navui, `(23 assertions - ...)` reviewui, `(27 assertions, ...)` timeline,
`(45 assertions: ...)` practice, `(40)` practiceui, `49 assertions` runcheck, `(48 assertions)`
spelltip, `(66 assertions)` probecheck, and the Forever-suite list `forevercheck (13)`,
`adaptercheck (19 / 15 under forever / tbc)`, `corecheck (10 / 8)`, `modulecheck (12)`,
`svcheck (6 / 1)`, `consolecheck (11 / 1)`, `parsecheck (10)`, `bookcheck (14)`, `tipcheck (14)`,
`clockcheck (13)`, `spellsui (12)`, `measurecheck (9)`, `releasecheck (13, ...)` (keep the
parenthesis's words, drop the number), `costcheck (3, tbc, T45)`; the Probe row's `probecheck 82`,
the recorder's `recordcheck 24`, Measure's `measurecheck 26`, Dashboard_Rows' `tools/dashui.lua 56`;
and step 3's `(ten self-tests ...)`, `38 assertions`, `31 assertions`, `50 assertions`.

**`docs/TESTING.md`, `docs/DECISIONS.md`, TOCs** -- nothing. No TBC behaviour changed (the replay's
combat hook dispatches through `MD:On`: same event, same handler), so no DECISIONS entry.

## Deviations and findings

- **Files outside the table.** `tools/data/apicheck-fixture/Handlers.lua`, `Bad.lua` and
  `Client/Ok.lua` gained the selftest's new cases (the plan's "apicheck selftest +2" lives there).
  No other wave-5 task touches them.
- **Twin TOCs were already asserted** -- by `tools/probecheck.lua` ("the Forever TOCs carry the one
  version and differ only in their marker"), so A10's "nothing asserts identity" held only for the
  module folders. releasecheck's check is added as planned (it is the packaging suite; the probe
  suite's copy can go when A8 splits the probe).
- **Finding 1 (not fixed, not this task's lines):** `UI/ReplayWindow.lua` `MD:CoachOnOpen`'s callback
  sets `MD.coachSearch = nil` unconditionally. When `/md coach N` (or Review's Coach) cancels the
  automatic coach and starts its own search, the cancelled search's callback runs on the next frame
  and clears the NEW handle: the author's search still runs to its card, but `/md coach cancel` no
  longer reaches it and a second `/md coach` starts a concurrent search. Fix: clear only
  `if MD.coachSearch == handle`. reviewui's one-frame tick documents it.
- **Finding 2 (not fixed: `tools/wowstub.lua` is P14's this wave): `make check` takes ~105 s, 86 s of
  it probecheck** (also on `a185bfb`). `tools/wowstub.lua:37` captures `local rawtype, rawxpcall =
  type, xpcall` at every dofile, but after the first Forever profile `type` is the stub's own
  secret-aware wrapper -- so each re-dofile wraps the previous wrapper, and probecheck's 14 fresh
  stubs make every `type()` call walk a chain. Taking the first stub's originals
  (`local PREV = rawget(_G, "STUB")` before `_G.STUB = S`, then
  `local rawtype, rawxpcall = (PREV and PREV.rawtype) or type, (PREV and PREV.rawxpcall) or xpcall`
  and `S.rawtype, S.rawxpcall = rawtype, rawxpcall`) brought probecheck to **1.05 s** in a scratch
  copy, same result. Worth handing to P14 or the next stub task.
- `tools/check.sh --tree` resolves a name through `./release.sh --list`'s printed lines (release.sh
  is not this task's file and has no "resolve only" option); a change to that line format needs the
  regex in `resolve_tree` to follow.
- `make release` with no SRC now shows its menu through `tools/check.sh --pick` (the same list,
  default 1), so the check can run on the chosen source before release.sh builds it.
- Q4's "every subprocess through one environment-scrubbing helper" is covered where check.sh starts
  processes (`env -u ST_FLAVOUR`); `importcheck`'s own spawn of `importfixture.lua` is not this
  task's file and runs unflavoured under check.sh.
