# T17c — a party member's real max through a status bar, off until the probe says so

Status: **accepted** 2026-09-29 (lead review at the end), after T17b (a5e49e0). M3, the last part of the planner's amendment to
ruling 1.

## Goal

The adapter can read a party member's max health by handing the client's (secret) value to a hidden
`StatusBar` and reading it back; the recorder records that value as a plain max when it comes back
plain, so the scenario uses the real max and no stand-in at all. The path ships **off** -- a
constant in the adapter -- because whether a status bar hands a secret back plain is UNKNOWN until
the author's TESTING §38.3 report; switching it on after that report is a one-line change. For the
planner's amendment ("the stand-in goes entirely if §38.3's status-bar readback returns a secret max
plain") and for the author's coached pulls, whose percentages would then be exact.

## Facts

- The ruling: `docs/FOREVER-PLAN.md`, "Planner rulings for M3", the amendment dated 2026-09-28 (end
  of day): "... and the stand-in goes entirely if §38.3's status-bar readback (T13e) returns a
  secret max plain."
- The answer is UNKNOWN: `docs/probe/` holds only the build 70009 reports (`1.60.1_70009.md`,
  `1.60.1_70009-m2.md`), both from before T13e; the question is asked by `Client/Probe.lua`
  `BarReadback` (679-743, T13e) and answered by the line `bar UnitHealthMax(party1): set ok, read
  plain <n>` or `... read secret` in the report TESTING §38.3 asks for
  (`docs/probe/<build>-alpha4-party.md`). Nothing past alpha.3 is installed yet (handover).
- A party member's max is secret in and out of combat; the player's is plain (`FOREVER-PLAN.md`
  §1.2; T13e Facts; the stub's `forever` profile, `tools/wowstub.lua` 579-582).
- The pattern for a secret leaving through a widget: `MD.API.DrawUnitPower` (`Client/API.lua`
  310-325) fetches the function through `MD.API.Has`, hands the raw value to the bar's setters
  inside one `pcall`, and never reads it. `MD.API.IsSecret` (106) asks both predicates.
- T13e's own lesson (`Client/Probe.lua` 713-715): a shared bar keeps the previous value after a
  failed set, so a read after a failed set reports someone else's answer.
- The stub's `StatusBar` stores what it is given and hands it back (`FrameMT:SetMinMaxValues` /
  `GetMinMaxValues`, `tools/wowstub.lua` 400, 403), so under the `forever` profile a secret set is a
  secret read; T13e's probecheck item replaced the getter through `getmetatable(_G.UIParent)` to
  make it answer plain or raise.
- The recorder: `Modules/SpellTuner_Recorder/Recorder_Forever.lua` `R:Refresh` (64-116) records
  `maxHP = -1, maxSecret = true` for every token but the player (86-93); `CopyRoster` (121-128)
  copies `name, guid, class, role, level, maxHP, maxSecret` into the stream.
