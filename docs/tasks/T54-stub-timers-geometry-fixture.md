# T54 -- Stub timers, geometry and the import fixture (plan P10)

Status: **built** 2026-09-30 on branch `plan/P10` (base `fecaad4`), wave 4 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P10)

Review items Q8, Q12, Q6 and the importcheck half of Q4
(`docs/review/2026-09-30-project-review.md`):

- **(a) Q8.** `C_Timer.After` in the stub ignored its delay and never fired from `S.Tick`. The five
  suites that relied on it (`recordcheck`, `probecheck`, `practiceforever`, `spellsui`,
  `importfixture`) called the queued functions by hand, at moments they chose. So the R10 death
  re-poll (`Recorder_Forever.lua`, `MD.API.After(1, ...)`), which exists because of *when* it runs,
  ran "immediately". `Core_TBC.lua`'s `After(5, WriteProfile)` never ran at all. Now the stub keeps
  a due time, `S.Tick` fires whatever is due, and the suites assert that nothing is left pending
  instead of flushing.
- **(b) Q12.** The stub has no geometry, and `wincheck` installed its own privately. That geometry
  moves into the stub as an opt-in `S.Geometry(true)`, with a deterministic text metric (6 px per
  character, scaled by font size). `wincheck` uses it.
- **(c) Q6 + Q4.** `importfixture.lua` stamps a fixed version token, so a version bump no longer
  breaks importcheck. `importcheck` runs every subprocess through one helper that scrubs the
  environment.

Owned files (section 4, wave 4): `tools/wowstub.lua`, `tools/wincheck.lua`, `tools/recordcheck.lua`,
`tools/probecheck.lua`, `tools/practiceforever.lua`, `tools/spellsui.lua`, `tools/importfixture.lua`,
`tools/importcheck.lua`. The only other file touched is `tools/data/import-forever-sv.lua`, the
fixture `importfixture.lua` writes (one line; see Deviations). No shipped file was changed.

## What was built

| file | change |
|---|---|
| `tools/wowstub.lua` | **Timers.** `C_Timer.After(delay, fn)` queues `{ due = S.now + delay, fn, seq }` in `S.timers`, which now lists only the pending timers. At its end, `S.Tick(dt)` fires every timer due at the new `S.now`, after the `OnUpdate` scripts and the tickers. Timers fire in due order, and in queue order when two are due together. A timer queued while this pass runs waits for a later tick, as the client's `After(0)` runs on the next frame. `S.Pending()` counts the pending timers; `S.Due()` counts those already due. `NewTicker` is unchanged. **Geometry** (`S.Geometry(true)` / `(false)`, off by default): `wincheck`'s block, promoted unchanged. UIParent's effective scale is `S.uiScale` (default 1), in a 768-high base space. Each frame has its own scale and its recorded points. `GetLeft` / `GetTop` are computed for a frame with one point on UIParent. Strata, level, toplevel, user-placed, clamped, resizable and resize bounds are stored and read back. On top of that comes a text metric: `GetStringWidth` (and `GetUnboundedStringWidth`) is 6 px per visible character of the widest line x font size / 12, and `GetStringHeight` is the font size per line. `\|cAARRGGBB` and `\|r` take no room, `\|\|` counts as one character and a texture counts as one. The font size comes from `SetFont`, else from the object passed to `SetFontObject` (stored only in geometry mode), else 12. `S.Geometry(false)` restores every method it replaced. |
| `tools/recordcheck.lua` | `Settle(S, label)` replaces the three hand flushes. It ticks the clock one second past the combat flag, where the recorder's `After(1, ...)` finishes the pull. It notes any timer still pending after a pull that ended out of combat. (A chain pull, R11, is back in combat, and the probe's 2 s snapshot for the new fight is legitimately pending.) **+2 checks:** the R10 re-poll runs at +1 s: nothing is stored at +0.5 s, and the dead flag, set half a second *after* the combat flag, is seen at +1 s. At the end, nothing was ever left pending. R10's existing check now reads the pull stored that way. |
| `tools/probecheck.lua` | Step 2 ticks the clock 2 s in combat (the snapshot runs then) instead of calling the queue. Step 11 ticks 2 s after each fight. Step 14's "next frame" is `Sx.Tick(0)`. `NoteLeft` collects anything still pending. **+1 check:** no step left a timer pending. |
| `tools/practiceforever.lua` | The ESC's "next frame" is `S.Tick(0)` instead of a hand-run of the callbacks queued since the press. **+1 check:** nothing is pending after it. |
| `tools/spellsui.lua` | The same change for the picker's ESC. `pending == 0` is folded into the existing check (count unchanged). |
| `tools/wincheck.lua` | The private geometry block (about 70 lines) is gone. The suite sets `S.uiScale = 0.71` and calls `S.Geometry(true)` at the same point as before. `NextFrame()` is `S.Tick(0)`. The "code hide queues nothing" check reads `S.Pending()`. **Count equal (55), and the transcript is identical to the parent's.** |
| `tools/importfixture.lua` | `MD.version = "0.0.0-fixture"`, set right after the harness loads (before any fight is played or stored), as the file already fixes `date()` / `time()`. The pull's end is `At(S.now + 1)` plus an `assert(S.Pending() == 0)` instead of a flush. |
| `tools/importcheck.lua` | `Sh(cmd, set, cwd)`: every subprocess, including the scratch `rm` / `mkdir`, the fixture rebuild, each `import.lua` run and the TBC export in its own folder, starts under `env -u ST_FLAVOUR -u MD_SAVEDVARS`. A caller names what it wants set (`{ { "ST_FLAVOUR", "forever" } }` for the "via run.sh --flavour" case). **+1 check:** the fixture's practice fights carry `0.0.0-fixture` and not the TOC's version. |
| `tools/data/import-forever-sv.lua` | Regenerated by `tools/run.sh tools/importfixture.lua`. The whole diff is one line: `["version"] = "0.16.3"` -> `"0.0.0-fixture"`. Firing the probe's 2 s timer during the fixture pull changed nothing stored. |

