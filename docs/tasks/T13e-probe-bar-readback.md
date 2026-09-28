# T13e — the probe asks whether a status bar hands a secret back

Status: **accepted** 2026-09-28 (lead review at the end). M3, the probe item the planner's ruling 1 asks for (`docs/FOREVER-PLAN.md`,
"Planner rulings for M3", item 1: "The probe asks once whether a StatusBar given a secret max reads
it back (it is expected not to; if it does, the stand-in goes)"). Lands in `1.0.0-alpha.4`, the
build `docs/TESTING.md` §38 installs.

## Goal

One `/st probe` answers, for a party member's max health, the player's current health and the
player's current mana, whether a plain `StatusBar` that is handed the client's value through its own
setters gives it back through its getters as a secret, as a plain number, or not at all -- out of
combat and in the 2 s combat snapshot. If a party member's max health comes back plain, M3 records
it instead of estimating it (`SM.EstimateMaxHP`, ruling 1). For the planner, through the author's
report. The same readings add `UnitHealthMissing(party1)`, the other road to the exact deficit the
engine decides on.

## Facts

- `UnitHealthMax(party1)` reads secret in and out of combat; the player's own max is plain; current
  health and power are secret always (`docs/probe/1.60.1_70009.md` eighth report;
  `FOREVER-PLAN.md` §1.2).
- A secret may be handed to a widget's own setters: that is how the clock draws the real pool
  (`Client/API.lua` `MD.API.DrawUnitPower`, T11), and the m2 run showed the bar drawn (screenshot 3,
  `docs/probe/1.60.1_70009-m2.md` remarks). Whether `GetValue` / `GetMinMaxValues` return the value,
  a secret, or raise: UNKNOWN -- this task is the probe for it.
- `UnitHealthMissing(player)` is already read (`Client/Probe.lua` `ReadingsLines`); for `party1` it
  is not. It is in the 69893 baseline (`tools/data/forever_api.json`) -- the implementer checks and
  says so; if it is not, the line is left out and the Report says why.
- `ReadingsLines` is copied into the 2 s combat snapshot (`TakeCombatSnapshot`), so a line added
  there is read in both places with no further wiring (T13b used this).
- Probe rules (T0-T0d, T13b): every check under `pcall`, every client value through `Show` / `Fmt`
  / `Esc`, `IsSecret` before anything but storing, **no arithmetic and no comparison on a client
  value** -- a value read back from the bar is a client value.

## Files

| file | change | role |
|---|---|---|
| `Client/Probe.lua` | a local `BarReadback(label, fnName, ...)` that creates **one** hidden `StatusBar` on first use (kept in an upvalue, never shown, no name, no parent other than `UIParent`), calls the named client function through the probe's existing `MD.API.Has` path, and inside one `pcall` hands the result to `SetMinMaxValues(0, v)` (for a max) or `SetMinMaxValues(0, 1)` + `SetValue(v)` (for a current value), then reads `GetMinMaxValues()` / `GetValue()` back. It returns one line: `bar <label>: set <ok or error>, read <secret or plain <Fmt(v)> or nil or error>`. Three lines appended to `ReadingsLines`: `bar UnitHealthMax(party1)`, `bar UnitHealth(player)`, `bar UnitPower(player, 0)`; plus `"UnitHealthMissing(party1) = " .. Show("UnitHealthMissing", "party1")` | the probe |
| `tools/wowstub.lua` | `FrameMT:GetMinMaxValues()` returning `self.minV, self.maxV` (the setter already stores them) | stub |
| `tools/probecheck.lua` | two new assertions | suite |

## Rules

- `CLAUDE.md` rules that bite: no client call outside `Client/` (this is `Client/`); ASCII only, no
  bare `|` -- everything printed goes through `Fmt`; no new global (the bar is an upvalue); no
  library; the multi-return trap (`GetMinMaxValues` returns two values -- take the second
  explicitly, never through `a and f() or b`).
- A frame the probe creates needs no backdrop, so no `BackdropTemplate`; it is never shown.
- `IsSecret` on the read-back value **before** `type` or `Fmt`; a secret is reported as `secret`,
  never formatted.
