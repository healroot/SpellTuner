# T75 -- Kit layout and sizes (plan P31)

Status: **built** 2026-10-01 on branch `plan/P31` (base `0e7dded`), wave 14 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. No file was added, so no TOC line is needed.

## The task (docs/PLAN-refactor-ux.md section 5, P31)

Review items (`docs/review/2026-09-30-project-review.md`): **U14** (a resize grip on windows that
cannot shrink: Spells/Settings `minW == w == 860`, nothing reflows), **U26** (no size scale; the number
font only in the theme), **U30** (the font offset does not reach measurements: view-tab widths from
`#text * 8 + 16`, check hit rects measured once), **U31** (layout parts: the header title centred on the
whole header while a back button takes 84 px; sheets have no `x`; the mask is mute; nav buttons 22 tall
and view tabs 20, both at -2). Approved mockups (`docs/mockups/refactor-ux.html`): M1's note "Both
columns fit at 860 x 560, so the resize grip is gone (P31: it hides where a group's minimum equals its
size)", M4's "Text size 0: widths measured from the text" panel (tabs and check click areas follow the
text) and the window chrome (`.hdr`, `.hdr .back`, `.hdr .x`, `.grip`, `.nb`, `.vt`).

Owned files (section 4, wave 14): `UI/Style.lua`, `UI/Windows_Forever.lua`, `tools/themecheck.lua`,
`tools/navui.lua`, `tools/wincheck.lua`. All five were edited, plus this task file; nothing else.

## What was built

### Gated on `UI.THEMED` (TBC keeps every current size and position)

- **View-tab widths from the text** (`UI/Style.lua`, `CreateNavFrame`'s `BuildViews`): a tab is its
  text's width plus 12 each side (minimum 40), measured through the new `UI.TextWidth(text, font, fs)`
  -- the button's own font string when it holds that text (its unbounded width where the client has
  `GetUnboundedStringWidth`, since a string anchored inside a button may be cut), else one hidden
  measuring string set to the font. TBC keeps `math.max(64, #v.text * 8 + 16)`. `CreateNavBox` (no
  caller yet) measures the same way under the theme (8 each side; TBC `#text * 7 + 14`).
- **The nav and view rows aligned**: under the theme a view tab is `UI.H.toolbar` (22) tall, the
  height of the nav's group buttons, both rows starting 2 below the window's top (TBC: tabs 20).
- **Pixel overlaps**: the nav's group buttons and the view tabs overlap by `UI.px(1)` instead of one
  unit, through `UI.PixelLayout` (a no-op without `UI.PIXEL`, so TBC keeps its literal 1). A pooled tab
  that becomes the first of a row drops its old layout.
- **Check hit rects from the label** (`CreateCheckButton`): under the theme `cb:Measure()` sets the
  click area from the label's measured width, and runs again whenever the box shows (the font offset
  may have moved since it was made). TBC measures once at creation, as before.
- **The header title between back and `x`** (`CreateMovableFrame`): under the theme the title is
  anchored LEFT at the back button's width + 4 (the `x`'s 20 + 4 while the back button is hidden, so it
  stays centred on the header) and RIGHT at the `x`'s left - 4, one line, cut rather than wrapped,
  re-laid by the back button's `OnShow` / `OnHide`. TBC keeps it centred on the whole header.
- **Sheets get the 20x20 `x`** (`CreateSheet`): a red `x` at the right of the title row, inside the
  1-px edge (`UI.px(1)` under `UI.PIXEL`); a click hides the sheet, so the mask and the ESC entry go
  through the sheet's own `OnHide`. A button the caller anchors by its TOPRIGHT to the sheet's TOPRIGHT
  (the bindings sheet's title-row Done) is laid left of the `x` at the same offsets (`UI.CreateButton`
  on a parent with `isSheet` and `closeBtn`), so the two never overlap. TBC builds no sheet.
