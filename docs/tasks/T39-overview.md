# T39 -- Overview: My spells, Whole book, Export

Status: **built** 2026-09-30 on branch `ui/T39` (base f4342b3, the integrated head with T38, T40 and
T42), for review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T39** | **Overview** (3.6): My spells; Whole book as today's table under the new look, one row per rank under each family header, with `+` / `listed`; Export moved (format unchanged); the old Spellbook view removed. | `UI/SpellsPane_Forever.lua`, `UI/Dashboard_Forever.lua` | `tools/spellsui.lua` (+3: Whole book has a row per known rank of every family; a gap row; `+` adds); `python3 tools/refcheck.py` on an Export from the stub (format unchanged) | T38 |

Spec sections it cites: 3.6 (Overview, whole), and through it 3.5 (the RANKS columns, rows, tags,
gap rows, the row hover), 4.1 (the palette and text tokens: no gold), 4.2 (fonts, `UI.Pitch`) and
4.3 (table metrics); 8.1 decision 11 (today's table kept as Whole book).

## What was built

**`UI/SpellsPane_Forever.lua`** -- the Overview view, the rail's first row, rebuilt:

- **The title row**: `OVERVIEW` (the accent title font), then `[My spells][Whole book]` (a kit
  button group, 84 + 88) and `[Export]` (70x20). The buttons sit at the view's right edge (556),
  anchored from the pane's left, so a wider window never floats Export to its far edge (section
  1's complaint). The mode is remembered in `db.ui.overview` (`mine` by default).
- **My spells**: one row per family in the player's list, in its order, on T30's table options
  (`FONT_NUM`, right-justified numbers, `UI.Pitch(20)` rows, a 22-px header with its rule, zebra,
  full-width rows, `marker = "bar"` so no gold): the family's icon (16x16 on a 1-px black edge) and
  name, `Suggested` (the rank in the accent), its `Value`, `Per mana` and `To OOM` (from a full
  pool, as 3.5), a 1-px `line` rule, then `Highest` with its `Value` and `Per mana`. A family with
  no value shows its ranks and no numbers; a family the book no longer has is greyed with `not in
  your spellbook`. A click opens the family's view; the hover is the game's own tooltip for the
  suggested rank (T38's `GameTip`), the kit tooltip for a stale row. Under the table: `Click a row
  to open that spell.` and, muted, `Whole book lists every family in your spellbook the same way,
  with + to add it.` (an empty list says how to fill it).
- **Whole book**: today's Spellbook table under 3.5's look. Sections `Heals` / `Damage` / `Other`
  (accent); per family a header row -- its icon, its name, and at the right a 16x16 `+` or a grey
  (`muted`) `listed`; a stale family's `Text read before combat - may be out of date` in `bad`
  under its header; then **T38's own rows** (`FamilyRows`, `RenderRankRow`): one per rank from 1 to
  the highest listed, gaps as one `disabled` spanning row, ranks not learned (`learn at 20`), the
  per-mana bar, the `best` / `max` / `dominated` tags, the suggested row's fill and 2-px bar. The
  value column is headed `Value` (heals and damage share it). A family with no value keeps Rank /
  Lvl / Mana / Cast / Tag and leaves the value cells empty. Other's rule is T10c's: only kindless
  spells cast for mana, and one muted line counts the rest (`2 passives and spells with no mana
  cost not listed - Export has them`). A click on a family's header or rows opens it (its preview,
  with T36's banner, when it is not in the list); `+` adds it to the end of the list and Overview
  stays where it is (the rail follows through `ListChanged`, the header then reads `listed`); a rank
  row's hover is T38's (the game's tooltip through `MD.API.SetTooltipSpell` plus the block, or the
  kit tooltip's reason for a gap or a rank not learned); a family header's hover is the kit tooltip
  (its name, in the list or not, `Click to open it.`).
- **Export** moved to the title row; `ExportText` is untouched (same scope, the whole book, same
  probe block format).
- **Refresh**, 3.5's split applied here: every 2 s while shown, a full render when what the table
  was drawn from changed (the mode, the book's generation, the bonus-healing reading, the pool's
  max, the pitch, the list), else only the To OOM cells change, in place (`api:UpdateCells`). The
  two tables are built once per pitch, as T38's.
- **Removed**: today's Spellbook table code (`SPELL_COLS`, `RenderSpellRow`, `BuildSpellRows`,
  `AddFamilyRows`, the mana and legend lines, the `*`, the `suggested: Rank N` header text, the
  gold row, the window-edge hover).

**`UI/Dashboard_Forever.lua`**: the Spells comment says the old Spellbook view is gone and where
its parts went. No code there referred to it any more (T36 had moved it); an old saved path
`{ "spells", "spellbook" }` already falls back to the rail's first row, Overview.

## Tests first

`tools/spellsui.lua`: items 1-17 (T10-T10c and the review's) now open Overview in Whole book and
hold the table in its new shape -- 3.5's rank rows with a Tag column, no star, no gold, To OOM from
full, a gap as a row of its own, Other's families as family headers, the rank row's hover the
game's tooltip; T36's item 31b clicks a listed family in My spells and an unlisted one in Whole
book; and four new items after T38's. Against the base's pane (the old table), 14 fail:

```
the Spellbook view lists every family of the book, heals then damage then other FAIL - order=BigSpell, GapFamily, Healing Touch, Regrowth, Rejuvenation, Wrath
each rank row shows the book's own numbers                               FAIL - checked=0
the suggested rank is tagged best and marked by the bar, never starred or gold FAIL - suggestedId=1058 header="Rejuvenation   suggested: Rank 2" rankCell="Rank" tag="" fill=false gold=|cffffcc00300|r
a number the book does not have is a dash, never a zero                  FAIL - value=Heal permana=Per mana persec=Per s
gaps and stale values are noted under the family                         FAIL - gap=nil stale=nil under=false
casts to OOM count from the clock's pool when full, never the drained one FAIL - defaultPoolCasts=27 fromFull=27 rowCasts=nil cell=To OOM
hovering a row shows the spell's tooltip block                           FAIL - calls= first=nil blocks=0
each non-empty section has a title row before its first family, and an empty one has none FAIL - heals=1 damage=16 other=19 firstFamily=2 wrath=17 firstOther=nil emptyDamageAbsent=true
hovering a family or an Other row shows its full name                    FAIL - familyRow=true otherRow=false famOk=true otherOk=false
a Rage cost is named in the Mana column and the export, never read as mana FAIL - mana=Mana permana=Per mana toOOM=To OOM export=cost: 10 Rage
T39 Whole book has a row per known rank of every family, under its header FAIL - bad=Bearform id 92100 rows=nil headers=9 families=10 ranks=14 r4tag=
T39 Whole book: a gap is one disabled row across the table               FAIL - order= rank="" wide="nil" tip="Nourish Rank 4 / Not learned yet: learn at level 20."
T39 Whole book: + adds a family to the list; a listed one reads listed   FAIL - raised: ...tools/spellsui.lua:1572: attempt to index field 'listed' (a nil value)
T39 My spells: a row per listed family, suggested against highest; a click opens it FAIL - raised: ...tools/spellsui.lua:1589: attempt to call method 'SetOverviewMode' (a nil value)
33 ok, 14 failed
```

(Item 12's comparison was made nil-safe first, so on the old table it fails rather than stopping
the suite.) After: `spellsui 47 ok, 0 failed` (43 -> 47).

**Export, format unchanged**: item 8 still writes the stub's export and runs
`python3 tools/refcheck.py <export> --data tools/data/refcheck-fixture/data.json` (exit 0). By hand,
the export from the stub on this branch and on the base (the base's `UI/SpellsPane_Forever.lua`
put back for one run) are byte-identical (`cmp`); refcheck on it: `refcheck: 4 spells, 0 agree, 0
disagree, 4 not in the reference`, exit 0.

## The full check

The loop in `docs/TOOLS.md` section 1 plus the suites since added (themecheck, wincheck,
tabscheck): every count as on the base except `spellsui` 43 -> 47 (this task's). TBC: simcheck
PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 35, dashui 63,
regencheck 27, simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice 74, practiceui 49,
migrate 7; adaptercheck/tbc 15, corecheck/tbc 8, svcheck/tbc 1, consolecheck/tbc 1 -- no shared
file touched. Forever: probecheck 87, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24,
scenariocheck 12, gatecheck 9, replayforever 15, reviewforever 11, coachforever 18, practiceforever
24, bindscheck 6, parsecheck 12, bookcheck 21, tipcheck 37, clockcheck 20, spellsui 47, measurecheck
30, releasecheck 13, themecheck 23, wincheck 53, tabscheck 24, adaptercheck/forever 22,
corecheck/forever 10, svcheck/forever 6, consolecheck/forever 17. `python3 tools/apicheck.py`: 0
findings; `--selftest`: 10 of 10; `python3 tools/refcheck.py --selftest`: ok. `luac -p` on
`UI/SpellsPane_Forever.lua`, `UI/Dashboard_Forever.lua` and `tools/spellsui.lua`.

## Deviations

- **spellsui +4, not +3**: the row's three (a row per rank of every family, a gap row, `+` adds)
  plus one for My spells (one row per listed family in the list's order, the suggested rank against
  the highest, the header labels, a click opening the view), which nothing else would hold.
- **Items 1-17 rewritten to the new shapes** rather than kept verbatim, as T37 did for the tooltip:
  the table they held is the one this task replaces. Changed claims: item 3 (the suggested rank
  is tagged `best` and barred, no star, no gold -- was "starred and named in its family's header"),
  item 6 (To OOM counts from a full pool at the clock's max, 3.5's column -- was the clock's
  current pool; "the pane never rewrites the book's own casts" is unchanged), item 7 (the rank
  row's hover is the game's tooltip plus one block -- was the block alone), items 5, 12-15 (a gap
  is a row; Other's families are family headers), item 1's name ("Whole book lists ...").
- **To OOM in Overview is from full**, 3.5's column, in both tables; the old pane's "Mana N
  (modelled M)" line is gone with the rest of the old header (the spec's title row has none). The
  modelled "now" count lives in a family's card (T38).
- **Words and sizes the spec leaves open**: My spells' column widths (the name 128, Suggested 62,
  Value 46, Per mana 58, To OOM 52, the rule at 384, Highest 50, Value 40, Per mana 50: 524 from x =
  8); a family with no value leaves its value cells empty in both tables; the stale note reads as
  the card's (`Text read before combat - may be out of date`, `bad`); the empty-list line; the
  hover texts of a family header and of `+`; the mode remembered in `db.ui.overview` (no default
  added: nil reads `mine`; `Core_Forever.lua` is outside this row).
- **Files outside the row**: none. `tools/wowstub.lua` and the shared files are untouched;
  `docs/TOOLS.md`'s spellsui row is T44's.
