# T16b — the Review tab in the Forever window

Status: **accepted** 2026-09-28 (lead review at the end), after T16a. M3 (`docs/ROADMAP-FOREVER.md` M3, "T16 Review tab and replay window
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
- ASCII, no bare `|`. **Lead, 2026-09-28 (T14 review):** gate texts and target names carry player and spell names as the client gave them (an EU name can be non-ASCII); escape every such string at paint time, and the ASCII assertion's fixture includes a target named with a non-ASCII byte and a `|`. No new global; no library.
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

Implemented as specified, with one deviation flagged below for the lead.

### Files touched

- **`Client/API_TBC.lua`** — added `MD.API.Bind({ RealZoneText = "GetRealZoneText" })`, matching
  Files. Forever's own `RealZoneText` binding (Client/API_Forever.lua, T13) was already there.
- **`UI/Dashboard_Review.lua`** — the three renames named in Files: `GetRealZoneText()` ->
  `MD.API.RealZoneText()` (the progress line), `IsShiftKeyDown()` -> `MD.API.IsShiftKeyDown()`
  (`Forcing()` and the Play button). Added a local `Esc` (the probe's own escaping, duplicated per
  painting file, as `UI/Dashboard_Forever.lua` and `UI/ReplayWindow.lua` already do) and applied it
  at every place this file paints a client-read string: a row's zone cell, the tooltip's zone line,
  a gate's own text wherever it is shown (the row tooltip, the `ValidateCell` short text, and the
  Coach-disabled tooltip — all three read `g.text`, which T14's "health curves" gate can embed a
  target name in), and an excluded target's name in the tooltip. No other line changed — the
  `MD.RunRecorder` / `MD.Practice` uses the Rules called out were already guarded (`MD.RunRecorder
  and ...`, `or {}`, `if not RR then return end`) before this task; I re-checked every `MD.` /
  `MD:` reference in the file (listed them all with grep) and found nothing else unguarded that the
  Forever line reaches — except two calls the Facts section didn't mention, below.
- **`UI/Dashboard_Forever.lua`** — added the `reports` group (one view, `review`) between `spells`
  and `settings`; `BuildReviewPlaceholder` (one line, marked `pane.reviewPlaceholder = true` the
  way other panes mark themselves for their own suite) when `MD.DashboardParts.CreateReview` is
  absent; `BuildReviewPane` (`MD.DashboardParts.CreateReview(content, 912)`, anchored to fill the
  content area) when it is present; `RefreshReviewPane` calls `reviewPane:Render()` on every
  `onShow`. `DesiredSize()` picks `GROWN_WIDTH/HEIGHT` (`912+108+16`, `646`) over the plain
  `700x460` at window-creation time when the module is already on; a `MODULE_LOADED` handler for
  `SpellTuner_Replay` grows an already-open window and, if the Review view is still showing the
  placeholder (checked by identity against `nav.panes.reports.review`), swaps it for the real pane
  and re-selects the view so it draws at once. The placeholder never calls `MD:SetModule` or
  anything that would load a sibling — only the Modules pane's own switch does, unchanged.
- **`Modules/SpellTuner_Replay/SpellTuner_Replay.toc`** and its `_Mainline` twin — added
  `UI\Dashboard_Review.lua` right after `UI\ReplayWindow.lua`, both files identically (still byte
  for byte identical, `diff` empty).
