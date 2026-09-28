# T1 — the client adapter: bindings per flavour, secrets become nil, and a capability table

Status: **done -- lead-accepted 2026-09-28** (written and implemented the same day; see the Review at the end). M1 (`docs/ROADMAP-FOREVER.md` §2), task line
"T1 Client adapter + capability table". Needs T5 (the Forever stub profile and the TOC-driven
harness); taken after it.

## Goal

`MD.API` becomes the adapter the plan describes (`docs/FOREVER-PLAN.md` §3.2): a shared
`Client/API.lua` that knows how to call a client function safely -- present or absent, raising or
not, secret or plain -- and two small per-flavour files, `Client/API_Forever.lua` and
`Client/API_TBC.lua`, that say which client function each adapter name means on that client and
which events that client forbids. Every adapter call returns plain values or `nil` plus a reason
(`"absent"`, `"error"`, `"secret"`), so no shared file can ever hold a secret. `MD.API.Capabilities()`
lists every binding with its client name and whether this client has it -- the table `/st dump`
prints (T3). Nothing calls the new bindings yet: the core moves onto them in T1b. For every later
task that reads the client, and for the author's bug reports.

## Facts

Report numbers refer to `docs/probe/1.60.1_70009.md` (eighth and ninth at HEAD; sixth and seventh
via `git show ad94b2f^:` and `git show ad94b2f:` of the same path).

- The plan's contract (§3.2): "`Client/API.lua` is the **only** file that calls `C_*` or a Blizzard
  global. Everything else calls `MD.API.SpellInfo(id)`, `MD.API.UnitHealth(unit)`, ... Each
  wrapper: checks presence once (so a missing function is a capability, not a crash), `pcall`s, and
  **converts a secret into `nil` plus a reason** (`issecretvalue`), so no arithmetic on a secret ever
  happens outside this file." The roadmap (§1.1) puts the per-client bindings in
  `Client/API_Forever.lua` and `Client/API_TBC.lua`, with `Client/API.lua` shared and dispatching.
- `Client/API.lua` today: `MD.API.Has(name)` (walks a dotted name inside one `pcall`, answers
  `false` for absent, `true` for a secret or a non-callable scalar, the function or table itself
  otherwise; cached per name) and `MD.API.client` (`"forever"` for interface 16000-19999, `"tbc"`
  for 20000-29999, else `"unknown"`). Listed by `SpellTuner_Mainline.toc`, `SpellTuner.toc` and
  `SpellTuner_TBC.toc`, right after the `Client\TOC_*.lua` marker.
