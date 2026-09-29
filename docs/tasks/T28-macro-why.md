# T28 -- Macro block: the untyped first-line read, the `SetAction` path and `/st tooltip why`

Status: built on branch `ui/T28` (base `af266e5`), 2026-09-29. Spec: `docs/SPEC-forever-ui.md`
5.5 and the T28 row in section 9. The author took every recommendation (8.1).

## The row (section 9, verbatim)

> **Macro block: the untyped first-line read, the `SetAction` path and `/st tooltip why`** (5.5).
> Adapter: in the Macro post-call, `data.lines[1].tooltipID` whatever its type, after the
> Spell-typed search and before the owner's slot; `hooksecurefunc(GameTooltip, "SetAction",
> function(tt, slot) ...)` using the **slot argument** (`ActionInfo(slot)`, then `MacroSpell`); a
> last-hover record (strings only: path, each step's answer); a shared once-per-showing guard.
> `SpellTip`: records `Lines`' outcome (`block` / `not in book` / `no value`). Core: the
> `tooltip why` command.
>
> Files: `Client/API_Forever.lua`, `UI/SpellTip_Forever.lua`, `Core_Forever.lua`,
> `tools/wowstub.lua` (`hooksecurefunc` on the stub tooltip, `S.SetActionTooltip(slot)`, a Macro
> data whose first line is not Spell-typed), `tools/adaptercheck.lua`.
>
> Tests: `tools/tipcheck.lua` (+5: the untyped first line gives the block; the SetAction path gives
> it from the slot argument with no owner; Macro plus SetAction on one showing gives it once; `why`
> names each step and outcome; a raising owner adds nothing). Needs: --.

## What was built

- **`Client/API_Forever.lua`**
  - The Macro post-call resolves in three steps: (1) the first Spell-typed line (T25); (2) **the
    first line's `tooltipID` whatever its type** (ElvUI's own read); (3) the owner's slot (T25).
    When the post-call's `data` is nil, `tt:GetTooltipData()` is read (under `pcall`).
  - Each id is handed to `fn(tooltip, id)`, which now answers `done, note`. `done` stops the chain.
    Anything else lets the next step try, so a first line naming an id that is not a spell still
    leaves the slot its turn. An id already tried in the chain is not offered again.
  - **`MD.API.OnActionTooltip(fn)`** (new, recorded as `OnActionTooltip = "GameTooltip.SetAction"`)
    installs `hooksecurefunc(GameTooltip, "SetAction", ...)` once, through `MD.API.Call`. The hook
    uses **the slot it is handed**, never the owner: `ActionInfo(slot)`, then `MacroSpell` for a
    macro, then a `spell` sub-type's own id (T25's order, now in one function, `SlotSpell`, shared
    with the owner path).
  - **The last-hover record** (`MD.API.LastMacroHover()`) holds strings only: `path` (the paths
    that fired on the showing: `macro post-call`, `SetAction hook`) and `steps` (each step's answer
    with what `fn` said, e.g. `slot 61 -> macro 3 -> GetMacroSpell 5188 -> block`). There is one
    record per showing, kept on the tooltip until `OnTooltipCleared`, so both paths of one showing
    write into it. The SetAction hook records only a macro slot, or a showing a Macro post-call
    already recorded, so hovering a plain spell button never overwrites the last macro hover.
    Every client value goes into the record through `Desc`, which checks `IsSecret` first, cuts a
    string to letters, digits and `_ -.`, and names anything else by its type. So the record is
    ASCII with no pipe.
  - `MD.API.tooltipHooks = { macro = "on" | "absent" | "error" | "not registered", action = ... }`.
  - Everything runs under `pcall` (the chain, the hook, `fn` itself), and the tooltip-cleared hook
    is installed under `pcall` too.
- **`UI/SpellTip_Forever.lua`**
  - `Lines` records its outcome in `SpellTip.lastOutcome`: `block`, `not in book` (an id the book
    does not list and `Book:ReadSpell` cannot value), `no value` (a book spell with no amount), or
    `no id`. Its returns are unchanged.
  - `OnSpell` answers `done, outcome` (`block`, `already shown`, `off`, `error`, or the `Lines`
    outcome). **The guard is shared and holds whatever the id.** Once a showing has its block, any
    path that resolves any id adds nothing. `_spellTipId` is set only when a block was added.
    Without an `OnTooltipCleared` hook, it falls back to the old same-id rule.
  - `SpellTip:Why()` builds one line, and `MD_READY` also calls `MD.API.OnActionTooltip(OnSpell)`.
- **`Core_Forever.lua`**: `/st tooltip why` prints that line and changes nothing. `/st tooltip`
  alone still toggles the block. The usage is now `/st tooltip [why]`.
- **`tools/wowstub.lua`** (forever profile only, each hunk tagged `-- T28`):
  - `hooksecurefunc` (table and global forms; `S.secureHooks[method]` counts installs).
  - `GameTooltip.SetAction(slot)`: it clears, fires `OnTooltipCleared`, then runs the Macro
    post-calls with `S.actionTooltipData[slot]` when one is set. The hooks run after it.
  - `S.SetActionTooltip(slot, data, owner)`: the owner is nil unless given.
  - `S.MacroDataUntyped(id, lineType)`.
- **`tools/adaptercheck.lua`**: `OnActionTooltip` added to `FOREVER_ONLY_NAMES`.

A line from the suite, for a macro hover whose first line names a passive spell and whose slot
names Healing Touch:

```
tooltip why: macro post-call on, SetAction hook on; last macro hover: path macro post-call; spell line: none; first line: type 0 id 92040 -> no value; slot 7 -> macro 3 -> GetMacroSpell 5185 -> block
```

## Tests first

The five new `tipcheck` assertions were written, with the stub helpers, before any change to the
shipped files. On the old code: `22 ok, 5 failed`:

```
T28: an untyped first line gives the block                               FAIL - type0=0 none=0 want=8
T28: the SetAction path gives the block from the slot argument, with no owner FAIL - got=0 want=8 hooks=nil entry=nil
T28: a Macro post-call and the SetAction hook on one showing give the block once FAIL - lines=8 want=8 why=... spell tooltip lines: off
T28: /st tooltip why names the path, each step and what Lines said       FAIL - ... spell tooltip lines: on // ... spell tooltip lines: off
T28: a raising owner or slot adds nothing, never raises, and why says so FAIL - ok=true,true,true,true lines=0 why1=... spell tooltip lines: on ...
```

On the old code `/st tooltip why` toggled the block, which the `why` assertions also catch. After
the change: `27 ok, 0 failed`.

Changing `_bindings` without the name made `adaptercheck/forever` fail `every binding is on MD.API
and in the capability table` (21 / 1). With `OnActionTooltip` in `FOREVER_ONLY_NAMES` it passes 22.

## Full check

The suite loop in `docs/TOOLS.md` §1 plus `apicheck`, its `--selftest` and `refcheck --selftest`.
It was run before and after, and the diff is:

- `tipcheck`: 22 -> **27** (the five T28 assertions).
- `apicheck`: 0 findings. Distinct globals went from 45 to 46 (`hooksecurefunc`, in the adapter,
  in the 69893 baseline).
- Everything else is identical, including every TBC suite (`simcheck` PASS, `reccheck` 54,
  `replaycheck` 80, `replayui` 98, `runcheck` 78, `reviewui` 44, `navui` 25, `dashui` 56,
  `regencheck` 27, `simwindow` 8, `solvercheck` 77, `timeline` 27, `spelltip` 48, `practice` 74,
  `practiceui` 49, `migrate` 7). The Forever suites: `probecheck` 86, `forevercheck` 13,
  `modulecheck` 14, `kitcheck` 7, `recordcheck` 24, `scenariocheck` 12, `gatecheck` 9,
  `replayforever` 11, `reviewforever` 10, `coachforever` 18, `practiceforever` 15, `bindscheck` 6,
  `parsecheck` 12, `bookcheck` 17, `clockcheck` 17, `spellsui` 17, `measurecheck` 30,
  `releasecheck` 13. The dual-flavour suites: `adaptercheck` 22 / 15, `corecheck` 10 / 8,
  `svcheck` 6 / 1, `consolecheck` 14 / 1. `apicheck --selftest` 10 of 10, `refcheck --selftest` ok.
- `luac -p` passes on all six changed Lua files.

No TBC file changed. None of the shared files named in the project rules was touched.

## Deviations

1. **The chain falls through on an id that gives no block.** The spec gives the order only. As
   written, a first line naming an id that is not a spell (a macro index, say) would have hidden
   the slot's answer. Instead, each step's id is offered in turn, and the chain stops at the first
   that shows a block, or when the block is off. `why` records each step's outcome, so the report
   still shows what every step answered.
2. **The `GetTooltipData()` fallback feeds the Spell-typed search as well as the first-line read.**
   The spec named it for the first-line read. The fallback costs nothing when `data` is present,
   and it means a nil `data` still gets the typed search.
3. **The guard holds whatever the id, and `_spellTipId` is set only when a block was added.** The
   old guard was keyed by id. With it, a post-call naming rank 1 and a slot naming rank 2 on one
   showing would add two blocks, which is the case the third `tipcheck` assertion covers. T37
   re-keys the guard by `(id, detail)` for its refresh.
4. **`why` says more than the three outcomes.**
   - It starts with the registration state of both paths (`macro post-call on | absent`,
     `SetAction hook on | absent`), which answers the spec's condition 1 in the same line.
   - Its steps can also end `already shown`, `off`, `error` or `tried above`.
   - It says `path none` before any macro hover, and adds `(block off: /st tooltip)` when the block
     is switched off.
5. **`Lines`' outcome is only in `SpellTip.lastOutcome`, not a second return value.** A second
   return would reach every caller that passes `Lines`' result on (the Lua multi-return trap).
6. **Not done here:**
   - The `- macro` header marker is T37's row.
   - The `docs/TOOLS.md` tipcheck row (now 27) and `CLAUDE.md` are T44's, to keep this branch
     inside its row's files.
