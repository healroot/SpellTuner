# T33 -- the ESC stack and combat

Status: **built** 2026-09-30 on branch `ui/T33` (base 3407386), awaiting review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T33** | **ESC stack and combat** (6.5, 6.6): the proxy, `Push`, the `OnHide` hook that removes a frame's entries however it hides, the `quiet` flag, `onEsc` returning true to stay, `UI.OnPopup` wired, the `db.ui.escStack` fallback; hide/keep in combat with reopen; the debug console to `FULLSCREEN`, its remembered place, and its stack entry instead of `UISpecialFrames` (guarded, TBC unchanged); the copy box to FULLSCREEN_DIALOG / 20 and closing open lists; the probe's `esc=` line. | `UI/Windows_Forever.lua`, `UI/Dashboard_Forever.lua` (drop its `UISpecialFrames` entry), `UI/DebugConsole.lua`, `Client/Probe.lua` | `tools/wincheck.lua` (+8: one ESC closes one entry; the proxy re-arms; a window closed by its x leaves no entry; a code hide of the proxy pops nothing; practice's entry stays on its first ESC; the console is one entry; combat hides and restores the path; during a takeover only the replay comes back); `tools/probecheck.lua` (+1); `tools/consolecheck.lua` | T32 |

Spec sections: 6.1 (rules 1, 2, 4), 6.2 (the table: strata, ESC and combat columns; the copy box
"closes first", "centred on the window that asked"; "Opening the copy box closes any open list"),
6.5 (ESC), 6.6 (combat), 4.3 ("Window scale" -- the console and the copy box take `db.ui.scale`),
7 (the console's strata, saved place and stack entry gated on `MD.Win`; TBC unchanged), 8.1
(decision 4: hide in combat and reopen on the same view).

## What was built

| file | change |
|---|---|
| `UI/Windows_Forever.lua` | **The ESC stack.** `SpellTunerEscProxy`, an invisible frame created at load, is the only SpellTuner name the manager puts in `UISpecialFrames`; it is shown while `Win.stack` has an entry. `Win:Push(frame, onEsc)` puts `{ frame, onEsc }` on top (one entry per frame: a frame pushed again moves to the top with its new `onEsc`), hooks the frame's `OnHide` once (`HookScript`), and shows the proxy. The hook removes the frame's entries however it hides (the x, a combat hide, a takeover, End, a parent) -- `Win:Remove(frame)`, which then prunes every entry no longer on screen (shown, and every parent up to UIParent shown: a list whose window hid) and, with nothing left, hides the proxy **quietly** (`proxy.quiet = true`, so its `OnHide` returns at once). An ESC press: the client hides the proxy; its `OnHide` (`Win:OnEsc`) prunes, takes the top entry off, schedules the re-arm (`MD.API.After(0, ...)`: the proxy shown again on the next frame while entries remain), then runs its `onEsc` (default: hide its frame); an `onEsc` returning true goes back on top (practice's pause). The entry leaves before its `onEsc` runs, so one that raises cannot wedge the stack. A frame still shown inside its own `OnHide` only lost its parent (UIParent under Alt+Z, a loading screen): the proxy then pops nothing and a window keeps its entry. `UI.OnPopup` (the kit's hook, T31) pushes a dropdown list when shown and removes it when hidden; `Win:CloseLists()` hides every open list; `Win:TopWindow(exclude)` is the newest non-list frame on the stack. `Win:Register` takes `onEsc` and `combat` in its spec and hooks `OnShow` to push the window (and pushes it at once if already shown). **The fallback:** `db.ui.escStack = false` makes `Push` add the frame's name to `UISpecialFrames` instead (today's rule); `Win:SetEscStack(on)` switches either way and carries what is open across (for T42's checkbox). **The probe record:** each press is summed up on the next frame into `db.ui.escTest` (`stack`: one press closed at most one entry and the proxy came back while entries remained; `all`: one press closed several; `stuck`: the proxy did not come back); `Win:EscLine()` renders it (`esc=stack (last press: 2 open, 1 closed, the proxy shown again)`, `esc=untested`, `esc=off (...)`). **Combat:** `ROLES` gains a `combat` default (host and takeover `hide`, tool `stay`), a window's `spec.combat` (a string, or a function asked at that moment) wins. `PLAYER_REGEN_DISABLED` with `db.ui.combat ~= "keep"` hides every shown window whose rule is `hide` and remembers it (the main window with `MD:SelectedView()`); `PLAYER_REGEN_ENABLED` shows each one that is still hidden again, the main window through `Win:ShowMain(group, view)`. During a takeover the main window was already hidden, so it is not remembered and only the replay comes back. |
| `UI/Dashboard_Forever.lua` | The `tinsert(UISpecialFrames, "SpellTunerDashboard")` goes (kept only for a load without the manager); the `OnShow` script is set **before** `MD.Win:Register`, since `Register` hooks `OnShow` and a later `SetScript` would drop the hook. |
| `UI/DebugConsole.lua` (shared) | Behind `if MD.Win` (the manager is on the Forever TOCs only): the console registers as `{ key = "console", role = "tool" }` (FULLSCREEN / 10, toplevel, clamped, `db.ui.scale`, its place in `db.ui.win.console` saved on a drag) and its open calls `MD.Win:Place("console")` instead of re-centring; it has no `UISpecialFrames` line. The copy box (`MD:ShowCopyPopup`) is FULLSCREEN_DIALOG / 20, takes the window scale, closes every open list, is centred on `MD.Win:TopWindow()` (else the screen) and is pushed on the stack once shown. Without `MD.Win` (TBC) every line runs as before: DIALOG / 1, the `UISpecialFrames` entry, the re-centre, the copy box at FULLSCREEN_DIALOG / 10 on the screen's centre. |
| `Client/Probe.lua` | A `== windows` section between `== toc` and `== to do`: one line, `MD.Win:EscLine()` under `pcall` and through `Esc` (`esc=no window manager` when the probe runs without the kernel), and an `esc to do:` line in `== to do` while it reads `esc=untested`. Under the manager the probe's own box is a stack entry (pushed on every show) instead of a `UISpecialFrames` line, so one ESC closes one thing there too. |
| `tools/wincheck.lua` | +9 (30 -> 39), section 11. ESC is simulated as the client's `CloseSpecialWindows` (every shown frame named in `UISpecialFrames` hidden in one pass) and "the next frame" runs the `C_Timer.After` callbacks queued since the last one. The eight of the row, plus the fallback (below). |
| `tools/probecheck.lua` | +1 (86 -> 87), step 14: the whole Forever TOC; the report says `== windows` / `esc=untested` with an `esc to do:` line, then after one ESC with the main window and the console open, `esc=stack (last press: 2 open, 1 closed, the proxy shown again)` and no to-do line, ASCII. |
| `tools/consolecheck.lua` | forever +3 (14 -> 17): the console FULLSCREEN / 10, toplevel, one stack entry, not a special frame; it opens at its saved `db.ui.win.console` TOPLEFT rather than re-centred; the copy box FULLSCREEN_DIALOG / 20, on top of the stack, and an open dropdown list closed. The forever session's frames record strata, level, toplevel and points (suite-local, like `wincheck`'s geometry; case 7's fresh session does not have it). tbc stays at 1: its one assertion now also requires `MD.Win == nil` and the console's own `UISpecialFrames` entry. |

No stub hunk (`tools/wowstub.lua` untouched: the suites' own overrides record what they read), no
new adapter binding (`MD.API.After` was already bound), no TOC change (`UI/Windows_Forever.lua` is
already on both Forever TOCs, and `UI/DebugConsole.lua` / `Client/Probe.lua` load after it).

**For T34** (the replay and practice takeover): the replay window still has its own
`tinsert(UISpecialFrames, "SpellTunerReplayWindow")` (`UI/ReplayWindow.lua` 1132), so on Forever,
until T34 registers it, one ESC with the replay open closes the replay and the stack's top together.
T34 registers it with `role = "takeover"`, an `onEsc` (practice: pause and return true, then end)
and `combat = function() return live and "stay" or "hide" end` -- the practice session ends itself
on combat (its own guard), so the manager must not remember it to reopen.

## Tests first

The new assertions against the base's files (before any change outside `tools/`):

```
T33: the console is one entry: FULLSCREEN / 10 on top of the stack, not a special frame FAIL - DIALOG/1 entries 0 special true
T33: one ESC closes one entry: the list, then the console, the main window last FAIL - false false false
T33: the proxy re-arms on the next frame; the last ESC closes the main window and leaves it down FAIL - false false 0
T33: a window closed by its x leaves no entry, and the proxy goes down with the last FAIL - false false
T33: a code hide of the proxy pops nothing: no onEsc, no press recorded, quiet cleared FAIL - false calls 0
T33: practice's entry stays on its first ESC (pause) and goes on the second (end) FAIL - false false false
T33: combat hides the main window and restores it on the same view; keep leaves it FAIL - false false spells/book false
T33: during a takeover combat hides the replay, and only the replay comes back FAIL - false false true false
T33: db.ui.escStack = false falls back to one UISpecialFrames entry per window, and back FAIL - false true
30 ok, 9 failed
```

```
the Forever console is FULLSCREEN / 10, toplevel, one stack entry, not a special frame FAIL - DIALOG/1 entries 0
the Forever console opens where it was left, not re-centred              FAIL - CENTER nil nil,nil
the copy box is FULLSCREEN_DIALOG / 20, on top of the stack, and closes an open list FAIL - true true FULLSCREEN_DIALOG/10
14 ok, 3 failed          (consolecheck, forever; tbc 1 ok, 0 failed)
```

```
T33: the esc= line: untested with a to-do line, then esc=stack after one press FAIL - no == windows
86 ok, 1 failed          (probecheck)
```

After the change: wincheck `39 ok, 0 failed`, consolecheck `17 ok` / `1 ok`, probecheck `87 ok`.
The Alt+Z clause of "a code hide of the proxy pops nothing" (the proxy's and a window's `OnHide`
run while they stay shown) was added with the guard it tests, after the first green run.

## The full check

The suite loop of `docs/TOOLS.md` section 1 plus `themecheck`, `wincheck` and `tabscheck`, run on
this branch and on an export of the base (3407386); every suite's whole output diffed:

- **Counts:** wincheck 30 -> 39, probecheck 86 -> 87, consolecheck/forever 14 -> 17. Every other
  count identical: simcheck PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44,
  navui 35, dashui 63, regencheck 27, simwindow 8, solvercheck 77, timeline 27, spelltip 48,
  practice 74, practiceui 49, migrate 7, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24,
  scenariocheck 12, gatecheck 9, replayforever 14, reviewforever 11, coachforever 18,
  practiceforever 20, bindscheck 6, parsecheck 12, bookcheck 17, tipcheck 37, clockcheck 20,
  spellsui 17, measurecheck 30, releasecheck 13, themecheck 23, tabscheck 24; adaptercheck 22 / 15,
  corecheck 10 / 8, svcheck 6 / 1, consolecheck 17 / 1 (forever / tbc). All 0 failed.
- **Output:** every TBC suite's output is byte-identical to the base's except lines that differ
  between two runs of the base itself (table addresses, and the frame-sliced search's
  `[sim] search N evaluations` in replayui / reviewui, 19 / 21 / 28 across runs of the base). On
  the Forever side, besides the new lines: corecheck/forever's probe chat line reads `241 lines`
  instead of `238` (the `== windows` header, its line and the `esc to do:` line), and
  reviewforever's `forced=true (N frames)` varies between runs of the base too.
- `python3 tools/apicheck.py`: 8 Forever TOCs, 47 files, 46 distinct globals, 0 findings;
  `--selftest` 10 of 10. `python3 tools/refcheck.py --selftest`: ok.
- `luac -p` (tools/.lua/lua-5.1.5/src/luac) on `UI/Windows_Forever.lua`, `UI/Dashboard_Forever.lua`,
  `UI/DebugConsole.lua`, `Client/Probe.lua`, `tools/wincheck.lua`, `tools/probecheck.lua`,
  `tools/consolecheck.lua`: clean.

The TBC line is untouched: `UI/Windows_Forever.lua` is not on the TBC TOC, and every change to
`UI/DebugConsole.lua` is behind `if MD.Win` with the old lines in the `else`.

## Deviations

- **wincheck is +9, not +8.** The ninth is the `db.ui.escStack = false` fallback (the dashboard's
  name back in `UISpecialFrames`, the proxy down, one ESC closing it as before, and back to the
  stack), which the row lists as part of the task but not among its eight tests. T42 adds the
  Settings control's own test.
- **The esc= values.** 6.5 names `esc=stack` and `esc=all`; the line also says `esc=stuck` (the
  proxy was not shown again on the next frame while entries remained -- the UNVERIFIED case itself),
  `esc=untested`, `esc=off` and, when the probe runs without the kernel, `esc=no window manager`,
  each with the press's numbers. It sits in its own `== windows` section, and the result is kept
  in `db.ui.escTest`, so a `/reload` between the press and `/st probe` does not lose it.
- **The probe's own report box** joins the stack under the manager rather than keeping its
  `UISpecialFrames` line (6.5's "the copy box ... leave UISpecialFrames"; the row names only the
  `esc=` line for this file). Its strata is unchanged.
- **"Centred on the window that asked"** is read as the newest window on the stack (not a list, not
  the copy box itself): `MD:ShowCopyPopup(title, text)` has no caller argument, and every caller
  is either a window on the stack or a chat command.
- **Alt+Z / loading screens.** Not in the spec: the client runs `OnHide` on a shown frame when
  UIParent hides, which would have popped the top entry (the proxy) and dropped every window's
  entry. Both hooks now ignore an `OnHide` whose frame is still shown.
