# F3 -- Whole book empty until a scroll

Status: **built** 2026-10-02 on branch `fix/F3`, base `2ffece3` (0.16.6). Waiting for the
integrator. Forever only: TBC's Spells group has no Overview with two tables (T84 deviation),
so nothing changes there.

## The symptom (the author, 0.16.6 Forever)

> "whole book" is empty when opened, fixed once start scrolling (really like the idea)

Spells -> Overview -> [Whole book]: the table is blank; one wheel notch over it and every row
is there.

## The cause

`SpellsPane:RenderOverview` (`UI/SpellsPane_Forever.lua:1517` on `2ffece3`,
`pane.scroll:SetContentHeight(y)`) resizes the Overview's scroll child **while the scroll frame
is on screen**: My spells is a short table (268 px in the suite's book, under the 528-px
window), Whole book a long one (674 px there, hundreds of rows on a real character). The client
draws a ScrollFrame's scroll child through the rect it last took from that child -- at the
layout pass when the pane appeared, and again on `UpdateScrollChildRect` or
`SetVerticalScroll`. Nothing in the pane ever made either call after a render. The only code
that did was the mouse wheel: `UI/Style.lua:2999-3008` (`scrollFrame:VerticalScroll`, reached
from its `OnMouseWheel`) calls `SetVerticalScroll`, and that is exactly the author's "fixed once
start scrolling". Opening Overview straight into Whole book (the remembered mode) draws, because
the size changed before the pane's first layout pass; switching to it from My spells does not.

The rows themselves were always rendered: `pane.lastRows`, the row frames and the table frame
were right on the parent (every T39 item passed). The client half -- which rect a ScrollFrame
draws through -- cannot be run offline; the suite models it (below), and the in-game check in
"To verify" is what confirms it.

Not the cause: `UI/Dashboard_Rows.lua`'s scrolled window (`opts.scroll`, `SetVisibleRows`,
`Reveal`) -- Overview's tables are created without `opts.scroll` and paint every row.

## The fix (`UI/SpellsPane_Forever.lua` only)

- `RefreshScrollChild(scroll, top)`, a local beside `OverviewSignature`: `UpdateScrollChildRect`
  (when the frame has it), then `SetVerticalScroll` with the offset set anew -- 0 when `top`,
  else the current offset clamped to the new range (`GetVerticalScrollRange`, the kit's own).
  Every method guarded; a nil answer reads 0.
- `RenderOverview` ends with `RefreshScrollChild(pane.scroll, newTable)` right after
  `SetContentHeight`; `newTable` is `pane.mode ~= mode` (the first render and every switch
  between My spells and Whole book), so a newly shown table starts at its top. A re-render of
  the same table (the 2-s tick when the book, the list or the pitch changed, + Add) keeps the
  reader's place.
- No timer, no OnUpdate: the same call, in the same frame as the render.

`UI/Style.lua`'s `CreateScrollFrame` was not edited (shared with TBC and outside this task's
files); the family view (`SpellsPane:LayoutBlocks`) has the same pattern but no report -- see
deviations in the hand-off.

## The test (`tools/spellsui.lua`, one item)

`F3 Whole book draws its rows when opened, no scroll needed; back and forth keeps them`. The
stub has no ScrollFrame, so the item models the client's half on the Overview's own frame
(instance methods, removed again at the end): the frame is 528 tall; the child rect is taken
when the pane appeared and again on `UpdateScrollChildRect` / `SetVerticalScroll`; a row is
drawn when it is in the window and inside the rect last taken; the wheel is counted and never
sent. Steps: [Whole book] from My spells, [My spells], [Whole book] again, scroll Whole book
down (146 px, its whole range), [My spells], [Whole book] -- each must draw every row in its
window, at offset 0, with no wheel event.

- Parent `2ffece3`: **FAIL** -- `book 12/26 at 0, mine 9/9 at 0, book again 12/26 at 0, mine
  after a scroll 3/3 at 146, book at its top 25/25 at 146` (12 of 26 rows: only those inside
  My spells' 268 px).
- Here: **ok** -- `book 26/26 at 0, mine 9/9 at 0, book again 26/26 at 0, mine after a scroll
  9/9 at 0, book at its top 26/26 at 0 wheel=0 scrolled=146 mineH=268 bookH=674`.

## Counts

| suite | before (`2ffece3`) | after |
|---|---|---|
| `spellsui/forever` | 52 ok | 53 ok |

Every other suite unchanged; `make check` green with `spellsui/forever` at 53 in
`tools/data/expected-counts.json` (integrator's line), `python3 tools/apicheck.py` 0 findings,
`python3 tools/textcheck.py` green.

## To verify (in game, Forever)

`/st` -> Spells -> Overview -> [My spells], then [Whole book]: the rows are there at once,
from the top, with no wheel. Scroll Whole book down, [My spells], [Whole book]: back at its top,
full. Wait 2 s on a scrolled Whole book (the tick): it stays where it was.
