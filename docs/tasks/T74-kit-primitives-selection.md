# T74 -- Kit primitives: pixel edges and one selection language (plan P30)

Status: **built** 2026-10-01 on branch `plan/P30` (base `7b77391`), wave 13 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. No file was added, so no TOC line is needed.

## The task (docs/PLAN-refactor-ux.md section 5, P30)

Review items (`docs/review/2026-09-30-project-review.md`): **A20** (the primitives half: 17 literal
`0.115`s and ~27 other colours in `CreateButton`, `CreateCheckButton`, `CreateEditBox`, `CreateSlider`,
`CreateScrollFrame` and the movable frame's header; `BUTTON_COLORS` frozen at load; `P.close` unread),
**U1** (the nav's selected state is its hover state: moving down the nav lights every button like the
selected one) and **U3** (only frames styled by `StylizeFrame` get a crisp pixel; every button and
check border is soft next to a crisp window edge at the author's 0.71 scale). Approved mockup:
`docs/mockups/refactor-ux.html`, the rules marked P30 -- `.nb.on` (the nav: `selected` fill, 2-px accent
bar on the left), `.vt.on` (view tabs: the bar at the bottom), `.btn.act` ("a button group's active
member = selected fill + 2 px accent bar"); spec 4.3's "selected: accent 0.3 fill plus a 2-px accent bar".

Owned files (section 4, wave 13): `UI/Style.lua`, `tools/themecheck.lua`, `tools/navui.lua`. All three
were edited, plus this task file; nothing else.

## What was built (UI/Style.lua)

### The primitives read tokens (A20)

- **`UI.PALETTE` moved up** to the tokens section, ahead of the primitives that read it (it sat with the
  navigation, after them), and gained the primitives' fills, each holding the literal the primitive
  carried: `button` (0.115, 1), `buttonHover` (0.23), `field` (0.115, 0.9: edit box, check box), `well`
  (0.15, 0.9: the copy box), `track` (0.1, 0.8: a scroll bar), `thumb` (accent 0.8), `check` (accent 0.7),
  `checkHover` (accent 0.1), `accentFill` (accent 0.3), `accentHover` (accent 0.6), `close` / `closeHover`
  (Cell's red, the values the theme already sets -- `P.close` is now read), `go` / `goHover` (green),
  `info` (blue), `warn` (yellow), `clear` (0, 0, 0, 0).
- **One text token added**, `UI.TEXT.dimmed` = `666666` (0.4: a disabled check box, slider or edit box,
  `FONT_DISABLE`'s grey). Not a legacy token: the theme does not map it, so a disabled control stays 0.4
  on both lines (see Deviations).
- **`BUTTON_COLORS`** is a table of palette key pairs, read when a button is made through the new
  `UI.ButtonColors(name) -> fill, hover` (an unknown name the plain grey pair; `none` has no hover) --
  no longer tables frozen when the file loaded, so the theme reaches them.
- `CreateButton` (its `bg` texture, border), `CreateCheckButton` (fill, border, tick, hover, the
  enabled / disabled colours), `CreateEditBox` (fill, enabled / disabled text), `CreateScrollFrame`
  (track, thumb), `CreateScrollEditBox` (well), `CreateSlider` (track, thumb in all four states, the
  disabled greys) and `CreateMovableFrame`'s header (`PALETTE.header`) read `UI.Fill` / `UI.RGB` /
  `UI.PALETTE`. The separator's and the titled pane's black shadow read `border`.

On TBC every key holds the old literal, so every colour is equal; on Forever the theme leaves these
keys (its `close` / `closeHover` are the same values, and `header` follows its `nav`, the same 0.115),
so Forever's colours are equal too. The 0.777 accent of the titled pane's and the separator's rule is
not a primitive's and stays (P34 owns the rule colour).

### Pixel edges and insets (U3)

- **Controls under `UI.PIXEL`**: a bordered `CreateButton` and the check box take `StylizeFrame`'s
  pixel backdrop (edge and insets `UI.px(1)`) and are registered in `UI.pixelFrames`, so
  `UI.RestylePixels` re-applies them keeping the colours shown (a hover, a selection). Without
  `UI.PIXEL` (TBC) the backdrop each always had: the button's 1-unit edge with 1-unit insets, the check
  box's 1-unit edge without insets (private `ControlBackdrop`). The edit box, slider and scroll frame
  were already `StylizeFrame`'d, so already pixel.
- **What is not a backdrop** goes through the new `UI.PixelLayout(region, fn)`: under `UI.PIXEL` it runs
  `fn(region)` now and registers it in the weak-keyed `UI.pixelLayouts`, which `UI.RestylePixels` runs
  again (its count includes them); off, it does nothing and the literal layout stands. Used for: the
  check box's tick and hover (inset `px(1)`), the separator's and titled pane's rule and shadow
  (`px(1)` high, the shadow offset `px(1)`), the movable frame's header overlapping the window edge by
  `px(1)`, and the selection's hover layer and bar (below).
- `UI.px` is unchanged: it returns `n` with no usable screen height (TBC), so nothing moves there.

### One selection language, under `UI.THEMED` only (U1)

`UI.CreateButtonGroup(buttons, onClick, onActive, onInactive, opts)` -- `opts` is new and optional.

- **Without the theme** (TBC): unchanged -- the active button takes its hover colour and loses its hover
  scripts; the others light to the hover colour under the pointer. No texture is built.
- **Under `UI.THEMED`**: each button gets two textures, made once (`b.selHover`, `b.selBar`). The active
  button is the `selected` fill (accent 0.28) with its **2-px accent bar** shown -- `opts.bar = "left"`
  (the nav's groups, `UI.CreateNavFrame` and `UI.CreateNavBox` pass it) or at the bottom (the default:
  view tabs and every other group -- Review's source buttons, the Overview's My spells / Whole book,
  the replay's speeds, Practice's group) -- inset `px(1)` inside the edge, `px(2)` thick, re-laid by
  `RestylePixels`. **Hover is the `hover` fill (accent 0.12) laid over whatever the button shows, the
  active one included**: every member keeps `OnEnter` / `OnLeave`, so hovering down the nav no longer
  lights a button like the selected one, and hovering the selected one still answers. `b.active` says
  which member is selected.
- The nav's view-button pool hides a reused button's selection parts when it resets it.

## Tests first

The assertions were written first and run against the parent's `UI/Style.lua` (`git show
7b77391:UI/Style.lua`, the new suites in place):

```
tools/themecheck.lua (forever)   28 ok, 3 failed
  T74: a kit button's edge and insets are UI.px(1), registered for restyling      FAIL - 1
  T74: the active nav group is selected + a 2-px left bar, never the hover fill   FAIL - fill 0.6, bar nil, tab nil, hover other nil / active false
  T74: UI.RestylePixels re-lays a kit button's edge and its selection bar         FAIL - edge 1, bar nil
tools/themecheck.lua (tbc)       8 ok, 0 failed   (the new guard: the old literals, by design green on the parent)
tools/navui.lua (tbc)            37 ok, 0 failed  (the new guard: TBC's active style is today's, by design green on the parent)
```

The two TBC assertions are the plan's "TBC did not move" guards: they pin the old colours and the old
selection behaviour, so they pass on the parent and must keep passing. After the change all five pass.

## Suites

| suite | before | after |
|---|---|---|
| `themecheck/forever` | 28 | 31 (+3: a button's edge and insets `UI.px(1)` and registered; the active nav group `selected` + a 2-px left bar, its view tab's at the bottom, the hover layer on the inactive and on the active button, never the 0.6 hover fill; `RestylePixels` re-lays the button's edge and its bar at a new screen height) |
| `themecheck/tbc` | 7 | 8 (+1: an `accent-hover`, a `red` and a plain button, a check box and an edit box paint the old literals, 1-unit edges -- the button's with insets, the check box's without --, nothing registered, no selection parts, the disabled label 0.4) |
| `navui/tbc` | 36 | 37 (+1: on TBC the active group and view tab carry the hover colour with no hover scripts, the others 0.115 lighting to it under the pointer, no bar) |
| every other suite | as `tools/data/expected-counts.json` | equal |

`make check`: 68 runs, all passed (the three notes are the counts above); `apicheck` 0 findings (57
files, 47 distinct globals); `textcheck` 0 findings (9 TOCs, 93 files); `luac -p UI/Style.lua`.

TBC byte-identity (principle 2): every suite's output was kept before the first edit and compared after.
`dashui/tbc` is identical; `navui/tbc` identical plus its one new line; `reviewui/tbc` identical apart
from the time-sliced search's evaluation counts and the `ms` timings (they differ between two runs of
the same code); `themecheck` adds its new lines and its token scan counts 127 reads instead of 99 (the
new `UI.Fill` / `UI.RGB` reads in `UI/Style.lua`, every one found in both flavours' tables). Every other
suite, both flavours, differs only in printed table addresses.

## Integrator lines

- **TOCs**: none (no new file).
- **`tools/data/expected-counts.json`**: `"navui/tbc": 37,` (was 36), `"themecheck/forever": 31,` (was
  28), `"themecheck/tbc": 8,` (was 7).
- **`docs/TOOLS.md`** section 1:
  - the `navui.lua` row ends: `Since **T74** (37): on TBC the active group and view tab are today's
    (hover colour, no hover scripts, no bar)`
  - the `themecheck.lua` row: `(T29, T69, T74; forever 31, tbc 8)`, and ends: `Since **T74**: a kit
    button's edge `UI.px(1)` and registered, the active nav group `selected` + a 2-px left bar (view
    tab: bottom) with the hover layer kept on it, `RestylePixels` re-laying the edge and the bar; under
    tbc the primitives' old literals and 1-unit edges`
- **`docs/DECISIONS.md`**: none needed -- TBC does not change (tokens equal the literals, `UI.px` is
  identity there, the selection style is gated on `UI.THEMED`). If the integrator wants the Forever
  look change on record, one line:

  > ### One selection language (T74, P30, 2026-10-01)
  > On Forever a button group's active member is the `selected` fill plus a 2-px accent bar (left on
  > the nav's groups, bottom elsewhere) and hover is the `hover` fill laid over any member, the active
  > one included (spec 4.3, mockup `.nb.on` / `.vt.on` / `.btn.act`). TBC keeps the active button in its
  > hover colour (decision 10 is wave C's).

- **`CLAUDE.md`**, appended to the `UI/Style.lua` row:
  **T74 (P30, review A20, U1, U3):** `UI.PALETTE` defined before the primitives, with their fills
  (`button`, `buttonHover`, `field`, `well`, `track`, `thumb`, `check`, `checkHover`, `accentFill`,
  `accentHover`, `close` / `closeHover`, `go` / `goHover`, `info`, `warn`, `clear` -- TBC's literals,
  which the theme leaves) and `UI.TEXT.dimmed` (0.4, a disabled control); `BUTTON_COLORS` names palette
  keys, read at creation (`UI.ButtonColors(name)`); a bordered button and the check box take the pixel
  backdrop and the registry under `UI.PIXEL`; `UI.PixelLayout(region, fn)` registers what is not a
  backdrop (rules, insets, bars, the header's overlap) for `UI.RestylePixels`; under `UI.THEMED` a
  button group's active member is `selected` + a 2-px accent bar (`opts.bar = "left"` on the nav's
  groups, bottom elsewhere) with the `hover` layer kept on every member. TBC unchanged
- **`docs/TESTING.md`** section 44, a check for the author on Forever:

  > **Selection and edges (P30).** `/st`: the selected group on the left is a dim accent fill with a
  > 2-px accent bar on its left edge; move the pointer down the other groups -- each gets a faint tint,
  > none looks selected; hover the selected group -- it tints too and keeps its bar. The view tabs on top
  > (Reports, Settings): the selected one has the bar along its bottom. At your 0.71 scale, button and
  > check-box borders are as crisp as the window's edge; change the window scale in Settings -> General
  > and they stay crisp. **TBC:** `/md` -- the nav and tabs look exactly as before.

## Deviations

- **The base commit.** The task text names `7b773917b8c0aa0d5bd1e98d1e5d1d6d3a0e3e7f`, which is not an
  object in this repository; `7b77391` (`7b77391f591c6c4bddb6d8ce387e47eb03148021`, "docs: wave 12 of the
  refactor plan (T73) -- integrator lines", the recent-commits head) is the commit it abbreviates, and
  the branch starts there.
- **`UI.TEXT.dimmed` instead of `disabled`.** A disabled control was 0.4 grey; TBC's `disabled` token is
  `555555` (0.33) and 4.1's `4D4D4D` (0.30), so reading `disabled` would have moved both lines. `dimmed`
  holds 0.4 and the theme (not this task's file) does not map it, so nothing moves; whether the kit's
  disabled controls take 4.1's `disabled` under the theme is for P34 with the other legacy tokens.
- **The new palette keys are not overwritten by the theme**, because `UI/Theme_Forever.lua` is not this
  task's file; they equal what Forever painted (the theme already wrote `close` / `closeHover` with the
  same values). Mapping `button` onto `nav`, `field` / `well` / `track` onto 4.1's fills belongs to P34,
  which owns the theme.
- **Layout offsets left alone**: the nav's 1-unit overlaps between group buttons and between view tabs,
  the resize grip and every size are P31's (U14, U26, U30, U31). The 0.777 rule colour is P34's.
- **A group button's tooltip under the theme**: `CreateButtonGroup` sets `OnEnter` / `OnLeave`, which
  replaces a tooltip hooked on the button, as `Highlight` already did on both lines; no group button
  passes tooltip lines today. P32 (one tooltip) owns the mechanism.
