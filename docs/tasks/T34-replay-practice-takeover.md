# T34 -- the replay and practice takeover

Status: **built** 2026-09-30 on branch `ui/T34` (base 9a04b62), awaiting review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T34** | **Replay and practice takeover** (6.3): the main window hidden with its path, the replay at the main window's top centre in screen pixels (or its saved place), the `< SpellTuner` back button (`opts.back`), DIALOG strata, `ShowMain` during a takeover (closes a review replay and opens the requested view; refused during practice), practice ESC pause then end, End -> replay directly -> back to Practice, the `replayPos` migration. Guarded by `if MD.Win`. | `UI/ReplayWindow.lua`, `UI/Windows_Forever.lua`, `UI/Style.lua` (`opts.back`) | `tools/wincheck.lua` (+7: the main window hides and back restores the path; a replay from chat has no back button; the placement at scales 0.71 and 1 lands on the main window's top centre; `/st` during a replay takeover closes it and opens the requested view; `/st` during practice is refused and nothing shows; End opens the replay without showing the main window; `replayPos` migrated once); `tools/replayui.lua` 98 unchanged (tbc); `tools/replayforever.lua` | T32, T33 |

Spec sections: 6.1 (rules 1 and 2: one big window at a time; the replay in DIALOG against the main
window's HIGH), 6.2 (the Replay and Practice rows: strata, position, ESC, combat), 6.3 (the
takeover, whole), 6.5 (the stack entry and an `onEsc` that returns true to stay), 6.6 (combat), 7
(the shared replay window gated on `MD.Win`; the kit's `opts.back` additive), 8.1 (decision 3:
takeover), 10 step 8 (the in-game check this answers).

## What was built

