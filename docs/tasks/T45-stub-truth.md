# T45 (P1) -- Stub truth

Status: **built** 2026-09-30 on branch `plan/P1` (base `d8a926f`), awaiting the wave-1 integration.

## The task (docs/PLAN-refactor-ux.md section 5, P1)

Review Q1 (the forever stub's secret is a table, so every `IsSecret` guard on an event payload is
untested), every stub knob waves 2-4 need, and Q15's live-cost gap.

- (a) Under the forever profile `type(secret)` answers `"number"`; the stand-in keeps raising on
  arithmetic, compare, index, call, concat. Drop `adaptercheck.lua:227`. The stub header lists the
  gaps Lua 5.1 cannot close as review-only.
- (b) Knobs, each defaulting to today's answer: `S.powerType`, `UnitPowerMax(u, t)` per type, a raid
  (`S.raid`, `GetRaidRosterInfo`), `UnitName`'s realm, `SetValue` clamping, `IsMouseOver` /
  `GetMouseFocus` from `S.mouseFocus`, an `xpcall` that passes its extra arguments.
- (c) New `tools/costcheck.lua` (tbc): the live branch of `SD:GetCost`, the static fallback, and
  `/md verify`'s COST line.

Owned files (section 4, wave 1): `tools/wowstub.lua`, `tools/adaptercheck.lua`, `tools/clockcheck.lua`,
new `tools/costcheck.lua`. Nothing shipped is changed. **TBC: no** (test code only).

## What was built

