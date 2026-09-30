# T42 -- Settings -> General: appearance and windows

Status: **built** 2026-09-30 on branch `ui/T42` (base 9a04b62), awaiting review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T42** | **Settings -> General: appearance and windows.** An APPEARANCE titled pane: the font offset slider (-2..+2, `UI.ApplyFonts`, then the Spells re-render), the window scale slider (70-120 %, through `MD.Win`). A WINDOWS pane: combat `hide` / `keep` (kit dropdown), `Close one window per ESC` (`db.ui.escStack`), `Reset window positions` (`/st ui reset`). T37's tooltip detail dropdown sits in the same pane. | `UI/Dashboard_Forever.lua`, `UI/Windows_Forever.lua` | `tools/wincheck.lua` (+4: each control writes its `db` field and applies it; reset clears `db.ui.win`) | T29, T32, T33 |

Spec sections it cites: 4.2 (the font offset, -2..+2, `UI.ApplyFonts`, the pitches and the Spells
re-render), 4.3 (the window scale, 70-120 %, `SetScale` with the position converted), 6.5 (the ESC
stack and its `db.ui.escStack = false` fallback), 6.6 (`db.ui.combat = "hide"` / `"keep"`), 5.6
(T37's detail key), 8.1 (decisions 4, 5 and 13 as recommended), and 4.3's metrics for a titled
pane (title at 0, rule at -17, first control at -27, 12 between sections).

## What was built

| file | change |
|---|---|
| `UI/Dashboard_Forever.lua` | Settings -> General rebuilt as three `UI.CreateTitledPane` sections, 12 apart, each across the view. **SPELL TOOLTIPS**: `Add SpellTuner lines to spell tooltips` and T37's `Detail lines` dropdown (unchanged behaviour; its label now `UI.FONT`, in line with the check). **APPEARANCE**: `Font offset`, a kit slider -2..+2 (`UI.FONT_OFFSET_MIN` / `_MAX`) step 1, which on every change writes `db.ui.fontOffset = UI.ApplyFonts(value)` -- every font object re-sized, and through T36's wrapper of `UI.ApplyFonts` the Spells pane's pitches and rail re-laid at once; `Window scale`, a percentage slider 70-120 (from `MD.Win.SCALE_MIN` / `_MAX`) step 5, which on the mouse-up (or Enter in its box) calls `MD.Win:SetScale(value / 100)` -- `db.ui.scale` written, every managed window scaled, saved places converted, edges re-snapped (T32); the scale waits for the mouse-up, as in Cell, so the window does not scale under the pointer mid-drag. The existing `Show the mana clock` check sits under the two sliders. **WINDOWS** (only with `MD.Win`): `In combat` with a kit dropdown (`Hide, reopen after` / `Keep them open`, `MD.Win.COMBAT_MODES`) through `MD.Win:SetCombat`; `Close one window per ESC` through T33's `MD.Win:SetEscStack` (the stack or one `UISpecialFrames` entry per window, switched at once with what is open carried over); `Reset window positions`, a button doing what `/st ui reset` does (`MD.Win:Reset()` and the same chat line). `RefreshGeneralPane` (every visit) sets each control from the saved state. The controls are kept on the pane (`fontSlider`, `scaleSlider`, `combatDropdown`, `escCheck`, `resetButton`, beside the existing `tooltipCheck`, `detailDropdown`, `clockCheck`). |
| `UI/Windows_Forever.lua` | `Win.COMBAT_MODES` (the dropdown's two items with their hover text), `Win:CombatMode()` (`"keep"` or `"hide"`; anything else saved reads as the default) and `Win:SetCombat(mode)` (writes `db.ui.combat`; the next `PLAYER_REGEN_DISABLED` reads it, as T33's `EnterCombat` already did); `Win:ScalePercent()` (the scale as the slider shows it). `Win:Reset`'s comment names the Settings button; it still clears `db.ui.win` only (the scale, combat and ESC rules are kept). |
| `tools/wincheck.lua` | +6 (39 -> 45), section 12, forever. The pane is found by its `fontSlider`; a slider is driven as a player types into its box (the kit's `OnEnterPressed` runs both callbacks), a dropdown row and a button by their `OnClick`. (1) the three titled panes, T37's dropdown in SPELL TOOLTIPS, the font slider in APPEARANCE, the combat dropdown in WINDOWS; (2) font offset: typing 2 writes `db.ui.fontOffset = 2`, `UI.FONT` at 15, the Spells rail's rows 22 tall; typing 4 is held to 2 (range -2..2); back at 0 gives 13 and 20; (3) window scale: 90 writes `db.ui.scale = 0.9`, the window scaled and its TOPLEFT where it was on screen; 150 is held to 1.2 (range 70..120); (4) combat: the dropdown shows `hide`, `keep` writes `db.ui.combat` and a pull leaves the window open, `hide` and a pull hides it and it comes back on Settings -> General; (5) the ESC check: off writes `db.ui.escStack = false`, the window's name in `UISpecialFrames`, the stack empty and the proxy down; on puts it back on the stack; (6) the reset button clears `db.ui.win` and re-centres the window at Settings' 860 x 560. |

No stub hunk, no shared file, no adapter binding, no TOC change (both files are Forever-only and
already listed). TBC is untouched: neither file is on `SpellTuner_TBC.toc`.

## Tests first

`tools/wincheck.lua` with the six new assertions against the base's `UI/Dashboard_Forever.lua` and
`UI/Windows_Forever.lua`:

```
T42: Settings -> General has SPELL TOOLTIPS, APPEARANCE and WINDOWS titled panes FAIL - no pane
T42: the font offset slider (-2..+2) writes db.ui.fontOffset and applies it (fonts, the Spells rail) FAIL - no slider
T42: the window scale slider (70-120 %) writes db.ui.scale and applies it through MD.Win FAIL - no slider
T42: the combat dropdown writes db.ui.combat (hide / keep) and the next pull follows it FAIL - nil false false true true
T42: 'Close one window per ESC' writes db.ui.escStack and switches the stack at once FAIL - nil false
T42: 'Reset window positions' clears db.ui.win and re-centres the window at its default size FAIL - 485.00,310.00
39 ok, 6 failed
```

After the change:

```
T42: Settings -> General has SPELL TOOLTIPS, APPEARANCE and WINDOWS titled panes ok
T42: the font offset slider (-2..+2) writes db.ui.fontOffset and applies it (fonts, the Spells rail) ok - at +2 size=15 row=22; back at 0 size=13 row=20; range -2..2
T42: the window scale slider (70-120 %) writes db.ui.scale and applies it through MD.Win ok - scale=1.00 frame=1.00
T42: the combat dropdown writes db.ui.combat (hide / keep) and the next pull follows it ok - true true true true true
T42: 'Close one window per ESC' writes db.ui.escStack and switches the stack at once ok - true true
T42: 'Reset window positions' clears db.ui.win and re-centres the window at its default size ok - 961.50,540.85
45 ok, 0 failed
```

## The full check

The suite loop of `docs/TOOLS.md` section 1 plus `wincheck`, `themecheck` and `tabscheck`, run on
this branch and on an export of the base (9a04b62), and diffed: **the only difference is wincheck
39 -> 45.** Every other count identical and 0 failed: simcheck PASS, reccheck 54, replaycheck 80,
replayui 98, runcheck 78, reviewui 44, navui 35, dashui 63, regencheck 27, simwindow 8,
solvercheck 77, timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7, probecheck 87,
forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9,
replayforever 14, reviewforever 11, coachforever 18, practiceforever 20, bindscheck 6, parsecheck 12,
bookcheck 17, tipcheck 37, clockcheck 20, spellsui 35, measurecheck 30, releasecheck 13,
themecheck 23, tabscheck 24; adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1,
consolecheck 17 / 1 (forever / tbc).

- `python3 tools/apicheck.py`: 0 findings (8 Forever TOCs, 48 files). `--selftest`: 10 of 10.
- `python3 tools/refcheck.py --selftest`: ok.
- `luac -p` on `UI/Dashboard_Forever.lua`, `UI/Windows_Forever.lua`, `tools/wincheck.lua`: ok.

## Deviations

- **wincheck is +6, not +4.** One assertion per control (font offset, window scale, combat, ESC,
  reset: five, where the row counts four) and one for the layout (the three titled panes and which
  control sits in which).
- **"T37's tooltip detail dropdown sits in the same pane"** is read as the Settings -> General view,
  not the WINDOWS section: the dropdown shares a titled section, SPELL TOOLTIPS, with the tooltip
  check it qualifies (T37's note, "T42 moves it into its titled pane"). A key for the tooltip block
  under WINDOWS would be hard to find.
- **A third section and the clock check.** The row names two panes; the existing tooltip check and
  detail dropdown needed a titled pane of their own (SPELL TOOLTIPS, above), and `Show the mana
  clock` sits under the two sliders in APPEARANCE, where the look of things is set.
- **`Win:SetCombat` / `Win:CombatMode` / `Win.COMBAT_MODES` / `Win:ScalePercent`** are new in the
  manager, so the pane holds no rule of its own (what an unknown saved value means, the range of
  the percentage).
- **The scale applies on the mouse-up** (or Enter in the slider's box), not on every step of a drag;
  the font offset follows every step.
