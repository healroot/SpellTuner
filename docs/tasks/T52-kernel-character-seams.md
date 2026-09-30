# T52 -- Kernel: the character, and two test seams (plan P8)

Status: **built** 2026-09-30 on branch `plan/P8` (base `4702b5c`), wave 3 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P8)

Review items (`docs/review/2026-09-30-project-review.md`): B1, B2, A31 (`PLAYER_LEVEL_UP`), Q15
(`MD.API.Invalidate`, `MD:SetTalents`).

- **(a) B1.** `usesMana` answered from data: `MD.API.UnitPowerMax("player", 0)` read plain and greater
  than 0. Only when that read is absent, secret or raised does the code fall back to today's
  `UnitPowerType == 0`.
- **(b) B2.** `InTreeForm` falls back to the buff scan only when `GetShapeshiftFormID` is absent or
  raised, never when it answered `nil`.
- **(c) A31.** `PLAYER_LEVEL_UP`: `tonumber(level)` only after `MD.API.IsSecret(level)` is false;
  else the adapter's `UnitLevel`.
- **(d) Q15.** `MD.API.Invalidate(name)` clears one `Has` cache entry (for tests); `MD:SetTalents(tbl)`
  in `Core_TBC.lua` sets the talent ranks, and `tools/harness.lua` uses it instead of overriding
  `MD:TalentRank` after load.

Owned files (section 4, wave 3): `Core.lua`, `Core_TBC.lua`, `Client/API.lua`, `tools/harness.lua`,
`tools/corecheck.lua`, `tools/adaptercheck.lua`. Nothing else was touched.

## What was built

| file | change |
|---|---|
| `Core.lua` | **B1:** `MD:DetectProfile` reads `MD.API.UnitPowerMax("player", 0)`; when it is not secret and is a number, `usesMana = max > 0`; otherwise (`nil, "absent" / "secret" / "error"`) `usesMana = MD.API.UnitPowerType("player") == 0` as before. The old comment ("druids are checked at login (caster form)") is replaced by the rule. **A31:** the `PLAYER_LEVEL_UP` handler asks `MD.API.IsSecret(level)` first and calls `tonumber` only on a plain argument; an unreadable one falls to `MD.API.UnitLevel("player")`, then the level already held. |
| `Core_TBC.lua` | **B2:** `MD:InTreeForm` returns `id == TREE_FORM_ID` whenever `pcall(GetShapeshiftFormID)` succeeded, `nil` included (caster form); the "Tree of Life" buff scan runs only when the function is absent or raised. **Q15:** `MD:SetTalents(tbl)` -- the ranks are `tbl`, held not copied, and every `ScanTalents` takes it instead of the client until `MD:SetTalents(nil)` (which gives `MD.talents` a fresh table rather than wiping the tool's); before login the login scan finds it, after login it rescans at once. `ScanTalents` keeps its client path byte for byte and fires `TALENTS_CHANGED` and its debug line on both paths. Nothing in the game calls `SetTalents`. |
| `Client/API.lua` | **Q15:** `MD.API.Invalidate(name)` -- forgets one name's cached `Has` answer (a non-string is ignored). Not a binding, so the capability table and `/st dump` are unchanged. |
| `tools/harness.lua` | The TBC path calls `MD:SetTalents(TALENTS)` before login instead of `function MD:TalentRank(...)`. `MD.harnessTalents` is still that table, so `tools/regencheck.lua`'s edits to `MD.harnessTalents["Dreamstate"]` still change the ranks (same table), and the suites now run the real `TalentRank` and the login scan. |
| `tools/corecheck.lua` | +3 under both flavours, +2 under tbc only (below). |
| `tools/adaptercheck.lua` | +1 under both flavours (below). |

### The new assertions

- `corecheck` (both) **a login in Cat form keeps the mana side (B1)**: `S.powerType = 3`, the mana max
  left at the stub's 7009, `MD:DetectProfile()` -> `usesMana == true`.
- `corecheck` (both) **a class with no mana pool does not use mana (B1)**: `WARRIOR`, power type 1,
  `S.powerMax[0] = 0` -> `false`.
- `corecheck` (both) **an unreadable mana max falls back to the power type (B1)**: power type 3 and,
  on forever, `S.powerMax[0] = S.Secret()`; on tbc (which has no secrets) a `UnitPowerMax` that raises,
  swapped in through `MD.API.Invalidate`. Either way no raise and `usesMana == false`; on tbc the
  raising function must actually have been called (the max is read at all).
- `corecheck` (tbc) **a secret level from PLAYER_LEVEL_UP is not stored (A31)**: a marker table, an
  `issecretvalue` recognising it (reached through `MD.API.Invalidate("issecretvalue")`), and a
  `tonumber` that hands a secret back unchanged, as the client's does for a secret number (whose type
  is `"number"`), where Lua's own answers `nil` for a table. `PLAYER_LEVEL_UP(marker)` leaves
  `MD.player.level` plain and equal to `UnitLevel`; `PLAYER_LEVEL_UP(65)` afterwards still stores 65.
  Everything restored.
