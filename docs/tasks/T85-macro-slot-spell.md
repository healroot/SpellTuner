# T85 -- a spell macro's slot is its spell id (build 70124)

Status: **built** 2026-10-01 on branch `fix/macro-slot` (base `c911339`), awaiting the integrator.
One file of the addon changed (`Client/API_Forever.lua`), plus the stub and one suite. No TOC
changes. `tools/data/expected-counts.json` is integrator-owned and was **not** edited in the
branch; `make check` was run with the line below applied, then the line reverted.

## The task

`docs/probe/1.60.1_70124.md`, "What it settles": on Forever, `GetActionInfo(slot)` on a macro
that casts a spell returns `("macro", <spell id>, "spell")` -- the **spell id itself**, not a macro
index -- and `GetMacroSpell(<that id>)` answers nothing. A text-only macro returns
`("macro", <macro index>, "")`. The owner-slot path (T25, `MD.API.OnMacroTooltip`'s third step)
and the `SetAction` hook (T28, `MD.API.OnActionTooltip`) both went through `SlotSpell`, which
handed that id to `GetMacroSpell` **first** and took the `"spell"` sub-type only as a fallback.

**Fix:** when the action is a macro and its third return is `"spell"`, the second return is the
spell id, used directly; `GetMacroSpell` is asked only for a macro index (sub-type empty).

### What the old code got wrong

- It asked `GetMacroSpell` with a spell id. On the 70124 shape that answers nothing, so the old
  fallback did reach the id -- but `/st tooltip why` recorded a meaningless
  `-> macro 774 -> GetMacroSpell nil -> spell sub-type` step.
- **A low spell id that is also a live macro index** (account macros 1-120, character 121-138;
  Fireball rank 1 is 133, Frostbolt rank 1 116, Charge 100) made `GetMacroSpell` answer **that
  other macro's spell**, and the block shown was the wrong spell's. The stub models this with
  `S.macroSpells[774] = 5185`: the old code showed Healing Touch's block on a Rejuvenation macro.

## What was built

- **`Client/API_Forever.lua` `SlotSpell`:** after `kind == "macro"`, a `"spell"` sub-type answers
  `slot N -> macro spell <id>` and the id (plain, else nil); only otherwise
  `slot N -> macro <index> -> GetMacroSpell ...` as before. The trailing sub-type fallback is
  gone (unreachable). `ActionInfo` goes through `MD.API.Call`, so a secret return already makes
  `kind` nil and `subType` is plain when compared. The (3) step's comment says the 70124 shapes.
- **`tools/wowstub.lua`:** `S.SpellMacroAction(slot, spellId)` and `S.TextMacroAction(slot, index)`
  set the two 70124 shapes; `GetMacroSpell` logs every argument in `S.macroSpellCalls`.
  `GetActionInfo` itself is unchanged (a two-value `S.actions` row still answers two values, so
  `probecheck` and the practice suites see what they saw).
- **`tools/tipcheck.lua`** (+3, a T85 section before T37):
  1. a spell macro by owner slot and by `SetAction`: the spell's block, `GetMacroSpell` never
     called, why reads `slot 61 -> macro spell 774 -> block` and names no `GetMacroSpell`;
  2. a spell macro whose id is also a macro index: its own spell's block, not that macro's;
  3. a text macro: nothing added, nothing raised, `GetMacroSpell` asked twice with index 2, why
     reads `slot 62 -> macro 2 -> GetMacroSpell nil`.

## Failing first (fix not applied, tests and stub in)

```
tools/run.sh tools/tipcheck.lua
46 ok, 2 failed
  FAIL T85: a spell macro's slot resolves to its own spell id, GetMacroSpell never asked - owner=6 hook=6 want=6 calls=2
       why=... slot 61 -> macro 774 -> GetMacroSpell nil -> spell sub-type -> block // ... SetAction slot 61 -> macro 774 -> GetMacroSpell nil -> spell sub-type -> block
  FAIL T85: a spell macro whose id is also a macro index gives its own spell, not that macro's - got=6 want=6
```

(The text-macro check passes on the old code too: that path is unchanged, it guards it.)

## Suites, before and after

| suite | before | after |
|---|---|---|
| `tipcheck/forever` | 45 | **48** (+3) |
| every other suite | unchanged | unchanged |

`make check` (with the expected-counts line applied): **72 run(s), all passed**, 67 counted
against 67 expected; `python3 tools/apicheck.py`: 60 files, 48 distinct globals, **0 findings**;
textcheck 0 findings; `luac -p` clean on the three files.

## Integrator lines

**`tools/data/expected-counts.json`:** `"tipcheck/forever": 48,` (was 45).

**CLAUDE.md, the `Client/API_Forever.lua` / `Client/API_TBC.lua` row,** append:

> **T85** (build 70124, `docs/probe/1.60.1_70124.md`): a macro slot's `GetActionInfo` is
> `("macro", <spell id>, "spell")` for a spell macro -- the id is the spell, taken as it is
> (`slot N -> macro spell <id>` in `/st tooltip why`) -- and `("macro", <macro index>, "")` for a
> text macro, the only shape handed to `GetMacroSpell`; a low spell id that is also a live macro
> index no longer reads that other macro's spell

**docs/TOOLS.md, the `tipcheck.lua` row,** append: `Since **T85** (48): build 70124's macro slot
shapes -- a spell macro's slot is its spell id by owner and by SetAction with GetMacroSpell never
asked, a spell id that is also a macro index giving its own spell, a text macro adding nothing
and asking GetMacroSpell its index`.

## Not done (noted for the planner)

- **`Engine/Practice.lua` `PR.SlotSpell`** (practice's Import from Keybindings) has the same
  shape: on a `"macro"` action it reads `MacroBody(id)` -- `GetMacroInfo` by index -- so on
  Forever a spell macro's spell id is read as a macro index and the binding is reported as
  "the macro casts no heal this addon models" (or, for a low id, another macro's body).
  `PR.BindsReport` likewise prints `macro <id>` through `GetMacroInfo`. Out of this task's scope;
  the same rule (sub-type `"spell"` -> `PR.SpellFromID(id)`) would fix it.
- A real hover on 70124 is still to be seen (the probe doc's last line); the probe already dumps
  these shapes.
