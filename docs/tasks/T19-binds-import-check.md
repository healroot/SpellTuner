# T19 — the bindings imports, checked against the Forever builds rather than assumed

Status: **accepted** 2026-09-29 (lead review at the end); re-checked by the lead 2026-09-29 against the tree at 3fc0623 (after T17b/T17c):
line numbers, the adapter bindings T18 added, and the baselines below are current. M4 (`docs/ROADMAP-FOREVER.md` M4, "T19 bindings + imports re-verified";
exit: "Cell / Clique / keybinding import works against the Forever builds of those addons
(re-checked, not assumed)").

## Goal

`/st binds check` writes one copy-box report of what the three import sources look like on this
client -- the key bindings and the action slots they lead to, Cell's click-castings, Clique's binds
-- in the shapes the importers read, escaped, with whether each importer recognised them. The
importers themselves refuse a shape they do not recognise with a named reason, instead of guessing.
The author runs it on the beta and pastes the result; the lead fixes an importer from that paste,
never from memory. For the M4 exit.

## Facts

- The importers (`Engine/Practice.lua`, shared by both TOCs; T18 put their client calls behind the
  adapter as `MD.API.BindingCount` / `Binding` / `BindingAction` / `ActionInfo` / `MacroInfo` /
  `Specialization`, bound in `Client/API_TBC.lua` 42-47 and `Client/API_Forever.lua`):
  `PR.ImportKeybinds` (453) walks `BindingCount` / `Binding(i)` (whose return shape "moved between
  clients (a category was added)", 462-464), `BindingAction`, follows a command to an action slot
  (`PR.SlotForCommand` 410: `ACTIONBUTTON<n>`, `MULTIACTIONBAR<b>BUTTON<n>` at Blizzard's page
  offsets, or a frame carrying an `action` attribute -- `FrameSlot` 402, ElvUI, Bartender, Dominos)
  and reads the slot (`ActionInfo` -> spell or macro, `MacroBody` 249 -> `PR.MacroSpell` 231).
  `PR.ImportCell` (299) reads `_G.CellCharacterDB.clickCastings` through `CellList` (286: `common`
  when `useCommon`, else `[MD.API.Specialization() or 1]`, else `[1]`), each entry `{ attr, kind,
  action }` decoded by `PR.CellKey` (257). `PR.ImportClique` (347) reads `CliqueBinds` (330):
  `Clique.db.profile.binds`, or `CliqueDB3` / `CliqueDB` `.profiles["<name> - <realm>"]` (else any
  profile) `.binds`, each bind `{ key, type, spell / macro ... }`. `PR.ApplyImport` (505) merges.
- Every one of these formats was read from the **TBC** builds of Cell and Clique (v0.15.1-v0.15.2);
  whether the Forever builds exist and keep them is UNKNOWN (plan §2.4: "Cell's Forever release, if
  any, may store click-castings differently -- re-check"). The author's beta folder is known to hold
  EllesmereUI (plan §1.5); Cell and Clique there are UNKNOWN.
- `GetSpecialization` is **not** in the Forever baseline: `Client/API_Forever.lua` 106-108 leaves
  `MD.API.Specialization` nil there, so `CellList` falls to spec 1 on Forever. The keybinding
  functions (`GetNumBindings`, `GetBinding`, `GetBindingAction`, `GetActionInfo`, `GetMacroInfo`)
  are all in the 69893 baseline (`tools/data/forever_api.json`, checked by the lead).
- The report's helpers on the Forever TOC: `MD:ShowCopyPopup(title, text)` (`UI/DebugConsole.lua`
  136, listed by `SpellTuner_Mainline.toc`); the build via `MD.API.BuildInfo` (`Client/API.lua`
  399); the character via `MD.API.UnitName("player")` / `MD.API.RealmName()`. The escaping rule
  (`\` -> `\\`, `|` -> `||`, every byte outside printable ASCII -> `\ddd`) exists only as file-local
  copies (`Client/Probe.lua`'s `Esc`, `UI/Dump_Forever.lua` 10-21): `Engine/Practice.lua` gets its
  own local copy of the same rule, named in the Report, not a new shared function.
- The command: `Modules/SpellTuner_Practice/Commands_Forever.lua` 22 registers `binds` (and 23
  `bindings`) as `ToggleBindings` through `MD:AddCommand`; `check` is its argument.
- Other add-ons' SavedVariables are ordinary tables, not client values -- but on this client any
  value read through them could still be a secret only if the client put one there, which it does
  not for add-on data; the check still reads them under `pcall` and `type()` before indexing.

## Files

| file | change | role |
|---|---|---|
| `Engine/Practice.lua` | `PR.BindsReport()` -> the report text below; each importer checks the shape it reads (types of the fields it indexes) and returns `nil, { source, error = "<what it expected> - <what it found>" }` on anything else | the importers |
| `Modules/SpellTuner_Practice/Commands_Forever.lua` | `/st binds check` -> `MD:ShowCopyPopup("SpellTuner binds check", PR.BindsReport())` | command |
| `tools/bindscheck.lua` (new, forever) | the suite below | suite |

### The report (`PR.BindsReport()`)

```
=== SpellTuner binds check  build <b>  <char>  <date> ===
== keybindings
count: <GetNumBindings or absent>
binding 1 = <every return of GetBinding(1), escaped>          (the first 5 rows whole: the shape)
bound: <n> keys; resolved to a slot: <m>; to a spell: <s>; to a macro: <k>
first 10 resolved: <key> -> <command> -> slot <n> -> <spell|macro name>
importer: <n> bindings imported, <k> skipped (<reasons, counted>)
== Cell
CellCharacterDB: <absent | table>
clickCastings: <absent | type>, keys: <sorted top-level keys, escaped, first 20>
first entry: <one entry, depth 3, escaped>
importer: <recognised: n bindings | not recognised: reason>
== Clique
Clique: <absent | table>; Clique.db.profile.binds: <absent | type>; CliqueDB3: ...; CliqueDB: ...
first bind: <one, depth 3, escaped>
importer: <recognised: n bindings | not recognised: reason>
```

ASCII only, every add-on or client string through the probe's escaping rule (`||` for a pipe --
though the copy box renders `||` as `|`, m2 287, so the reader of the paste expects a single one).

## Rules

- Nothing is imported by `check`; it only reads. No client call outside `Client/`; add-on tables read
  under `pcall`, `type()` first.
- The TBC importers' behaviour on a recognised shape is unchanged: practice 74, practiceui 49.
- No new global; no library; ASCII, no bare `|` in anything rendered (every add-on or client string
  through the local `Esc`).
- The multi-return trap: `MD.API.Binding(i)` returns a variable number of values -- pack them
  (`{ MD.API.Binding(i) }` with `select("#", ...)` where a trailing nil matters), never
  `a and f() or b`.
- Tests first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/bindscheck.lua` ends `6 ok, 0 failed`. Names, verbatim:
   1. "the report has the three sections in order, ASCII, with no bare pipe"
   2. "with neither Cell nor Clique loaded the report says absent and nothing raises"
   3. "a Cell table in the TBC shape is recognised and its first entry shown"
   4. "a Cell table in an unknown shape is refused with what was expected and what was found"
   5. "a Clique table in an unknown shape is refused the same way"
   6. "the keybinding section shows the first rows whole and counts what resolved"
2. TBC practice 74, practiceui 49; every other suite at its count (at 3fc0623: the TBC sixteen as
   in `docs/tasks/HANDOVER.md`, probecheck 73, forevercheck 13, modulecheck 14, kitcheck 7,
   recordcheck 15, scenariocheck 9, gatecheck 8, replayforever 10, reviewforever 8, coachforever 13,
   practiceforever 8, parsecheck 11, bookcheck 15, tipcheck 14, clockcheck 15, spellsui 15,
   measurecheck 18, adaptercheck 22/15, corecheck 10/8, svcheck 6/1, consolecheck 11/1);
   `python3 tools/apicheck.py` 0 findings, `--selftest` 10 of 10, `refcheck.py --selftest` ok.
   `bindscheck` is added to the loop the lead runs (it is not yet in `docs/TOOLS.md` §1).
3. `luac -p` clean.
4. Paste into the Report: the failing run; bindscheck in full; the report text for the TBC-shaped
   fixture and for the unknown shapes; every other tail; apicheck; luac; `git status --short`.

## Out of scope

- Changing an importer to a Forever format nobody has seen (that waits on the author's paste).
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

### What was done, file by file

- `tools/bindscheck.lua` (new, forever, written first): the six checks named in Acceptance 1, verbatim. It loads the Practice module as `tools/practiceforever.lua` does, builds `MD.SpellData` with `MD.RankMath:SpellKit({ live = true })`, and takes the report only through a `Report()` wrapper so a missing or raising `PR.BindsReport` fails the checks instead of crashing the suite. Check 1 also runs `/st binds check` with `MD.ShowCopyPopup` replaced and asserts the title and that the body is the report. Check 5 also asserts that the TBC-shaped Clique table still imports (1 binding).
- `Engine/Practice.lua`:
  - New file-local helpers before `MacroBody`: `Esc` (its own copy of the probe's rule, `\` -> `\\`, `|` -> `||`, non-printable bytes -> `\ddd`; not a shared function), `Safe` (index under `pcall`, `type()` first), `TypeName`, `KeysOf` (sorted, escaped, at most 20), `Dump` (a value to depth 3, escaped), `Found`.
  - `CellList` is split into `CellPick` (the list the importer would use) and `CellList` (that, plus the shape check). `PR.ImportCell` now returns `nil, { source = "Cell", error = "expected ... - found ..." }` for: `CellCharacterDB` not a table; `clickCastings` missing or not a table; `useCommon` set with `common` not a table; no `common` / spec list; a list that is not a list of tables; or no entry with a string first field (the first entry's keys are named). Behaviour on a recognised shape is unchanged (practice 74, practiceui 49). A non-table entry inside a recognised list is now skipped with a reason instead of raising.
  - `CliqueBinds` is split the same way (`CliquePick` + shape check): `Clique.db.profile.binds`, `CliqueDB3` / `CliqueDB` `.profiles[...]` `.binds`, each wrong type named; no bind with a string `key` and string `type` is refused, naming the first bind's keys. The "any profile" fallback now takes the first profile by name instead of by `pairs` order (deterministic; identical when the character's own profile exists). `PR.ImportClique` returns the reason; a non-table bind is skipped with a reason.
  - `PR.ImportKeybinds`: the per-row logic moved into local `BindingKeys` and `PackBinding` (packs every return of `MD.API.Binding(i)` with `select("#")`, no `and/or`), used by both the importer and the report. New refusal: if `GetBinding(1)` does not return a command string first, `nil, { error = "expected GetBinding(1) to return a command name string first - found ..." }`.
  - New `PR.BindsReport()` in the format of the task (below). It reads only; the importers run under `pcall`.
- `Modules/SpellTuner_Practice/Commands_Forever.lua`: `/st binds check` -> `MD:ShowCopyPopup("SpellTuner binds check", MD.Practice.BindsReport())`. Only `binds` takes the argument; the help line now reads `/st binds [check]`. `bindings` is unchanged.

Format choices the task left open: the `first 10 resolved:` header is followed by one indented line per key (`  <key> -> <command> -> slot <n> -> <what>`), `none` after the header if there are none; `what` is `spell <id> (<family if this addon models it>)`, `macro "<name>"` or `empty`. `binding i = ` shows every return, strings quoted and escaped, `nil` for a nil. Errors from the shape checks are escaped when built (so the report does not escape them twice). The importer line reads `recognised: n bindings, k skipped (<reason> xN; ...)`, `n` being what would be imported. The build in the header is `GetBuildInfo`'s second return (`70009` under the stub).

### The failing run (before any addon code; `PR.BindsReport` did not exist)

```
with neither Cell nor Clique loaded the report says absent and nothing raises                   FAIL -
a Cell table in the TBC shape is recognised and its first entry shown                           FAIL -
a Cell table in an unknown shape is refused with what was expected and what was found           FAIL -  // Cell is not loaded, or it has no click-castings.
a Clique table in an unknown shape is refused the same way                                      FAIL -
the keybinding section shows the first rows whole and counts what resolved                      FAIL -
the report has the three sections in order, ASCII, with no bare pipe                            FAIL - iH=nil nonAscii=false bare=false popup=nil

0 ok, 6 failed
```

### bindscheck after (check lines; each prints the report text as its detail, omitted here)

```
with neither Cell nor Clique loaded the report says absent and nothing raises                   ok
a Cell table in the TBC shape is recognised and its first entry shown                           ok
a Cell table in an unknown shape is refused with what was expected and what was found           ok
a Clique table in an unknown shape is refused the same way                                      ok
the keybinding section shows the first rows whole and counts what resolved                      ok
the report has the three sections in order, ASCII, with no bare pipe                            ok

6 ok, 0 failed
```

### The report text

TBC-shaped fixture (Cell `common` with a macro, a spell id and `togglemenu`; a `CliqueDB3` profile with a spell and a target bind):

```
== Cell
CellCharacterDB: table
clickCastings: table, keys: class, common, useCommon
first entry: {"type5", "macro", "Main overtime"}
importer: recognised: 2 bindings, 1 skipped (bound to togglemenu x1)
== Clique
Clique: absent; Clique.db.profile.binds: absent; CliqueDB3: table (profiles: table); CliqueDB: absent
first bind: {key="BUTTON1", spell="Rejuvenation", type="spell"}
importer: recognised: 1 bindings, 1 skipped (bound to target x1)
```

Unknown shapes (Cell entries with named fields; Clique binds with `button` / `action`):

```
== Cell
CellCharacterDB: table
clickCastings: table, keys: common, useCommon
first entry: {key="BUTTON1", spell="Rejuvenation"}
importer: not recognised: expected each click-casting entry to be { attribute, kind, action } with a string attribute such as "type1" - found entry 1 = table with keys: key, spell
== Clique
Clique: absent; Clique.db.profile.binds: absent; CliqueDB3: table (profiles: table); CliqueDB: absent
first bind: {action="heal", button="1"}
importer: not recognised: expected each Clique bind to be { key = <string>, type = <string>, ... } - found entry 1 = table with keys: action, button
```

Keybinding section (six rows, the fixture of check 6; the header line of the report and the sections above are as in the suite):

```
count: 6
binding 1 = "ACTIONBUTTON1", "1", "SHIFT-1"
binding 2 = "ACTIONBUTTON2", "2", nil
binding 3 = "MULTIACTIONBAR1BUTTON1", "Q", nil
binding 4 = "TOGGLEBACKPACK", "B", nil
binding 5 = "TARGETSELF", "F1", nil
bound: 7 keys; resolved to a slot: 4; to a spell: 2; to a macro: 1
first 10 resolved:
  1 -> ACTIONBUTTON1 -> slot 1 -> spell 1058 (Rejuvenation)
  SHIFT-1 -> ACTIONBUTTON1 -> slot 1 -> spell 1058 (Rejuvenation)
  2 -> ACTIONBUTTON2 -> slot 2 -> macro "Heal M"
  Q -> MULTIACTIONBAR1BUTTON1 -> slot 61 -> empty
importer: 3 bindings imported, 0 skipped
```

### Every other suite (last line each) and the gates

```
simcheck      ... measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS
reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56,
regencheck 27, simwindow 8, solvercheck 70, timeline 27, spelltip 48, practice 74, practiceui 49,
migrate 7, probecheck 73, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 15,
scenariocheck 9, gatecheck 8, replayforever 10, reviewforever 8, coachforever 13,
practiceforever 8, parsecheck 11, bookcheck 15, tipcheck 14, clockcheck 15, spellsui 15,
measurecheck 18, bindscheck 6            -- each "N ok, 0 failed"
adaptercheck forever 22 / tbc 15, corecheck 10 / 8, svcheck 6 / 1, consolecheck 11 / 1   -- each "N ok, 0 failed"
apicheck: 8 Forever TOCs, 44 files, 45 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok       (refcheck.py --selftest)
```

`luac -p` clean on `Engine/Practice.lua`, `Modules/SpellTuner_Practice/Commands_Forever.lua`, `tools/bindscheck.lua` (the 5.1.5 `luac` under `tools/.lua`).

`git status --short` (nothing added, committed, stashed or reset):

```
 M Engine/Practice.lua
 M Modules/SpellTuner_Practice/Commands_Forever.lua
 M docs/tasks/HANDOVER.md
 M docs/tasks/T19-binds-import-check.md
?? tools/bindscheck.lua
```

(`docs/tasks/HANDOVER.md` and this file were already modified before this task began.)

### Skipped / notes

- Not touched: `docs/TOOLS.md` (the lead adds `bindscheck` to the loop), TBC's own `/st binds`-equivalent (`Core_TBC.lua`); the task's Files list names the Forever command only.
- The stub's `date()` prints 2025-09-04 in the report header; that is the stub's clock.
- Nothing about a Forever format was guessed: the importers still read only the TBC formats and now say so when they meet anything else.
- No question.

## Lead review (2026-09-29)

Accepted, no change by the lead. The lead read the diff, reran every suite with `bindscheck` added
(bindscheck 6, practice 74, practiceui 49, every other suite at its baseline; apicheck 0 findings
over 44 files -- 45 distinct globals, the new ones `rawget` / `next`, Lua builtins -- `--selftest`
10 of 10, refcheck ok) and `luac -p` on the three files.

- The implementer's three behaviour changes are on **unrecognised** states only and are accepted:
  Cell with `useCommon` set and no `common` table is refused (was: fell through to spec 1); Clique's
  any-profile fallback takes the first profile by name (was: `pairs` order); a non-table entry in a
  recognised list is skipped with a reason (was: raised).
- Escaping: add-on strings are escaped once, where the report line or the error text is built; the
  skip reasons the binding window already showed are unchanged.
- Style, not acceptance: the per-entry `if type(entry) ~= "table"` wrappers in `PR.ImportCell` and
  `PR.ImportClique` are indented two spaces inside four-space blocks (to keep the diff small).
- Next: the author runs `/st binds check` on the beta (TESTING §40) and pastes it; an importer is
  changed from that paste only.
