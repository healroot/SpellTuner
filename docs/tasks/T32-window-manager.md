# T32 -- the window manager, core

Status: **built** 2026-09-30 on branch `ui/T32` (base 9c2a26e), awaiting review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T32** | **Window manager, core**: `MD.Win:Register(frame, {key, role})`, strata/level/toplevel per 6.2, TOPLEFT anchoring, saved positions with `SetUserPlaced(false)`, clamping, `db.ui.scale` with the position converted on a change, `UI.RestylePixels` on `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED` / a scale change, per-group size and minimum and the resize grip (`CreateMovableFrame opts.resizable`), `MD.Win:ShowMain(group, view)` with `MD:SelectView` routed through it, `/st ui reset`. The dashboard registers; the late grow goes. | `UI/Windows_Forever.lua` (new), `UI/Style.lua` (opts), `UI/Dashboard_Forever.lua`, `Core_Forever.lua`, both Forever TOCs | new `tools/wincheck.lua` (forever: strata; a per-group size restored; switching Spells -> Reports keeps the TOPLEFT; a clamp; a scale change converts the saved position; a scale event restyles) | T29 |

Spec sections: 4.3 (window scale, `UI.RestylePixels`), 6.1 (rules 1, 2, 5, 6), 6.2 (the main
window's row; the role strata), 6.3 (only "every caller of `MD:SelectView` goes through
`MD.Win:ShowMain`"; the takeover itself is T34), 6.7 (sizes per group, the grip, the late grow
gone), 7 (the manager Forever-only; the kit's `opts` additive), 8.1 (decision 6: resizable, a size
per group).

## What was built