Demonstration of the stub alone (an ad-hoc script, not a suite):

```
off: width  40  left 0
on : width  54  (|cffff0000Hello|r || x -- 9 visible chars at 12)
on : width at 18  81   height 18
on : font object 10, two lines: 30 20
on : centred 100x50 at uiScale 1: 632.67 409
off again: width 40  left 0
After(1) and After(0) queued (the latter queuing another After(0)): pending 2, due 1
after S.Tick(0.5): z@0.5            pending 2
after S.Tick(0.5): z@0.5 n@1 a@1    pending 0
```

## Failing first

**recordcheck, the R10 re-poll at +1 s.** Here is the new R10 block with its `Fresh` / `Settle`
helpers, excerpted into a scratch script and run on the parent's stub (`fecaad4`) and then on the
new one:

```
parent stub (exit 1):
R10 (review Q8): the death re-poll runs at +1 s on the clock: nothing stored at +0.5 s, the death seen at +1 s FAIL - stored at stop/+0.5/+1 = 0/0/0 deaths=nil pending=4
new stub:
R10 (review Q8): the death re-poll runs at +1 s on the clock: nothing stored at +0.5 s, the death seen at +1 s ok - stored at stop/+0.5/+1 = 1/1/2 deaths=1 pending=0
```

On the parent, the re-poll only ever ran when the suite flushed by hand. On the clock it never
runs: 4 timers are left pending and nothing is stored. The whole new `recordcheck.lua` on the
parent's stub fails from its first pull on (`a pull starts at combat and ends after it ...
FAIL - rec=nil`) and stops with an index error at check 13. Every hand flush it relied on is gone.

**importcheck under `--flavour tbc`.**

```
parent (exit 1):   the committed fixture is what tools/importfixture.lua writes today  FAIL   19 ok, 1 failed
new importcheck on the parent's fixture (exit 1):
                   the fixture carries a fixed version token, not the TOC's ...        FAIL - stamped=0.16.3 toc=0.16.3
                   (the fixture check now passes under --flavour tbc: the helper scrubbed ST_FLAVOUR)
