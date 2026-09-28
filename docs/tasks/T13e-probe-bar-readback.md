# T13e — the probe asks whether a status bar hands a secret back

Status: **open**. M3, the probe item the planner's ruling 1 asks for (`docs/FOREVER-PLAN.md`,
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

(implementer)
