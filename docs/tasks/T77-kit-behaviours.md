# T77 -- Kit behaviours: lists, the rail, font events (plan P33)

Status: **built** 2026-10-01 on branch `plan/P33` (base `7c32bf5`), wave 16 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. No TOC line is needed: every file this task
touches is already listed where it has to be (`UI/ContextMenu.lua`, which the rail's menu now uses,
is on both main TOCs right after the kit since T71 / T76).

## The task (docs/PLAN-refactor-ux.md section 5, P33)

Review items (`docs/review/2026-09-30-project-review.md`): **U12** (dropdown lists open off-screen,
sub-lists always to the right; the chevrons are the letters `v` and `>`), **U8** (the rail's hover
controls are 14-px targets, the red `x` 2 px from `v`, they hide the rank, and a row has no tooltip,
so `R1` is never explained), **U16** (the rail has no overflow), **A31** (events): extension by
wrapping -- SpellsPane wrapped `UI.ApplyFonts`, `UI/Windows_Forever.lua` assigned `UI.OnPopup`;
`FONTS_CHANGED` and `UI_POPUP` events instead.

Mockup: `docs/mockups/refactor-ux.html` **M4**, approved 2026-09-30 with **layout B** (section 7.1:
"rail hover is layout B (one `x`, Move up / Move down / Remove in a right-click menu, drag still
reorders)"): the `R1` tag kept, one 18-px `x`; the right-click menu "the same ContextMenu Review
uses", titled with the spell's name; any row hovered for half a second shows `Suggested  Rank 1 of
2 known`, `Per mana  1.90` and `Drag to reorder. Right-click for more.`, a stale reading adds `Read
before combat: the spell text was hidden during the fight.`; 25 spells scroll between Overview and
the fixed footer (a 5-px bar, an accent thumb, the wheel 3 rows a notch, a row selected off-screen
scrolled into view); a list near the bottom of the screen opens upward, a sub-list near the right
edge opens to the left; the chevrons 8 x 8 textures pointing the way the list opens, the letters
when the texture is missing; "Both flips apply on TBC too".

## What was built

| File | Change |
|---|---|
| `UI/Style.lua` | **Kit events.** `UI.Popup(list, shown)` fires `UI_POPUP` through the kernel's `MD:Fire`; `UI.OnPopup` is the same function under its old name (UI/ContextMenu.lua announces through it), nobody assigns it any more; the kit's own lists (`WatchPopup`) fire through it. `FONTS_CHANGED (offset)`: the theme's `UI.ApplyFonts` (UI/Theme_Forever.lua) is kept as the sizer when it is installed and read back through the kit's own function, which fires the event once the fonts are re-sized and answers the sizer's answer (a metatable on `MD.UI` for that one key -- Deviation 1); with no sizer (TBC) `UI.ApplyFonts` is nil as before. **Lists at the screen's edge** (both lines): `UI.ListSide(button, list)` -- `"up"` when the list under the button would leave the screen's bottom and fits above, else `"down"`; `UI.SubListSide(row, list, gap)` -- `"left"` when beside the row it would leave the right edge and fits on the left, else `"right"`; rectangles in screen pixels (units times effective scale), anything unreadable keeps the old side. `CreateDropdown` / `CreateTreeDropdown` place the list on every open (`dd:PlaceList()`, `dd.side`: `BOTTOMLEFT` at the button's `TOPLEFT` + 1 when up), the tree's second list `TOPRIGHT` at the row's `TOPLEFT` - 2 when it flips (`dd.subSide`). **Chevrons** (`UI.CreateChevron(parent, dir)`): under `UI.THEMED` an 8 x 8 texture from `Interface\Buttons\SquareButtonTextures` at the game's own arrow coordinates (`SquareButton_SetIcon`'s), pointing down / up (the dropdown after its list opened upward) / right / left (a tree parent row after its list flipped); the letter (`v ^ > <`) when the theme is off or `SetTexture` answers false. TBC keeps the letter `v` and the grey `>` in the parent row's text, unchanged. **The rail** (`UI.CreateRail`, mockup M4 layout B): on hover a movable row keeps its tag and shows **one 18-px `x`** (`^` / `v` removed); the right-click menu is `UI.CreateContextMenu`'s (built on first use, titled with the row's name in capitals, Move up / Move down -- each disabled at its end -- / Remove); a row hovered `UI.RAIL_TIP_DELAY` (0.5 s, the row's own OnUpdate) shows the kit tooltip: the name, the caller's `tooltip` (a string or a list of line-model lines), and for a movable row `UI.RAIL_HINT` (`Drag to reorder. Right-click for more.`) in `muted`; **the movable rows scroll** when they outgrow the space between the fixed rows and the footer -- whole rows, the ones out of view hidden (`row.clipped`), the fixed rows, the rule and the footer never move, a 5-px bar (the `track` token, an accent thumb at 0.8) at the right with the rows inset to clear it, the wheel 3 rows a notch (`rail:Scroll`, `rail:ScrollTo`, clamped), `rail:Select(id)` scrolls the row into view (`rail:ScrollIntoView`), the layout redone on `OnSizeChanged`; a rail not laid out yet (too short for one row) shows every row as before; a drag counts slots from the scroll offset. `ShowTooltips`' TBC path takes a line table's text (the rail's hint; no TBC caller passes one). |
| `UI/SpellsPane_Forever.lua` | Subscribes to `FONTS_CHANGED` (`SpellsPane:FontsChanged()`) instead of wrapping `UI.ApplyFonts`. Each listed family's rail row carries its tooltip lines (`RailTip`): `Suggested  Rank N of M known` (M the known ranks, the header's count), `Per mana  N.NN` (`MD.Words.PerMana(e, "cell")`), and for a stale reading the muted `Read before combat: the spell text was hidden during the fight.`; a stale row (not in the book) keeps `not in your spellbook`. |
| `UI/Windows_Forever.lua` | `MD:RegisterCallback("UI_POPUP", ...)` instead of assigning `UI.OnPopup`: the same push / remove on the ESC stack, a nil list ignored. |
| `tools/navui.lua` | Loads `UI/ContextMenu.lua` after the kit (the rail's menu). The T31 popup check listens to `UI_POPUP` instead of assigning the hook. Six new checks, each under `pcall` with the geometry and the theme switched back whatever happens (below). |
| `tools/spellsui.lua` | Two new checks (below). |
| `tools/wincheck.lua` | One new check (below). |

## The new checks

- `navui` (tbc): **a list near the bottom of the screen opens upward** (`S.Geometry`; a dropdown at
  y 40 opens `BOTTOMLEFT`/`TOPLEFT`, one at y 700 opens down; no theme: the letter `v` stays);
  **a sub-list near the right edge opens to the left** (the row 150 px from the right edge:
  `TOPRIGHT`/`TOPLEFT`; at x 200: right; TBC's grey `>` in the text); **under the theme the
  chevrons are 8x8 textures pointing the way the list opens** (down, up after the flip, a parent
  row's right, none on a leaf row); **25 rail rows scroll above a fixed footer** (400 tall with a
  48-px footer: 16 rows shown, the 17th clipped, the last shown row clear of the footer, the bar
  up; the wheel moves 3; Overview stays at 18; `Select` of row 25 scrolls to it; a long wheel back
  clamps at 0; the footer's anchor untouched); **a hovered rail row keeps its tag and shows one
  18-px x; right-click: Move up / Move down / Remove** (no `^`/`v`, the menu titled `SPELL 2`, Move
  down reports one move `fam:2>3` and closes the menu, Move up disabled on the first row); **a rail
  row's tooltip after half a second** (nothing at 0.3 s; at 0.6 s the name, the pairs, the hint
  last; hidden on leave).
- `spellsui` (forever): **FONTS_CHANGED alone re-pitches the rail and the spell view** (the offset
  set to 2 and the event fired by hand: rows 22 tall, 21 apart, the header 50; back to 20);
  **a rail row's tooltip** on the real pane (Rejuvenation: `Suggested` / `Rank 2 of 2 known`,
  `Per mana` with the book's value, the hint; not before 0.5 s).
- `wincheck` (forever): **the manager hears UI_POPUP (no hook assigned)** -- `UI.OnPopup ==
  UI.Popup`; a frame announced shown is on top of the stack and leaves it when announced hidden; a
  tree dropdown's list and a right-click menu (UI/ContextMenu.lua) join the stack, one ESC closes
  the menu, the next the list, the main window staying up.

## Failing first

The parent `7c32bf5` (extracted with `git archive`) with the three suites dropped in:

```
=== navui (tbc)                   39 ok, 7 failed
  FAIL a list takes UI.LIST_STRATA - DIALOG / FULLSCREEN_DIALOG, 0 popup calls
  FAIL T77: a list near the bottom of the screen opens upward - low TOPLEFT/BOTTOMLEFT, high TOPLEFT/BOTTOMLEFT, arrow "nil"
  FAIL T77: a sub-list near the right edge opens to the left - near the edge TOPLEFT/TOPRIGHT, inside TOPLEFT/TOPRIGHT, text "Healing Touch   |cff777777>|r"
  FAIL T77: under the theme the chevrons are 8x8 textures pointing the way the list opens - raised: tools/navui.lua:498: attempt to index field 'arrow' (a nil value)
  FAIL T77: 25 rail rows scroll above a fixed footer; the wheel moves 3; a selected row is scrolled to - shown 25 (1..25), after the wheel from 1, selected to 25, back to 1, bar false
  FAIL T77: a hovered rail row keeps its tag and shows one 18-px x; right-click: Move up / Move down / Remove - raised: UI/Style.lua:279: attempt to concatenate field '?' (a table value)
  FAIL T77: a rail row's tooltip after half a second: its name, its lines, the drag hint - raised: UI/Style.lua:279: attempt to concatenate field '?' (a table value)
