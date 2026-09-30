# T31 -- the kit: rail, sheet and lists

Status: **built** 2026-09-30 on branch `ui/T31` (base 9c2a26e), for review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T31** | **Kit: rail, sheet and lists.** `UI.CreateRail(parent, w, opts)` (rows, selection bar, hover `^ v x`, drag reorder with the insertion line, right-click menu, new dot, footer slot); nav `layout = "rail"`, **the content frame re-anchored per group in `nav:Select`** (-8 for a rail group, -32 otherwise), **`nav:SetViews` skipping `BuildViews` for a rail group**, `BuildViews` on a button pool; `UI.CreateSheet(pane, maskRegion, ...)` and `UI.CreateMask(region)`; dropdown lists read `UI.LIST_STRATA`, the tree dropdown's second list at the first's level +10, and `UI.OnPopup(list, shown)` called when set. | `UI/Style.lua` (additive) | `tools/navui.lua` (25 unchanged, +10: a rail group has no top row and its content starts at -8; switching back to a view-row group puts it at -32; `SetViews` on a rail group creates no button; calling `SetViews` five times on Reports leaves the same number of button frames; rail rows are views; reorder fires once; a mask swallows clicks on its region and not outside it; a list takes `UI.LIST_STRATA`; the second list is above the first) | T29 |

Spec sections it cites: 3.1 (where the rail lives, the per-group content anchor, rail rows as nav
views, `SetViews` on a rail group, the button pool), 3.2 (the rail's rows, hover controls, drag,
menu, new dot, footer), 6.2 (the lists' strata, `UI.LIST_STRATA`, the tree's second list at +10),
6.4 (sheets and masks), 6.5 (`UI.OnPopup`), 7 (kit additions and kit behaviour, TBC effect none).
The theme (T29) already sets `UI.LIST_STRATA = "FULLSCREEN_DIALOG"` on Forever.

## What was built

All in `UI/Style.lua`, additive; nothing on TBC declares a rail group, builds a rail or a sheet,
or sets `UI.LIST_STRATA` / `UI.OnPopup`.

**Nav (`UI.CreateNavFrame`).**

- `AnchorContent(isRail)`: the content frame's TOPLEFT is `-NAV_PAD` (-8) under a rail group,
  `-(NAV_TOP + NAV_PAD)` (-32) otherwise, re-anchored in `nav:Select` whenever the group changes
  (and once at creation, at -32 as before).
