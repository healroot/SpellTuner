# T36 -- the Spells pane: rail and picker

Status: **built** 2026-09-30 on branch `ui/T36` (base 3407386), for review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T36** | **Spells pane: rail and picker**: `UI/SpellsPane_Forever.lua` split out of `Dashboard_Forever.lua`; the Spells group in `layout = "rail"`; views from `Tabs`; the picker sheet with search, masking the view only; drag-in from the spellbook (`MD.API.CursorInfo`; **the cursor is never cleared**); `/st spell <name>` through `ShowMain` when present; the preview banner; pitches through `UI.Pitch`, and a re-render when the font offset changes. | `UI/SpellsPane_Forever.lua` (new), `UI/Dashboard_Forever.lua`, `Client/API_Forever.lua`, `Core_Forever.lua`, `tools/wowstub.lua`, both Forever TOCs, `tools/adaptercheck.lua` | `tools/spellsui.lua` rewritten (the rail lists the seeded families; a tick adds a view; `/st spell` selects one; a drop adds at the row and leaves the cursor as it was; the rail takes a drop while the picker is open; at offset +2 the rail rows are 22 apart) | T31, T35 |

Spec sections it cites: 3.1 (where it lives, `/st spell`), 3.2 (the rail, the actions table, the
cursor rule), 3.3 (the seed on first open, the reconcile's appends with the new dot, a family the
book no longer has), 3.4 (the picker sheet), 3.6 (the preview banner, Export's scope), 4.2 (the
pitches and the font offset re-render), 6.4 (sheets and masks) and 6.6 (the picker refuses to open
in combat).

## What was built

**`UI/SpellsPane_Forever.lua`** (new, `MD.SpellsPane`; Forever TOCs only, after
`UI\Dashboard_Rows.lua`, before `UI\Dashboard_Forever.lua`). Everything the Spells group shows and
does now lives here; `UI/Dashboard_Forever.lua` only wires it (the group definition from
`SpellsPane:Group()`, `onCreate` -> `SpellsPane:Create(content)`, `onShow` ->
`SpellsPane:Show(view)`, `SpellsPane:Attach(nav)` once the nav exists, and the window opening on
the rail's first row instead of `"book"`). The old Spellbook code (the columns, the row renderer,
the hover, the rows builder, Export) moved over unchanged but for the note column's width (below).

- **The rail group.** `{ id = "spells", layout = "rail", views = SpellsPane:Views(), rail = {...} }`:
  title `MY SPELLS`, `rowHeight = UI.Pitch(20)`, a 48-px footer, the empty line `Add the spells you
  want to watch.`, and the callbacks. Views are `overview` (a fixed row) and `fam:<family>` per key
  of `MD.Tabs:Get(book)` -- the first call seeds the list, so the seed runs when the window is
  first built. A row carries the family's icon, its suggested rank as the tag (`R1`), the new dot
  (`Tabs:IsNew`), or, for a key `Tabs:Resolve` calls `stale`, the greyed name and the kit's `not in
  your spellbook` tooltip. Every client-read name is escaped (the probe's `Esc`).
- **The list follows every change.** `SpellsPane:RefreshRail()` calls `nav:SetViews("spells", ...)`
  when the set or order of rows changed (3.1), and otherwise repaints the rows in place (a tag, the
  dot) so the view on screen is not re-selected. It runs on `BOOK_CHANGED` (after
  `Spells/Tabs.lua`'s reconcile, which registered first), after every edit, and after a view marks
  its family seen. A re-entrant call (a rescan fired while the rail is being built) is deferred and
  run once after.
- **Edits.** Hover `x` / the menu's Remove -> `Tabs:Remove`; `^` / `v` / a drag / the menu ->
  `Tabs:Move`; the footer's `Wrath removed  [Undo]` line (shown while `Tabs:UndoKey()` answers) ->
  `Tabs:Undo`; `[ + Add ]` (164x20) opens the picker.
- **The picker sheet** (3.4): `UI.CreateSheet(view, view, 300, 400, "ADD SPELLS")` where `view` is
  the area right of the rail (`nav:RailView("spells")`), so **the mask covers the spell view, not
  the rail**; anchored TOPLEFT to the rail's TOPRIGHT +4. A search box (filters by substring, case
  ignored, as you type), sections HEALS / DAMAGE / OTHER (14-px accent titles over a 1-px accent
  rule at 0.6), rows of a 14x14 kit check, a 16-px icon, the name and the rank range (`R1 - R2`),
  the tip `Tip: drag a spell from your spellbook onto the list.`, and `[Reset to my heals]` /
  `[Done]`. Ticking appends (`Tabs:Add`), unticking removes and records `removed`; changes apply at
  once and Done only closes the sheet. Passives are not listed. The ticks follow every change the
  rail makes while the sheet is open. In combat it does not open (one chat line).
- **The drop** (3.2): the rail's `onDrop(at)` reads `MD.API.CursorInfo()`; a `"spell"` with a plain
  id is found in the book (by id, else by the spell's name) and its family goes in at the drop row
  (`Tabs:Add(key, at)`), or moves there when it is listed already. `canDrop` is true while the
  cursor holds a spell, so a click on the rail then drops rather than selects. **Nothing calls
  `ClearCursor`**: the spell stays on the cursor. Anything else on the cursor, or an id that
  resolves to no family, adds nothing.
- **`MD.API.CursorInfo()`** (`Client/API_Forever.lua`, recorded in the capability table as
  `GetCursorInfo`, in `tools/adaptercheck.lua`'s `FOREVER_ONLY_NAMES`): `kind, spellId` -- the kind
  only when a plain string, the id only for a `"spell"` whose fourth return is a plain number;
  anything secret, absent or raising answers nil. The shape is retail's, UNVERIFIED on Forever.
- **`/st spell <name>`** (`Core_Forever.lua`): `MD:OpenSpell(rawArg)` -> `SpellsPane:Find` (an exact
  name, then a prefix, case-insensitive; the player's list before the rest of the book) ->
  `MD:SelectView("spells", "fam:<family>")`, which goes through `MD.Win:ShowMain`. No match: `spell:
  no spell in your spellbook starts with '<text>'` (escaped). Empty: the Spells group.
- **The preview** (3.6): a family not in the list (from `/st spell`, or a click on it in Overview)
  opens its view with the banner `Not in your list.  [+ Add to my spells]` and no rail row
  selected. The button adds it and selects its view.
- **The views, for now.** *Overview* is today's Spellbook table and Export (T39 turns it into My
  spells / Whole book); a click on a family's header or rank opens that family (its view, or its
  preview). *A family's view* is a header (a 32x32 icon with a 1-px black edge, the name in
  `FONT_HEAD`, `Heal - Rank 2 of 2 known` in `text2`, the pool `~364 / 364 mana` with the `~` part
  in `mana` blue, or `mana not modelled yet` in `muted`) over that family's rows of the same table
  (T38 builds 3.5 in its place). A stale family's view reads `Healing Wave is not in this
  character's spellbook.` with a **[Remove]** button (3.3). Both re-render every 2 s while shown.
