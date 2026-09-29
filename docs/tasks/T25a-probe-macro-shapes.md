# T25a -- the probe dumps what a macro action's tooltip data and GetActionInfo return

Status: written 2026-09-29; handed out after T25 is accepted (both touch `tools/wowstub.lua`).

## Goal

`/st probe`'s `== shapes` section gains the lines that confirm (or refute) every UNKNOWN T25 rests
on: the `Enum.TooltipDataType` values for Spell and Macro; for the first three action slots holding
a macro, `GetActionInfo`'s three returns, `GetMacroSpell` and `GetMacroInfo` on its id, and the
tooltip data `C_TooltipInfo.GetAction(slot)` returns (its type, id and every line's type /
tooltipType / tooltipID / left text); and what the client handed a Macro post-call the probe
registers at load, when the author hovered a macro before typing `/st probe`. The to-do list asks
for that hover. For the lead, so T25's assumed shapes become facts in the author's next report.

## Facts

- T25 (`docs/tasks/T25-macro-tooltip.md` Facts) lists the four UNKNOWNs: `Enum.TooltipDataType.Macro`
  and whether a macro fires it; the macro spell on a data line as `tooltipType` / `tooltipID`;
  `GetActionInfo`'s id and subType for a macro; the button's slot as `owner.action` or its `action`
  attribute.
- Present on 70009: `TooltipDataProcessor.AddTooltipPostCall`, `GetActionInfo`, `GetMacroInfo`,
  `C_TooltipInfo` (`docs/probe/1.60.1_70009.md` 33, 35, 49; `Client/Probe.lua` 175 lists them). In
  the 69893 baseline: `GetMacroSpell`, `C_TooltipInfo.GetAction`.
- `Client/Probe.lua`: `IsSecret` (28), `Esc` (58), `Fmt` (67), `ShapesLines(order)` (1184, the
  section's body), `== shapes` emitted at 1658, the to-do list from 1682, the load-time
  registrations from 1932 (every one under `pcall`, the `doing` marker set first). The probe sees
  raw values -- that is its job (CLAUDE.md, `Client/Probe.lua` row) -- but every check is under
  `pcall`, every result a string, no arithmetic on a client value, and every client string passes
  `Esc` before it is a line.
- Action slots on the retail engine run 1-180 (UNVERIFIED on Forever; the loop is bounded by that
  number, not by a client value).
- `tools/probecheck.lua` 82 today.

## Files

| file | change | role |
|---|---|---|
| `Client/Probe.lua` | in `ShapesLines`: `macro types Spell=<v> Macro=<v>` (each `Fmt`, `absent` when nil); up to three `macro action <slot> info=<t>,<id>,<sub> GetMacroSpell=<v> GetMacroInfo=<name>,<icon>` lines (slots 1-180 walked with `GetActionInfo` under `pcall`, a secret or non-string type skipped) each followed by `macro action <slot> tooltip type=<v> id=<v> lines=<n>` and up to 6 `macro action <slot> line <i> type=<v> tooltipType=<v> tooltipID=<v> left=<Esc text>`; `macro actions: none on your bars` when none; `macro hover: <n> seen, last type=<v> id=<v> line1 tooltipType=<v> tooltipID=<v> owner action=<v> attr=<v>` from a Macro post-call registered at load (only if the constant and `AddTooltipPostCall` exist; the callback counts and stores strings only, under `pcall`, never adds a line to the tooltip); the to-do line `macro to do: put a macro that casts a spell on an action bar, hover it, then type /st probe` until a hover was seen | the probe |
| `tools/wowstub.lua` | forever profile: `C_TooltipInfo.GetAction(slot)` answering `S.actionTooltips[slot]` (nil otherwise) | stub |
| `tools/probecheck.lua` | the four assertions below | Forever suite |

## Rules

- The probe's own rules (above): `pcall` everywhere, strings only, `IsSecret` before anything but
  storing, `Esc` on every client string, ASCII, no bare pipe; no arithmetic on a client value; no
  new global. The post-call must never raise into the tooltip and never change it.
- Tests first: the new assertions against today's code, the failures pasted, then the code.
- Git: no `add`, `stash`, `checkout -- <path>`, `reset`, commit. No `docs/` or `CLAUDE.md` edit except
  this Report.

## Acceptance

1. `bash tools/run.sh tools/probecheck.lua` ends `86 ok, 0 failed` (82 + 4). New assertions, names
   verbatim:
   1. "shapes names the tooltip data types for Spell and Macro" -- both lines' values as the stub has
      them.
   2. "shapes dumps a macro action's GetActionInfo, GetMacroSpell and tooltip data whole" -- stub
      slot 13 = `{ "macro", 2, "spell" }`, `S.macroSpells[2]` a spell id, `S.actionTooltips[13]` a
      Macro data table with two lines (one carrying `tooltipType` / `tooltipID`, one a text with a
      `|` in it): every field appears, the pipe escaped.
   3. "a hovered macro is recorded by the probe's own post-call, and the to-do line goes" -- before
      a hover the `macro to do` line is present and `macro hover: 0 seen`; after
      `S.ShowMacroTooltip` the count is 1 with the line-1 fields, and the to-do line is gone.
   4. "the macro lines never raise on a secret or raising client" -- `GetActionInfo` returning a
      secret stand-in for one slot, `C_TooltipInfo.GetAction` raising, and `GetMacroSpell` absent:
      the probe completes, the lines say `secret` / `error` / `absent`.
2. Unchanged: every other suite of the loop at the post-T25 baseline. `python3 tools/apicheck.py` 0
   findings, `--selftest` 10 of 10.
3. Paste: the failing run, the passing run, `luac -p Client/Probe.lua`, a stub probe report's
   `macro` lines, the loop's last lines.

## Out of scope

`Client/API_Forever.lua` and `UI/SpellTip_Forever.lua` (T25's); every other probe section.

## Report

(implementer)