| file | change |
|---|---|
| `UI/Windows_Forever.lua` (new) | **`MD.Win`**, listed after `UI/Theme_Forever.lua` in both Forever TOCs, not in TBC's. `Win.ROLES` (6.2): `host` HIGH / 10, `takeover` DIALOG / 10, `tool` FULLSCREEN / 10, each toplevel. `Win.SIZES` (6.7): Spells and Settings 860 x 560, minimum 860 x 480; Reports and Simulate 1036 x 646, minimum 1036 x 600. **`Win:Register(frame, { key, role, sizes })`** sets the role's strata, level and toplevel, `SetClampedToScreen(true)`, `SetUserPlaced(false)`, `SetScale(db.ui.scale)`, chains `frame.OnMoved` (the kit's drag end) to `SavePosition` and `frame.OnResized` (the grip's mouse-up) to `SaveSize`, and places it. **`Win:Place(key)`**: the group's size (saved, else default, never under the minimum) and `SetResizeBounds(minW, minH)` (`SetMinResize` where only that exists); the TOPLEFT at `db.ui.win[key].x / .y` (frame units, from UIParent's BOTTOMLEFT), else where it was put this session, else centred; **clamped** (left and right inside the screen, the left winning for a window wider than it; the header's top and the frame's bottom inside, the header winning), anchored `TOPLEFT` to `UIParent` `BOTTOMLEFT`, `SetUserPlaced(false)`. The wanted place is kept apart from the clamped one, so a bigger group the clamp pulled in goes back when a smaller group returns (6.7: "only then does the nav move"). **`SavePosition`** reads `GetLeft` / `GetTop`, clamps, saves, re-anchors. **`SaveSize`** saves the group's size raised to its minimum in `db.ui.win[key].sizes[group] = { w, h }` and re-places. **`SetGroup(key, group)`**: the group's size, the TOPLEFT kept. **`SetScale(s)`**: held to 0.7-1.2, written to `db.ui.scale`, every saved (and this session's) position converted `x * old / new`, `SetScale`, re-placed, then `UI.RestylePixels()`. **`Restyle()`** on `UI_SCALE_CHANGED` and `DISPLAY_SIZE_CHANGED` (through `MD:On`): `UI.RestylePixels()` and every window re-placed (clamped onto a smaller screen). **`Reset()`**: `db.ui.win = {}`, every window back at its default size, centred. **`ShowMain(group, view)`**: `MD:OpenMainWindow(group, view)` -- the door T34 adds the takeover rules to. |
| `UI/Style.lua` (additive) | `UI.CreateMovableFrame(..., notUserPlaced, opts)`: **`opts.resizable`** gives `SetResizable(true)` and a 16x16 grip button at the bottom right (the chat frame's size-grabber textures) whose mouse-down `StartSizing("BOTTOMRIGHT")` and mouse-up `StopMovingOrSizing()` then `f:OnResized()` when set (keeping `SetUserPlaced(false)` under `notUserPlaced`, as the drag does). `UI.CreateNavFrame(..., onShow, opts)` hands `opts` (and `opts.notUserPlaced`) to it. TBC passes neither: its calls are the same calls as before. |
| `UI/Dashboard_Forever.lua` | Built at 860 x 560 with `{ resizable = true, notUserPlaced = true }` and registered as `main` / `host` with `MD.Win.SIZES`; every nav selection calls `MD.Win:SetGroup("main", group)`. **The late grow is gone**: `GROWN_WIDTH` / `DesiredSize` and the `SetSize` on `SpellTuner_Replay`'s `MODULE_LOADED` are removed (the placeholder swaps stay). `MD:OpenMainWindow(group, view)` is the old `SelectView` body (a nil group opens on the remembered path); **`MD:SelectView` goes through `MD.Win:ShowMain`** when `MD.Win` exists; `/st` (`ToggleDashboard`) opens through `ShowMain()` too. The `UISpecialFrames` entry stays until T33. |
| `Core_Forever.lua` | **`/st ui reset`** -> `MD.Win:Reset()` and one chat line; anything else prints the usage. |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `UI\Windows_Forever.lua` after `UI\Theme_Forever.lua`. |
| `tools/wowstub.lua` (one hunk, `-- T32`) | `UI_SCALE_CHANGED` and `DISPLAY_SIZE_CHANGED` in the forever profile's allowed events (it raises on any other, so `MD:On` would silently skip them). |
| `tools/wincheck.lua` (new, forever) | 30 assertions. The stub's frames have no geometry, so the suite gives the frame metatable (after load, its own process only) a scale per frame, recorded points, strata / level / toplevel / user-placed / clamped / resizable / resize bounds, and `GetLeft` / `GetTop` for one-point anchors to `UIParent` in a 768-high base space (UIParent's effective scale = the UI scale, 0.71 on a 1920 x 1080 screen, as `UI.px` assumes). Asserts: the TOC placement; `MD.Win`'s API; `SelectView` through `ShowMain`; the main window registered as the host; HIGH / 10 / toplevel; not user-placed, clamped; TOPLEFT to BOTTOMLEFT; the takeover and tool strata; Spells 860 x 560 with its 860 x 480 bounds; the 16x16 grip; Reports 1036 x 646 with its bounds; **Spells -> Reports keeps the TOPLEFT**; **a per-group size restored** and saved; a size under the minimum raised; a drag saved; **a clamp** at the right edge, a bigger group pulled back in, the header kept on screen; `SetScale(0.8)` applied, **the saved position converted** and the window's screen TOPLEFT unmoved, the 70-120 % hold; **`UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED` and a window scale change restyle the 1-px edge**; `MODULE_LOADED` no longer grows the window; `/st ui reset` clears `db.ui.win` and centres the window at its default size; a saved place and a group's saved size used. |

## Tests first

`tools/wincheck.lua` against the base (9c2a26e, a `git archive` export with only the suite added):

```
UI/Windows_Forever.lua is in both Forever TOCs and not in TBC's                FAIL
MD.Win exists with Register, ShowMain, SetScale and Reset                      FAIL
0 ok, 2 failed (stopped: no MD.Win)
```

Nothing further can run without the manager, so the same export was run again with the new
manager, `Style.lua`, `Core_Forever.lua`, the TOCs and the stub hunk in, but **the base's
`UI/Dashboard_Forever.lua`**, to show the dashboard half is held too: 8 ok, 22 failed -- routing,
registration, HIGH / 10, not user-placed, the TOPLEFT anchor, every size, the grip, the drag, each
clamp, the scale, the late grow (`1036x646` on Spells), the reset and the saved place all FAIL;
what passes is the manager alone (the role table, a restyle on the two events, which re-snaps every
registered pixel frame, and the reset clearing `db.ui.win`) and two geometric facts a window that
never moves satisfies.

## Full check

- `tools/wincheck.lua` **30 ok, 0 failed** (new).
- The loop in `docs/TOOLS.md` §1 plus `themecheck` and `tabscheck`: every suite at its base count --
  simcheck PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25,
  dashui 56, regencheck 27, simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice 74,
  practiceui 49, migrate 7, probecheck 86, forevercheck 13, modulecheck 14, kitcheck 7,
  recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 11, reviewforever 10,
  coachforever 18, practiceforever 20, bindscheck 6, parsecheck 12, bookcheck 17, tipcheck 27,
  clockcheck 17, spellsui 17, measurecheck 30, releasecheck 13, themecheck 23, tabscheck 24;
  adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1, consolecheck 14 / 1 (forever / tbc).
  No count changed.
- The TBC UI suites that load `UI/Style.lua` (dashui, navui, replayui, reviewui, practiceui):
  **full output** diffed with the base's `Style.lua` and with this one -- identical apart from
  reviewui's wall-clock milliseconds (`opened ... 0 ms` / `1 ms`).
- `python3 tools/apicheck.py`: 0 findings (47 files, was 46: the manager). `--selftest`: 10 of 10.
  `python3 tools/refcheck.py --selftest`: ok.
- `luac -p` on every changed Lua file: ok.

## Deviations

- **`Win:Place(key)`** is public (the row names Register, ShowMain and reset only): T42's reset
  button, T34's takeover and the suite's reload case use it.
- **`MD:OpenMainWindow(group, view)`** is new in `Dashboard_Forever.lua`: `ShowMain` needs a door
  to the window that is not `MD:SelectView` (which now calls `ShowMain`), and T34 puts its rules in
  front of it.
- **Geometry in the suite, not the stub.** The frame geometry (scale, points, `GetLeft` / `GetTop`,
  strata and the rest) is installed by `tools/wincheck.lua` on the stub's frame metatable in its own
  process, so no other suite's frames change; the stub gained only the two events. T33 / T34 extend
  the same file and reuse it (the `TOP` anchor T34's placement needs is already modelled).
- **The clamp is computed by the manager** rather than left to `SetClampedToScreen` (which is also
  set): the result is deterministic, testable, and the same whether or not the client clamps a
  frame anchored by code.
- The window's scale is applied by `Register`; the Settings slider is T42's. The console and the
  copy box register in T33; the replay and practice windows in T34.
- `docs/TOOLS.md`'s loop does not list `wincheck` yet (nor T29's `themecheck` or T35's `tabscheck`):
  the docs are T44's row.