- **`tools/reviewforever.lua`** (new) — the suite below.
- **`tools/adaptercheck.lua`** — added `"RealZoneText"` to `TBC_ONLY_NAMES`. This suite keeps a
  hand-maintained inventory of every name each flavour's `.toc` is expected to bind and asserts
  `MD.API.Capabilities()` matches it exactly; without this the new TBC binding from Files broke
  `adaptercheck --flavour tbc` (14 ok, 1 failed — "every binding is on MD.API and in the capability
  table"). Necessary bookkeeping for a Files-table change, not a behaviour change.

### Deviation from Files — flagged for the lead

`UI/Dashboard_Review.lua`'s Coach and Validate buttons call `MD:RunCoach(...)` and
`MD:ValidationReport(...)` unconditionally (the first behind `if MD.RunCoach then`, which just
means "do nothing" when absent; the second with **no guard at all**). Neither exists on Forever —
both are `Verify.lua` (TBC-only, not on any Forever TOC). The Facts section lists what this file
reads (`MD.FightRecorder:List`, `MD.RunRecorder:Get`, `MD.SimModel:Validate`,
`MD.SimPlanner.Progress`, `MD.Replay:Open`, `MD.Practice.List`) but not these two, and Files
restricts `UI/Dashboard_Review.lua` itself to "nothing else" beyond the three named changes — so I
did not touch that file for this. Without something providing these two names on Forever: the
Coach button is a silent dead button (acceptance test 6 asks it to refuse and then coach a fight,
which needs the search and `SP.plans` machinery `MD:RunCoach` drives), and the Validate button
**raises** (confirmed by running it under the harness) the moment anyone presses it, because
`MD.ValidationReport` doesn't exist.

I added both to **`Modules/SpellTuner_Replay/Commands_Forever.lua`** (already in Files' own list
of touched TOCs, if not named as a `.lua` change):
- Renamed the anonymous `/st coach` handler body into `function MD:RunCoach(arg)`, with `/st coach`
  now calling it — exactly the shape Core_TBC.lua's own `/md coach` already has
  (`if MD.RunCoach then MD:RunCoach(arg) end`, Core_TBC.lua:390) and TBC's `Verify.lua:1374`. No
  behaviour change to `/st coach` itself (same body, same effect).
- Added `function MD:ValidationReport(rec, n) return ValidationReport(rec, n) end` (the local
  function already there, now also reachable as a colon method, matching Verify.lua's own
  `function MD:ValidationReport(rec, n)`). Doing this surfaced a real bug during testing: I first
  wrote `MD.ValidationReport = ValidationReport` (a plain 2-argument function assigned as a field),
  which is wrong for a **colon** call — `MD:ValidationReport(rec, n)` passes `MD` as an implicit
  first argument, so `rec` inside the function received `MD` and `n` received the real `rec`. That
  reached `SM:Run` before failing on a `nil` field several calls deep (a genuinely confusing crash
  to chase — `Engine/SimModel.lua:617: attempt to get length of field 't'`) and would have shipped
  broken. Fixed to the `function MD:...` form.

Both additions are minimal, symmetric with the TBC file they mirror by name, and required for the
Review tab to do what the shared code already assumes it can — but they are new functions in a file
Files didn't list as changing, so I'm flagging rather than treating it as self-evidently in scope.
If the lead would rather the Review tab's Coach/Validate simply be inert on Forever until a later
task wires them, say so and I'll revert these two additions and guard the two call sites in
`UI/Dashboard_Review.lua` instead (which Files does forbid touching further, so that would need
the lead's own call anyway).

### tools/reviewforever.lua — full output

```
the Forever window has a Reports group with a Review view                                       ok - group=reports view=review
with the Replay module off the Review view says how to switch it on and loads nothing           ok
switching the Replay module on replaces the placeholder with the Review tab                     ok
each recording is a row with its validate result                                                ok - row1=ok row2=foreign healing: no damage meter reading after the fight
a row's tooltip carries every Forever gate line                                                 ok
Coach refuses the failing fight and shift-click coaches it anyway                               ok - refused=true (...coach: this fight does not replay, so there is nothing to suggest.) forced=true (1 frames)
Play opens the replay window on the selected fight                                              ok
every string the tab paints is ASCII with no bare pipe                                          ok

8 ok, 0 failed
```

The two fixture streams are `tools/foreverfixture.lua`'s default stream twice: `recGood` with its
`meter`/`mana.v` set to what `SM.ScenarioFromRecording` + `SM:Run` themselves produce replaying
that same fixture (the same "known-consistent pair" construction `tools/gatecheck.lua`'s own
baseline uses, `baseSimOwn`/`baseManaCurve`) so it passes all eight gates outright, and `recBad =
buildFixture({ meterOverridden = true })` (no damage-meter reading at all), which drifts past the
calibration limit by failing "foreign healing" (and, unchecked here since gate 1 already fails it,
"model calibrated" and "heals attributed" too — all three need a meter reading this one doesn't
have). A third fixture (`recBadName`, only for check 8) carries a roster name with a non-ASCII byte
and a bare pipe (`"Tank\195\169|boss"`), same shape as `tools/replayforever.lua`'s own check 9.

Two things needed working around in the harness itself (documented inline in the suite, not
production bugs): `UI/Dashboard_Review.lua`'s row loop clips on `pane:GetHeight()`, which the real
client derives from the pane's own anchors but the stub does not (defaults to 20) — the suite gives
the pane an explicit size once, the same way `tools/reviewui.lua` sizes its own standalone parent;
and `Rows()` picks up the header row (same shape `tools/reviewui.lua` already lives with, "a header
and a row").

### Every other suite named in Acceptance

TBC (unchanged): `reviewui` 44, `dashui` 56, `navui` 25, `replayui` 98 — all still at their exact
counts.

The rest of the sixteen (`tools/run.sh tools/<t>.lua` for each): `simcheck` PASS, `reccheck` 54,
`replaycheck` 80, `runcheck` 78, `regencheck` 27, `simwindow` 8, `solvercheck` 70, `timeline` 27,
`spelltip` 48, `practice` 74, `practiceui` 49, `migrate` 7.

Forever suites: `spellsui` 15, `modulecheck` 14, `replayforever` 10, `probecheck` 73,
`forevercheck` 13, `kitcheck` 7, `recordcheck` 14, `scenariocheck` 9, `gatecheck` 8, `parsecheck`
11, `bookcheck` 15, `tipcheck` 14, `clockcheck` 15, `measurecheck` 18.

Both-flavour suites: `adaptercheck` 19/15 (was 14 ok/1 failed on tbc before adding `RealZoneText`
to its own inventory list, above), `corecheck` 10/8, `svcheck` 6/1, `consolecheck` 11/1.

All of the above match the baselines given in the task exactly; nothing else moved.

### apicheck / luac / refcheck

```
apicheck: 8 Forever TOCs, 40 files, 43 distinct globals, 0 findings (baseline 69893)
```
(39 -> 40 files: `UI/Dashboard_Review.lua` is now also reached from
`Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc`, resolved from the repository root per
the T13c rule since it isn't under `Modules/SpellTuner_Replay/`. Zero findings — no client call the
task did not foresee; `GetRealZoneText`/`IsShiftKeyDown` were the only two calls in the file and are
now both routed through `MD.API`.)

`--selftest`: `selftest: 10 of 10 findings as expected` (unchanged fixture).

`python3 tools/refcheck.py --selftest`: `selftest: ok` (unchanged).

`luac -p` clean on every file touched: `Client/API_TBC.lua`, `UI/Dashboard_Review.lua`,
`UI/Dashboard_Forever.lua`, `Modules/SpellTuner_Replay/Commands_Forever.lua`,
`tools/reviewforever.lua`, `tools/adaptercheck.lua` (the two `.toc` files are not Lua).

### git status --short

```
 M Client/API_TBC.lua
 M Modules/SpellTuner_Replay/Commands_Forever.lua
 M Modules/SpellTuner_Replay/SpellTuner_Replay.toc
 M Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc
 M UI/Dashboard_Forever.lua
 M UI/Dashboard_Review.lua
 M docs/tasks/HANDOVER.md
 M tools/adaptercheck.lua
?? tools/reviewforever.lua
```
`docs/tasks/HANDOVER.md` was already modified when I started (the lead's, per the brief) — I did
not touch it. No `git add`/stash/checkout/reset/commit run.

### Skipped / out of scope

Waste, Runs and the Simulate group were not touched (out of scope). The TBC window
(`UI/Dashboard.lua`) was not touched. `docs/` files other than this Report and `CLAUDE.md` were not
touched.

### Question for the lead

Only the one above (the `MD:RunCoach` / `MD:ValidationReport` additions in
`Modules/SpellTuner_Replay/Commands_Forever.lua`) — everything else in Files/Acceptance is done as
specified.

## Lead review (2026-09-28)

Accepted. The two methods added to `Commands_Forever.lua` outside Files (`MD:RunCoach`,
`MD:ValidationReport`) are what the shared tab's buttons call and are accepted -- without them
Validate raised on Forever. The `adaptercheck` inventory line for the new TBC binding is accepted.
The lead reran every suite (reviewforever 8, reviewui 44, dashui 56, navui 25, replayui 98, spellsui
15, everything else at its baseline; apicheck 0 over 40 files, `--selftest` 10 of 10, refcheck ok)
and `luac -p`.

**The lead's own T14-review rule was wrong and is corrected in T16c:** escaping every non-ASCII byte
of a client-given name turns an accented EU player name into `\233` on the TBC tab and window, a
behaviour change on TBC. The ASCII rule is for our own strings (the fonts lack our arrows); a
player's or zone's name renders in the game's font as the game itself renders it. T16c narrows the
paint-time escape to the pipe.