- The scenario treats a roster entry with `maxSecret == false` and `maxHP > 0` as the real max
  (`maxSource = "recorded"`, T17b's `ChooseMaxes` in `Modules/SpellTuner_Replay/Scenario_Forever.lua`).
- recordcheck asserts "a party member's max health is recorded unknown, the player's as read"
  (`tools/recordcheck.lua` 244-251); it must keep holding with the path off.

## Files

| file | change | role |
|---|---|---|
| `Client/API.lua` | `MD.API.BAR_READS_MAX = false` with a comment naming the report line that switches it on; `MD.API.HealthMax(unit)`: the client's `UnitHealthMax` through `MD.API.Has`; absent -> `nil, "absent"`; a plain number -> that number (no bar); a secret with the constant false -> `nil, "secret"` without touching any frame; with it true -> one hidden `StatusBar` created on first use (an upvalue, no name, parent `UIParent`, never shown), reset with `SetMinMaxValues(0, 1)`, then inside one `pcall` the raw value handed to `SetMinMaxValues(0, v)`; a failed set -> `nil, "error"` without reading; else the second return of `GetMinMaxValues()` read inside a `pcall`: raised -> `nil, "error"`; `IsSecret` -> `nil, "secret"`; a plain number `> 0` -> that number; anything else -> `nil, "error"`. Beside `DrawUnitPower` | the adapter |
| `Modules/SpellTuner_Recorder/Recorder_Forever.lua` | in `R:Refresh`, for a token other than the player: `MD.API.HealthMax(token)`; a number -> `maxHP = n, maxSecret = false, maxVia = "bar"`; otherwise as today (`-1`, `true`). `CopyRoster` copies `maxVia` | the recorder |
| `tools/adaptercheck.lua` | three assertions, forever only | suite |
| `tools/recordcheck.lua` | one assertion | suite |

## Rules

- `CLAUDE.md`: client calls in `Client/` only -- the recorder calls `MD.API.HealthMax`, never the
  bar or `UnitHealthMax`; **no arithmetic or comparison on a secret** -- the raw value is only ever
  handed to a setter, and the read-back is compared (`> 0`) only after `IsSecret` is false and
  `type` is `"number"`; the **multi-return trap** -- `GetMinMaxValues` returns two values: take them
  into two locals, never through `a and f() or b`; no new global (`BAR_READS_MAX` and `HealthMax` are
  fields of `MD.API`); no library; the bar needs no `BackdropTemplate` (never styled or shown).
- The constant ships `false`. Do not switch it on, in the code or in a test that does not restore it.
- `Client/API.lua` is loaded by both TOCs: nothing on TBC calls `HealthMax`; adaptercheck under
  `tbc` stays at 15.
- Tests first: write the four assertions, run them, and paste the failing run before touching the
  addon.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh --flavour forever tools/adaptercheck.lua` ends `22 ok, 0 failed`; under `tbc`,
   `15 ok, 0 failed`. New names, verbatim:
   - "a party member's max through a status bar is off until the probe says so" -- with
     `BAR_READS_MAX` false: `HealthMax("party1")` is `nil, "secret"` and the bar's getter was never
     called (a spy on the stub's `GetMinMaxValues`); `HealthMax("player")` is the plain number.
   - "with the readback on, a bar that hands back a secret gives nil, secret" -- the stub as it is;
     the return is `nil, "secret"` and no secret leaves (`issecretvalue` false on every return).
   - "with the readback on, a bar that hands back a plain max gives that number, and a raising bar
     gives nil, error" -- the getter replaced to answer `0, 12345`: `12345`; replaced to raise:
     `nil, "error"` and `HealthMax` itself does not raise. The getter and the constant restored.
2. `bash tools/run.sh tools/recordcheck.lua` ends `15 ok, 0 failed`. New name, verbatim: "with the
   readback on and a bar that reads back plain, a party member's max is recorded plain" -- a kept
   recording made in a fresh session (`NewSession`) with the constant on and the getter answering
   the Tank's own `hpMax`: the Tank's roster entry in the stored stream has `maxHP` equal to it,
   `maxSecret == false`, `maxVia == "bar"`; the existing "recorded unknown" assertion unchanged and
   passing (its session keeps the constant off).
3. Every other suite at its count (T17b's baselines: coachforever 13, everything else as in the
   handover); `python3 tools/apicheck.py` 0 findings, `--selftest` 10 of 10, `refcheck.py
   --selftest` ok.
4. `luac -p` clean on every Lua file touched.
5. Paste into the Report: the failing first run; adaptercheck (both flavours) and recordcheck in
   full; every other suite's tail (`docs/TOOLS.md` §1 loop); apicheck and its selftest; refcheck
   selftest; luac; `git status --short`.

## Out of scope

- Switching the constant on (the lead does that, one line, after the author's §38.3 report).
- `Client/Probe.lua` (T13e's question stays as it is), `MD.API.DrawUnitPower`, the clock.
- The scenario and the coach (T17b already treat a plain max as recorded). The player's own max.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

**What was done.**

- `tools/adaptercheck.lua`: three assertions (verbatim names), forever only, written first. `tools/recordcheck.lua`: one assertion (verbatim name), written first, in a fresh `NewSession` with the constant on and the bar getter replaced through `getmetatable(_G.UIParent)`; the constant and the getter are restored in the same block, and the existing "recorded unknown" assertion is untouched.
- `Client/API.lua`: `MD.API.BAR_READS_MAX = false` (comment names the probe line that switches it on) and `MD.API.HealthMax(unit)`, beside `DrawUnitPower`, as specified: `UnitHealthMax` through `Has` (absent -> `nil, "absent"`), a plain number returned as it is with no bar, a secret with the constant not true -> `nil, "secret"` without touching a frame; with it true one lazily made hidden `StatusBar` (upvalue, no name, parent `UIParent`), reset with `SetMinMaxValues(0, 1)`, the raw value handed to `SetMinMaxValues(0, v)` inside one `pcall`, a failed set -> `nil, "error"` without reading, the second return of `GetMinMaxValues()` read inside a `pcall` into two locals, then raised -> `nil, "error"`, secret -> `nil, "secret"`, plain number > 0 -> that number, anything else -> `nil, "error"`.
- `Modules/SpellTuner_Recorder/Recorder_Forever.lua`: `R:Refresh` calls `MD.API.HealthMax(token)` for every token but the player; a number -> `maxHP = n, maxSecret = false, maxVia = "bar"`, otherwise `-1, true` as before. `maxVia` is kept on the live entry and `CopyRoster` copies it.
- The constant ships `false`; nothing turns it on outside the two tests, which restore it (each asserts the original was `false`).

**Skipped.** Nothing. Out-of-scope files untouched (Probe, DrawUnitPower, clock, scenario, coach, docs).

**Surprising.** The first (failing) adaptercheck run printed no error text: the harness output just stopped after the last old assertion with exit code 1 (`HealthMax` was nil, so the new block raised). The recordcheck failure was a plain assertion failure. A raising run is still a failing run; no assertion was changed afterwards. `docs/tasks/HANDOVER.md` was already modified before I started (git status at the start of the conversation).

**Question.** None.

### The failing first run (before any addon code)

```
$ bash tools/run.sh --flavour forever tools/adaptercheck.lua 2>&1 | tail -3     (exit code 1)
the add-on bindings are C_AddOns on Forever                              ok
no secret ever leaves the adapter                                        ok
(the new block raised on MD.API.HealthMax == nil; no "N ok" line was printed)

$ bash tools/run.sh tools/recordcheck.lua 2>&1 | tail -4
|cff9966ffSpellTuner:|r Recorder: loaded
with the readback on and a bar that reads back plain, a party member's max is recorded plain FAIL - rec=table: 0x60b34d407660 tank=-1,true,nil

14 ok, 1 failed
  FAIL with the readback on and a bar that reads back plain, a party member's max is recorded plain - rec=table: 0x60b34d407660 tank=-1,true,nil
```

### adaptercheck, forever (full)

```
every binding is on MD.API and in the capability table                   ok
a missing client function answers nil, absent                            ok
a raising client function answers nil, error                             ok
every return comes back, nils in the middle kept                         ok
Bind never replaces the adapter's own members                            ok
AddonVersion reads the flavour's TOC                                     ok - got 1.0.0-alpha.5, expected 1.0.0-alpha.5
Print reaches the chat frame                                             ok
t1-print-old-frame
Print follows the chat frame the UI has now                              ok
no binding raises, whatever it is given                                  ok
Copy keeps plain fields and drops secret ones                            ok - copy1.n=5 copy1.nested=nil copy2.nested.a=1 copy1._secret=1
Constant reads a plain enum value and nothing else                       ok - player=0 missing=nil notAFunction=nil
a copying binding hands back a copy, never the client's table            ok
DrawUnitPower hands the values over without reading them                 ok
current health and power are nil, secret, in and out of combat           ok
the player's maxima are plain and a party member's health max is nil, secret ok
GetManaRegen: two numbers out of combat, nil, secret in combat           ok
the combat log is forbidden on Forever, other events are not             ok
the add-on bindings are C_AddOns on Forever                              ok
no secret ever leaves the adapter                                        ok
a party member's max through a status bar is off until the probe says so ok - flag=false a=nil b=secret calls=0 p=5000
with the readback on, a bar that hands back a secret gives nil, secret   ok - a=nil b=secret leaked=false
with the readback on, a bar that hands back a plain max gives that number, and a raising bar gives nil, error ok - plain=12345 okRaise=true ra=nil rb=error
22 ok, 0 failed
```

### adaptercheck, tbc (full)

```
|cff9966ffSpellTuner:|r first run — the widget is unlocked for 60s so you can drag it. |cffffff00/md lock|r when done, |cffffff00/md help|r for commands.
every binding is on MD.API and in the capability table                   ok
a missing client function answers nil, absent                            ok
a raising client function answers nil, error                             ok
every return comes back, nils in the middle kept                         ok
Bind never replaces the adapter's own members                            ok
AddonVersion reads the flavour's TOC                                     ok - got 0.15.4, expected 0.15.4
Print reaches the chat frame                                             ok
t1-print-old-frame
Print follows the chat frame the UI has now                              ok
no binding raises, whatever it is given                                  ok
Copy keeps plain fields and drops secret ones                            ok - copy1.n=5 copy1.nested=nil copy2.nested.a=1 copy1._secret=nil
Constant reads a plain enum value and nothing else                       ok - player=nil missing=nil notAFunction=nil
a copying binding hands back a copy, never the client's table            ok
DrawUnitPower hands the values over without reading them                 ok
TBC readings pass through plain                                          ok
the add-on bindings are the classic globals on TBC                       ok
15 ok, 0 failed
```

### recordcheck (full)

```
|cff9966ffSpellTuner:|r Recorder: loaded
the recorder registers nothing until its module is on                                      ok - before=0 after=1
|cff9966ffSpellTuner:|r Recorder: loaded
a pull starts at combat and ends after it, and the damage meter is read once combat is over ok - rec=table: 0x581851bf14e0 dur=40 meter.read=current ownCasts=6 spent=165 foreignShare=0.23076923076923
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
|cff9966ffSpellTuner:|r Recorder: loaded
with the readback on and a bar that reads back plain, a party member's max is recorded plain ok - rec=table: 0x581851be5270 tank=9000,false,bar

15 ok, 0 failed
```

### The docs/TOOLS.md section 1 loop, tails

```
simcheck      |cff9966ffSpellTuner:|r   measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS
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
recordcheck   15 ok, 0 failed
scenariocheck 9 ok, 0 failed
gatecheck     8 ok, 0 failed
replayforever 10 ok, 0 failed
reviewforever 8 ok, 0 failed
coachforever  13 ok, 0 failed
practiceforever 8 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
adaptercheck/forever 22 ok, 0 failed
adaptercheck/tbc 15 ok, 0 failed
corecheck/forever 10 ok, 0 failed
corecheck/tbc 8 ok, 0 failed
svcheck/forever 6 ok, 0 failed
svcheck/tbc   1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc 1 ok, 0 failed
apicheck: 8 Forever TOCs, 44 files, 44 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok
```

### luac

`tools/.lua/lua-5.1.5/src/luac -p Client/API.lua Modules/SpellTuner_Recorder/Recorder_Forever.lua tools/adaptercheck.lua tools/recordcheck.lua` -> no output, exit 0.

### git status --short

```
 M Client/API.lua
 M Modules/SpellTuner_Recorder/Recorder_Forever.lua
 M docs/tasks/HANDOVER.md
 M docs/tasks/T17c-party-max-bar-readback.md
 M tools/adaptercheck.lua
 M tools/recordcheck.lua
```
(`docs/tasks/HANDOVER.md` was modified before I began.)

## Lead review (2026-09-29)

Accepted, no change by the lead. The lead read the diff, reran every suite (adaptercheck 22 / 15,
recordcheck 15, coachforever 13, every other suite at its baseline; apicheck 0 findings over 44
files, `--selftest` 10 of 10, refcheck ok) and `luac -p` on the four files.

- `MD.API.BAR_READS_MAX` ships `false` (Client/API.lua 333); both tests that switch it on assert the
  original was `false` and restore it with the getter.
- The raw value is only handed to `SetMinMaxValues`; the read-back is compared only after
  `IsSecret` is false and `type` is `"number"`; the bar is reset before each set and a failed set is
  never read -- T13e's lesson kept.
- **Switching it on** is the lead's one-word change after the author's §38.3 report shows `bar
  UnitHealthMax(party1): set ok, read plain <n>` (in and out of combat); if it reads `secret`, the
  path stays off and T17b's leave-one-out max is the answer.