- **Pitches** (4.2): the rail rows (20), the family header (48), the banner (20), the picker rows
  (20) and its section titles (22) go through `UI.Pitch`. `UI.ApplyFonts` is wrapped at load, so
  any change of the offset (T42's slider, the login's saved offset) calls
  `SpellsPane:FontsChanged()` at once: `rail:SetRowHeight(UI.Pitch(20))`, the family view re-laid
  out, the picker rebuilt if open, the view on screen re-rendered.

**`tools/wowstub.lua`** (hunks tagged `-- T36`): `GetCursorInfo` answers `S.cursor` (retail's shape;
both functions are in the 69893 baseline), `ClearCursor` counts into `S.clearCursorCalls`.

**TOCs**: `UI\SpellsPane_Forever.lua` after `UI\Dashboard_Rows.lua` in `SpellTuner_Mainline.toc`
and `SpellTuner.toc`. The TBC TOC is untouched.

## Tests first

`tools/spellsui.lua` rewritten: items 1-17 (T10-T10c, the review's R13/R38) now open the
`overview` view and hold today's table as before (the ASCII walk moved last, so the rail, the
picker and the views are in it); the kindless fixtures come first and the heal fixtures after the
T36 block, so the rail is tested against the stub's own book (Healing Touch R1, Rejuvenation R1/R2,
Wrath R1). The T36 block runs each item under `pcall`.

Against the base (the new suite, the old code): **17 ok, 16 failed** -- every T36 item (`attempt to
index upvalue 'SP' (a nil value)`, `attempt to call field 'CursorInfo'`, `/st spell` printing the
command list, `dot=false`). Item 31b ("a family clicked in Overview opens ...") was added after that
run; it raises the same way on the old code. `tools/adaptercheck.lua` (forever) with `CursorInfo`
in `FOREVER_ONLY_NAMES`, against the base `Client/API_Forever.lua`: **21 ok, 1 failed** (`every
binding is on MD.API and in the capability table`).

After: **spellsui 34 ok, 0 failed**. The seventeen new:

- the Spells group is a rail: MY SPELLS, Overview, then the seeded families (Healing Touch,
  Rejuvenation; no view row; content at -8; tags `R1` / `R2`; the icon)
- + Add opens the picker over the spell view, not over the rail (the mask's region is the rail
  view, the sheet at the rail's TOPRIGHT +4; HT and Rejuvenation ticked, Wrath not; a passive not
  listed, a free spell under Other)
- a tick adds the family to the rail as a view (and `MD:SelectView("spells", "fam:Wrath")` selects it)
- unticking removes it, and the rail's Undo line brings it back (`removed` recorded, `Wrath removed`)
- the picker's search filters by substring
- a drop adds at the row and leaves the cursor as it was (Wrath dropped on Healing Touch's row goes
  first; `S.cursor` the same table, `ClearCursor` never called)