- `corecheck` (tbc) **Tree form: the buff scan only when the form API is missing or raised (B2)**: with
  a "Tree of Life" buff on the player, `GetShapeshiftFormID` answering `nil` -> `false`, answering `2`
  -> `true`, raising -> `true` (buff), absent -> `true` (buff). The buff list carries both
  `"Tree of Life"` and `"Spell33891"`: `Core_TBC.lua` captures `GetSpellInfo(33891)` at load, before the
  harness names 33891.
- `adaptercheck` (both) **Invalidate makes a later Has see a new global**: `Has("T52_LATE")` is `false`;
  the global defined, `Has` still `false` (cached); after `Invalidate`, the function; another name's
  cache untouched; the global removed and invalidated, `false` again.

## Tests first (on the parent's code, only the tests changed)

All four runs rc 1 (`tools/run.sh --flavour <f> tools/<suite>.lua`, failures and footers):

```
== corecheck/forever rc=1
a login in Cat form keeps the mana side (B1)                             FAIL - usesMana=false
12 ok, 1 failed
== corecheck/tbc rc=1
a login in Cat form keeps the mana side (B1)                             FAIL - usesMana=false
an unreadable mana max falls back to the power type (B1)                 FAIL - raised: .../tools/corecheck.lua:178: attempt to call field 'Invalidate' (a nil value)
a secret level from PLAYER_LEVEL_UP is not stored (A31)                  FAIL - raised: .../tools/corecheck.lua:326: no MD.API.Invalidate
Tree form: the buff scan only when the form API is missing or raised (B2) FAIL - nil->true 2->true raised->true absent->true
9 ok, 4 failed
== adaptercheck/forever rc=1
Invalidate makes a later Has see a new global                            FAIL - raised: .../tools/adaptercheck.lua:308: attempt to call field 'Invalidate' (a nil value)
22 ok, 1 failed
== adaptercheck/tbc rc=1
Invalidate makes a later Has see a new global                            FAIL - raised: .../tools/adaptercheck.lua:308: attempt to call field 'Invalidate' (a nil value)
15 ok, 1 failed
```