| file | change |
|---|---|
| `UI/Style.lua` (shared, additive) | `UI.CreateMovableFrame`'s `opts.back` (a label, or `true` for `< Back`): an 84x20 `accent-hover` button at the header's TOPLEFT, `header.backBtn`, created hidden; a click calls `f:OnBack()` when set. TBC never passes it. |
| `UI/Windows_Forever.lua` | **The takeover.** `Win:TakeOver(key, kind)` is called by the window right before it shows; `kind` is `"replay"` (a review replay, or a practice's) or `"practice"` (a session being played). With the main window shown: its path (`MD:SelectedView()`) is remembered, its top centre measured in screen pixels (`(GetLeft + GetWidth / 2) * GetEffectiveScale`, `GetTop * GetEffectiveScale`) into `w.over`, and it hides after the replay is placed. With a takeover of the same window already on screen (End -> its replay, the next pull of a run, the suggested column filling in) the place and the way back are kept. Otherwise (a replay from chat) the saved place or the centre, and no back button. A practice session's way back is always Simulate -> Practice (`Win.PRACTICE_PATH`), and the back button is hidden while it is played. `Win.takeover = { key, kind, path }`. **Placement:** `Win:Place` puts a takeover never dragged at `w.over` -- `SetPoint("TOP", UIParent, "BOTTOMLEFT", cx / rs, top / rs)` with `rs` the replay's effective scale, clamped as a TOPLEFT would be -- so a width that changes later keeps it centred; a drag saves `db.ui.win.replay` (T32's `SavePosition`) and that wins from then on, until `/st ui reset`. **The way back:** `Register` gives a takeover's frame `OnBack` (hide it) when it has the kit's back button, and hooks its `OnHide`: `Win:TakeoverHidden(key)` ends the takeover and opens the main window on the remembered path -- so the back button, the x, ESC and End all return it. A hide by `EnterCombat` (`Win.combatHiding`) keeps the takeover (the replay comes back after combat, the main window still hidden, T33's rule). A takeover closed in combat any other way (practice ended by combat) records the main window in `combatHidden` so it comes back after combat, unless `db.ui.combat = "keep"`, where it opens at once. **`ShowMain`:** during a practice session whose window is shown it prints `Practice is running: ESC pauses, ESC again ends it.` and returns; otherwise `Win:CloseTakeovers()` (the takeover forgotten, every shown takeover window hidden without giving the main window back, and none left in `combatHidden`) and then the requested view opens. **`Win:Adopt(key, { point, relPoint, x, y })`**: an old anchor to UIParent turned into the manager's saved TOPLEFT by arithmetic on the screen (`ScreenIn`) and the frame's size -- no `GetLeft`, which a hidden frame may not answer -- clamped, then placed. `Win.inCombat` is set by `EnterCombat` (under `keep` too) and cleared by `LeaveCombat`. |
| `UI/ReplayWindow.lua` (shared) | `Build` passes `notUserPlaced` and `{ back = "< SpellTuner" }` to `UI.CreateMovableFrame` only when `MD.Win` exists, and then registers the window as `{ key = "replay", role = "takeover", onEsc = EscPress, combat = ... }` (DIALOG / 10, toplevel, clamped, on the ESC stack, `db.ui.scale`), after its `OnHide` script; the `SetFrameStrata("HIGH")`, the `UISpecialFrames` entry and the `replayPos` `OnMoved` stay on the TBC branch only. `db.replayPos`, when present, is adopted into `db.ui.win.replay` once and deleted. `EscPress`: a practice being played pauses (`SetPlaying(false)`, `live:SetPaused(true)`) and stays on the stack; a second press while paused ends it into its replay (`MD:StopPractice(true)`) and stays for the replay; a replay hides. The combat rule is `"stay"` while a practice is played (its own guard ends it) and the takeover role's `"hide"` otherwise. `MD:OpenReplay` calls `MD.Win:TakeOver("replay", "replay")` and `MD:OpenPractice` `MD.Win:TakeOver("replay", "practice")`, each right before `frame:Show()`, after `Layout` has sized the window. TBC's calls are argument for argument today's. |
| `tools/wincheck.lua` | +8 (39 -> 47), section 12: the Practice module loaded (Recorder and Replay with it), one `tools/foreverfixture.lua` recording, auto-coach off. The seven of the row, plus the practice ESC (below); ESC on a review replay is folded into the Play check. |
| `tools/replayforever.lua` | +1 (14 -> 15): the window is the manager's `"replay"` takeover, not a `UISpecialFrames` entry, with a `< SpellTuner` button that a replay from chat (the main window hidden) does not show, and a takeover with no way back. |

No stub hunk (`tools/wowstub.lua` untouched: wincheck's suite-local geometry already reads a `TOP`
point), no new adapter binding (`MD.API.UnitAffectingCombat` was already bound), no TOC change.

## Tests first

The new assertions against the base's `UI/` files (tests already written):

```
T34: db.replayPos is migrated into db.ui.win.replay once, then deleted         FAIL - false nil
T34: a replay from chat has no back button, opens centred in DIALOG, main stays hidden FAIL - nil HIGH 306.00,424.60
T34: Play hides the main window with its path; < SpellTuner or ESC closes the replay and restores it FAIL - false false false reports/review
T34: the replay opens with its top centre on the main window's, at UI scales 0.71 and 1 FAIL - 447.30,447.30 vs 217.26,440.20 TOPLEFT / 630.00,630.00 vs 306.00,620.00 TOPLEFT
T34: /st modules during a replay takeover closes it and opens Settings -> Modules FAIL - false true settings/modules
T34: /st during practice is refused with one line and nothing shows            FAIL - false lines 0
T34: practice ESC pauses, ESC again ends it into its replay; back goes to Simulate -> Practice FAIL - false false settings/modules
T34: End opens the replay without showing the main window; back returns to Practice FAIL - false simulate/practice
39 ok, 8 failed          (wincheck)
```

```
T34: the replay is the manager's takeover, on the ESC stack; from chat no back button FAIL - registered=false special=true back=nil
14 ok, 1 failed          (replayforever)
```

After the change: wincheck `47 ok, 0 failed`, replayforever `15 ok, 0 failed`.

## The full check

The suite loop of `docs/TOOLS.md` section 1 plus `wincheck`, `themecheck` and `tabscheck`, run on
this branch and on the base (the branch's diff reverted, then re-applied):

- **Counts:** wincheck 39 -> 47, replayforever 14 -> 15. Every other count identical: simcheck
  PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 35, dashui 63,
  regencheck 27, simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice 74, practiceui 49,
  migrate 7, probecheck 87, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24,
  scenariocheck 12, gatecheck 9, reviewforever 11, coachforever 18, practiceforever 20, bindscheck 6,
  parsecheck 12, bookcheck 17, tipcheck 37, clockcheck 20, spellsui 35, measurecheck 30,
  releasecheck 13, themecheck 23, tabscheck 24; adaptercheck 22 / 15, corecheck 10 / 8, svcheck
  6 / 1, consolecheck 17 / 1.
- **TBC output:** the whole output of replayui, practiceui, reviewui, navui, dashui, practice and
  runcheck diffed against the base: identical but for replayui's `[sim] replay 1 opened ... N ms`
  timings and one `[sim] search N evaluations` line, which vary run to run on the same tree (the
  search is sliced on `debugprofilestop()`; three runs of this branch gave 17 and 19).
- `python3 tools/apicheck.py`: 0 findings (8 Forever TOCs, 48 files). `--selftest`: 10 of 10.
  `python3 tools/refcheck.py --selftest`: ok.
- `luac -p` (5.1.5): `UI/ReplayWindow.lua`, `UI/Style.lua`, `UI/Windows_Forever.lua`,
  `tools/wincheck.lua`, `tools/replayforever.lua`.

## Deviations

1. **wincheck +8, not +7.** The row's task text names "practice ESC pause then end", which its test
   list does not; it has its own check (the first ESC pauses and stays, the second ends it into its
   replay with the main window never shown, and that replay's back goes to Simulate -> Practice).
   ESC on a review replay (section 10 step 8: "only the replay closes, and the main window is back
   on Review") is folded into the Play check rather than counted apart.
2. **Practice's second ESC opens its replay.** 6.2's practice row says "2nd, while paused: end
   (kept)"; 6.3 ("When it ends, its replay opens directly"), mockup 5 and section 10 step 8 ("ESC
   again ends it and opens the replay") say it opens the replay, which is what End does. Built as
   End.
3. **Combat during practice** (the spec does not say where the main window goes): the practice's
   own guard ends it and hides the window, as today; the takeover ends with it, and the main window
   is remembered to come back after combat on Simulate -> Practice (under `db.ui.combat = "keep"` it
   opens at once). A review replay hidden by combat keeps its takeover, per 6.6.
4. **The x on a practice session** keeps the session (today's rule) and gives the main window back
   on Simulate -> Practice, by 6.3 item 3 ("the x, ESC and End close the replay and show the main
   window on the remembered path").
5. **`ShowMain` also closes a replay opened from chat** (no takeover, no path), so a command never
   shows the two together (6.3: "The two are never shown together by a command").
6. **The saved place stays a TOPLEFT.** `db.ui.win.replay` is the manager's `{ x, y }` TOPLEFT, like
   every window T32 saves; only the unsaved takeover placement anchors by `TOP`, as 6.3 writes it.