- A group with `layout = "rail"` draws no view row. On its first selection (or the first
  `nav:Rail` / `nav:RailView` call) the nav builds a holder over the content: the rail
  (`UI.CreateRail`, 172 wide unless `group.rail.width`, options from `group.rail`) down the left
  edge, and the view area right of it at +8. That group's panes are built into the view area
  (`onCreate` is handed it as `content`). The rail's rows are the group's views; a click selects
  through `nav:Select`, so `db.uiPath` and `MD:SelectView("spells", "fam:Rejuvenation")` work,
  and the selection is marked on the rail (`nav.highlightView` is the rail's `Select`).
  `nav:Rail(groupID)`, `nav:RailView(groupID)` expose them (nil for a view-row group).
- `nav:SetViews` on a rail group only hands the rail its new rows (and re-selects); it never runs
  `BuildViews`.
- `BuildViews` takes its buttons from `nav.viewButtonPool`, reusing hidden ones by index (text,
  size, anchors, colours and hover scripts put back as `CreateButton` left them). `nav.viewButtons`
  is still the list of the buttons in use, so the 25 old assertions read it unchanged.

**`UI.CreateRail(parent, w, opts)`** (3.2). `rail.frame` in the `pane` fill with the black edge;
`opts.title` (11 px, `muted`, 18 tall); rows 20 tall (`opts.rowHeight`, which a Forever pane passes
through `UI.Pitch`) overlapping by 1 px; per row a 16-px icon at x=4 in a 1-px black frame
(texcoord 0.08-0.92), the name at x=24 (x=8 for a `fixed` row such as Overview), truncated before
whatever sits at the right, the tag at -6 in `FONT_NUM_SMALL` / `muted`, the 6x6 accent new dot left
of it, a `stale` row's name in `disabled` with no tag and the tooltip "not in your spellbook"; a
1-px `line` rule after the fixed rows; `opts.empty` shown when no movable row is listed. Selected:
the `selected` fill and a 2-px accent bar; hovered: the `hover` fill and, on a movable row, the
three 14x14 controls `^` `v` `x` (`x` red-hover) in place of the tag and dot. Drag reorder: the row
lifts to alpha 0.5 on `OnDragStart`, a 2-px accent insertion line follows the cursor
(`GetCursorPosition`, the toolkit), and `OnDragStop` reports **once** (`opts.onMove(id, to)`,
`to` the new place among the movable rows, which is `Tabs:Move`'s argument) -- a second
`OnDragStop` (Cell's note: the client can fire it twice) and a drag ended by the rail hiding move
nothing. Right-click on a movable row opens the kit menu (Move up / Move down / Remove from list)
in the lists' strata, telling `UI.OnPopup`. Drops: `OnReceiveDrag` on a row reports
`opts.onDrop(at)` (before that row; a fixed row means 1), on the rail's own ground `#rows + 1`; a
click drops instead of selecting while `opts.canDrop()` says so. **The kit never reads or clears
the cursor** (3.2): the caller (T36) does. `rail:Footer()` is the slot pinned at the bottom
(`opts.footerHeight`) for T36's `[ + Add ]` and Undo line. `rail:SetRows`, `Select`, `Rows`,
`OpenMenu`, `SetRowHeight` (for T36's re-render on a font-offset change).

**`UI.CreateMask(region, level)` / `UI.CreateSheet(pane, maskRegion, w, h, title)`** (6.4). The mask
covers `region` (`SetAllPoints`), at the given level (default the region's +30), in the `mask`
colour, mouse and wheel enabled so it swallows both; hidden until its sheet shows. The sheet is a
child of the pane at the pane's level +50, its mask over `maskRegion` (default the pane) at the
pane's +30; the `pane` fill with a 1-px accent edge, a 20-px title row (`nav` fill, 1-px black
line under it, the title in the 13-px accent font), `sheet:Body()` under it, centred on the mask
region until the caller anchors it (the picker: the rail's TOPRIGHT +4). Showing one sheet hides
the other (`UI.openSheet`): only one is open at a time.

**Dropdown lists** (6.2, 6.5). `UI.CreateDropdown`'s list and `UI.CreateTreeDropdown`'s first list
take `UI.LIST_STRATA or "DIALOG"`; the tree's second list stays `FULLSCREEN_DIALOG` and is set to
the first list's level +10 at creation and each time it opens, and it now hides with the first. Each
list calls `UI.OnPopup(list, true / false)` from its `OnShow` / `OnHide` when the hook is set (the
scripts are set after the list's first `Hide`, so building a dropdown tells nobody).

## Tests first

`tools/navui.lua` (tbc, as before): the 25 assertions untouched, ten added at the end. The stub
keeps no geometry, so the suite instruments its own frames for itself at the top (points,
`SetAllPoints`, strata, frame levels with a child one above its parent, mouse) -- in the suite, not
in `tools/wowstub.lua`, so no other suite sees a change. The mask assertions hit-test by rectangle:
the topmost (strata, then level) visible, mouse-enabled frame under a point.

Against the base (9c2a26e): **25 ok, 10 failed**:

```
a rail group: no top row, content at -8        FAIL - 4 view buttons, 4 shown, top -32
a view-row group puts it back at -32           FAIL - top -32 -> -32, 2 buttons
SetViews on a rail group creates no button     FAIL - 10 -> 15
five SetViews on Reports: same button frames   FAIL - 20 -> 35
rail rows are views                            FAIL - 0 rows, click -> fam:Healing Touch
reorder fires once                             FAIL -
a mask swallows clicks on its region           FAIL
and not outside it                             FAIL
a list takes UI.LIST_STRATA                    FAIL - DIALOG / DIALOG, 0 popup calls
the second list is above the first             FAIL - DIALOG 1 / FULLSCREEN_DIALOG 1
```

After: **35 ok, 0 failed**:

```
a rail group: no top row, content at -8        ok - 0 view buttons, 0 shown, top -8
a view-row group puts it back at -32           ok - top -8 -> -32, 2 buttons
SetViews on a rail group creates no button     ok - 2 -> 2
five SetViews on Reports: same button frames   ok - 3 -> 3
rail rows are views                            ok - 5 rows, click -> fam:Rejuvenation
reorder fires once                             ok - fam:Wrath>2
a mask swallows clicks on its region           ok
and not outside it                             ok
a list takes UI.LIST_STRATA                    ok - DIALOG / FULLSCREEN_DIALOG, 2 popup calls
the second list is above the first             ok - FULLSCREEN_DIALOG 1 / FULLSCREEN_DIALOG 11
```

The paths the ten do not reach (hover controls and their clicks, the menu and its three items, no
menu or controls on a fixed row, drops on a row, on a fixed row, on the ground and by click, a drag
past the end, a drag onto itself, a drag ended by hiding, the empty rail, a stale row's tooltip,
one sheet at a time, `SetRowHeight`) were driven by a scratch script under both flavours (tbc with
`UI/Style.lua` alone, forever with the theme loaded): no raise, the expected callbacks.

## Full check

The loop in `docs/TOOLS.md` section 1 plus `themecheck` and `tabscheck`, on this branch, with every
suite's full output compared with the same loop on the base: every count and last line unchanged
except **navui 25 -> 35** -- simcheck PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78,
reviewui 44, dashui 56, regencheck 27, simwindow 8, solvercheck 77, timeline 27, spelltip 48,
practice 74, practiceui 49, migrate 7, probecheck 86, forevercheck 13, modulecheck 14, kitcheck 7,
recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 11, reviewforever 10,
coachforever 18, practiceforever 20, bindscheck 6, parsecheck 12, bookcheck 17, tipcheck 27,
clockcheck 17, spellsui 17, measurecheck 30, themecheck 23, tabscheck 24, releasecheck 13,
adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1, consolecheck 14 / 1; `apicheck`: 8 Forever
TOCs, 46 files, 46 distinct globals, **0 findings**; `apicheck --selftest` 10 of 10;
`refcheck --selftest` ok. `luac -p` on `UI/Style.lua` and `tools/navui.lua`: ok.

The other lines that differ between the two runs are noise that differs between any two runs
(table addresses, milliseconds, and the search's evaluation and frame counts, which are sliced on
`debugprofilestop()`), with one exception: `modulecheck`'s informational walk line reads **73**
strings under the Forever window instead of 74 (not an assertion). That is the pool: the walk
opens Spells, then Settings, and Settings' view row now reuses the Spells button instead of
leaving a hidden one behind.

The TBC line: TBC declares no rail group and never sets `UI.LIST_STRATA` or `UI.OnPopup`, so its
content stays at -32, its lists in `DIALOG`, and the pool draws the same buttons; every TBC suite's
count and output are as before (navui's first 25 lines identical).

## Deviations

- **The instrumentation is in the suite, not the stub.** The row allows touching
  `tools/wowstub.lua` as far as the row needs; recording geometry in the suite itself needed no
  stub change at all, so parallel tasks' stub edits (T32's window checks will want points and
  strata too) cannot conflict with this one.
- **"switching back to a view-row group puts it at -32"** asserts the transition (-8, then -32):
  the old code is at -32 always, and an assertion that passes on the old code would not be a test.
- **The ten** are the row's nine items with "a mask swallows clicks on its region and not outside
  it" as two assertions; `UI.OnPopup` is checked inside "a list takes `UI.LIST_STRATA`" (one call
  on open, one on close).
- **The nav builds the rail and hands the area right of it to `onCreate`** (and adds `nav:Rail` /
  `nav:RailView`): 3.1 says the rail "sits at the content's left edge" and every rail row is a
  nav view, but not whose frame a pane is built in; building the rail's panes into the area right
  of it keeps T36's panes from having to dodge the rail, and gives the picker's mask its region.
- **Row pitch.** Rows are 20 tall and overlap by 1 px (3.2, 4.3), so their tops are
  `rowHeight - 1` apart: 19 at offset 0, 21 at +2 with `rowHeight = UI.Pitch(20)`. T36's test
  line "at offset +2 the rail rows are 22 apart" holds for the row height, not the top-to-top
  pitch; T36 should measure the height (or say which it means).
- **Added beyond the row, for T36:** `rail:SetRowHeight(h)` (the re-render when the font offset
  changes), `opts.canDrop` (a click that drops, 3.2's `OnMouseUp`), the stale row's default tooltip
  "not in your spellbook". The `[ + Add ]` button, the `Wrath removed [Undo]` line, the empty-rail
  wording and the picker itself are T36's; the kit gives the footer slot and the `empty` option.
- **The rail's menu is its own small popup list**, not a `UI.CreateDropdown` (which is a button
  with a list under it); it is in `UI.LIST_STRATA` and tells `UI.OnPopup`, as the dropdowns do.
- **The tree dropdown's second list now hides with the first** (a hook on the first list's
  `OnHide`). Once T33 closes a list through the ESC stack by hiding it, the second list must go
  too; on TBC every path that hid the first list already hid the second (`dd:Close`), so nothing
  changes there.
- **No rail scrolling**: the spec gives none. At 560 high a rail holds about 24 rows above a
  48-px footer; rows past that run under the footer.
- **Sheets carry no ESC entry and no combat refusal**: those are T33's (the stack) and T36 / T40's
  (the picker and the bindings sheet refuse to open in combat).
- `docs/TOOLS.md` section 1's navui line is not updated: T44 writes the docs for the wave.
