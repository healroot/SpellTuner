# T19 — the bindings imports, checked against the Forever builds rather than assumed

Status: **open**, after T18. M4 (`docs/ROADMAP-FOREVER.md` M4, "T19 bindings + imports re-verified";
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

- The importers (`Engine/Practice.lua`, T18 puts their client calls behind the adapter):
  `PR.ImportKeybinds` walks `GetNumBindings` / `GetBinding(i)` (whose return shape "moved between
  clients (a category was added)", 451), `GetBindingAction`, follows a command to an action slot
  (`PR.SlotForCommand`: `ACTIONBUTTON<n>`, `MULTIACTIONBAR<b>BUTTON<n>` at Blizzard's page offsets,
  or a frame carrying an `action` attribute -- ElvUI, Bartender, Dominos) and reads the slot
  (`GetActionInfo` -> spell or macro, `GetMacroInfo` body -> `PR.MacroSpell`). `PR.ImportCell` reads
  `CellCharacterDB.clickCastings` per spec (`GetSpecialization`, 277) "decoded the way Cell encodes
  it" (`PR.CellKey`). `PR.ImportClique` reads `Clique.db.profile.binds` or `CliqueDB3` / `CliqueDB`
  keyed by `"<name> - <realm>"`.
- Every one of these formats was read from the **TBC** builds of Cell and Clique (v0.15.1-v0.15.2);
  whether the Forever builds exist and keep them is UNKNOWN (plan §2.4: "Cell's Forever release, if
  any, may store click-castings differently -- re-check"). The author's beta folder is known to hold
  EllesmereUI (plan §1.5); Cell and Clique there are UNKNOWN.
- Forever has no specializations in the retail sense at level 10-20 (UNKNOWN what
  `GetSpecialization` answers; T18's apicheck run says whether it exists at all).
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
- No new global; no library; ASCII, no bare `|` in anything rendered.
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
2. TBC practice 74, practiceui 49; every other suite at its count; apicheck 0.
3. `luac -p` clean.
4. Paste into the Report: the failing run; bindscheck in full; the report text for the TBC-shaped
   fixture and for the unknown shapes; every other tail; apicheck; luac; `git status --short`.

## Out of scope

- Changing an importer to a Forever format nobody has seen (that waits on the author's paste).
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

(implementer)
