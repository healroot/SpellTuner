# T13f — the Forever recorder stamps what the shared screens read, and times its pre-pull HoTs

Status: **accepted** 2026-09-28 (lead review at the end). M3, two follow-ups from the lead's reviews of T13d and T17.

## Goal

A v3 stream carries the three summary numbers the shared Review tab, replay window and card already
read from a TBC stream -- own casts, mana spent, foreign share -- so a Forever row stops showing
`0 casts, 0 mana` and the card stops warning `labelled 110 of 0 spent`; and a pre-pull HoT's
remaining time is the time left **at the pull**, not at the out-of-combat read up to 2 s earlier. For
the author's Review tab and for T13d's attribution of pre-pull ticks.

## Facts

- The shared readers: `UI/Dashboard_Review.lua` 430-441 (`rec.ownCasts`, `rec.spent`,
  `rec.foreignShare`), `UI/ReplayWindow.lua` 1376 and 1903-1904 (`ownCasts`, `spent`),
  `Engine/SimPlanner.lua` 1156-1160 (the card's `labelled N of M spent` check against `rec.spent`),
  `Engine/SimModel.lua` 1343 (v2 gate, `foreignShare`; the v3 gate reads the meter, T14).
- TBC's recorder stamps them (`Engine/FightRecorder.lua` 455-456, 576-577, 590): `ownCasts` += 1 per
  own cast, `spent` += its cost when > 0, `foreignShare = foreign / (own + foreign)`.
- On Forever the foreign share is the damage meter's (T14 gate 5): `others / (own + others)` of
  `rec.meter` when `read == "current"`; absent otherwise.
- `Modules/SpellTuner_Recorder/Recorder_Forever.lua`: `ScanAuras` runs every 2 s out of combat and
  stores `remaining = expirationTime - now` at scan time; `PLAYER_REGEN_DISABLED` copies the last
  scan into `initial.auras` unchanged (T13d lead review 3: up to 2 s early).
- T13's stream field list ("Nothing else") is widened by exactly `ownCasts`, `spent`, `foreignShare`.

## Files

| file | change | role |
|---|---|---|
| `Modules/SpellTuner_Recorder/Recorder_Forever.lua` | `ownCasts` and `spent` counted as `OWNCAST` is pushed (an `amt` of -1 adds nothing to `spent`); `foreignShare` set after the meter is read (nil when it was not); `ScanAuras` remembers its own `GetTime()`, and the pull's `initial.auras` subtracts `t0 - scanTime` from each `remaining`, dropping an entry that has run out | the recorder |
| `tools/recordcheck.lua` | assertion 2 also requires `ownCasts == 6`, `spent` = the six casts' book costs, `foreignShare == 120 / 520`; assertion 10 also requires the pre-pull Rejuvenation's `remaining` to be its expiry minus `t0` (the fixture scans at least 1 s before the pull). **Names and count unchanged (14)** | suite |

## Rules

- `CLAUDE.md` rules that bite: no client call outside `Client/` (`GetTime` is the toolkit's); every
  event argument through `IsSecret` (rule 8); no new global; comments say why.
- No other file. The TBC line untouched.
- Tests first: the new clauses fail against the current recorder first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or any
  `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/recordcheck.lua` ends `14 ok, 0 failed`; the new clauses failed first
   (paste the run).
2. Every other suite at its count (baseline at 46ebdd9: coachforever 8, reviewforever 8,
   replayforever 10, gatecheck 8, scenariocheck 9, kitcheck 7, probecheck 73, modulecheck 14,
   forevercheck 13, parsecheck 11, bookcheck 15, tipcheck 14, clockcheck 15, spellsui 15, measurecheck
   18; adaptercheck 19/15, corecheck 10/8, svcheck 6/1, consolecheck 11/1; the TBC sixteen).
3. `python3 tools/apicheck.py` 0 findings over 40 files; `--selftest` 10 of 10.
4. `luac -p` clean.
5. Paste into the Report: the failing run, recordcheck in full, every other tail, apicheck, luac,
   `git status --short`.

## Out of scope

- The max-health estimate and the causality question (escalated, T17 review). The Review tab and the
  card themselves. `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

### Files touched

- `Modules/SpellTuner_Recorder/Recorder_Forever.lua`:
  - `ScanAuras` now also stores `R.lastScanTime = now` (the moment the scan actually ran) beside
    `R.lastAuras`.
  - `CopyAuraList(list, elapsed)` takes the elapsed time between the last scan and the pull start
    and subtracts it from every numeric `remaining`; an entry whose adjusted `remaining` has run
    out (`<= 0`) is dropped rather than carried in negative. A `nil` remaining (no expiration) is
    left alone.
  - `PLAYER_REGEN_DISABLED` computes `elapsed = t0 - (R.lastScanTime or t0)` (clamped to >= 0) and
    passes it into `CopyAuraList`, so `initial.auras[*].remaining` is time-left-at-the-pull, not
    time-left-at-the-scan.
  - The stream table now starts with `ownCasts = 0, spent = 0`.
  - `UNIT_SPELLCAST_SUCCEEDED` increments `active.ownCasts` by 1 per own cast pushed, and adds
    `amt` to `active.spent` only when `amt > 0` (an unpriced cast's `amt == -1` adds nothing, per
    Facts).
  - `ReadMeter`'s `"current"` branch now also sets `s.foreignShare = others / (own + others)`
    (0 when both are 0); the two earlier `"none"` early-returns leave `foreignShare` unset (absent),
    matching "absent otherwise" in the task's Facts.

- `tools/recordcheck.lua` (tests first):
  - Assertion 2 now also asserts `rec.ownCasts == 6`, `rec.spent == 165` (the six casts' book
    costs: 25+25+25+25+40+25) and `rec.foreignShare` within 1e-4 of `120/520` (own 400, others 120
    from the fixture's `S.meter.sources`).
  - The fixture now advances two extra half-second ticks (`S.Tick(0.5)` x2) right after the last
    out-of-combat scan (which lands on the existing `%4` tick boundary at t=8) and before
    `PLAYER_REGEN_DISABLED` fires, so the pull's own `t0` is a full second after the scan that
    primed `R.lastAuras` — without that gap the old and new formulas for `remaining` are
    indistinguishable. Every absolute time after that point (`At(28)->At(29)`, `At(37.5)->At(38.5)`,
    `At(38)->At(39)`, `At(48)->At(49)`) was shifted by the same +1s so every other assertion's
    *relative* timing (roster swap 20s in, death ~29.5-30s in, `dur == 40`) is unchanged.
  - Assertion 10 now expects `remaining` of 899 (908 expiry - 9 t0) instead of the old 900
    (908 - 8 scan time), and its detail string prints the stored `remaining` too.
  - Assertion count is unchanged (14); no other assertion's name or shape changed.

### Tests first

Before touching the recorder, the two updated clauses failed as expected (12 ok, 2 failed):

```
a pull starts at combat and ends after it, and the damage meter is read once combat is over FAIL - rec=table: 0x... dur=40 meter.read=current ownCasts=nil spent=nil foreignShare=nil
own HoTs on the party are read before the pull, never in combat                            FAIL - auras=1 auraCalls before=18 after=18 tgt=2 remaining=900

12 ok, 2 failed
  FAIL a pull starts at combat and ends after it, and the damage meter is read once combat is over - ...
  FAIL own HoTs on the party are read before the pull, never in combat - ...
```

After the recorder changes, `bash tools/run.sh tools/recordcheck.lua`:

```
the recorder registers nothing until its module is on                                      ok - before=0 after=1
a pull starts at combat and ends after it, and the damage meter is read once combat is over ok - rec=table: 0x64be2cd3ec40 dur=40 meter.read=current ownCasts=6 spent=165 foreignShare=0.23076923076923
damage and heals are kept per tracked token, once each; other tokens are ignored           ok - dmg=3 heal=1
own casts carry their spell, cost and the target named when they were sent; an unfinished cast is a cancel ok - caststart=7 owncast=6 cancel=1 cast1.amt=25 castR2.amt=40 cancel.amt=0
the party keeps its indices across a roster change mid-pull                                ok - tgt=3
a party member's max health is recorded unknown, the player's as read                      ok - p1=375,false p2=-1,true p3=-1,true
mana is the clock's modelled pool every two seconds, marked modelled                       ok - manaModelled=true samples=20
a death is recorded once, from UnitIsDeadOrGhost                                           ok - deaths=1 died=1
a secret argument is counted and never stored                                              ok - unreadable=1 dmg=3
own HoTs on the party are read before the pull, never in combat                            ok - auras=1 auraCalls before=18 after=18 tgt=2 remaining=899
a short pull is dropped, a kept one enters a ring of eight                                 ok - before=1 after=1
the stream holds only numbers, strings, booleans and tables of them, nothing secret        ok
the list command prints one ASCII line per recording                                       ok - lines=2 list=2 ascii=true
the recorder answers the list, get, pin and address calls the replay window and Review use ok

14 ok, 0 failed
```

### Every other suite (baseline at 46ebdd9)

```
simcheck      ... -> PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow     8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
probecheck    73 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   14 ok, 0 failed
kitcheck      7 ok, 0 failed
recordcheck   14 ok, 0 failed
scenariocheck 9 ok, 0 failed
gatecheck     8 ok, 0 failed
replayforever 10 ok, 0 failed
reviewforever 8 ok, 0 failed
coachforever  8 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed

adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc     15 ok, 0 failed
corecheck/forever    10 ok, 0 failed
corecheck/tbc         8 ok, 0 failed
svcheck/forever       6 ok, 0 failed
svcheck/tbc           1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc      1 ok, 0 failed
```

All counts match the baseline exactly. `simcheck`, `reccheck`, `replaycheck`, `replayui`,
`runcheck`, `reviewui`, `navui`, `dashui`, `regencheck`, `simwindow`, `solvercheck`, `timeline`,
`spelltip`, `practice`, `practiceui`, `migrate` are "the TBC sixteen" (each declares
`HARNESS_FLAVOUR = "tbc"` and was run via the plain `bash tools/run.sh tools/<t>.lua` loop above,
same as the acceptance's list of 15 named counts + `recordcheck`).

### apicheck / refcheck

```
apicheck: 8 Forever TOCs, 40 files, 43 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok   (refcheck.py --selftest)
```

### luac -p

```
$ tools/.lua/lua-5.1.5/src/luac -p Modules/SpellTuner_Recorder/Recorder_Forever.lua tools/recordcheck.lua
luac -p clean
```

(The `luac` wrapper `tools/.lua/luac` built by `run.sh` had no execute permission in this
worktree; `tools/.lua/lua-5.1.5/src/luac`, the same binary `run.sh` builds, was used directly and
passed clean on both touched files.)

### git status --short (end of task)

```
 M Modules/SpellTuner_Recorder/Recorder_Forever.lua
 M docs/TESTING.md
 M docs/tasks/HANDOVER.md
 M tools/recordcheck.lua
?? docs/tasks/T13f-recorder-summary.md
```

No `git add`/`stash`/`checkout`/`reset`/commit was run. `docs/TESTING.md` shows as modified but I
never opened or edited it in this session (only `Modules/SpellTuner_Recorder/Recorder_Forever.lua`
and `tools/recordcheck.lua` were touched, per the task's Files list) — that diff (a new §39
in-game session for the recorder/replay/coach) was already present in the worktree when I started
and is the lead's, same as `docs/tasks/HANDOVER.md`.

### Scope

Only the two files named in the task's Files table were changed. The TBC recorder
(`Engine/FightRecorder.lua`) was not touched. Nothing else under `docs/` was written to except
this Report.

### Questions

None — the Facts held as stated: the shared readers (`UI/Dashboard_Review.lua`,
`UI/ReplayWindow.lua`, `Engine/SimPlanner.lua`, `Engine/SimModel.lua`) already read
`rec.ownCasts`/`rec.spent`/`rec.foreignShare` with no Forever-side stamping; TBC's
`Engine/FightRecorder.lua` stamps them at the lines cited; `ScanAuras`/`PLAYER_REGEN_DISABLED`
in `Recorder_Forever.lua` matched the described "up to 2s early" staleness exactly.

## Lead review (2026-09-28)

Accepted as delivered. The lead reran every suite (recordcheck 14, everything else at its baseline;
apicheck 0 over 40 files, `--selftest` 10 of 10, refcheck ok) and `luac -p`. Shifting the fixture's
later times by 1 s to open the scan-to-pull gap is accepted: every relative timing the other
assertions read is unchanged. The `docs/TESTING.md` change in the tree is the lead's (§39).