new (exit 0):      21 ok, 0 failed      (and 21 under --flavour forever and with no flavour)
```

**importcheck after a version bump (Q6).** Each tree was copied to scratch, then
`release.sh --set-version 9.9.9` was run in the copy:

```
parent: the committed fixture is what tools/importfixture.lua writes today  FAIL   19 ok, 1 failed
new:    21 ok, 0 failed
```

**wincheck on the promoted geometry:** 55 before, 55 after, and the transcript is byte-identical to
the parent's.

## Suites (exit codes checked; the loop in docs/TOOLS.md section 1, plus importcheck under both flavours)

Before (base `fecaad4`) and after, each suite's full transcript was compared, with table addresses,
millisecond timings and the checkout path masked.

| suite | before | after |
|---|---|---|
| `recordcheck` | 29 | **31** |
| `probecheck` | 87 | **88** |
| `practiceforever` | 27 | **28** |
| `importcheck` | 20 (rc 1 under `--flavour tbc`) | **21** (rc 0 under no flavour, `forever` and `tbc`) |
| `spellsui` | 48 | 48 (one detail string gains `pending=0`) |
| `wincheck` | 55 | 55 (identical transcript) |
| every other suite: simcheck 13, reccheck 63, replaycheck 82, replayui 103, runcheck 81, reviewui 48, navui 35, dashui 64, regencheck 27, simwindow 8, solvercheck 84, restcheck 51, timeline 27, spelltip 48, costcheck 3, practice 81, practiceui 52, migrate 7, forevercheck 16, modulecheck 14, kitcheck 7, scenariocheck 14, gatecheck 9, replayforever 15, reviewforever 13, coachforever 20, bindscheck 6, parsecheck 15, bookcheck 21, tipcheck 37, clockcheck 23, measurecheck 30, releasecheck 16, themecheck 23, tabscheck 24; adaptercheck 23/16, corecheck 13/13, svcheck 6/1, consolecheck 17/1 | equal | equal, transcripts identical |
| `apicheck.py` | 0 findings, selftest 10/10 | same |
| `textcheck.py` | 0 findings, selftest 2/2 | same |
| `refcheck.py --selftest` | 2/2 | same |

The stub change alone (with the old suites) was also run over every suite that does not touch
`S.timers`. All of them, TBC's included, produced the same transcripts as on the parent. Timers now
fire in suites that tick past them: `Core_TBC.lua`'s `After(5, WriteProfile)`, `UI/Advisor.lua`'s 2 s
/ 5 s debounces, the probe's 2 s snapshot and `Windows_Forever.lua`'s `After(0)`. None of them
changed an assertion or a printed line. The only masked differences are run-to-run noise:
`replayui`'s frame-sliced `search N evaluations` lines, and on the parent even its `best (... binds
3|5)`, which vary between two runs of the same code (six runs on the parent gave binds 5, 3, 5, 3, 3, 5). `releasecheck`
fails in a copy that is not a git checkout (review Q7) and passes in the worktree. `luac -p` passes
on all eight changed tools and on the fixture.

## Integrator lines

**docs/TOOLS.md section 1** (append to each row's text):

- `recordcheck.lua`: ` Since **T54** (31): a pull ends on the stub's clock one second after the combat flag (no hand flush) -- the R10 re-poll runs at +1 s, nothing stored at +0.5 s, a dead flag half a second late still seen; no timer left pending after any pull (review Q8)`
- `probecheck.lua`: ` Since **T54** (88): the 2 s combat snapshot runs when the clock reaches it, the ESC's next frame is a tick; no step leaves a timer pending (review Q8)`
- `practiceforever.lua`: ` Since **T54** (28): the ESC's next frame is a tick of the clock and leaves no timer pending (review Q8)`
- `spellsui.lua`: ` Since **T54**: the picker's ESC next frame is a tick of the clock, nothing left pending (count unchanged)`
- `importcheck.lua`: ` Since **T54** (21): every subprocess runs with ST_FLAVOUR and MD_SAVEDVARS unset (green under --flavour tbc, review Q4); the fixture carries the fixed version "0.0.0-fixture", so --set-version no longer breaks it (review Q6)`
- `wincheck.lua`: in its row replace `the frame geometry is modelled by the suite itself, not the stub` with `the frame geometry is the stub's opt-in S.Geometry(true), since T54`

**docs/TOOLS.md section 4** (after the sentence on the stub's two profiles):

```
Since T54 (review Q8, Q12): `C_Timer.After` keeps a due time and `S.Tick` fires what is due at its
end (a suite ticks the clock past a delay and asserts `S.Pending() == 0`; it never calls
`S.timers` by hand), and `S.Geometry(true)` switches on an opt-in geometry -- scales, points,
GetLeft / GetTop for a frame on UIParent at `S.uiScale`, and a text metric of 6 px per visible
character x font size / 12 -- which `wincheck.lua` uses; off, a frame has none, as before.
```

**tools/data/expected-counts.json** (when it exists): `recordcheck` 31, `probecheck` 88,
`practiceforever` 28, `importcheck` 21 (also under `--flavour tbc`).

**CLAUDE.md**, in the `tools/` row, after `tools/wowstub.lua` fakes just enough client API for the
non-UI files to load;`:

```
 since T54 its `C_Timer.After` fires on `S.Tick` at its due time (`S.Pending()`; suites never flush by hand) and `S.Geometry(true)` is an opt-in geometry with a deterministic text metric (wincheck's, promoted);
```

**docs/HISTORY.md**: the session entry is the integrator's.
**docs/TESTING.md**, **docs/DECISIONS.md**, **TOCs**: nothing. Only offline tools changed, and no
TBC behaviour moved.

## Deviations

- **`tools/data/import-forever-sv.lua` changed**, although section 4 does not list it. It is the
  file `importfixture.lua` writes, and importcheck's first check compares the two byte for byte. Q6's
  fixed token cannot land without regenerating it. The diff is the one version line, and no other
  wave-4 task touches it.
- **"Nothing left due" means "nothing left pending".** Once the stub fires everything due at the end
  of each tick, `S.Due()` after a tick is always 0. So each suite asserts `S.Pending() == 0` after
  ticking past the delay: nothing the step queued is still waiting. `S.Due()` exists for a suite that
  inspects the queue mid-tick. There is one scoped exception, in `recordcheck`: a pull that ends with
  combat already restarted (R11's chain pull). There the next fight's own 2 s probe timer is
  correctly pending, so that pull is not held to the rule.
- **The "nothing pending" checks are new assertions** in `recordcheck` (+1 besides R10's +1),
  `probecheck` (+1) and `practiceforever` (+1), rather than folded into existing checks. In
  `spellsui` it is folded into its ESC check, and `wincheck` adds none: the plan asks for an equal
  count there.
- **The text metric has no suite assertion of its own.** No suite in this wave's list is the natural
  place for it, and `wincheck` must keep its count. The demonstration above is the evidence. The
  first UI task that asserts a width (the U12 dropdown flips, the U16 rail overflow) will be its test.
- `replayui`'s `best (... binds 3|5)` varies between runs of identical code on the parent (a
  frame-sliced search whose slices depend on `os.clock`). This task does not touch it; it is
  noted for P13's runner, which should not compare that line.