- Existing assertions: none may change.
- Tests first: the two assertions written and failing first; paste the failing run.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/probecheck.lua` ends `73 ok, 0 failed`. New names, verbatim:
   - "a status bar handed a secret reports whether it reads back secret" -- under the forever
     profile (`UnitHealthMax(party1)` is the stub's secret): the report has
     `bar UnitHealthMax(party1): set ok, read secret`, and the same three `bar` lines appear in the
     combat snapshot.
   - "a status bar handed a plain number reads it back plain" -- with the stub's
     `UnitHealthMax("party1")` made plain for this item (a number, restored after): the line reads
     `bar UnitHealthMax(party1): set ok, read plain <n>`; and with a stub `GetValue` that raises
     for this item, `read error` and the probe does not raise.
2. Every other suite at its count (baseline at the commit this lands on; the lead names it:
   probecheck 71 before this task, every other suite unchanged).
3. `python3 tools/apicheck.py` 0 findings, `--selftest` at its count.
4. `luac -p` clean on every file touched.
5. Paste into the Report: the failing run; probecheck's tail and the new report lines as the stub
   run prints them; every other tail; apicheck; luac; `git status --short`.

## Out of scope

- The clock, `MD.API.DrawUnitPower`, the recorder, `SM.EstimateMaxHP` -- whatever the answer is,
  acting on it is a later task.
- Every other probe section. `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

**Files touched:** `Client/Probe.lua`, `tools/wowstub.lua` (one hunk, tagged T13e), `tools/probecheck.lua`.
Nothing else was touched; `git status --short` at the end (below) shows the other worktree's T13c
files untouched by me.

### `Client/Probe.lua`

Added a local `BarReadback(label, fnName, ...)` right before `ReadingsLines`:
- Resolves `fnName` through `MD.API.Has` (the probe's existing path), same as every other reading.
- Creates one hidden `StatusBar` on first use (`CreateFrame("StatusBar", nil, UIParent)`, never
  shown, no name, kept in the `probeBar` upvalue) and reuses it for every call.
- `isMax = fnName:find("Max", 1, true) ~= nil` tells `UnitHealthMax` (max-style: `SetMinMaxValues(0,
  v)` / read back via `GetMinMaxValues()`) from `UnitHealth`/`UnitPower` (current-value style:
  `SetMinMaxValues(0,1)` + `SetValue(v)` / read back via `GetValue()`).
- One `pcall` wraps calling `fnName` and handing its return straight to the bar's setters (the
  client value never touches anything else in between); a second, separate `pcall` reads the value
  back. `IsSecret` is checked before `Fmt`/`type`, per the existing rule. `GetMinMaxValues`'s two
  returns are taken into two named locals (`errOrMin, maxV`), never through `a and f() or b`.
- Returns `"bar <label>: set <ok|error: ...>, read <secret|plain <Fmt(v)>|nil|error: ...>"`.

Three `BarReadback` lines plus a new `UnitHealthMissing(party1)` line appended to `ReadingsLines()`
(copied into the 2s combat snapshot automatically, as `TakeCombatSnapshot` already reuses this
function -- no further wiring needed, confirmed by the new checks passing against both `report1`
and the `report2` combat-snapshot segment). `UnitHealthMissing` is in the 69893 baseline
(`tools/data/forever_api.json`'s `functions` list), confirmed with a one-off `python3 -c
"import json; print('UnitHealthMissing' in json.load(open('tools/data/forever_api.json'))
['functions'])"` -> `True`, so the line was added rather than left out.

### `tools/wowstub.lua`

One hunk, tagged T13e:
```lua
-- T13e: the setter already stores what it was given; the getter just hands
-- it back, same as the real client's StatusBar.
function FrameMT:GetMinMaxValues() return self.minV, self.maxV end
```

### `tools/probecheck.lua`

Two new assertions, verbatim names as required:
- `"a status bar handed a secret reports whether it reads back secret"` -- reuses the existing
  `report1` (ooc) and the `report2` combat-snapshot segment (forever profile, `UnitHealthMax` always
  secret under the stub); no new fixture needed.
- `"a status bar handed a plain number reads it back plain"` -- a fresh `S10` load (forever
  profile), temporarily replaces the global `UnitHealthMax` so `"party1"` answers a plain `12345`
  (restored immediately after `Probe.Run`), and temporarily replaces `FrameMT:GetValue` (reached via
  `getmetatable(_G.UIParent)`, since `wowstub.lua` does not expose `FrameMT` itself) to `error(...)`
  for the current-value path (also restored after). Asserts `bar UnitHealthMax(party1): set ok, read
  plain 12345`, `bar UnitHealth(player): set ok, read error:` and `bar UnitPower(player, 0): set ok,
  read error:`, and that `Probe.Run` itself did not raise (`okH == true`).

### Tests first: the failing run