- an item on the cursor adds nothing; a click with a spell drops it
- the rail takes a drop while the picker is open, and the picker follows (its tick turns on)
- `MD.API.CursorInfo` answers a spell id only when plain
- `/st spell` selects one, through `MD.Win:ShowMain`
- `/st spell` on a family not in the list opens its preview; Add lists it
- `/st spell` with no match says so
- a family the book no longer has stays in the rail, greyed, with Remove
- a newly learned heal appears with the new dot until opened
- a family clicked in Overview opens its view, or its preview when not listed
- the picker does not open in combat
- at font offset +2 the rail rows are 22 tall (21 apart, the 1-px overlap), the header 50

## Full check

The loop in `docs/TOOLS.md` section 1 plus `tabscheck`, `themecheck` and `wincheck`, on this branch
and on an export of the base (3407386), compared line by line: every suite's count and last line
unchanged -- simcheck PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44,
navui 35, dashui 63, regencheck 27, simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice
74, practiceui 49, migrate 7, probecheck 86, forevercheck 13, modulecheck 14, kitcheck 7,
recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 14, reviewforever 11, coachforever 18,
practiceforever 20, bindscheck 6, parsecheck 12, bookcheck 17, tipcheck 37, clockcheck 20,
measurecheck 30, releasecheck 13, tabscheck 24, themecheck 23, wincheck 30, adaptercheck 22 / 15,
corecheck 10 / 8, svcheck 6 / 1, consolecheck 14 / 1 -- except **spellsui 17 -> 34** (above). The
other lines that moved are table addresses and millisecond timings, and modulecheck's own walk
(`73 strings reached under the window` -> 96: the rail, its footer and the family view). `python3
tools/apicheck.py`: `8 Forever TOCs, 48 files` (47 before: the new file), 46 distinct globals, **0
findings**; `--selftest` 10 of 10; `refcheck.py --selftest` ok. `luac -p` on
`UI/SpellsPane_Forever.lua`, `UI/Dashboard_Forever.lua`, `Core_Forever.lua`,
`Client/API_Forever.lua`, `tools/spellsui.lua`, `tools/wowstub.lua`, `tools/adaptercheck.lua`: ok.
(On the export, releasecheck cannot run -- it reads `git ls-files`; on this branch it passes 13.)

The TBC line: no TBC-loaded file changed. The stub's two new globals exist under both profiles and
no TBC file calls them; every TBC suite's output is as before, line for line, but for timings.

## Deviations

- **The views are interim.** 3.5 (one spell's view) is T38's and 3.6's My spells / Whole book is
  T39's. So that the rail has something to open, *Overview* is today's Spellbook table with Export,
  and a family's view is a header over that family's rows of the same table. Both are replaced
  whole by T38 / T39; the rail, the list, the picker, the drop, `/st spell` and the preview do not
  change when they are.
- **The table's note column is 90 wide (was 180)**, the table 548 (was 620): the view right of the
  rail is 556 wide in an 860 window, and the old 638-px table would have run under the scroll
  frame's edge. Its three words (`not learned`, `dominated`, `max rank`) fit.
- **The preview is shown in the Overview view's slot, with no rail row selected**, and
  `db.uiPath` keeps `overview`. The kit's `nav:Select` refuses a hidden view, and a visible one
  would put a family that is not in the list into the rail. Clicking Overview ends the preview;
  adding the family (the banner's button, the picker, a drop) lists it.
- **"22 apart"**: rail rows are 20 tall and overlap by 1 px (3.2, 4.3), so at +2 they are 22 tall
  and their tops 21 apart; the item asserts both and is named for the height (T31's note on the
  same line).
- **The table rows' pitch does not follow the offset**: the old table's cells are
  `GameFontHighlightSmall`, which `UI.ApplyFonts` does not size, so its 16-px rows stay. T38 / T39's
  tables are built on `UI.FONT_NUM` and `UI.Pitch(20)`.
- **The re-render hook wraps `UI.ApplyFonts`** in this file (the theme is outside the row's files),
  so every caller of it -- the login's saved offset, T42's slider -- re-renders the Spells pane
  without knowing about it.
- **Picker sections by kind**: "free spells are listed under Other" is read as the picker, unlike
  Overview's Other rule, listing kindless spells with no mana cost (under Other); a heal or damage
  spell stays in its own section whatever it costs.
- **A drop of a family already listed moves it** to the drop row (3.2 says the drop inserts at the
  row; `Tabs:Add` refuses a listed key).
- **No ESC entry for the picker**: the ESC stack is T33's, not in this base; the sheet closes with
  Done and hides with its window. *Integration (Wave 3, T33 before T36):* `OpenPicker` pushes the
  sheet onto `MD.Win`'s stack (6.5: the sheets join it), so one ESC closes the picker and not the
  window; `tools/spellsui.lua` +1 (35).
- `CLAUDE.md` and `docs/TOOLS.md` are not updated: T44 writes the docs for the wave.
