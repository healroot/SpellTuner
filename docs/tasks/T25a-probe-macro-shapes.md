# T25a -- the probe dumps what a macro action's tooltip data and GetActionInfo return

Status: **accepted** 2026-09-29 (handed out in a24569e, after T25 8ffd300).

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

**Done.** `Client/Probe.lua`: `MacroLines()` (called last in `ShapesLines`) prints `macro types Spell=<v> Macro=<v>` (`absent` when `MD.API.Constant` reads nothing plain); walks action slots 1-180 with `GetActionInfo` under `pcall`, skipping a secret or non-string type, for the first three `"macro"` slots: `macro action <slot> info=<t>,<id>,<sub> GetMacroSpell=<v> GetMacroInfo=<name>,<icon>` (a secret id prints `<secret>` and is not passed on), `... tooltip type=<v> id=<v> lines=<n>` (or `tooltip <absent>` / `<error: ...>` / `nothing` / `<secret>`), and up to 6 `... line <i> type= tooltipType= tooltipID= left=` lines; `macro actions: none on your bars`; `macro hover: 0 seen` or `macro hover: <n> seen, last type=.. id=.. line1 tooltipType=.. tooltipID=.. owner action=.. attr=..`. A Macro post-call is registered at load (only if `MD.API.Constant("Enum.TooltipDataType.Macro")` and `AddTooltipPostCall` exist, `doing` set first, under `pcall`); it counts and stores strings only (`RecordMacroHover` under its own `pcall`) and never touches the tooltip. The to-do line `macro to do: ...` follows Q9 until a hover was seen. `tools/wowstub.lua`: `S.actionTooltips` and `C_TooltipInfo.GetAction(slot)`. `tools/probecheck.lua`: step 13, the four assertions, names verbatim.

**Tests first.** Before the code: `82 ok, 4 failed` (the four new names FAIL). After: `86 ok, 0 failed`.

`luac -p Client/Probe.lua`, `tools/probecheck.lua`, `tools/wowstub.lua`: ok (`tools/.lua/lua-5.1.5/src/luac`).

Stub report's macro lines (slot 13 a macro, `S.macroSpells[2] = 5185`, two tooltip lines, no hover):
```
macro types Spell=1 Macro=25
macro action 13 info=macro,2,spell GetMacroSpell=5185 GetMacroInfo=Heal Mac,Interface\\Icons\\INV_Misc_QuestionMark
macro action 13 tooltip type=25 id=2 lines=2
macro action 13 line 1 type=0 tooltipType=1 tooltipID=5185 left=Heal
macro action 13 line 2 type=0 tooltipType=nil tooltipID=nil left=a||cff00ff00b
macro hover: 0 seen
macro to do: put a macro that casts a spell on an action bar, hover it, then type /st probe
```

**The loop (docs/TOOLS.md 1), last lines:** every suite at its baseline (probecheck 86, practiceforever 15 on the first run, measurecheck 30, adaptercheck 22/15, ...) except **tipcheck: `21 ok, 1 failed` -- `FAIL the macro hook is registered through the adapter, and off means off - one=false off=true entry=true`**. `apicheck` 0 findings, `--selftest` 10 of 10, `refcheck --selftest` ok.

**Question (not fixed, outside this task's Files).** `tools/tipcheck.lua` line 591 asserts `#S.tooltipPostCalls[MACRO] == 1`. The harness loads the whole Forever TOC, so the probe's own Macro post-call (this task's required load-time registration) is now the second entry beside `UI/SpellTip_Forever.lua`'s. Nothing in the addon is wrong; the assertion counts callbacks instead of finding T25's. The lead should either relax line 591 (e.g. `#list == 2`, or find the callback that adds a block) or say the probe should register elsewhere (e.g. lazily at PLAYER_LOGIN, which would not change the count for suites that never fire it).

Skipped: nothing else. No commit, no git state changes. `docs/TESTING.md` shows as modified in the tree; not by me.

## Lead review (2026-09-29)

Accepted. Read the diff: every client read under `pcall`, secrets named and never compared (the
action type checked with `IsSecret` before `== "macro"`, a secret id not passed on), strings only in
the hover record, the post-call never touching the tooltip, `doing` set around the registration. The
tipcheck failure the implementer reported is the lead's own task-writing miss (T25's assertion
counted Macro post-calls, and this task required a second one at load); the lead's **one-line
change**: `tools/tipcheck.lua` 591 expects two Macro post-calls, the probe's (at load) then the
adapter's. Lead's run of the whole loop: every suite at its baseline except probecheck 86 (82),
tipcheck 22 (17), measurecheck 30 (26), practiceforever 15 (9); adaptercheck 22/15; apicheck 0
findings over 44 files, selftest 10 of 10, refcheck selftest ok.
