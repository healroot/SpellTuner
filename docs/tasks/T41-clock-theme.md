# T41 -- the clock under the theme

Status: **built** 2026-09-30 on branch `ui/T41` (base 9c2a26e), awaiting review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T41** | **Clock under the theme** (4.4). | `UI/Clock_Forever.lua` | `tools/clockcheck.lua` | T29 |

Spec sections: 4.4 ("**Clock**: a pixel-snapped 1-px border and the `bg` fill. The 160x4 mana bar
gets a 1-px black backing, so it reads on bright ground. The text is unchanged."), 4.1 (`bg`,
`border`), 4.3 (`UI.px`, `UI.StylizeFrame` under `UI.PIXEL`, borders staying one pixel after a
scale change without a reload), 6.1 rule 6 and the 6.2 row ("The clock is a HUD. The manager never
touches it": MEDIUM strata, `db.clock.point`, never moved or scaled).

## What was built

| file | change |
|---|---|
| `UI/Clock_Forever.lua` | A local `Snap()`: `UI.StylizeFrame(widget, UI.PALETTE.bg, UI.PALETTE.border)` (the theme's #161616 at 0.96, a black edge; under T29's `UI.PIXEL` the edge and insets are `UI.px(1, widget)` and the frame is in `UI.pixelFrames`), and the bar's backing sized `160 + 2px` x `4 + 2px`. The backing (`Clock.barBack`) is an ARTWORK texture of the widget, `SetColorTexture(0, 0, 0, 1)`, centred on the bar: the bar is a child frame and draws above it, the backdrop beneath it. `CreateWidget` calls `Snap()` instead of the bare `UI.StylizeFrame(widget)` it had. **`Paint` re-snaps whenever `UI.px(1, widget)` differs from the value last snapped to**, so a UI scale or display change re-edges the widget and re-sizes the backing on the next 0.5 s tick, with no reload and without the window manager (which never touches the clock). The text, its font, the bar (160x4, 0.3/0.6/1, `MD.API.DrawUnitPower`), the hover, visibility and position are unchanged. |
| `tools/clockcheck.lua` | +3 (17 -> 20), forever: the widget's fill is `UI.PALETTE.bg`, its border `UI.PALETTE.border`, its edge and insets `UI.px(1)` and it is in `UI.pixelFrames`; `Clock.barBack` is a black texture of the widget, `160 + 2px` x `4 + 2px`, with the bar still 160x4; at effective scale 0.64 the next tick re-snaps the edge and the backing to the new `UI.px(1)` and keeps the fill. |

No other file changed: no stub hunk, no shared file, no adapter binding (the physical height already
reaches `UI.px` through T29's `MD.API.PhysicalScreenSize`).

## Tests first

`tools/clockcheck.lua` with the three new assertions against the base's `UI/Clock_Forever.lua`:

```
the clock is filled with the theme's bg and edged in one physical pixel  FAIL - bg=0.1,0.1,0.1,0.9 edge=0.71111111111111 px=0.71111111111111
the mana bar has a black backing one physical pixel wider on every side  FAIL - back=false w=nil h=nil want 161.42222222222 x 5.4222222222222
a UI scale change re-snaps the clock's edge and the bar's backing without a reload FAIL - edge=0.71111111111111 backW=nil want px=1.1111111111111

17 ok, 3 failed
```

(The old clock already had a one-physical-pixel edge at load, because T29's `UI.PIXEL` reaches every
`StylizeFrame`; what it lacked was the `bg` fill, the backing, and a re-snap after a scale change.)

After the change: `20 ok, 0 failed`. The full output differs from the base's only by the three new
lines and the count: every existing line, the text shapes and the three-moment demonstration
(text and hover) are byte-identical.

## The full check

The suite loop of `docs/TOOLS.md` section 1 plus `themecheck` and `tabscheck`, run on this branch and
on an export of the base (9c2a26e) and diffed:

- **clockcheck 17 -> 20** (the three above). Every other count identical: simcheck PASS, reccheck
  54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27,
  simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7,
  probecheck 86, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12,
  gatecheck 9, replayforever 11, reviewforever 10, coachforever 18, practiceforever 20, bindscheck 6,
  parsecheck 12, bookcheck 17, tipcheck 27, spellsui 17, measurecheck 30, themecheck 23,
  tabscheck 24, releasecheck 13; adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1,
  consolecheck 14 / 1 (forever / tbc). All 0 failed.
- (On the base *export* releasecheck fails its CRLF step because the export is not a git checkout
  and the suite copies the tree with `git ls-files`; in this worktree it is 13 ok.)
- `python3 tools/apicheck.py`: 8 Forever TOCs, 46 files, 0 findings; `--selftest` 10 of 10.
- `python3 tools/refcheck.py --selftest`: ok.
- `luac -p` (tools/.lua/lua-5.1.5/src/luac) on `UI/Clock_Forever.lua` and `tools/clockcheck.lua`: clean.

The TBC line is untouched: `UI/Clock_Forever.lua` is on the Forever TOCs only.

## Deviations

- The re-snap after a scale change is the clock's own (a comparison of `UI.px(1, widget)` in
  `Paint`, every 0.5 s tick) rather than an event. The spec has the window manager (T32) call
  `UI.RestylePixels()` on `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED`, which would re-edge the
  widget (it is in the registry) but cannot know the backing's size, and 6.1 says the manager never
  touches the clock. Registering those two events here would also need them in the stub's
  `FOREVER_EVENTS`, the stub T32 (on a parallel branch) is the one to extend for them. The tick costs one adapter read of the
  physical screen size per half second; when T32's `RestylePixels` lands, the clock's own re-snap
  simply finds nothing to do or repeats the same edge.