=== spellsui (forever)            48 ok, 2 failed
  FAIL T77: FONTS_CHANGED alone re-pitches the rail and the spell view - height=20 apart=19 header=48 back=20
  FAIL T77: a rail row's tooltip: Suggested  Rank N of M known, Per mana, the drag hint - early=false shown=false first=nil want=Rank 2 of 2 known suggested=false permana=false hint=false
=== wincheck (forever)            65 ok, 1 failed
  FAIL T77: the manager hears UI_POPUP (no hook assigned); a tree's list and the menu each close on one ESC - up true hookFree false pushed false removed true tree true menu true escMenu true escTree true
```

(The first navui line is the T31 check rewritten to listen to the event: on the parent the kit
announced only through an assigned hook.)

Mutations, on the branch (scratch copy):
- `rail:Select` without `ScrollIntoView`: `navui` 45 ok, 1 failed (`selected to 19`).
- `UI.SubListSide` never answering `"left"`: `navui` 45 ok, 1 failed (`near the edge TOPLEFT/TOPRIGHT`).

## Suite counts

Before: `7c32bf5` (`git archive`), `tools/check.sh` 68 runs, all passed, 63 counted against 63
expected. After: this branch, 68 runs, all passed, 63 counted (the three NOTEs are the new counts);
apicheck 0 findings (8 Forever TOCs, 57 files, 47 globals), textcheck 0 findings (9 TOCs, 94 files).
`luac -p` passes on `UI/Style.lua`, `UI/SpellsPane_Forever.lua`, `UI/Windows_Forever.lua`.

| Run | Before | After |
|---|---|---|
| `navui/tbc` | 40 | **46** |
| `spellsui/forever` | 48 | **50** |
| `wincheck/forever` | 65 | **66** |
| every other run | | equal |

Outputs compared with the parent's, run by run (`tools/.lua/check/*.out`): apart from table and
function addresses, millisecond timings and the time-sliced searches' evaluation counts (`reccheck`,
`reviewui`, `runcheck`, `replayui` -- they move run to run), the only differences are the three
suites above and `modulecheck`'s informational walk (`83 strings reached under the window` -> `74`:
each rail row builds one control instead of three, and the rail's menu is built on first use).
**Every TBC UI suite's output is otherwise identical** -- `dashui` byte for byte, `navui`'s 40 old
lines (the popup line's detail included), `reviewui`, `replayui`, `practiceui`, `spelltip`,
`consolecheck`, `simwindow`, `ttocheck`, `importcheck`: TBC changes only by the flips, which no TBC
suite places near a screen edge.

## Integrator lines

**TOCs**: none.

**`tools/data/expected-counts.json`**: `"navui/tbc": 46,` (was 40), `"spellsui/forever": 50,` (was
48), `"wincheck/forever": 66,` (was 65). Every other count unchanged.

**`CLAUDE.md`**, the files table:
- `UI/Style.lua` row, append: ` **T77 (P33, review U8 / U12 / U16 / A31):** the kit's events -- `UI.Popup(list, shown)` fires `UI_POPUP` (`UI.OnPopup` its alias, never assigned), and `UI.ApplyFonts` (the theme's sizer, kept by a metatable on `MD.UI` for that key) fires `FONTS_CHANGED (offset)` once the fonts are re-sized; lists at the screen's edge on both lines (`UI.ListSide`: a dropdown's list opens upward when below would leave the screen; `UI.SubListSide`: a tree's second list opens left at the right edge); `UI.CreateChevron` -- under `UI.THEMED` 8 x 8 textures pointing the way the list opens, the letters otherwise (TBC's `v` and `>` unchanged); the rail (mockup M4 layout B): one 18-px `x` on hover with the tag kept, the right-click menu `UI/ContextMenu.lua`'s (Move up / Move down / Remove), a row tooltip after 0.5 s (its lines plus `Drag to reorder. Right-click for more.`), the movable rows scrolling above the fixed footer (5-px bar, wheel 3 rows, a selected row scrolled into view)`
- `UI/SpellsPane_Forever.lua` row, append: ` **T77 (P33):** subscribes to `FONTS_CHANGED` (no wrap of `UI.ApplyFonts`); each rail row's tooltip: `Suggested  Rank N of M known`, `Per mana`, a stale reading's `Read before combat ...``
- `UI/Windows_Forever.lua` row, append: ` **T77 (P33, review A31):** the dropdown lists and menus join the ESC stack through the kit's `UI_POPUP` event (it assigned `UI.OnPopup` before)`
- In the `UI/Style.lua` row's T31 sentence, `` `UI.OnPopup(list, shown)` when set`` becomes `` `UI_POPUP` (T77)``.

**`docs/TOOLS.md`** section 1:
- `navui.lua` row, append: ` Since **T77** (46): loads `UI/ContextMenu.lua`; the popup check listens to `UI_POPUP`; under `S.Geometry` a list near the bottom opens upward and a sub-list near the right edge opens left (TBC's letter kept), the themed chevrons, 25 rail rows scrolling above the fixed footer (wheel, select-into-view, clamp), the one-x hover and the right-click menu, the row tooltip after half a second`
- `spellsui.lua` row, append: ` Since **T77** (50): `FONTS_CHANGED` alone re-pitches the rail and the view; a rail row's tooltip (`Suggested  Rank N of M known`, `Per mana`, the hint)`
- `wincheck.lua` row, append: ` Since **T77** (66): the manager hears `UI_POPUP` with no hook assigned; a tree's list and a right-click menu each close on one ESC`

**`docs/TESTING.md`** section 44 (Kit, P30-P33), append for the author (Forever unless said):

> **Lists and the rail (P33).** These need a build newer than the 0.16.4 install. Settings ->
> General: move the window so the In combat dropdown sits near the bottom of the screen and open it:
> the list opens upward and its arrow points up (report if the arrow is missing, a box, or points the
> wrong way -- the arrows are the game's own `SquareButtonTextures`, not yet seen on this client).
> Practice -> Edit bindings with the window near the right edge: a spell's ranks open to the left.
> Spells: hover a rail row -- the `R1` tag stays and one red `x` appears; keep the pointer still for
> half a second: `Suggested  Rank 1 of 2 known`, `Per mana`, `Drag to reorder. Right-click for
> more.`; right-click a row: Move up / Move down / Remove. Add spells until the rail is longer than
> the window (or set Text size +2): the rows scroll with the wheel above `+ Add`, which never moves;
> `/st spell <a spell at the bottom>` scrolls it into view. Text size +2 and back: the rail and the
> spell view re-pitch at once. ESC with a dropdown open closes the list, not the window. **TBC:**
> `/md` -- a dropdown near the bottom of the screen opens upward; everything else looks as before.

**`docs/DECISIONS.md`**, one line under the refactor plan's entries:

> **Lists flip at the screen's edge on both lines (T77, P33, review U12, 2026-10-01).** A dropdown's
> list that would leave the bottom of the screen opens upward, and a tree dropdown's second list
> that would leave the right edge opens to the left -- on TBC too, since a list off the screen is a
> bug on either line (mockup M4). Nothing else of P33 reaches TBC: the chevron textures are under
> `UI.THEMED`, and the rail is not on the TBC TOC until C5.

**For the next owners** (no code reads these; text only):
- `UI/Dashboard_Forever.lua` line 189's comment says `UI.ApplyFonts is wrapped by
  UI/SpellsPane_Forever.lua`; it is announced by the kit (`FONTS_CHANGED`) now.
- `UI/ContextMenu.lua` announces through `UI.OnPopup`; `UI.Popup` is the name to use when it is next
  touched.
- `UI/Theme_Forever.lua` (C1 renames it `UI/Theme_Flat.lua`) may fire `FONTS_CHANGED` from
  `UI.ApplyFonts` itself; the kit's metatable in `UI/Style.lua` then goes (Deviation 1).

## Deviations

1. **`FONTS_CHANGED` is fired by the kit, not inside `UI.ApplyFonts`.** The plan says "`UI.ApplyFonts`
   fires `FONTS_CHANGED`", but `UI.ApplyFonts` is defined in `UI/Theme_Forever.lua`, which is not in
   P33's owned files (section 4, wave 16). So `UI/Style.lua` sets a metatable on `MD.UI` for the one
   key `ApplyFonts`: the theme's assignment is kept as the sizer, and every reader of
   `UI.ApplyFonts` (the theme's own `CORE_LOGIN`, Settings -> General's Text size, the suites) gets
   the kit's function, which calls the sizer and fires the event. Every other key of `MD.UI` is set
   and read as before (`rawset`). The effect is the plan's; the theme's next owner can fire the event
   itself and the metatable goes.
2. **The rail's menu is UI/ContextMenu.lua's, built on first use**, as the mockup says ("the same
   ContextMenu Review uses"); `Remove from list` is `Remove` (the mockup's word) and the menu has
   the row's name as its title. A rail on a TOC without `UI/ContextMenu.lua` has no menu (both main
   TOCs list it).
3. **The scroll is whole rows, not a `ScrollFrame`.** The mockup's bar is "the kit's own: an accent
   thumb, the same one Practice and Bindings use": it is drawn here with the same tokens (`track`,
   the accent thumb) but not by `UI.CreateScrollFrame`, because the fixed rows and the footer stay
   outside the scrolled part and rows never show half-cut; the thumb shows the position and is not
   draggable (the wheel and selection scroll). A rail whose height is not known yet shows every row.
4. **The sub-list flips sideways only** (the plan's and the mockup's case); a sub-list near the
   bottom of the screen is not moved up.
5. **More checks than the plan's "+3" in navui** (six: the two flips, the chevrons, the scroll, the
   hover with the menu, the tooltip), and +2 in spellsui, +1 in wincheck.
6. **In-game unknowns:** the chevron file and its coordinates (`SquareButtonTextures`, Blizzard's
   `SquareButton_SetIcon` values) are not verified on the Forever client -- the letters come back only
   when `SetTexture` answers false, so a missing file could still draw an empty box (TESTING asks);
   whether the mouse wheel reaches the rail through its row buttons (the client sends the wheel to
   the frame under the pointer that takes it; rows do not) is a game check too.
7. **Install:** not done from this worktree. The user's request to install the current version on
   both clients is the integrator's after the wave is merged; installing a plan branch before its
   merge would put unmerged code on the clients.
