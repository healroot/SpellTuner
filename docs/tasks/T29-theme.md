# T29 -- the Forever theme: palette, text tokens, fonts, font offset, pixel edges

Status: **built** 2026-09-29 on branch `ui/T29` (base af266e5), awaiting review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T29** | **Theme** (4.1-4.3): `UI/Theme_Forever.lua` (palette, `UI.TEXT`, new fonts, `UI.ApplyFonts`, `db.ui.fontOffset` clamped to -2..+2, `UI.Pitch`, `UI.PIXEL`, `UI.LIST_STRATA`); `UI/Style.lua` additive (`UI.px`, `StylizeFrame` honours `UI.PIXEL` and records the frame in a weak registry, `UI.RestylePixels()`); `MD.API.PhysicalScreenSize`; `Core_Forever.lua` defaults `ui = { fontOffset = 0, scale = 1, combat = "hide", escStack = true, win = {} }` | `UI/Theme_Forever.lua` (new), `UI/Style.lua`, `Client/API_Forever.lua`, `Core_Forever.lua`, `SpellTuner_Mainline.toc`, `SpellTuner.toc` | new `tools/themecheck.lua` (forever: gold absent from `UI.TEXT`, fonts built, an offset of +4 clamped to +2, `UI.Pitch(20)` at -2 / 0 / +2, `px` at scales 0.64 / 0.71 / 1, `RestylePixels` re-applies a new edge to a registered frame); `tools/navui.lua` 25 and `tools/dashui.lua` 56 unchanged | -- |

Spec sections: 4 (intro), 4.1, 4.2, 4.3; 6.2 (`UI.LIST_STRATA`); 7 (the theme row); 8.1 (decision
13: offset -2..+2).

## What was built