- **The grip drawn as three 1-px lines** (`UI.FlatGrip`, used by `CreateMovableFrame` under the theme
  instead of Blizzard's SizeGrabber art): lines from `(-d - 2, 2)` to `(-2, d + 2)` off the grip's
  bottom-right corner for d = 4, 8, 12, in `muted`, the accent under the pointer. Each is the client's
  `Line` region (`CreateLine`, thickness `UI.px(1)`) where the frame makes one, else a texture one
  pixel high turned 45 degrees about the same centre; both re-laid by `UI.RestylePixels`.
- **The grip hidden where a group's minimum equals its size** (`UI/Windows_Forever.lua`): Spells and
  Settings now have `minH = h = 560` (their minimum is their size: the rank table and card are a fixed
  540 and Settings' two columns fit 860 x 560, mockup M1), and `Win:Fixed(key, group)` /
  `IsFixed(def)` name such a group. `ApplySize` hides the grip on a fixed group and shows it on the
  others; `SizeFor` gives a fixed group its default size whatever an older session saved; `SaveSize`
  saves nothing for it. Reports and Simulate keep their grip and their saved sizes.

### Ungated, additive (no TBC caller reads them)

- `UI.H = { button = 20, small = 18, row = 20, toolbar = 22 }` -- panes adopt it when touched.
- `UI.FONT_NUM` (13) and `UI.FONT_NUM_SMALL` (11), Arial Narrow, white, defined in `UI/Style.lua`
  (`MakeFont` takes an optional face). Every shared caller already asks for them behind the theme
  (`Dashboard_Review.lua` under `THEMED`, the rail, Forever-only panes); `UI/Theme_Forever.lua` re-makes
  them at the same face and size (its `MakeFont` reuses the object) and resizes them with the offset.
- `UI.CreateMask(region, level, text)` takes an optional line of text, centred (Cell's mask), in
  `text2`; `mask:SetText(t)` sets or clears it later. The font string is made only when text is given;
  no caller passes one yet.
- `UI.TextWidth(text, font, fs)` (above).

## Tests first

The assertions were written first and run against the parent's `UI/Style.lua` and
`UI/Windows_Forever.lua` (`git show 0e7dded:<file>`, the new suites in place):

```
tools/navui.lua (tbc)            38 ok, 2 failed
  on TBC view tabs are #text * 8 + 16 by 20                       ok   (the guard, green by design)
  under the theme a view tab is as wide as its text               FAIL - 120 / 80, want 102 / 72
  under the theme the nav and view rows share a top and a height  FAIL - tops -2 / -2, heights 22 / 20
tools/themecheck.lua (forever)   31 ok, 6 failed
  T75: UI.H is the kit's size scale (button 20, small 18, row 20, toolbar 22)   FAIL - nil/nil/nil/nil
  T75: the header title sits between the back button and the x                 FAIL - left false -> false -> false
  T75: a sheet has a 20x20 x that hides it; a title-row button goes left of it FAIL - x false, done -> false TOPRIGHT
  T75: a check box's click area is measured from its label when it shows       FAIL - right inset nil, want -185
  T75: a mask carries an optional line of text                                 FAIL - nil
  T75: the grip is three 1-px Line regions where the client makes them         FAIL - 0 lines, first nil
tools/themecheck.lua (tbc)       8 ok, 1 failed
  tbc: T75: UI.H and the two Arial Narrow fonts are in the kit                 FAIL - H nil/nil/nil/nil, num nil nil
tools/wincheck.lua (forever)     61 ok, 4 failed
  Spells opens at 860 x 560 with the minimum 860 x 560 (T75: a fixed group)     FAIL - 860x560 (its bounds 860 x 480)
  T75: no grip on Spells or Settings (minimum = size), the grip on Reports      FAIL - spells true settings true reports true
  T75: under the theme the grip is three 1-px lines                             FAIL - 0 lines
  T75: Spells keeps 860 x 560 over an old saved size and a resize, saving none  FAIL - 900x600 / 950x620
```

After the change every one passes.

## Suites

| suite | before | after |
|---|---|---|
| `navui/tbc` | 37 | 40 (+3: on TBC the tabs are `#text * 8 + 16` by 20; under the theme a tab is its text's width + 24; under the theme the group row and the view row share a top (-2) and a height (22)) |
| `themecheck/forever` | 31 | 37 (+6: `UI.H`; the header title between back and `x`; a sheet's 20x20 `x` hiding it with a title-row button laid left of it; a check box's click area re-measured on show; a mask's line of text; the grip as three 1-px `Line` regions -- the suite lends the stub's frames a recording `CreateLine` for that one window) |
| `themecheck/tbc` | 8 | 9 (+1: `UI.H` and the two Arial Narrow fonts are in the kit, ungated) |
| `wincheck/forever` | 62 | 65 (section 4 rewritten: Spells opens at 860 x 560 with the minimum 860 x 560; +3: no grip on Spells or Settings, the grip on Reports; the grip as three 1-px lines; Spells keeps 860 x 560 over an old saved size and a resize, saving none. The per-group size, the saved size and the raise-to-minimum checks run on Reports -- 1100 x 700 restored, 1036 x 600 -- since Spells no longer resizes) |
| every other suite | as `tools/data/expected-counts.json` | equal |

`make check` (`tools/check.sh`): 68 runs, all passed (the four notes are the counts above); `apicheck`
0 findings (57 files, 47 distinct globals); `textcheck` 0 findings (9 TOCs, 93 files); `luac -p` on
`UI/Style.lua` and `UI/Windows_Forever.lua`.

TBC byte-identity (principle 2): every suite's output was kept before the first edit and compared after
(table addresses and `ms` timings normalised). `navui/tbc` and `themecheck/tbc` are identical plus their
new lines (`themecheck/tbc`'s token scan counts 129 reads instead of 127: the grip's and the mask's
`UI.RGB` reads, both found in TBC's tables). `dashui/tbc` differs in one count only: `frames 809 -> 809`
became `811 -> 811`, the two font objects `UI/Style.lua` now makes at load (the stub's registry counts a
font object as a frame; nothing is drawn). `reviewui/tbc`, `replayui/tbc`, `simwindow/tbc` and
`coachforever/forever` differ only in the time-sliced search's evaluation and frame counts, which differ
between two runs of the same code (`simwindow` gave 6, 5, 5 frames on three runs of this tree). Every
other suite, both flavours, is identical; `spellsui`, `practiceforever` (the bindings sheet) and
`reviewforever` included.

## Integrator lines

- **TOCs**: none (no new file).
- **`tools/data/expected-counts.json`**: `"navui/tbc": 40,` (was 37), `"themecheck/forever": 37,` (was
  31), `"themecheck/tbc": 9,` (was 8), `"wincheck/forever": 65,` (was 62).
- **`docs/TOOLS.md`** section 1:
  - the `navui.lua` row ends: `Since **T75** (40): on TBC the view tabs are `#text * 8 + 16` by 20;
    under the theme (UI.THEMED switched on for Style.lua's gate, the stub's geometry) a tab is its
    text's width + 24 and the group and view rows share a top and a height`
  - the `themecheck.lua` row: `(T29, T69, T74, T75; forever 37, tbc 9)`, and ends: `Since **T75**:
    `UI.H` (and, under tbc, the two Arial Narrow fonts in the kit); the header title between the back
    button and the x; a sheet's 20x20 x with a title-row button laid left of it; a check box's click
    area re-measured on show; a mask's line of text; the grip as three 1-px Line regions (a recording
    `CreateLine` lent to the stub for one window)`
  - the `wincheck.lua` row: `(... 65)`, and ends: `Since **T75**: Spells and Settings are fixed groups
    (minimum = size) with no grip, Reports keeps one; the grip is three 1-px lines; a fixed group ignores
    an old saved size and a resize; the resize checks run on Reports`
- **`docs/DECISIONS.md`**, one entry (a Forever behaviour change; TBC does not move):

  > ### Spells and Settings have one size (T75, P31, 2026-10-01)
  > On Forever the Spells and Settings groups are 860 x 560 with that as their minimum: nothing in them
  > reflows (the rank table and card are a fixed 540; Settings' two columns fit), so the resize grip is
  > hidden there (mockup M1) and a size saved for them by an earlier session is ignored. Reports and
  > Simulate keep the grip and their saved sizes (decision 6, a size per group, stands). Under the theme
  > the grip is three 1-px lines; TBC keeps Blizzard's grip art (it has no resizable window).

- **`CLAUDE.md`**:
  - appended to the `UI/Style.lua` row: **T75 (P31, review U14, U26, U30, U31):** `UI.H` (`button` 20,
    `small` 18, `row` 20, `toolbar` 22) and `UI.FONT_NUM` / `UI.FONT_NUM_SMALL` (Arial Narrow) in the
    kit, additive; `UI.TextWidth(text, font, fs)` (a button's own string, unbounded where the client
    has it, else a measuring string); `UI.CreateMask(region, level, text)` with `mask:SetText`. Under
    `UI.THEMED` only: view tabs as wide as their text (+12 each side) and `UI.H.toolbar` tall, aligned
    with the group row, both rows overlapping by `UI.px(1)`; check click areas re-measured on show
    (`cb:Measure()`); the header title between the back button and the x; a sheet's 20x20 x (a
    title-row button anchored to the sheet's TOPRIGHT goes left of it); the grip as three 1-px lines
    (`UI.FlatGrip`: `Line` regions, a turned texture where the frame makes none). TBC unchanged
  - appended to the `UI/Windows_Forever.lua` row: **T75 (P31, review U14):** Spells and Settings are
    fixed groups (`minH = h = 560`; `Win:Fixed(key, group)`): no grip, always their default size, nothing
    saved; Reports and Simulate keep the grip.
- **`docs/TESTING.md`** section 44, a check for the author on Forever:

  > **Layout and sizes (P31).** `/st`: Spells and Settings have no resize grip in the bottom-right
  > corner; Reports and Simulate have one, drawn as three thin diagonal lines that turn the accent colour
  > under the pointer, and dragging it still resizes. The view tabs along the top (Reports, Settings)
  > are as wide as their names and as tall as the Spells / Reports buttons on the left, their tops and
  > bottoms in one line. Open a replay from Review: the title sits between `< SpellTuner` and the x,
  > never under either. Open Spells -> `+ Add` and Simulate -> Practice -> Edit bindings: each sheet has
  > a red x at the right of its title row that closes it; the bindings sheet's Done sits left of the x.
  > Set Text size to +2, close and reopen the window, and click a Settings checkbox on the far end of its
  > label: it toggles. **TBC:** `/md` -- the window, its tabs and its checkboxes look exactly as before.

## Deviations

- **Spells and Settings' minimum height** went from 480 to 560. The plan's rule is "hidden where a
  group's minimum equals its size", and only the widths were equal (860); the mockup M1 says the grip
  is gone at 860 x 560, so the minimum is made the size. A size an older session saved for these groups
  (with the grip that existed until now) is ignored, since nothing would be left to shrink it back.
  wincheck's per-group-size checks that used Spells (900 x 600, raised to 860 x 480) now use Reports.
- **The view tabs are 22 tall under the theme**, not 20 as mockup M1's `.vt`: U31 asks for the two rows
  aligned and the nav's group buttons are 22 in every approved mockup (`.nb`), so the tabs take
  `UI.H.toolbar`. The content's top (-32) is unchanged, leaving 8 below a 22-px tab row.
- **The bindings sheet's Done** is not this task's file (`UI/BindingsWindow.lua`), and it sits at the
  sheet's top right where the new x goes. Rather than overlap them, `UI.CreateButton` lays a button
  anchored by its TOPRIGHT to a sheet's TOPRIGHT left of the sheet's x (a kit rule, documented in
  `UI/Style.lua`). Whoever next owns `UI/BindingsWindow.lua` (C1) may anchor it to `frame.closeBtn`
  explicitly or drop it in favour of the x.
- **The grip's lines**: the plan says three 1-px lines; the mockups draw them diagonal. The client's
  `Line` region draws a crisp diagonal; the stub's frames make none (their unknown methods answer nil),
  so a texture turned 45 degrees is the fallback, and the suites hold both paths (wincheck the
  fallback, themecheck the `Line` path through a lent `CreateLine`). *In-game check needed:* the three
  lines on Reports' grip are diagonal and one pixel thick at 0.71.
- **`FONTS_CHANGED`** is P33's: this task measures when a tab row is built (every group switch) and when
  a check box shows, and exposes `cb:Measure()` and `UI.TextWidth` for P33's re-measure; a window open
  across a Text size change keeps its tab widths until the group is switched (as today).
- **The back button** stays 84 wide (the mockup's `.hdr .back` pads its text by 8; nothing in U31 asks
  for it to shrink, and a narrower button only gives the title more room).
- **Nav overlaps**: the one-unit overlaps between group buttons and between view tabs become one pixel
  under `UI.PIXEL` (P30 left the layout offsets to P31). `CreateNavBox` (no caller) measures its tabs
  under the theme too.
- **No install** was made from this worktree: the author's request to install the current version on
  both clients is for the integrator once the wave is merged (`make install`, both flavours).