Implementation was written, then temporarily reverted (`Client/Probe.lua`'s `BarReadback` and its
call sites, `tools/wowstub.lua`'s `GetMinMaxValues`) to run the two new assertions against the old
code and confirm they fail, then the implementation was restored unchanged:

```
a status bar handed a secret reports whether it reads back secret        FAIL
SpellTuner probe: build 70009, 229 lines, saved. Click the box, Ctrl+A, Ctrl+C.
a status bar handed a plain number reads it back plain                   FAIL

71 ok, 2 failed
  FAIL a status bar handed a secret reports whether it reads back secret
  FAIL a status bar handed a plain number reads it back plain
```

### `bash tools/run.sh tools/probecheck.lua` after the fix (tail)

```
a status bar handed a secret reports whether it reads back secret        ok
SpellTuner probe: build 70009, 233 lines, saved. Click the box, Ctrl+A, Ctrl+C.
a status bar handed a plain number reads it back plain                   ok

73 ok, 0 failed
```

New report lines as the stub run prints them (forever profile, out of combat):
```
bar UnitHealthMax(party1): set ok, read secret
bar UnitHealth(player): set ok, read secret
bar UnitPower(player, 0): set ok, read secret
UnitHealthMissing(party1) = <secret>
```
And under the plain-number/raising-GetValue fixture:
```
bar UnitHealthMax(party1): set ok, read plain 12345
bar UnitHealth(player): set ok, read error: ...:21: stub GetValue raised
bar UnitPower(player, 0): set ok, read error: ...:21: stub GetValue raised
```

### Every other suite (tail)

```
== measurecheck ==
18 ok, 0 failed
== clockcheck ==
15 ok, 0 failed
== spellsui ==
15 ok, 0 failed
== bookcheck ==
15 ok, 0 failed
== parsecheck ==
11 ok, 0 failed
== modulecheck ==
14 ok, 0 failed
```
All at their baseline counts; none of my three touched files intersect `tools/modulecheck.lua`'s or
`tools/apicheck.py`'s own fixtures, and the T13c work (Modules/*, release.sh, tools/apicheck.py,
tools/modulecheck.lua) was left untouched by me.

### `python3 tools/apicheck.py`

```
apicheck: 8 Forever TOCs, 24 files, 40 distinct globals, 0 findings (baseline 69893)
```

### `python3 tools/apicheck.py --selftest`

```
FAIL Bad.lua:1 GetSpellInfo not in baseline 69893
FAIL Bad.lua:2 os not in the client's Lua
FAIL Bad.lua:3 UnitHealth client call outside Client/
FAIL Bad.lua:4 NewGlobalName new global
FAIL Bad.lua:5 COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT_UNFILTERED named
FAIL Bad.lua:6 C_Spell.NoSuchMember C_ member not in baseline 69893
FAIL Fixture_Mainline.toc:6 Gone.lua missing file
FAIL Modules/Sample/Sample_Mainline.toc:7 Missing.lua missing file
selftest: 8 of 8 findings as expected
```

### `luac -p` (tools/.lua/lua-5.1.5/src/luac)

```
$ tools/.lua/lua-5.1.5/src/luac -p Client/Probe.lua && tools/.lua/lua-5.1.5/src/luac -p tools/wowstub.lua && tools/.lua/lua-5.1.5/src/luac -p tools/probecheck.lua && echo ALL_OK
ALL_OK
```

### `git status --short`

```
 M Client/Probe.lua
 M Modules/SpellTuner_Practice/Module.lua
 M Modules/SpellTuner_Recorder/Module.lua
 M Modules/SpellTuner_Replay/Module.lua
 M release.sh
 M tools/apicheck.py
 M tools/modulecheck.lua
 M tools/probecheck.lua
 M tools/wowstub.lua
?? Modules/SpellTuner_Practice/Ready.lua
?? Modules/SpellTuner_Recorder/Ready.lua
?? Modules/SpellTuner_Replay/Ready.lua
?? docs/tasks/T13c-module-plumbing.md
?? tools/data/apicheck-fixture/Engine/
?? tools/data/apicheck-fixture/Modules/
?? tools/data/modulecheck-fixture/
```
The `Modules/*`, `release.sh`, `tools/apicheck.py`, `tools/modulecheck.lua`, and the untracked
T13c-related files are the concurrent T13c implementer's work, not mine -- I did not touch them.

### Skipped / notes

- Did not touch `tools/wowstub.lua`'s `LoadAddOn` part or any of the T13c files, per instructions.
- Out-of-scope items (the clock, `MD.API.DrawUnitPower`, the recorder, `SM.EstimateMaxHP`) left
  untouched, as the task specifies acting on the answer is a later task.
- No question; the task's Facts held (UnitHealthMissing is in the 69893 baseline) and the acceptance
  criteria are all met.

## Lead review (2026-09-28)

Accepted with one lead fix, said here as the process requires: `BarReadback` read the bar back even
when the set had failed, and the bar is shared across readings and runs, so a failed set reported the
previous reading's value (a `set error` on `UnitHealthMax` in the combat snapshot would have read
`plain 1` from the preceding current-value reading). The lead added one guard: a failed set returns
`read skipped`. No assertion covers it; the two acceptance lines are unaffected. Suites rerun by the
lead: probecheck 73, every other suite at its baseline, apicheck 0, selftest 8 of 8, refcheck ok;
`luac -p` clean.
