# T16b — the Review tab in the Forever window

Status: **open**, after T16a. M3 (`docs/ROADMAP-FOREVER.md` M3, "T16 Review tab and replay window
under the adapter"), the second half.

## Goal

The Forever window gets a **Reports** group with a **Review** view: with the Replay module on it is
the TBC Review tab -- every recorded fight with its validate column, the row tooltip carrying the
gate results, and Validate / Coach / Pin / Export / Play -- listing the v3 recordings and driving the
Forever gates (T14), coach and replay window (T16a); with the module off it says how to switch it on.
`UI/Dashboard_Review.lua` stays one file for both lines. For the author's review of their Forever
pulls.

## Facts

- The TBC window (`UI/Dashboard.lua` 191-250): group `reports` with views `Waste`, `Review`, and
  `Runs` once a run exists (`nav:SetViews`); `Review` is `MD.DashboardParts.CreateReview(content,
  CONTENT_W)` placed at `(0, -104)` / `(0, 24)` in the content; `CONTENT_W = 912`, the window
  `CONTENT_W + NAV_W (108) + 2 * NAV_PAD (8)` by 646.
- The Forever window (`UI/Dashboard_Forever.lua`): 700 x 460, groups `spells` (Spellbook) and
  `settings` (General, Modules); panes built once on first selection; `MD:SelectView` the single
  entry; `MODULE_LOADED` fires when a sibling finishes loading (T13c: after its last file).
- `UI/Dashboard_Review.lua` touches the client through `GetRealZoneText` and `IsShiftKeyDown` (luac
  listing, 2026-09-28) plus the toolkit; it reads `MD.FightRecorder:List`, `MD.RunRecorder:Get`,
  `MD.SimModel:Validate`, `MD.SimPlanner.Progress`, `MD.Replay:Open`, `MD.Practice.List`. On Forever
  T13 provides `MD.FightRecorder` / `MD:GetRecording`, T14 the v3 `Validate`, T16a the window and
  `MD.Replay`; runs and practice are absent (guarded).
- Waste (`UI/Dashboard_Waste.lua`) reads TBC's combat-log overheal store (`Engine/Overheal.lua`),
  which has no Forever source (plan §5: per-target overheal is gone) -- **not** ported.
- A v3 fight's percentages of a party member's health may rest on an estimated max (T13d); the
  Review row tooltip already prints the gate texts, which say so (T14).
- The TBC Review suite: `tools/reviewui.lua` 44 (tbc).

## Files

| file | change | role |
|---|---|---|
| `Client/API_TBC.lua` | `RealZoneText = "GetRealZoneText"` (Forever's is T13's) | binding |
| `UI/Dashboard_Review.lua` | `GetRealZoneText` -> `MD.API.RealZoneText`, `IsShiftKeyDown` -> `MD.API.IsShiftKeyDown` (T16a); every `MD.RunRecorder` / `MD.Practice` use guarded for nil (the run selector shows only `[Fights]` without runs); nothing else | the tab |
| `UI/Dashboard_Forever.lua` | a `reports` group (`Reports`) with one view `review` (`Review`), between Spells and Settings; the pane: `MD.DashboardParts.CreateReview(content, 912)` when `MD.DashboardParts.CreateReview` exists (it arrives with the Replay module), else a placeholder pane with one line `Review needs the Replay module - Settings -> Modules`; on `MODULE_LOADED` for `SpellTuner_Replay` a shown placeholder is replaced by the real pane; the window grows to the TBC size (912 + 108 + 16 wide, 646 high) so the tab fits -- the Spellbook pane keeps its own 620-wide table | the window |
| `Modules/SpellTuner_Replay/*.toc` | `UI\Dashboard_Review.lua` after `UI\ReplayWindow.lua` | TOCs |
| `tools/reviewforever.lua` (new, forever) | the suite below | suite |

## Rules

- No client call outside `Client/` (apicheck 0, rule 8). The TBC line unchanged: reviewui 44,
  dashui 56, navui 25, and the rest of the sixteen at their counts.
- The placeholder pane must not load the module (only the Modules pane's switch does).
- ASCII, no bare `|`. No new global; no library.
- Tests first: reviewforever written and failing first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/reviewforever.lua` ends `8 ok, 0 failed`, on two
   `tools/foreverfixture.lua` streams (one clean, one whose meter drifts past the calibration limit).
   Names, verbatim:
   1. "the Forever window has a Reports group with a Review view"
   2. "with the Replay module off the Review view says how to switch it on and loads nothing"
   3. "switching the Replay module on replaces the placeholder with the Review tab"
   4. "each recording is a row with its validate result"
   5. "a row's tooltip carries every Forever gate line"
   6. "Coach refuses the failing fight and shift-click coaches it anyway"
   7. "Play opens the replay window on the selected fight"
   8. "every string the tab paints is ASCII with no bare pipe"
2. TBC: reviewui 44, dashui 56, navui 25, replayui 98, the rest of the sixteen; the Forever suites
   (spellsui 15 -- the Spellbook pane in the larger window -- modulecheck, replayforever 10, ...).
3. `python3 tools/apicheck.py` 0 findings; `--selftest` as after T13a/T13c.
4. `luac -p` clean.
5. Paste into the Report: the failing run; reviewforever in full; every other tail; apicheck; luac;
   `git status --short`.

## Out of scope

- Waste (no Forever source), Runs, the Simulate group (T18 adds Practice), the TBC window.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

(implementer)