| file | change |
|---|---|
| `UI/Theme_Forever.lua` (new) | Listed right after `UI/Style.lua` in both Forever TOCs. At load: **`UI.PALETTE`** mutated in place with 4.1's fills (`bg` #161616 0.96, `pane` #1C1C1C, `nav` 0.115, `border`, `rule` accent 0.6, `line` #2A2A2A, `rowAlt` white 0.03, `hover` accent 0.12, `selected` 0.28, `suggested` 0.10, `mask` #262626 0.7, `close` (0.6, 0.1, 0.1, 0.6) and `closeHover` alpha 1), and the kit's own `frame` / `header` keys pointed at `bg` / `nav` so `UI.CreateNavFrame` and the dropdown lists follow. **`UI.TEXT.<token>` = `{ r, g, b, hex = "\|cffrrggbb" }`** for `accent` (Style.lua's class colour and its `accentHex`; druid `ff7c0a`), `text`, `text2`, `label`, `muted`, `disabled`, `mana`, `good`, `bad` -- no gold. **Fonts** (no outline, black shadow at 1, -1): `UI.FONT_HEAD` (Friz 16), `UI.FONT_BIG` (Friz 18), `UI.FONT_NUM` (`Fonts\\ARIALN.TTF` 13), `UI.FONT_NUM_SMALL` (ARIALN 11). **`UI.ApplyFonts(offset)`** rounds, clamps to -2..+2 (`UI.FONT_OFFSET_MIN/MAX`), re-sizes all twelve kit and theme font objects in place (Style's eight at their own sizes plus the four new), stores `UI.fontOffset` and returns the offset applied. **`UI.Pitch(n)`** = `n + max(0, offset)`. On `CORE_LOGIN` the saved `db.ui.fontOffset` is clamped, written back and applied. **`UI.PIXEL = true`**, **`UI.LIST_STRATA = "FULLSCREEN_DIALOG"`**. |
| `UI/Style.lua` (additive) | `UI.fontObjects` (name -> font object, filled by `MakeFont`, read by `ApplyFonts`). **`UI.px(n, frame)`** = `n * (768 / physicalHeight) / frame:GetEffectiveScale()` (frame defaults to `UIParent`), the height through `MD.API.PhysicalScreenSize`; with no binding (TBC) or no usable number it returns `n`. **`UI.StylizeFrame`** under `UI.PIXEL` sets `edgeSize` and all four `insets` to `UI.px(1, frame)` and records the frame in **`UI.pixelFrames`** (`__mode = "k"`, value = the colours it was styled with); without `UI.PIXEL` it is byte-for-byte today's backdrop and records nothing. **`UI.RestylePixels()`** re-applies the pixel backdrop to every registered frame, keeping the colours the frame shows now (`GetBackdropColor` / `GetBackdropBorderColor`, falling back to the recorded ones), each frame under its own `pcall`; returns the count. |
| `Client/API_Forever.lua` | `MD.API.PhysicalScreenSize` -> `GetPhysicalScreenSize` (69893 baseline). |
| `Core_Forever.lua` | `DEFAULTS.ui = { fontOffset = 0, scale = 1, combat = "hide", escStack = true, win = {} }`. |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `UI\Theme_Forever.lua` after `UI\Style.lua`. |
| `tools/themecheck.lua` (new, forever) | 23 assertions: the TOC placement (and absent from TBC's); `UI.TEXT` tokens present, shaped, gold-free, the accent the class colour, the hex values; the palette fills, the accent fills, `frame`/`header` following; the seven fonts of 4.2 with face and size; +4 clamped to +2 with every font +2; `UI.Pitch(20)` 22 / 20 / 20 at +2 / -2 / 0; the `db.ui` defaults; a saved +4 back as +2 at login and applied; `UI.PIXEL` and `UI.LIST_STRATA`; `MD.API.PhysicalScreenSize`; `UI.px` at 0.64 / 0.71 / 1 (and 3 px); `px` = n with no screen height; the pixel backdrop's edge and insets; the weak registry; `RestylePixels` re-applying a new edge after a screen and scale change; the current colours kept; the TBC path unchanged. |
| `tools/wowstub.lua` (hunks tagged `-- T29`) | `FrameMT:SetFont` records face/size/flags and `GetFont` hands them back (an object never given `SetFont` answers `"font", 12, ""` as before); `GetPhysicalScreenSize` answering `S.physicalWidth, S.physicalHeight` (1920 x 1080); templated frames get `GetBackdropColor` / `GetBackdropBorderColor`. |
| `tools/adaptercheck.lua` (tagged `-- T29`) | `"PhysicalScreenSize"` in `FOREVER_ONLY_NAMES`. |

## Tests first

`tools/themecheck.lua` against the base's addon code (before any addon or stub change):

```
the theme follows UI/Style.lua in both Forever TOCs and not in TBC's     FAIL
UI.TEXT carries every text token of 4.1                                  FAIL
each UI.TEXT token is r, g, b plus an ASCII |cffrrggbb hex               FAIL
Blizzard gold is absent from UI.TEXT                                     FAIL
UI.TEXT.accent is the class colour (druid ff7d0a in the stub)            FAIL
the text tokens' values (text2 b3b3b3, muted 7a7a7a, mana 4d99ff, bad e0605a) FAIL
UI.PALETTE holds 4.1's fills (bg 0.96, pane, nav, line, rowAlt, mask, border) FAIL
the accent fills: rule 0.6, hover 0.12, selected 0.28, suggested 0.10; close as Cell FAIL
the kit's window and header keys follow bg and nav                       FAIL
the fonts of 4.2 are built with their faces and sizes, no outline        FAIL - FONT_TITLE=nil/nil FONT_HEAD=nil/nil ...
an offset of +4 is clamped to +2 and every font grows by 2               FAIL - got=nil head=nil num=nil class=nil
UI.Pitch(20) is 20 at -2, 20 at 0 and 22 at +2                           FAIL - +2:nil -2:nil 0:nil small@-2=nil
db.ui defaults: fontOffset 0, scale 1, combat hide, escStack on, win {}  FAIL
a saved offset of +4 comes back +2 at login, applied to the fonts        FAIL - saved=nil FONT=nil
the theme sets UI.PIXEL and UI.LIST_STRATA = FULLSCREEN_DIALOG           FAIL
MD.API.PhysicalScreenSize answers the physical screen through the adapter FAIL - nilxnil
UI.px(n, frame) = n * 768 / physicalHeight / effective scale at 0.64, 0.71 and 1 FAIL - 0.64:nil ...
UI.px with no usable screen height is n itself                           FAIL - nil
StylizeFrame under UI.PIXEL uses UI.px(1) for the edge and the insets    FAIL - 1
the styled frame is in a weak-keyed registry                             FAIL
UI.RestylePixels re-applies a new edge and insets to a registered frame  FAIL - 1
a restyle keeps the frame's current fill and border colours              FAIL
without UI.PIXEL StylizeFrame is today's 1-unit edge and records nothing ok
1 ok, 22 failed
```

The last one is a regression guard for the TBC path and passes on the old code by design. The
accent line's expected hex was corrected afterwards from `ff7d0a` to `ff7c0a` (4.1's druid
#FF7C0A; Style.lua's `accentHex` truncates, as Blizzard's own `colorStr` reads). The
`adaptercheck` entry was checked the same way: with the list extended and the binding renamed away,
`adaptercheck/forever` fails `every binding is on MD.API and in the capability table` (21 / 1).

## Full check

- `tools/themecheck.lua` **23 ok, 0 failed** (new).
- The loop in `docs/TOOLS.md` §1: every suite at its base count -- simcheck PASS, reccheck 54,
  replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27,
  simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7,
  probecheck 86, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12,
  gatecheck 9, replayforever 11, reviewforever 10, coachforever 18, practiceforever 15,
  bindscheck 6, parsecheck 12, bookcheck 17, tipcheck 22, clockcheck 17, spellsui 17,
  measurecheck 30, releasecheck 13; adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1,
  consolecheck 14 / 1 (forever / tbc). No count changed.
- The sixteen TBC suites' **full output** diffed before and after: identical apart from
  wall-clock milliseconds, the frame-sliced search's evaluation counts (sliced on
  `debugprofilestop`) and table addresses.