- What is secret on 70009, as T5's stub now fakes it: current health and power of every unit, in
  and out of combat (sixth `== readings now`; seventh, eighth `== combat snapshot`); a party
  member's `UnitHealthMax` in and out of combat (eighth); `GetManaRegen()`'s two returns in combat
  only (seventh); own and party auras raise in combat (seventh, eighth). Plain: `UnitHealthMax` and
  `UnitPowerMax` of the player, `UnitIsDeadOrGhost`, `UnitClass`, `UnitName`, `UnitLevel`,
  `GetRealmName` (all printed plain in the sixth report's `== client` and `== readings now`).
- `issecretvalue` and `issecrettable` are both in the 69893 baseline (`tools/data/forever_api.json`,
  T5). Which of the two a secret *table* answers is UNKNOWN (T0b); ask both, as `Has` already does.
- **Registering `COMBAT_LOG_EVENT_UNFILTERED` on Forever is forbidden** and trips the blocked-action
  dialog; no Forever file registers it, not even under `pcall` (`docs/FOREVER-PLAN.md` §1.2; sixth
  report). TBC registers it today (`UI/Summary.lua`, through `MD:On`).
- Add-on management moved on Forever: `GetAddOnMetadata` absent, `C_AddOns.GetAddOnMetadata` and
  `C_AddOns.LoadAddOn` present (sixth report `== functions`). `C_AddOns.IsAddOnLoaded`,
  `IsAddOnLoadOnDemand` and `GetAddOnInfo` are in the baseline's `C_AddOns` namespace. On TBC
  `Core.lua` reads its version with the global `GetAddOnMetadata` (`Core.lua:8-10`), which works
  (the TBC suites read `0.15.4` through it).
- `C_Timer.After` and `C_Timer.NewTicker` are on both clients (Forever: baseline `C_Timer`; TBC:
  `Core.lua` ticks with `C_Timer.NewTicker` today).
- T5's stub answers `C_AddOns.GetAddOnMetadata` and `C_AddOns.IsAddOnLoaded` only; `LoadAddOn` and
  the rest arrive with T2. A binding to a function the stub lacks reads `present = false`, which is
  the correct answer for that stub.
- The Lua multi-return trap (`CLAUDE.md`): `a and f() or b` truncates `f()` to one value. A wrapper
  that returns a function's results must pack them with `select("#", ...)` and unpack with the
  count.

## Files

| file | change | role |
|---|---|---|
| `Client/API.lua` | extended (below); `Has` and `client` unchanged | the shared adapter core |
| `Client/API_Forever.lua` | new | Forever's bindings and forbidden events |
| `Client/API_TBC.lua` | new | TBC's bindings |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `Client\API_Forever.lua` right after `Client\API.lua` | the Forever TOCs |
| `SpellTuner_TBC.toc` | `Client\API_TBC.lua` right after `Client\API.lua` | the TBC TOC |
| `tools/adaptercheck.lua` | new suite, `HARNESS_FLAVOUR = { "forever", "tbc" }` | the adapter under both profiles |

### `Client/API.lua` (shared -- no flavour check, no name that exists on one client only)

1. `MD.API.IsSecret(v)`: true when `issecretvalue(v)` or `issecrettable(v)` says so, each reached
   through `Has` and called under its own `pcall`; false when both are absent or say no. Never
   raises.
2. `MD.API.Call(dotted, ...)`: `fn = Has(dotted)`; not a function -> return `nil, "absent"`.
   Otherwise `pcall(fn, ...)`, packed with `select("#", ...)`. Raised -> return `nil, "error", msg`,
   where `msg` is the error if it is a string and not secret, else `"<unreadable error>"`. Any
   return value for which `IsSecret` is true -> return `nil, "secret"` (all or nothing: one secret
   return makes the whole call secret). Otherwise return every value, with its count.
3. `MD.API.Bind(map)`: for each `Name = "dotted.client.name"`, installs
   `MD.API[Name] = function(...) return MD.API.Call(dotted, ...) end` and records the binding. A
   later `Bind` of the same `Name` replaces the binding (a flavour file may rebind a shared name).
   A `Name` that is already an `MD.API` member **and not a binding** (`Has`, `Call`, `client`, ...)
   is left alone and not recorded. `Bind` calls nothing on the client.
4. `MD.API.Capabilities()`: a new array, one entry per recorded binding, sorted by `name`:
   `{ name = Name, client = dotted, present = (type(Has(dotted)) == "function") }`.
5. `MD.API.ForbidEvent(event)` and `MD.API.CanRegisterEvent(event)` (true unless forbidden).
6. `MD.API.Print(text)`: `DEFAULT_CHAT_FRAME:AddMessage(text)` through `Has` and `pcall`; does
   nothing if the frame is absent.
7. `MD.API.AddonVersion()`: `MD.API.AddOnMetadata(<this addon's name>, "Version")` if that returns
   a string, else nil. The addon name comes from the file's `...`.
8. The shared bindings (the same client name on both clients), bound here with one `Bind` call:
   `UnitClass`, `UnitName`, `UnitLevel`, `UnitGUID`, `UnitExists`, `UnitIsDeadOrGhost`,
   `UnitAffectingCombat`, `InCombatLockdown`, `UnitHealth`, `UnitHealthMax`, `UnitPower`,
   `UnitPowerMax`, `UnitPowerType` (each to the global of the same name),
   `ManaRegen = "GetManaRegen"`, `RealmName = "GetRealmName"`, `BuildInfo = "GetBuildInfo"`,
   `After = "C_Timer.After"`, `NewTicker = "C_Timer.NewTicker"`.

### `Client/API_Forever.lua` (Forever TOCs only)

`Bind` `AddOnMetadata = "C_AddOns.GetAddOnMetadata"`, `IsAddOnLoaded = "C_AddOns.IsAddOnLoaded"`,
`LoadAddOn = "C_AddOns.LoadAddOn"`, `IsAddOnLoadOnDemand = "C_AddOns.IsAddOnLoadOnDemand"`,
`AddOnInfo = "C_AddOns.GetAddOnInfo"`; and `MD.API.ForbidEvent("COMBAT_LOG_EVENT_UNFILTERED")` with
a comment citing the sixth report. This is the one Forever file allowed to name that event.

### `Client/API_TBC.lua` (TBC TOC only)

`Bind` the same five names to the globals `GetAddOnMetadata`, `IsAddOnLoaded`, `LoadAddOn`,
`IsAddOnLoadOnDemand`, `GetAddOnInfo`. No forbidden events.

## Rules

- **No arithmetic, comparison, `#`, indexing or table key on a value the client returned** until
  `IsSecret` has said no -- in `Client/API.lua` too. `type()` is allowed first.
- The multi-return trap: never `a and f() or b`; pack with `select("#", ...)`.
- `Client/API.lua` stays free of flavour checks beyond the existing `client` computation; the
  per-client knowledge lives in the two new files.
- No new globals. `SPELLTUNER_TOC` stays the only global the `Client/` files set (besides the
  probe's own).
- The TBC addon's behaviour does not change: nothing outside `Client/` calls the new functions in
  this task, and loading `API_TBC.lua` calls nothing on the client.
- Tests first: write `tools/adaptercheck.lua`, run it under both flavours against today's
  `Client/API.lua`, see it fail, then write the adapter. Say which failed.
- Comments say why, not what.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `tools/run.sh --flavour forever tools/adaptercheck.lua` ends `14 ok, 0 failed` and
   `tools/run.sh --flavour tbc tools/adaptercheck.lua` ends `10 ok, 0 failed`. The assertions,
   names verbatim; 1-8 run under both flavours, 9-14 under forever only, 15-16 under tbc only:
   1. "every binding is on MD.API and in the capability table": for the 18 shared names and the 5
      add-on names, `type(MD.API[name]) == "function"`; `Capabilities()` has exactly one entry per
      name, sorted by `name`, each with a string `client` and a boolean `present`.
   2. "a missing client function answers nil, absent": after `MD.API.Bind({ T1Missing =
      "NoSuchNamespace.NoSuchFn" })`, `MD.API.T1Missing()` returns exactly two values, `nil` and
      `"absent"`, and its capability entry has `present == false`.
   3. "a raising client function answers nil, error": with a global `T1_RAISE` that calls
      `error("boom")`, bound as `T1Raise`, the call returns `nil`, `"error"` and a string containing
      `boom`.
   4. "every return comes back, nils in the middle kept": a global `T1_MULTI` returning
      `nil, 5, nil`, bound as `T1Multi`: `select("#", MD.API.T1Multi()) == 3` and the second value
      is 5.
   5. "Bind never replaces the adapter's own members": `MD.API.Bind({ Has = "T1_MULTI" })` leaves
      `MD.API.Has` the same function, and `Capabilities()` has no entry named `Has`.
   6. "AddonVersion reads the flavour's TOC": equals the `## Version:` of
      `SpellTuner_Mainline.toc` under forever and of `SpellTuner_TBC.toc` under tbc.
   7. "Print reaches the chat frame": the text given to `MD.API.Print` is what
      `DEFAULT_CHAT_FRAME.AddMessage` received.
   8. "no binding raises, whatever it is given": inside one `pcall`, every binding in
      `Capabilities()` is called directly (not through its own `pcall`) with `("player")`, with
      `S.inCombat` false and then true; the `pcall` returns true.
   9. "current health and power are nil, secret, in and out of combat": `MD.API.UnitHealth("player")`
      and `MD.API.UnitPower("player", 0)` each return `nil, "secret"` with `S.inCombat` false and
      true.
   10. "the player's maxima are plain and a party member's health max is nil, secret": with a
       `party1` added, `UnitHealthMax("player")` and `UnitPowerMax("player", 0)` are numbers and
       `UnitHealthMax("party1")` returns `nil, "secret"`.
   11. "GetManaRegen: two numbers out of combat, nil, secret in combat".
   12. "the combat log is forbidden on Forever, other events are not":
       `CanRegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") == false`, `CanRegisterEvent("UNIT_COMBAT") == true`.
   13. "the add-on bindings are C_AddOns on Forever": the entries for `AddOnMetadata`, `LoadAddOn`,
       `IsAddOnLoaded`, `IsAddOnLoadOnDemand`, `AddOnInfo` have `client` `C_AddOns.GetAddOnMetadata`,
       `C_AddOns.LoadAddOn`, `C_AddOns.IsAddOnLoaded`, `C_AddOns.IsAddOnLoadOnDemand`,
       `C_AddOns.GetAddOnInfo`; `AddOnMetadata` and `IsAddOnLoaded` are `present`.
   14. "no secret ever leaves the adapter": every value returned by every binding in test 8's
       calls, plus `UnitHealthMax("party1")` and `ManaRegen()` in combat, has `issecretvalue` and
       `issecrettable` false.
   15. "TBC readings pass through plain": `MD.API.UnitHealth("player") == 5000`,
       `MD.API.UnitPower("player", 0) == 7009`, `ManaRegen()` returns two numbers,
       `CanRegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") == true`, `MD.API.IsSecret(5) == false`.
   16. "the add-on bindings are the classic globals on TBC": the five entries' `client` are
       `GetAddOnMetadata`, `LoadAddOn`, `IsAddOnLoaded`, `IsAddOnLoadOnDemand`, `GetAddOnInfo`.
   The test globals (`T1_RAISE`, `T1_MULTI`) are removed at the end of the suite.
2. `tools/run.sh tools/forevercheck.lua` ends `13 ok, 0 failed` (its assertion 2 now covers
   `API_Forever.lua` through the TOC); `tools/run.sh tools/probecheck.lua` ends `58 ok, 0 failed`.
3. The sixteen TBC suites print today's tails (simcheck `... -> PASS`; reccheck 54, replaycheck 80,
   replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27, simwindow 8,
   solvercheck 70, timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7).
4. `SpellTuner.toc` and `SpellTuner_Mainline.toc` still differ on exactly one line (the marker).
5. `tools/.lua/lua-5.1.5/src/luac -p Client/API.lua Client/API_Forever.lua Client/API_TBC.lua tools/adaptercheck.lua`
   is clean.
6. `git status --short` shows exactly `M Client/API.lua`, `?? Client/API_Forever.lua`,
   `?? Client/API_TBC.lua`, `M SpellTuner.toc`, `M SpellTuner_Mainline.toc`, `M SpellTuner_TBC.toc`,
   `?? tools/adaptercheck.lua` and this task file.
7. Paste into the Report: both adaptercheck outputs in full; which assertions failed before the
   adapter was written; the forevercheck and probecheck tails; the sixteen tails; the `luac`
   output; `MD.API.Capabilities()` printed one entry per line under forever (a one-liner is fine);
   `git status --short`.

## Out of scope

- Moving any caller onto the adapter: `Core.lua` (T1b), `UI/`, `Engine/`, `Verify.lua`.
- Spell, spellbook, aura, tooltip, damage meter and talent bindings (M2/M3 add them with the code
  that reads them).
- A way to hand a secret to a status bar (`StatusBar:SetValue` accepts one, plan §2.5) -- the clock
  in M2 decides its shape.
- `Client/Probe.lua` (it sees raw values by design), `tools/wowstub.lua`, `tools/harness.lua`.
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

Implemented as specified.

### Files

- `Client/API.lua`: kept `Has` and `client` byte-for-byte unchanged (only the anonymous `local _, MD
  = ...` became `local ADDON_NAME, MD = ...`, needed for `AddonVersion`). Appended: `Pack` (a
  `select("#", ...)`-counted table, so a `nil` in the middle of a return list survives storage —
  Lua's `{...}` array constructor is fine for this since indices are explicit, but the count still
  has to come from `select`, never `#t`), `MD.API.IsSecret`, `MD.API.Call`, `MD.API.Bind`,
  `MD.API.Capabilities`, `MD.API.ForbidEvent`/`CanRegisterEvent`, `MD.API.Print`,
  `MD.API.AddonVersion`, and the one `Bind` call for the 18 shared names.
- `Client/API_Forever.lua` (new): binds the five add-on names to `C_AddOns.*` and forbids
  `COMBAT_LOG_EVENT_UNFILTERED`.
- `Client/API_TBC.lua` (new): binds the same five names to the classic globals, forbids nothing.
- `SpellTuner_Mainline.toc`, `SpellTuner.toc`: `Client\API_Forever.lua` added right after
  `Client\API.lua`.
- `SpellTuner_TBC.toc`: `Client\API_TBC.lua` added right after `Client\API.lua`.
- `tools/adaptercheck.lua` (new): `HARNESS_FLAVOUR = { "forever", "tbc" }`, assertions 1-8 run
  under both flavours (read from `S.flavour`), 9-14 gated on `flavour == "forever"`, 15-16 on
  `flavour == "tbc"`.

### Tests first

Wrote `tools/adaptercheck.lua` against today's `Client/API.lua` (no `Bind`/`Capabilities` etc. yet)
and ran it before touching the adapter:

```
$ bash tools/run.sh --flavour forever tools/adaptercheck.lua
.../tools/adaptercheck.lua:51: attempt to call field 'Capabilities' (a nil value)
EXIT=1

$ bash tools/run.sh --flavour tbc tools/adaptercheck.lua
.../tools/adaptercheck.lua:51: attempt to call field 'Capabilities' (a nil value)
EXIT=1
```

Both flavours failed identically at the first `MD.API.Capabilities()` call (assertion 1), as
expected — none of the new adapter surface existed. Then wrote `Client/API.lua`,
`Client/API_Forever.lua`, `Client/API_TBC.lua` and the three TOC lines, and re-ran.

### `tools/adaptercheck.lua` — forever (14 ok, 0 failed)

```
every binding is on MD.API and in the capability table                   ok
a missing client function answers nil, absent                            ok
a raising client function answers nil, error                             ok
every return comes back, nils in the middle kept                         ok
Bind never replaces the adapter's own members                            ok
AddonVersion reads the flavour's TOC                                     ok - got 1.0.0-alpha.1, expected 1.0.0-alpha.1
Print reaches the chat frame                                             ok
no binding raises, whatever it is given                                  ok
current health and power are nil, secret, in and out of combat           ok
the player's maxima are plain and a party member's health max is nil, secret ok
GetManaRegen: two numbers out of combat, nil, secret in combat           ok
the combat log is forbidden on Forever, other events are not             ok
the add-on bindings are C_AddOns on Forever                              ok
no secret ever leaves the adapter                                        ok
14 ok, 0 failed
```

### `tools/adaptercheck.lua` — tbc (10 ok, 0 failed)

```
|cff9966ffSpellTuner:|r first run -- the widget is unlocked for 60s so you can drag it. /md lock when done, /md help for commands.
every binding is on MD.API and in the capability table                   ok
a missing client function answers nil, absent                            ok
a raising client function answers nil, error                             ok
every return comes back, nils in the middle kept                         ok
Bind never replaces the adapter's own members                            ok
AddonVersion reads the flavour's TOC                                     ok - got 0.15.4, expected 0.15.4
Print reaches the chat frame                                             ok
no binding raises, whatever it is given                                  ok
TBC readings pass through plain                                          ok
the add-on bindings are the classic globals on TBC                       ok
10 ok, 0 failed
```

(The `first run` chat line is `Core.lua`'s own onboarding message firing on `PLAYER_ENTERING_WORLD`
under the tbc harness load — unrelated to this task, printed by every tbc-flavoured suite.)

### `forevercheck.lua` / `probecheck.lua`

```
$ bash tools/run.sh tools/forevercheck.lua | tail -3
a TBC-only tool skips under --flavour forever                            ok

13 ok, 0 failed

$ bash tools/run.sh tools/probecheck.lua | tail -3
Q1 is answered by a change in bonus damage                               ok

58 ok, 0 failed
```

### The sixteen TBC suites

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
```

All sixteen match the tails named in the Acceptance section exactly.

### `luac -p`

```
$ tools/.lua/lua-5.1.5/src/luac -p Client/API.lua Client/API_Forever.lua Client/API_TBC.lua tools/adaptercheck.lua
(clean, no output)
```

### `MD.API.Capabilities()` under forever (23 entries, sorted by name)

```
AddOnInfo              C_AddOns.GetAddOnInfo            present=false
AddOnMetadata          C_AddOns.GetAddOnMetadata        present=true
After                  C_Timer.After                    present=true
BuildInfo              GetBuildInfo                     present=true
InCombatLockdown       InCombatLockdown                 present=true
IsAddOnLoadOnDemand    C_AddOns.IsAddOnLoadOnDemand     present=false
IsAddOnLoaded          C_AddOns.IsAddOnLoaded           present=true
LoadAddOn              C_AddOns.LoadAddOn               present=false
ManaRegen              GetManaRegen                     present=true
NewTicker              C_Timer.NewTicker                present=true
RealmName              GetRealmName                     present=true
UnitAffectingCombat    UnitAffectingCombat              present=true
UnitClass              UnitClass                        present=true
UnitExists             UnitExists                       present=true
UnitGUID               UnitGUID                         present=true
UnitHealth             UnitHealth                       present=true
UnitHealthMax          UnitHealthMax                    present=true
UnitIsDeadOrGhost      UnitIsDeadOrGhost                present=true
UnitLevel              UnitLevel                        present=true
UnitName               UnitName                         present=true
UnitPower              UnitPower                        present=true
UnitPowerMax           UnitPowerMax                     present=true
UnitPowerType          UnitPowerType                    present=true
```

`LoadAddOn`, `AddOnInfo`, `IsAddOnLoadOnDemand` read `present=false` because the T5 stub only
answers `C_AddOns.GetAddOnMetadata` and `C_AddOns.IsAddOnLoaded` today (Facts) — the correct
answer for that stub, not a bug in the binding.

### `git status --short`

```
 M Client/API.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M SpellTuner_TBC.toc
?? Client/API_Forever.lua
?? Client/API_TBC.lua
?? docs/tasks/T1-client-adapter.md
?? docs/tasks/T1b-shared-core.md
?? docs/tasks/T2-modules-window.md
?? docs/tasks/T3-console-dump.md
?? docs/tasks/T4-savedvariables-guard.md
?? docs/tasks/T6-apicheck.md
?? tools/adaptercheck.lua
```

(The other `docs/tasks/T*.md` files were already untracked at session start, not touched by this
task.) `SpellTuner.toc` and `SpellTuner_Mainline.toc` still differ on exactly one line (line 8, the
`Client\TOC_Plain.lua` / `Client\TOC_Mainline.lua` marker).

### Notes / deviations

- None. Every Fact checked out: `Has`/`client` needed no change, T5's stub secrets matched the
  Facts list exactly (current health/power always secret on Forever, party max health always
  secret, the player's own maxima plain, `GetManaRegen` secret only in combat, the combat log
  forbidden), and `C_AddOns` on the T5 stub answers only `GetAddOnMetadata`/`IsAddOnLoaded` as
  documented.
- Nothing outside `Client/` was touched; `Core.lua`, `UI/`, `Engine/`, `Verify.lua` are unchanged
  (T1b's job). Nothing calls the new bindings yet.
- Did not touch `CLAUDE.md`, `docs/PLAN.md`, `docs/HISTORY.md`, `docs/FOREVER-PLAN.md`, or any
  `docs/` file other than this Report section. No git commands beyond `git status --short` were
  run; nothing was staged or committed.

## Review (lead, 2026-09-28)

Accepted as delivered. Diff read in full; every acceptance line rerun: adaptercheck `14 ok` under
forever and `10 ok` under tbc; forevercheck `13`; probecheck `58`; the sixteen TBC tails unchanged;
the two Forever TOCs differ only on the marker; `luac -p` clean. The adapter does no arithmetic,
comparison or indexing on a client return before `IsSecret`; `Call` packs with `select("#")`; no
new global; `COMBAT_LOG_EVENT_UNFILTERED` is named only in `Client/API_Forever.lua`. Tests first
shown by a failing run (`Capabilities` nil under both flavours). The error text `Call` returns is a
raw client string -- whoever renders it escapes it (T3's dump does).