| file | change |
|---|---|
| `tools/wowstub.lua` | **Q1.** In `UseProfile("forever")` a wrapped `type`: a `S.Secret()` stand-in answers `"number"`, `S.Secret("string")` answers `"string"` (for a secret name or GUID when a later suite needs one), a `S.SecretTable()` still `"table"`, everything else Lua's own answer. The stand-in's metatable is unchanged (it still raises on arithmetic, `<`/`<=`, secret-vs-secret `==`, index, newindex, call, `..`, `tostring`). Lua's own `type` and `xpcall` are captured at the top of the file (`rawtype`, `rawxpcall`; `S.rawtype` for a harness) so the stub's own frame code still sees a secret as a table. The header and the `SECRET_MT` comment now say what is review-only: `#secret`, `secret == plain` and `t[secret]` (Lua 5.1 gives a table no hook for them, the client raises on all three). **Knobs**, all at the old answer by default: `S.powerType = 0` behind `UnitPowerType` (a unit's own `.powerType` wins; one return, as before); `S.powerMax = {}` -- `UnitPowerMax(u, t)` answers `S.powerMax[t]` when set (`t` nil = the current type, as the client), else `S.manaMax` (the forever profile's player branch goes through the same function; other units stay secret); `S.raid = false` -- `IsInRaid()` is `S.raid == true` and `GetRaidRosterInfo(i)` answers from `S.units["raid" .. i]` in the client's order (name -- `Name-Realm` for a unit with a realm --, rank `.rank` or 0, subgroup `.subgroup` or 1, level, localized class, token, zone, online, isDead, role nil, isML false, combatRole), nil for a missing unit; `UnitName(u)` returns `name, realm` for a unit with `.realm` and the single value it always did otherwise (the forever profile's two-value form now carries the realm); `FrameMT:SetValue` clamps a plain number to a plain `SetMinMaxValues` range and a new range clamps the value already there (a secret value or a secret bound is stored unread and never compared -- `MD.API.DrawUnitPower` and `HealthMax` hand bars secrets); `S.mouseFocus = nil` -- `FrameMT:IsMouseOver()` is true for that frame and each of its ancestors, `GetMouseFocus()` answers it and `GetMouseFoci()` answers `{ it }` (the forever profile's baseline pruning removes `GetMouseFocus`, which 69893 lacks, and keeps `GetMouseFoci`); a global `xpcall(f, handler, ...)` that passes the extra arguments to `f` as the WoW client does (no arguments: Lua's own call; some: a tail call through one closure, so `f`'s frame sits directly under `xpcall`). |
| `tools/adaptercheck.lua` | The `t[secret] = ...` line is gone (a table keyed by a secret cannot exist on the client, and with `type(secret) == "number"` `Copy` would count the key as a second secret). Count unchanged, 22 / 15. |
| `tools/clockcheck.lua` | +1 (20 -> 21): **in a fight the book is never indexed by a secret spell id.** For one fight the suite wraps `MD.Book.Get` (its `spells` table becomes a proxy whose `__index` records every key) and `MD.Book.ReadSpell`, casts `S.Secret()` then Rejuvenation R1, and asserts no secret key reached either and that the plain cast did spend. It watches the table because the stub cannot trap `t[secret]`. |
| `tools/costcheck.lua` | New, tbc, 3: Healing Touch R1 (5185, static 20 with the harness's talents, base 25) given a live cost of static + 7 through `S.liveCosts` -- `SD:GetCost` answers `27, "api"`; with the live cost cleared, `20, "table"`; `MD:RunVerify()` with the live cost set prints exactly one `COST|r HealingTouch R1 (5185): static 20 (base 25), live 27 (used)` line. The assertion matches only the COST line, so P3's em-dash fixes elsewhere in `Verify.lua` do not move it. |

No knob has an assertion of its own in this task (the plan gives every suite but clockcheck and
costcheck equal counts; the knobs are asserted by the tasks that use them: P4/P5 the raid and realm,
P7 the clamp and the mouse focus, P8 the power type and max, P11 `xpcall`). They were smoke-tested
here by a scratch script (not committed), 27 of 27: every default equal to the old answer (one
return from `UnitPowerType` and `UnitName`, `S.manaMax` for any type, `IsInRaid` false and
`GetRaidRosterInfo(1)` nil, an unranged slider keeping 500, `IsMouseOver` false), then each knob --
power type 3 with `powerMax[3] = 100` and a warrior's `powerMax[0] = 0`, `Healer, OtherRealm`, a raid
roster of two with subgroups and `Healer-X`, `xpcall(function(a, b) return a + b end, print, 2, 3)`
-> `true, 5` (and a nil argument kept), the clamp at both ends and on a new range, the mouse over a
child and its parent but not `UIParent`, and under the forever profile `type(secret) == "number"`,
arithmetic still raising, `GetMouseFocus` pruned and `GetMouseFoci` kept, a secret on a bar and a
secret max left unread, a secret `powerMax[0]`.

## Tests first

**The Q1 mutation** (the `IsSecret` half removed from `Recorder_Forever.lua:458`,
`if type(amount) ~= "number" then`), `tools/run.sh tools/recordcheck.lua`:

```
parent stub (d8a926f):  24 ok, 0 failed                                   rc=0
P1 stub:                 21 ok, 3 failed                                  rc=1
  FAIL damage and heals are kept per tracked token, once each; other tokens are ignored - dmg=4 heal=1
  FAIL a secret argument is counted and never stored - unreadable=0 dmg=4
  FAIL the stream holds only numbers, strings, booleans and tables of them, nothing secret
```

The guard was restored (`git checkout`) and recordcheck is 24 again.

**All seven guards of review Q1 mutated at once** (`Recorder_Forever.lua:458, 485, 498, 567, 568`,
`Spells/Measure.lua:796`, `UI/Clock_Forever.lua:247`), P1 stub: recordcheck red (the three above),
measurecheck red (it raises `attempt to use a secret value (stub)` from `Spells/Measure.lua:813` --
arithmetic on the amount the guard let through), clockcheck red on the new assertion
(`keys=3 secret=2`); scenariocheck, gatecheck, coachforever, forevercheck and adaptercheck stay green
(those sites are not on their paths). Restored.

**clockcheck +1**: with only `UI/Clock_Forever.lua:247` mutated
(`if type(spellID) == "number" then`), the new assertion is red on the P1 stub
(`FAIL in a fight the book is never indexed by a secret spell id - keys=3 secret=2`) and green on the
parent stub (`keys=1 secret=0`: the stand-in's `type` was `"table"`, so the second clause alone kept
the secret out). "a cast with a secret id ... is counted, never guessed" stays green under the
mutation either way -- `book.spells[secret]` is a quiet miss in Lua 5.1, which is exactly the gap the
new assertion watches. Restored.

**costcheck**, a fresh suite: with `SD:GetCost`'s live branch dropped (`local live = nil`),
`2 ok, 1 failed`, rc=1 (`FAIL a live cost for a druid heal is what GetCost answers (api) - cost=20
src=table live=27 static=20`). Restored: 3 ok.

**No B27+.** The type override alone, on unmodified code, turned exactly one suite red:
adaptercheck/forever, on the `t[secret]` line the plan drops (`copy1._secret=2`). Nothing shipped
failed.

## Suites (exit codes checked, both flavours)

| suite | before (d8a926f) | after |
|---|---|---|
| clockcheck | 20 | **21** |
| costcheck | -- | **3** (new) |
| adaptercheck forever / tbc | 22 / 15 | 22 / 15 |
| every other suite in docs/TOOLS.md section 1 | | equal: simcheck PASS (0 FAIL lines), reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 35, dashui 63, regencheck 27, simwindow 8, solvercheck 77, restcheck 51, timeline 27, spelltip 48, practice 80, practiceui 50, migrate 7, probecheck 87, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 15, reviewforever 11, coachforever 18, practiceforever 25, bindscheck 6, parsecheck 12, bookcheck 21, tipcheck 37, spellsui 47, measurecheck 30, releasecheck 13, importcheck 19, themecheck 23, tabscheck 24, wincheck 53, corecheck 10 / 8, svcheck 6 / 1, consolecheck 17 / 1 |

Every suite exits 0. `python3 tools/apicheck.py`: 0 findings; `--selftest` 10 of 10;
`refcheck.py --selftest` ok. `luac -p` on the four files.

**Byte comparison.** Every suite's full output was captured on the parent stub and on the P1 stub.
The only differences besides clockcheck's new line are timings (`12 ms` / `13 ms`, `2 ms` / `3 ms`)
and table / function addresses (`table: 0x...`) -- which differ from run to run on the same code. The
TBC suites are otherwise byte-identical.

## Integrator lines

- **docs/TOOLS.md section 1, the table**, a new row after `spelltip.lua`:
  `| costcheck.lua | **the live-cost branch** (T45, tbc, 3): a live cost for a druid heal is what `SD:GetCost` answers (`api`), the static table when the client says nothing (`table`), and `/md verify` prints one COST line when the two disagree |`
- **docs/TOOLS.md, the `clockcheck.lua` row**, appended: ` Since **T45** (21): in a fight the book is never indexed by a secret spell id (the suite watches the book's keys, since the stub cannot trap `t[secret]`)`
- **docs/TOOLS.md, the `adaptercheck.lua` row**, appended: ` Since **T45**: no table keyed by a secret (it cannot exist on the client)`
- **docs/TOOLS.md, the loop**: add `costcheck` to the first `for` list (after `spelltip`).
- **docs/TOOLS.md, the paragraph on the `forever` profile** (after "... does not have."), appended:
  `Since **T45** a secret's `type()` answers `"number"` (`S.Secret("string")` for a string), as the client answers the type under the secret, so an `IsSecret(x) or type(x) ~= "number"` guard is tested on its IsSecret half. Three things stay **review-only**, because Lua 5.1 gives a table no hook for them and the client raises on all three: `#secret`, `secret == plain` and a secret used as a table key. The stub's knobs (T45): `S.powerType`, `S.powerMax[t]`, `S.raid` with `S.units["raidN"]`, a unit's `realm`, a slider's value clamped to its range, `S.mouseFocus` (`IsMouseOver`, `GetMouseFocus`, `GetMouseFoci`), and an `xpcall` that passes its extra arguments as the client's does.`
- **tools/data/expected-counts.json** (when P13 creates it): `clockcheck` 21, `costcheck` 3,
  `adaptercheck` 22 (forever) / 15 (tbc); everything else as the table above.
- **CLAUDE.md**, the `Client/Probe.lua` row, after "which the client does raise on;": insert
  `since T45 (P1) the stand-in's `type()` answers `"number"`, as the client's does, and those three are review-only;`
  and in the `tools/` row's list of Forever suites, after `` `clockcheck` (13), ``: `` `costcheck` (3, tbc, T45), ``.
- **docs/HISTORY.md**: `T45 (P1): the forever stub's secret answers type() as "number"; the knobs waves 2-4 need; costcheck.`
- TOCs, docs/TESTING.md, docs/DECISIONS.md: none.

## Deviations

- `S.Secret(kind)` takes an optional type (`"string"`), not in the plan: a secret name or GUID
  answers `"string"` on the client, and without it a later suite could not stand one in. The default
  is the plan's `"number"`.
- `GetMouseFoci()` added beside `GetMouseFocus()`: retail (and the 69893 baseline) has only
  `GetMouseFoci`, so the forever profile prunes `GetMouseFocus`, as the client would.
- `SetMinMaxValues` also clamps the value already there (the client does); the plan names only
  `SetValue`. No suite moved.
- `GetRaidRosterInfo` names a unit with a realm `Name-Realm`, as the client's roster does; P4/P5
  should read the name part if they need the bare name.