- `python3 tools/apicheck.py`: 0 findings (45 files, was 44: the theme). `--selftest`: 10 of 10.
  `python3 tools/refcheck.py --selftest`: ok.
- `luac -p` on every changed Lua file: ok.

## Deviations

- `UI.fontObjects` in `UI/Style.lua` is an addition the row does not name: `ApplyFonts` needs the
  kit's font objects, and Style.lua built them without keeping them (the client makes them
  globals, the stub does not; making the stub's `CreateFont` register a global would have changed
  `UI/ReplayWindow.lua`'s `FONT_PATH` under the TBC suites). Nothing on TBC reads it.
- `UI.PALETTE.closeHover` (the x at alpha 1) and `UI.FONT_OFFSET_MIN` / `MAX` are named here; 4.1
  and 4.2 give the values but not the keys.
- `ApplyFonts` also re-sizes Style.lua's `FONT_TITLE_DISABLE`, `FONT_DISABLE`, `FONT_SPECIAL`,
  `FONT_CLASS_TITLE` and `FONT_CLASS` (4.2: "shifts every size above"; they are the same kit).
- The palette's `nav` is Cell's 0.115 rather than #1D1D1D's 0.1137 (4.1 names both; the kit's
  header already used 0.115).
- `docs/TOOLS.md`'s suite loop does not list `themecheck` yet: docs are T44's; run it as
  `bash tools/run.sh tools/themecheck.lua`.
- `UI.LIST_STRATA` is only set here; the kit reading it (default `"DIALOG"`) is T31's.