Two tbc assertions failed on the missing seam rather than on the bug, so a second run put only
`MD.API.Invalidate` in (the parent's `Core.lua` and `Core_TBC.lua` unchanged) to show each bug itself:

```
== corecheck/forever rc=1
a login in Cat form keeps the mana side (B1)                             FAIL - usesMana=false
== corecheck/tbc rc=1
a login in Cat form keeps the mana side (B1)                             FAIL - usesMana=false
an unreadable mana max falls back to the power type (B1)                 FAIL - usesMana=false raised=false
a secret level from PLAYER_LEVEL_UP is not stored (A31)                  FAIL - stored=true plain65=true
Tree form: the buff scan only when the form API is missing or raised (B2) FAIL - nil->true 2->true raised->true absent->true
== adaptercheck/forever rc=0
== adaptercheck/tbc rc=0
```

(`raised=false`: the parent never reads the max at all; `stored=true`: the parent stores the secret the
event handed it.) The two B1 assertions that pass on the parent -- a warrior, and a secret max on
forever -- pin the fallback and the no-mana answer so the fix cannot overreach.

After the fix: `corecheck` 13 / 13, `adaptercheck` 23 / 16, all rc 0.

## Suites (exit codes checked; the loop in docs/TOOLS.md section 1)

| suite | before (4702b5c) | after |
|---|---|---|
| `corecheck` forever / tbc | 10 / 8 | **13 / 13** |
| `adaptercheck` forever / tbc | 22 / 15 | **23 / 16** |
| every other suite | simcheck 13, reccheck 63, replaycheck 82, replayui 98, runcheck 81, reviewui 46, navui 35, dashui 63, regencheck 27, simwindow 8, solvercheck 84, restcheck 51, timeline 27, spelltip 48, costcheck 3, practice 81, practiceui 50, migrate 7, probecheck 87, forevercheck 16, modulecheck 14, kitcheck 7, recordcheck 29, scenariocheck 14, gatecheck 9, replayforever 15, reviewforever 13, coachforever 20, practiceforever 25, bindscheck 6, parsecheck 15, bookcheck 21, tipcheck 37, clockcheck 23, spellsui 48, measurecheck 30, releasecheck 16, importcheck 20, themecheck 23, tabscheck 24, wincheck 53, svcheck 6 / 1, consolecheck 17 / 1 | all equal, all rc 0 |
| `simcheck` FAIL lines | 0 | 0 |
| `apicheck.py` / `--selftest` | 0 findings / 10 of 10 | same |
| `textcheck.py` / `--selftest` | 0 findings / 2 of 2 | same |
| `refcheck.py --selftest` | 2 of 2 | same |

`luac -p` passes on every changed `.lua`.

**Output, not only counts.** The parent tree (`git archive 4702b5c`) and this branch were each run
through every suite above (except `releasecheck`) and their full outputs diffed, the tree's path
normalised. 31 suites and `svcheck` / `consolecheck` under both flavours are byte-identical --
`reccheck`, `replaycheck`, `regencheck`, `spelltip`, `dashui`, `forevercheck`, `consolecheck`, `simcheck`,
`runcheck`, `restcheck`, `practice`, `practiceui` and `navui` among them. The other nine (`replayui`,
`reviewui`, `simwindow`, `solvercheck`, `kitcheck`, `recordcheck`, `replayforever`, `coachforever`,
`practiceforever`) differ only in lines that differ between two runs of the parent itself: table
addresses, `N ms`, `N frames`, and the coach's `search N evaluations` (sliced on
`debugprofilestop`). No other line moved. The harness's `SetTalents` in place of the `TalentRank`
override therefore changed nothing any suite prints -- `regencheck` (which edits
`MD.harnessTalents["Dreamstate"]` mid-run) and `spelltip` (which reads `MD.harnessTalents`) included.

## TBC

Two shared-file behaviour changes reach TBC, both bug fixes with a DECISIONS entry below:

- **B1.** A login or `/reload` in Cat or Bear form keeps the clock, the Advisor, the datatext, the
  self-assigned HEALER role and the mana cooldowns. For a character in caster form at login nothing
  changes (a mana user's max is above 0; a warrior's or rogue's mana max is 0).
- **B2.** In caster form next to another resto druid in Tree of Life, `InTreeForm()` is false: no tree
  modifiers in the rows or the kit, no `form = "tree"` in recordings, labels and the profile, no
  `FORM_CHANGED` when the other druid shifts. When the client has no `GetShapeshiftFormID` (or it
  raises) the buff scan is used exactly as before.

`MD:SetTalents` and `MD.API.Invalidate` are called by nothing in the game. No look, recorder format or
model rule changed.

## Integrator lines

**docs/DECISIONS.md** (new section, after T49's "Pins are capped in the Review tab, and a cross-realm
member keeps a bare name"):

> ## usesMana is whether the player has a mana pool; Tree form's buff scan is a fallback for a missing API only (2026-09-30, T52)
>
> **usesMana is whether the player has a mana pool.** `MD.player.usesMana` was the power type at login
> (`UnitPowerType("player") == 0`), so a druid who logged in or reloaded in Cat or Bear form (power
> type 3 or 1) had the clock, the Advisor, the datatext, the self-assigned HEALER role and the mana
> cooldowns switched off for the session -- nothing re-evaluated it. It is now answered from data:
> `MD.API.UnitPowerMax("player", 0)` read plain and above 0 (a druid in any form has a mana pool; a
> warrior or rogue has a maximum of 0). No class list: which classes use mana on Forever's retail
> engine is not guessed. Only when that read is absent, secret or raised does the current power type
> decide, as before. Both lines (`Core.lua` is shared).
>
> **Tree form: the buff scan is a fallback for a missing API only.** `GetShapeshiftFormID` answering
> `nil` is an answer (caster form). The buff scan by name used to run on that `nil` too and found
> another resto druid's Tree of Life party aura (34123, the same name), so the rank math, the kit, the
> recorder, the cast labels and the profile thought the player was in Tree form, and `FORM_CHANGED`
> fired whenever the other druid shifted or left range. The scan now runs only when the function is
> absent or raised. TBC only (`Core_TBC.lua`).

**CLAUDE.md**, table rows:

- `Client/API.lua` row, after `... the error handler).` and before ` Listed by **both** TOCs`: add
  ` **T52 (P8):** `MD.API.Invalidate(name)` forgets one name's cached `Has` answer -- for the offline
  tests, which swap a global after the adapter has answered for it; nothing in the game calls it.`
- `Core.lua` row, append before the closing ` |`: ` **T52 (P8):** `MD.player.usesMana` is whether
  the player has a mana pool -- `UnitPowerMax("player", 0)` read plain and above 0, the power type only
  when that read is unreadable (a login in Cat or Bear form no longer switches the mana side off, B1);
  `PLAYER_LEVEL_UP`'s argument asked `IsSecret` before `tonumber` (A31)`.
- `Core_TBC.lua` row, append before ` TBC TOC only |`: ` **T52 (P8):** `InTreeForm` takes the buff
  scan only when `GetShapeshiftFormID` is absent or raised, never on its `nil` (B2);
  `MD:SetTalents(tbl)` -- the ranks a scan takes, held by reference, until `SetTalents(nil)`; the
  harness's seam, nothing in the game calls it (Q15).`
- The `tools/` row's harness sentence, if the integrator keeps one: `tools/harness.lua` sets the
  build's talents with `MD:SetTalents` rather than replacing `MD:TalentRank`.

**docs/TOOLS.md** section 1:

- `adaptercheck.lua` row, append: `Since **T52** (23 / 16): `MD.API.Invalidate` makes a later `Has`
  see a global defined after the first answer, and leaves other names' answers alone (Q15)`.
- `corecheck.lua` row, append: `Since **T52** (13 / 13): a login in Cat form keeps the mana side, a
  class with no mana pool does not use mana, an unreadable mana max (secret on forever, raising on tbc)
  falls back to the power type (B1); on tbc a secret level from `PLAYER_LEVEL_UP` is not stored (A31)
  and Tree form takes the buff scan only when `GetShapeshiftFormID` is missing or raised (B2)`.

**docs/TESTING.md** section 44 (after waves 1-3, TBC): items 1 (**Cat form reload, B1**) and 2 (**Tree
aura, B2**) of the plan's section 9, as written there.

**tools/data/expected-counts.json** (when P13 creates it): `corecheck` 13 forever / 13 tbc,
`adaptercheck` 23 forever / 16 tbc.

No TOC changes.

## Deviations

- **The level assertion runs under tbc, not forever.** The forever stub's `FOREVER_EVENTS`
  (`tools/wowstub.lua`) does not list `PLAYER_LEVEL_UP`, so `MD:On` cannot register it and the kernel's
  handler (and `Spells/Book.lua`'s `MarkDirty` on level-up) never exists under the forever harness.
  `Core.lua` is shared, so the handler is exercised under tbc with a stand-in secret (above). The stub
  gap -- a retail event the Forever client surely accepts, refused offline -- is for P10, which owns
  `tools/wowstub.lua` in wave 4; this task does not own it.
- **Counts per flavour differ from the plan's "+5".** The plan's five `corecheck` assertions are all
  here; three run under both flavours (the unreadable-max case is a secret on forever and a raising
  function on tbc, which has no secrets), two under tbc only (the level, above, and Tree form, which is
  `Core_TBC.lua`): forever +3, tbc +5.
- **`MD:SetTalents` is by reference and pins the scan.** "Sets the talent ranks" is implemented as: the
  ranks ARE the table, and a scan takes it instead of the client until `SetTalents(nil)`. By reference
  because `tools/regencheck.lua` edits `MD.harnessTalents` mid-run and expects the ranks to follow;
  pinning the scan because the stub's talent API answers nothing and the login scan would otherwise
  wipe the harness's build (the old override hid that by never reading `MD.talents`).
- **Other research tools still override `MD:TalentRank`** (`tools/import.lua`, `reproduce.lua`,
  `strategies.lua`, `solvercmp.lua`, `wclcheckkit.lua`, `healcheck.lua`). Not this task's files; each
  can switch to `MD:SetTalents` when next touched (P13 owns five of them in wave 5).
