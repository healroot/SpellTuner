# T25 -- the SpellTuner block on a macro's tooltip

Status: handed out 2026-09-29.

## Goal

Hovering an action-bar button that holds a macro which casts a spell shows the same SpellTuner
block as hovering the spell itself, once per showing. The adapter resolves the macro's spell --
from the macro tooltip's own data, else from the button's action slot through `GetActionInfo` and
`GetMacroSpell` -- and hands shared code only a plain spell id; `UI/SpellTip_Forever.lua` appends
the block it already builds. The client's exact shapes are not yet observed on Forever; T25a adds
the probe lines that will confirm them, and this task is written so that any of the shapes below
works and every other shape adds nothing and raises nothing. For the author, who plays from macros.

## Facts

- The author's report, 2026-09-29, item 2 (via the planner): no SpellTuner block on macro
  tooltips; the block does show on spells (T9's hook works on the beta).
- T9's hook: `Client/API_Forever.lua` 88-104 `MD.API.OnSpellTooltip(fn)` --
  `MD.API.Constant("Enum.TooltipDataType.Spell")`, a wrapper that reads `data.id` under `pcall` and
  forwards only a plain, non-secret number, registered with
  `MD.API.Call("TooltipDataProcessor.AddTooltipPostCall", type, wrapper)`; recorded in
  `MD.API._bindings` by hand (105). `UI/SpellTip_Forever.lua` 235-268: `OnSpell(tt, id)` (once per
  showing through `tt._spellTipId`, cleared on `OnTooltipCleared`; the builder under `pcall`),
  registered at `MD_READY`.
- Present on build 70009: `TooltipDataProcessor.AddTooltipPostCall`, `GetActionInfo`,
  `GetMacroInfo` (`docs/probe/1.60.1_70009.md` 33, 35, 49). In the 69893 baseline
  (`tools/data/forever_api.json`): `GetMacroSpell`, `GetActionInfo`, `GetMacroInfo`,
  `C_TooltipInfo.GetAction`, `C_ActionBar.IsMacroActionWithShowTooltip`. `MD.API.ActionInfo` and
  `MD.API.MacroInfo` are already bound (`Client/API_Forever.lua` 110-116, T18); `GetMacroSpell` is not.
- **UNKNOWN on Forever -- T25a's probe lines answer these; until then the retail 12.x engine's
  shapes are the assumption, not a fact:**
  - `Enum.TooltipDataType.Macro` exists (retail value 25) and a macro on an action button fires the
    Macro post-call, not the Spell one.
  - The Macro data's lines carry the macro's spell as `line.tooltipType ==
    Enum.TooltipDataType.Spell` with `line.tooltipID` the spell id (retail: the first line).
  - `GetActionInfo(slot)` for a macro answers `"macro", <id>, <subType>`; `<id>` is the macro index
    (then `GetMacroSpell(index)` names its spell) or, on newer retail, already the spell id with
    `subType == "spell"`.
  - The hovered button keeps its slot as `owner.action` (Blizzard's buttons) or the `action`
    attribute (`owner:GetAttribute("action")`, ElvUI / Bartender) -- the same two places
    `PR.ImportKeybinds` reads (CLAUDE.md, `Engine/Practice.lua` row, v0.15.2).
- Reading the tooltip's owner and its fields (`tt:GetOwner()`, `owner.action`, `owner:GetAttribute`)
  is the widget toolkit, which CLAUDE.md allows anywhere; it stays in the adapter anyway so shared
  code sees only an id.

## Files

| file | change | role |
|---|---|---|
| `Client/API_Forever.lua` | bind `MacroSpell = "GetMacroSpell"`; `MD.API.OnMacroTooltip(fn)` (new, beside `OnSpellTooltip`, recorded in `MD.API._bindings` the same way): `false, "absent"` when `Enum.TooltipDataType.Macro` is nil; else a wrapper, entirely under `pcall`, that resolves a spell id in this order and calls `fn(tooltip, id)` once with the first plain, non-secret number it finds -- (1) the first data line whose `tooltipType` equals `Enum.TooltipDataType.Spell` and whose `tooltipID` is a number; (2) the owner's slot (`owner.action`, else `owner:GetAttribute("action")`, a number) -> `MD.API.ActionInfo(slot)`; when its first return is `"macro"`: `MD.API.MacroSpell(id)` if that is a number, else `id` itself when the third return is `"spell"`; nothing found -> no call | the adapter |
| `UI/SpellTip_Forever.lua` | at `MD_READY` also `MD.API.OnMacroTooltip(OnSpell)` when it exists; nothing else | the block |
| `tools/wowstub.lua` | forever profile: `Enum.TooltipDataType.Macro = 25` (commented: retail's value, UNVERIFIED on Forever); `GetMacroSpell(index)` from a new `S.macroSpells[index]`; `S.ShowMacroTooltip(tt, data, owner)` -- clear, fire `OnTooltipCleared`, set `tt:GetOwner()` to `owner`, run the Macro post-calls with `data`; `GetActionInfo` returns a third value when `S.actions[slot][3]` is set (existing callers unchanged) | stub |
| `tools/tipcheck.lua` | the five assertions below | Forever suite |

## Rules

- `CLAUDE.md`: no client call outside `Client/API.lua` / `Client/API_*.lua` (the owner read and
  every client table index happen in the adapter's wrapper); `IsSecret` on every value before
  anything but storing; never raise into the game's tooltip (the whole wrapper under `pcall`); no
  new global; the multi-return trap (`MD.API.ActionInfo` returns three values -- write the locals
  out, no `a and f() or b`); ASCII-only rendered strings.
- The block's content is not changed: the macro gets exactly what `SpellTip:Lines(id)` builds for
  that id. No restyle (a separate design workflow owns the look).
- Registering the Macro post-call must not change the Spell path: every existing tipcheck assertion
  keeps passing unchanged.
- Tests first: the new assertions against today's code, the failures pasted, then the code.
- **Other implementers are working in this tree at the same time** on `Engine/Practice.lua`,
  `UI/PracticePanel.lua`, `UI/BindingsWindow.lua`, `tools/practiceforever.lua` (T24) and
  `Spells/Measure.lua`, `Core_Forever.lua`, `tools/measurecheck.lua` (T26). Do not edit those. If a
  suite fails in a file you did not touch, wait a minute, re-run it once, and report it.
  `Client/Probe.lua` and `tools/probecheck.lua` are T25a's, after you: do not touch them.
- Git: no `add`, `stash`, `checkout -- <path>`, `reset`, commit. No `docs/` or `CLAUDE.md` edit except
  this Report.

## Acceptance

1. `bash tools/run.sh tools/tipcheck.lua` ends `22 ok, 0 failed` (17 + 5). New assertions, names
   verbatim:
   1. "a macro's tooltip gets its spell's block, from the tooltip data" -- `S.ShowMacroTooltip` with
      data `{ type = 25, lines = { { tooltipType = 1, tooltipID = <a known heal's id> } } }`: the
      tooltip's added lines equal what `S.ShowSpellTooltip` adds for that id on a fresh tooltip.
   2. "a macro's spell is found through its action slot when the data does not name it" -- data
      with no spell line, an owner with `action = 7`, `S.actions[7] = { "macro", 3 }`,
      `S.macroSpells[3] = <id>`: the same block; and with `S.actions[7] = { "macro", <id>, "spell" }`
      and no `S.macroSpells` entry: the same block; and an owner with only `GetAttribute("action")`.
   3. "a macro's block appears once per showing" -- the Macro post-call run twice without a clear
      adds the block once; after a clear, once more.
   4. "a macro with no spell, a secret id or a raising owner adds nothing and never raises" -- no
      spell line and no slot; `tooltipID` a secret stand-in; `GetMacroSpell` returning nil; an owner
      whose `GetAttribute` raises; `data` = nil: no line added, no error escapes.
   5. "the macro hook is registered through the adapter, and off means off" --
      `S.tooltipPostCalls[25]` holds exactly one function after `MD_READY`, and with
      `MD.db.spellTooltip = false` a macro showing adds nothing.
2. Unchanged: every other suite of the loop in `docs/TOOLS.md` §1 at `docs/tasks/HANDOVER.md`'s
   Baselines (suites T24 / T26 are changing: report their numbers as you find them), including
   `adaptercheck` 22/15 and `probecheck` 82 (the stub change must not move them).
   `python3 tools/apicheck.py` 0 findings (`GetMacroSpell` is in the baseline), `--selftest` 10 of 10.
3. Paste: the failing run before the change, the passing run after, `luac -p` of the two changed
   shipped files, the loop's last lines, apicheck's last line.

## Out of scope

`Client/Probe.lua` (T25a), the TBC tooltip (`UI/SpellTooltip.lua`), the block's lines
(`SpellTip:Lines`), the Practice importers' own macro reading, anything T24 / T26 own.

## Report

(implementer)
