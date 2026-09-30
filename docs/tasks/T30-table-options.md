# T30 -- table options: font, justify, pitch, zebra, full-width rows, the bar cell, the bar marker, in-place refresh

Status: **built** 2026-09-30 on branch `ui/T30` (base 9c2a26e); **reworked** the same day after
the review (see "Review" below), awaiting review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T30** | **Table options** in `Dashboard_Rows.lua`: `font`, per-column `justify`, `rowHeight` (read through `UI.Pitch` by the caller), `zebra`, `rowWidth` (full width), a `bar` cell type, `marker = "bar"`, `onUpdateCells` for in-place refresh. All nil gives today's table, gold included. | `UI/Dashboard_Rows.lua` | `tools/dashui.lua` (56 unchanged, +6 for the options, one asserting no `ffcc00` in a row built with `marker = "bar"`) | T29 |

Spec sections: 3.5 (the RANKS table: columns, justify, the per-mana bar, row states, the refresh
split), 4.1 (the `rowAlt` / `hover` / `selected` / `suggested` / `line` fills, the text tokens, gold
out of the Spell views), 4.2 (`FONT_NUM` for numbers; pitches through `UI.Pitch`), 4.3 (the table's
metrics: header 22 plus a 1-px `line` rule, rows 20, the row frame spanning the full table width).

## What was built

`UI/Dashboard_Rows.lua` (shared, both TOCs). `CreateTable(parent, width, opts)` takes these new
options; each falls back to today's value, so with all of them nil the table is byte for byte
today's, TBC's and the Forever Spellbook pane's alike, gold included:

| option | effect |
|---|---|
| `opts.font` | the font object name every cell is built from (as the `CreateFontString` template) instead of `GameFontHighlightSmall`; a column's own `col.font` wins (the Tag column's `FONT_SMALL`) |
| `col.justify` | `LEFT` (default) / `RIGHT` / `CENTER` per column; the header row's label follows its column |
| `opts.rowHeight` | the data rows' height and pitch (default 16); the caller passes `UI.Pitch(20)` |
| `opts.rowWidth` | a row's width: a number, or `true` for the table's whole width (default `width - 60`, today's); the spanning cell follows it |
| `opts.zebra` | even data rows get the `rowAlt` fill |
| `col.type = "bar"` | the per-mana cell: a `col.barWidth` (72) track (white 0.05, 8 tall, vertically centred), a `col.gap` (4), then the number in `row.cells[key]` over the rest of the column (40 of 116); the **header's** label spans the whole column (`col.x`, `col.w`: 116), so `Per mana` is right-aligned over the column, never cut to the number's 40 px; `row:SetBar(key, fraction, alpha)` scales the accent fill to `fraction` (clamped to 1), alpha 0.5 by default and 0.25 on a dominated row; a fraction that is not a number hides the bar and its track (a gap row) |
| `opts.marker = "bar"` | the suggested row is marked by the `suggested` fill (accent 0.10) and a 2-px accent bar at its left; a selected row (`r.selected`, or `api:SetSelected(id)`) takes the `selected` fill (0.28), with the bar still on when it is also the suggested one; hover takes the `hover` fill (0.12); the colour handed to `render` is `text` / `muted` (dominated) / `disabled` (not learned), **never gold**; the header labels are `muted` |
| `opts.onUpdateCells(row, r)` | `api:UpdateCells()` calls it for every data row shown, in place: nothing released, re-acquired or created; returns the count. This is 3.5's refresh split: the 2-s tick updates the To OOM cells and the `Now` value without a full render |

Also added for T38, which needs them and names no other file for them (see Deviations):
`opts.headerHeight` (default 18, today's header pitch; the caller passes `UI.Pitch(22)`; when set,
the header row's frame is that tall too, so its labels centre in the band and the rule lies on its
bottom edge -- unset, the header frame stays `rowHeight` tall as today),
`opts.headerRule` (`true` for the theme's `line`, or an `{r, g, b, a}`: a 1-px rule, `UI.px(1)`,
along the header's bottom edge), `opts.headerColor`, `opts.onClick(row, r, button)` (a data row's
click, for selecting the rank that drives the card), `opts.wideFont` (the spanning cell's font,
default `opts.font`) and `api:SetSelected(id)`. `api` also carries `headerHeight` and `rowWidth`.

Colours come from `UI.PALETTE` / `UI.TEXT` when the Forever theme wrote them (T29) and from
literals otherwise (`rowAlt` white 0.03, `hover` / `selected` / `suggested` from `UI.accent`,
`line` #2A2A2A; the text colours `|cffffffff`, `|cff8a8a8a`, `|cff555555`, `|cff888888`), so an option
works without the theme and none of it reaches TBC, which passes no options. The fill, the marker
and the bar textures are built only when an option asks for them: the all-nil table creates exactly
the frames, textures and font strings it always did.

Nothing reads a client value; no new adapter binding (`FOREVER_ONLY_NAMES` untouched).

## Tests first

The six new checks at the end of `tools/dashui.lua` (tbc; after every existing check, so none of
the 56 sees them). The stub records no `SetPoint`, `SetJustifyH`, font string template or texture
layer, so the section wraps those four methods on the stub's frame metatable itself, runs, and
puts them back: `tools/wowstub.lua` is untouched. Against the base's `UI/Dashboard_Rows.lua`:

```
T30 font and justify: the table's font, a column's own FAIL - GameFontHighlightSmall/LEFT
T30 rowHeight and rowWidth: 540 x 20 rows under a 22 header FAIL - 496 x 16 at -22, -38
T30 zebra: even rows take rowAlt, odd rows nothing FAIL - no fill texture
T30 bar cell: fraction x 72, the number after it, dominated 0.25 FAIL - no bar
T30 marker = bar: fill and a 2-px bar, no ffcc00 in the rows FAIL - |cffffcc00R1|r
T30 onUpdateCells: data rows refreshed in place  FAIL - n=nil calls=0 frames 915 -> 915

56 ok, 6 failed
```

After (the first build): `62 ok, 0 failed`; 63 after the review's check below. The first 56 lines of output are identical to the base's.

## Review (2026-09-30) and the rework

The reviewer rejected the first build (d8cc5bb) on one defect and one nit, both fixed in
`UI/Dashboard_Rows.lua`:

1. **The bar column's header label was squeezed into the number's cell.** `AcquireRow` placed a
   `type = "bar"` column's font string after the bar (`col.x + 72 + 4`, 40 px wide) on every pooled
   row, the header included, and the generic path turns word wrap off, so T38's `Per mana` would
   have been cut to `Per ...`. Now `PlaceBarCells(row, asHeader)` anchors a bar column's cell at
   `col.x` / `col.w` on the header row and after the bar on a data row; `Render` places each row
   per role (a pooled frame can be a header in one render and a data row in the next) and `Release`
   puts it back as a data row. Only rows with a bar column carry anything to place, so the all-nil
   table and the Spellbook pane are untouched.
2. **The header frame was `rowHeight` tall under `headerHeight`.** With `opts.headerHeight` set,
   `Render` now sizes the header row to it (22), so its labels centre in the band and the 1-px rule
   drawn at `y - headerH + px` lies on the frame's own bottom edge; `Release` gives the frame back
   its `rowHeight`. Without the option nothing changes (the Spellbook pane's header stays as it was).

Test first: one more check at the end of `tools/dashui.lua`, `T30 bar header: the label over the
whole column, the header 22 tall` -- the header's `pm` cell at x 60, width 116, `RIGHT`, the header
22 tall; then a second render, where the pool hands the header the first render's last data row and
the first header comes back as a data row: the new header again 60 / 116 / 22, the old one's cell
at 136 / 40 and 20 tall. Against d8cc5bb's `UI/Dashboard_Rows.lua`:

```
T30 bar header: the label over the whole column, the header 22 tall FAIL - header pm @136 w=40 h=20; again @136 w=40 h=20; old header as a row @136 w=40 h=20

62 ok, 1 failed
```

After: `63 ok, 0 failed`. So dashui is 56 -> **63** (the row's +6, plus this one).

## Full check

- The loop in `docs/TOOLS.md` §1, plus `themecheck` and `tabscheck`: every suite at its base count
  except `dashui` 56 -> **63** (the row's +6, and the review's +1). simcheck PASS, reccheck 54, replaycheck 80, replayui
  98, runcheck 78, reviewui 44, navui 25, dashui 63, regencheck 27, simwindow 8, solvercheck 77,
  timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7, probecheck 86, forevercheck 13,
  modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 11,
  reviewforever 10, coachforever 18, practiceforever 20, bindscheck 6, parsecheck 12, bookcheck 17,
  tipcheck 27, clockcheck 17, spellsui 17, measurecheck 30, releasecheck 13, themecheck 23,
  tabscheck 24; adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1, consolecheck 14 / 1
  (forever / tbc).
- Every suite's **full output** diffed against the base: identical apart from table and function
  addresses, wall-clock milliseconds and the frame-sliced searches' evaluation / frame counts
  (sliced on `debugprofilestop`), and dashui's seven new lines and its total. After the rework,
  spellsui, navui and practiceui are identical to d8cc5bb's, and dashui differs only in the new
  check's line and its total.
- `python3 tools/apicheck.py`: 0 findings (46 files). `--selftest`: 10 of 10.
  `python3 tools/refcheck.py --selftest`: ok.
- `luac -p` on `UI/Dashboard_Rows.lua` and `tools/dashui.lua`: ok.

## Deviations

- **Options the row does not name**: `headerHeight`, `headerRule`, `headerColor`, `onClick`,
  `wideFont` and `api:SetSelected(id)`. 3.5 and 4.3 give the RANKS table a 22-tall header with a
  1-px `line` rule, a `selected` row state that a click sets, and `muted` table headers, and T38
  (the only consumer) names only `UI/SpellsPane_Forever.lua`, `Spells/Book.lua` and
  `Client/API_Forever.lua`, so the table has to offer them. All are nil-safe and untested beyond
  what the six checks cover (`SetSelected` is exercised by the marker check: the selected row reads
  0.28).
- The header's colour turns `muted` only with `marker = "bar"` (or an explicit `headerColor`), so a
  table with other options but no marker keeps today's `|cff888888` header.
- `tools/dashui.lua` wraps four stub methods locally instead of teaching `tools/wowstub.lua` to
  record them, to keep this wave's parallel branches off the shared stub.
- `docs/TOOLS.md` still says `dashui.lua` without a count; the suite list is T44's.
- `dashui` is +7 rather than the row's +6: the seventh check is the review's (the bar column's
  header label and the header's height), added with the fix.
