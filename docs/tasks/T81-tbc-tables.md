# T81 -- TBC tables: the rank table, Waste and Review on the one table (plan C2)

Status: **built** 2026-10-01 on branch `plan/C2` (base `70b424d`), wave C-b of
`docs/PLAN-refactor-ux.md`, beside C4. No new file, no TOC line: every changed file is already
listed where it needs to be. The integrator lines below are the expected counts, the CLAUDE.md
rows, TOOLS.md, one DECISIONS paragraph and the TESTING items.

## The task (docs/PLAN-refactor-ux.md section 5.C, C2; review U5, A23)

> The TBC rank table, Review and Waste become `opts` sets on the one generic table:
> right-justified numbers, 20-px rows, zebra, a header rule, the bar marker, and a Tag column
> instead of the gold note. The second `Render` is deleted.

Review U5: the TBC tables left-justify their numbers in a 10-pt Blizzard font on 16-px rows, so
`25`/`55`, `1.5s`/`inst` and `1.2k`/`980` do not line up. Review A23: `CreateTable` is two tables
in one closure (`opts == nil` is the TBC rank table with its own `Render`), so every Forever table
feature is a diff in a TBC-loaded file. The approved look is mockup M6's RANKS table
(`docs/mockups/refactor-ux.html`), with the answers of section 8.1: no gold (decision 10, answer
1) and `beaten` for `dominated` with a tooltip naming the rank that beats it (answer 7).

## What was built

### `UI/Dashboard_Rows.lua` (shared): one table

- **The no-options table is gone.** That covers its `COLS`, `EFFECTIVE_COLS`, `Fmt`, `AccentHex`,
  its second `api:Render` with the gold, the `*` and the note, and the header row's and data rows'
  hover through `MD.Tip:Columns` / `MD.Tip:Row(MD.RankMath:Explain(...))`. Those last two are TBC-only
  builders (`UI/Tip_TBC.lua`) that a Forever-loaded file reached behind `if not opts`.
- **`CreateTable(parent, width, opts)` raises without `opts.render`.** The message names T81.
- **The generic path is the only path.** Every `opts and` guard and the `if opts and opts.render`
  wrapper are gone (the body is de-indented, not changed).
- **A row's hover:**
  - the wash and the call happen only for a table with `onEnter`;
  - a header row has no row hover (its columns' `col.tooltip` hits are its hover);
  - `onLeave` falls back to `MD.Tip:Hide()`, as before.
- **Colours are token reads.** The default header colour is `muted` (it was the literal
  `|cff888888` without `marker = "bar"`). The row colour without the marker reads the tokens:
  `disabled`, the `accent` for a suggested row, `dominated`, `text`. No caller today reaches the
  latter: Review's result area ignores the colour, and every other table passes the marker.
- **Forever is unchanged.** Every Forever caller passes `opts.render` with either `marker = "bar"`
  or its own `headerColor`. The Review result area has no `onEnter` and no data ids, so its hover did
  nothing before and does nothing now.

### `UI/Dashboard.lua` (TBC): the rank table as an opts set

`MD.DashboardParts.CreateRankTable(content, width)` builds the table (it is on `DashboardParts` so
C3's Spells view can build its RANKS on it and `dashui` can build one). Its options:

- **Look.** `font = UI.FONT_NUM` (Arial Narrow 13). `rowHeight = UI.Pitch(20)`,
  `headerHeight = UI.Pitch(22)`, `headerRule`, `zebra`, `rowWidth = 600`, and `marker = "bar"`: the
  suggested row is marked by its fill and the 2-px accent bar, with no gold and no `*`.
  `headerFont = UI.FONT_SPECIAL` and `headerColor = label`, as Forever's RANKS.
- **Columns.** Rank (left), then Lvl, Mana, Heal/cast, HPM, HPS, Cast and To OOM, all
  right-justified:
  - **HPM** is a bar cell (80-px track, M6's): the fill is HPM over the best HPM shown among the
    family's real ranks, at 0.25 on a rank not learned or beaten.
  - **The Tag column** (84 px, `UI.FONT_SMALL`) replaces the gold note. It reads `learn at N` (not
    learned), `rolling` (Lifebloom's x2 / x3 rows), `best` (the suggested rank, in the accent),
    `max` (the highest known) or `beaten` (dominated, the author's word), each in `label` except
    `best`. Each tag explains itself on hover (`col.cellTooltip`, T78's mechanism):
    - `beaten` reads "Beaten by Rank N" with HPM and HPS side by side. The beater is
      `Spells/RankRules.lua`'s `DominatedBy`, which uses the same rule the dominance came from.
    - `best` gives the suggested rule's sentence, with "It is your highest rank too." for the old
      "efficient + max rank".
    - `rolling` keeps the old note's "6 ticks, no bloom".
    - `learn at N` reads "Not learned yet: learn at level N."
- **Hover.**
  - Every labelled header shows the glossary (`col.tooltip = Tip:Columns`), so the header still
    explains itself, as the hint line says.
  - A row's hover is its derivation (`Tip:Row(RankMath:Explain(id, variant))`). It now sits
    beside the row (`Tip:Show`, anchor `beside`) instead of at the window's right edge.
- **Effective mode.**
  - The three healing headers (Heal/cast, HPM, HPS) take the accent, through `opts.header`, which
    is written before each render.
  - A row with no overheal measurement of its own keeps its raw values and a muted `?`.
  - Nature's Grace's `*` after the cast stays, muted.
- **Per render.** `Render(rows)` writes `hpmFrac` and `beatenBy` on RankMath's rows. They are
  fresh on every `Compute`, so the values never outlive the render.
- **Review's hint line** names the Result column and Coach anyway. It used to name a "validate
  column" and a Coach that "only runs on fights that passed", both stale since C1.

### `UI/Dashboard_Waste.lua` (TBC): one table per grouping

Each grouping (Spell, Role, Class, Target) is an opts set on the one table, built on first sight
(a table's columns are fixed when it is built); the others are hidden.

- **Look.** Numbers right-justified in `UI.FONT_NUM_SMALL`, words in `UI.FONT_SMALL`, 20-px rows
  under a 22 header with its rule, and zebra, as Review's list.
- **Scrolling.** The list scrolls (the wheel, a thin bar), with the visible rows taken from the
  pane's height. T53's `... and N more (scroll: not yet)` tail line is gone, as it went from
  Review in P27.
- **Colours are tokens.** A guessed label is `text2` and the rest `text`. Secondary words are
  `muted`, and a missing cast or mana is `disabled`. Overheal is `bad` from 45% and `good` under
  30%; between them it is a local amber (`ffcc66`, the old value, since no theme token names it).
  Life Tap keeps the warlock's class colour.
- **The empty list's line and the total line** are kit font strings (muted).

### `UI/Dashboard_Review.lua` (both lines): the only list

Since C1 put the theme on the TBC TOC, `UI.THEMED` is true everywhere this file loads. P27's list,
an opts set on the one table, has therefore been the list on TBC since T80. T81 deletes what could
no longer run:

- the old 16-px row pool (`COLS`, `ROW_HEIGHT`, `AcquireRow`, the pane's `Release`);
- T53's `ListWindow` / `TailText`;
- `ValidateCell`;
- the chat-printing Validate;
- the `Coach*` star and the shift-click (`Forcing`, the shift-forced Play);
- the `if THEMED` branches of four tooltips.

The construction block's `if THEMED then` is now `do`, with the body unchanged. What the pane
does on either line is unchanged. Because the deleted Validate branch was the only one that
printed it, `MD:ValidationReport` is no longer called from this file.

## Failing first (on the parent `70b424d`)

The parent tree was taken with `git archive 70b424d`, and this branch's `tools/dashui.lua` and
`tools/reviewui.lua` were copied into it. `dashui` falls back to `CreateTable` with no options when
`CreateRankTable` is absent, which is the parent's rank table. So it runs to the end there and
fails check by check:

```
=== dashui (tbc) on 70b424d     exit 1   66 ok, 8 failed
  FAIL T81: the rank table's numbers are right-justified in Arial Narrow on 20-px rows - no R6 row
  FAIL T81: the suggested row is the fill and the bar, its tag best, no gold, no star - |cffffcc00R6 *|r
  FAIL T81: a Tag column (max, learn at N, beaten by Rank N, rolling), no note - max=nil learn=- beaten=- tip="" rolling=0
  FAIL T81: every header label explains the columns; a row's hover is its derivation - hits=0 glossary=nil row=nil
  FAIL T81: Effective mode puts the accent on Heal/cast, HPM, HPS and a ? on an unmeasured heal - |cffff7c0aHeal/cast|r / no R6
  FAIL T81: CreateTable refuses a table without opts.render (the second table is gone)
  FAIL a long Waste list scrolls to its last row, no tail line (T81) - rows=0 nil..nil, after the wheel 0 ..nil, tail=nil/nil, healed nil, h=nil
  FAIL T76: a header label shows its column's tooltip - header=true hit=true lines=2 plain=false
=== reviewui (tbc) on 70b424d   exit 0   50 ok, 0 failed
```

`reviewui` passes on the parent, as expected. Its new check holds the list's look, which C1 already
turned on; T81's Review work is the deletion of code that could not run. The mutation M3 below
shows the check can go red.

**Mutations** (a scratch copy of this branch, taken with `git archive`):

- **M1.** The rank table's Mana column loses `justify = "RIGHT"`. `dashui` fails
  `T81: the rank table's numbers are right-justified ...` (`cost LEFT`).
- **M2.** Waste's tables are built with `scroll = false`. `dashui` fails
  `a long Waste list scrolls to its last row ...` (all 40 rows painted, the wheel moves nothing).
- **M3.** Review's Spent column loses `justify = "RIGHT"`. `reviewui` fails
  `T81: Review's list is the one table ...`.

**The chat card is byte-identical** (the plan's "with the chat card byte-identical"). A scratch
script, not committed, did three things on the parent and on this branch:

1. recorded the shared fake pull (`tools/fakepull.lua`);
2. ran `/md coach 1 force` and kept every chat line;
3. ran the Review pane's Coach anyway and kept its one chat line and every line of the result area.

The two outputs are identical, apart from the `[sim] search N evaluations` debug-log lines. Those
count evaluations per frame slice, which is timed on `debugprofilestop()`, so they vary from run to
run. Filtered of those lines, `cmp` reports the files identical (104 lines each).

## Expected values that changed

| Suite | Check (old -> new) | Old expectation | New expectation |
|---|---|---|---|
| `dashui/tbc` | `a long Waste list ends with the tail line` -> `a long Waste list scrolls to its last row, no tail line (T81)` | 13 rows and `... and 27 more (scroll: not yet)` in a 300-high pane | 11 rows; the wheel reaches Spell 40; no tail line; numbers RIGHT, words not; 20-px rows |
| `dashui/tbc` | `T30 font and justify: the table's font, a column's own` (name kept) | also: the no-options table's header is `GameFontHighlightSmall`, `LEFT` | that clause dropped (there is no such table) |
| `dashui/tbc` | `T76: a header label shows its column's tooltip` (name kept) | the TBC rank table's columns carry no tooltip (0) | 8: every labelled column carries the glossary |

New: `dashui` +6. These are the six `T81:` checks: the look; the suggested row; the Tag column;
the header glossary and the row's derivation; Effective mode; and the refusal of a table without
`opts.render`. `reviewui` +1: `T81: Review's list is the one table ...`.

## Suites, before and after

Before: `tools/check.sh` on `70b424d` gave **71 runs, all passed**, 66 counted against 66.
After: `tools/check.sh` on this branch gave **71 runs, all passed**, 66 counted against 66. The
two notes are `dashui/tbc: 74 assertion(s), 68 expected` and
`reviewui/tbc: 50 assertion(s), 49 expected`.

| Suite | Before | After |
|---|---|---|
| `dashui/tbc` | 68 | **74** |
| `reviewui/tbc` | 49 | **50** |
| `navui/tbc`, `practiceui/tbc`, `replayui/tbc`, `spelltip/tbc`, `wincheck/tbc`, `themecheck/tbc` | 46, 52, 107, 49, 4, 9 | equal |
| `spellsui`, `reviewforever`, `replayforever`, `practiceforever`, `wincheck`, `themecheck` (forever) | 50, 22, 28, 29, 66, 37 | equal |
| every other suite | as `tools/data/expected-counts.json` | equal |
| `apicheck` | 0 findings, 8 Forever TOCs, 59 files, 48 globals | equal |
| `textcheck` | 0 findings, 9 TOCs, 95 files | equal |

`luac -p` passes on `UI/Dashboard_Rows.lua`, `UI/Dashboard.lua`, `UI/Dashboard_Waste.lua` and
`UI/Dashboard_Review.lua`.

## Integrator lines

**TOCs:** none (no file added, renamed or moved).

**`tools/data/expected-counts.json`:** `"dashui/tbc": 74`, `"reviewui/tbc": 50`.

**CLAUDE.md:**

- The `UI/Dashboard_Rows.lua` row:
  - drop "`nil` is the TBC table exactly as before (`tools/dashui.lua`)" and "all nil is the TBC
    table, gold included";
  - drop T76's "the TBC rank table's columns have none";
  - append:
    > **T81 (C2, review U5 / A23):** one table -- the no-options TBC table and its second `Render`
    > are deleted, `CreateTable` raises without `opts.render`, and no TBC-only builder
    > (`Tip:Row` / `Tip:Columns`) is reached from this shared file; the header's default colour and
    > a row's colour without the marker are token reads; a row hover only for a table with
    > `onEnter`.
- The `UI/Dashboard.lua` row: append
  > **T81 (C2):** the rank table is an opts set on the one table,
  > `MD.DashboardParts.CreateRankTable(content, width)` (C3 builds on it). Its look: numbers
  > right-justified in Arial Narrow on 20-px rows, zebra, the header rule, the suggested row's
  > fill and accent bar (no gold, no `*`), and an HPM bar. A Tag column (`best` / `max` /
  > `beaten` / `learn at N` / `rolling`, each with its own hover; `beaten` names the rank that
  > beats it through `RankRules.DominatedBy`) replaces the gold note. Every header shows the
  > glossary (`Tip:Columns`), and a row's derivation (`Tip:Row`) shows beside it. In Effective
  > mode the accent headers and the `?` stay. Review's hint names the Result column and Coach
  > anyway.
- The `UI/Dashboard_Waste.lua` row:
  - replace T53's sentence with:
    > **T81 (C2):** each grouping is an opts set on the one table (numbers right-justified, 20-px
    > rows, zebra, the header rule) and scrolls -- no tail line; token colours
- The `UI/Dashboard_Review.lua` row:
  - drop T53's "ends with a grey `... and N more (scroll: not yet)` line ... no scroll yet (P27 on
    Forever)" and the `Coach*` star / shift-click wording in its first sentences;
  - append:
    > **T81 (C2):** one pane on both lines -- P27's list (an opts set on the one table, scrolled,
    > the result area, the row menu with Coach anyway) is the only list; the old 16-px list, its
    > tail line, the `Coach*` star and shift-click are deleted (unreachable since T80)
- The `tools/` row: nothing beyond the counts (the counts live in the JSON).

**docs/TOOLS.md** section 1:

- `dashui.lua`: replace "the old 56 unchanged (an `opts == nil` table is the TBC one, gold
  included)" with "the table options", and T53's sentence with "Since **T81** (74): the TBC rank
  table is an opts set (right-justified Arial Narrow, 20-px rows, zebra, header rule, the
  suggested row's fill and bar with no gold or star, the Tag column and its hovers, the glossary
  on every header, the derivation beside the row, Effective mode) and a table without
  `opts.render` is refused; a Waste list scrolls to its last row with no tail line". In T76's
  sentence, "the rank table's columns none" becomes "the TBC rank table's eight labelled columns
  carry the glossary".
- `reviewui.lua`: replace T53's sentence with "Since **T80/T81** (50): the themed list scrolls a
  36-pull run to its end with no tail line; the list is the one table (right-justified numbers,
  20-px rows)".

**docs/DECISIONS.md**, a paragraph after "TBC takes the Forever window":

> **TBC's tables are the one table** (2026-10-01, T81 / C2; review U5 / A23, decision 10). The TBC
> rank table, Waste and Review are opts sets on `UI/Dashboard_Rows.lua`'s one table. Numbers are
> right-justified in Arial Narrow on 20-px rows, with zebra and a rule under the header.
>
> The rank table:
> - The suggested rank is marked by the row's fill and the accent bar. The gold, the `*` and the
>   "efficient rank" note are gone.
> - A Tag column says `best`, `max`, `beaten` (the author's word for dominated; its hover names
>   the rank that beats it), `learn at N` or `rolling`.
> - HPM carries a bar.
> - The column words stay TBC's (Heal/cast, HPM, HPS, To OOM) until the Spells view (C3).
>
> Waste scrolls instead of ending with "... and N more". The no-options table is deleted, so a
> table without `opts.render` raises.

**docs/TESTING.md** section 44, after item 30 (TBC, C2):

> 31. **TBC tables (C2).**
>     - `/md` -> Spells -> Rejuvenation: the numbers line up on the right, the rows are taller
>       and striped, and the suggested rank has a faint fill and an orange bar at its left (no
>       gold row, no `*`). The last column says `best`, `max`, `beaten` or `learn at N`.
>     - Point at a `beaten` tag: "Beaten by Rank N" with both HPM and HPS.
>     - Point at a column header: the glossary. Point at a row: its derivation, beside the row.
>     - Tick Effective: Heal/cast, HPM and HPS turn orange; a rank with no measurement shows `?`.
>     - Lifebloom's x2 / x3 rows say `rolling`.
>     - Reports -> Waste: the numbers line up on the right; with more spells than fit, the wheel
>       scrolls (no "... and N more" line).
>     - Reports -> Review: as after C1 (the hint above the list now names the Result column and
>       Coach anyway).

**docs/HISTORY.md**: the integrator's wave entry.

## Deviations

1. **The column words stay TBC's.** The table keeps Heal/cast, HPM, HPS and To OOM rather than
   M6's Heal, Per mana, Per sec and Casts. C2 names the look (justification, rows, zebra, rule,
   marker, Tag column), not the vocabulary. The glossary (`Tip:Columns` in `UI/Tip_TBC.lua`, C4's
   file this wave) and the hint line above the table both name the old words. M6's words, *Casts*
   reading `inf` / `999+`, and the hint line's removal belong with C3's view.
2. **An HPM bar cell** (M6's per-mana bar) was added beside the bar *marker* that the plan names.
   M6 draws both, and C3's view renders on this table.
3. **`MD.DashboardParts.CreateRankTable`** is new public surface, for C3 and for `dashui`.
4. **Review.** C1 had already made P27's list the TBC list, so C2's Review half is the deletion of
   the code that could no longer run. `reviewui` gains one check, which passes on the parent too
   (M3 shows it can fail). The chat card was checked byte for byte with a scratch script instead of
   a committed golden. A full card in a suite would pin the coach's search, which later engine
   tasks may legitimately change.
5. **Two small TBC-visible changes outside the table.**
   - Review's hint line (in `UI/Dashboard.lua`) now names the Result column and Coach anyway.
   - A rank row's derivation opens beside the row rather than at the window's right edge (U28,
     the rule every other table follows).
6. **Waste's middle overheal tone** stays the old amber literal (`ffcc66`), because the theme has
   no token for it. Its good and bad tones are the theme's `good` and `bad`.
7. **The pitch is read once.** The rank table's and Waste's 20 / 22 pitch is read when they are
   built (`UI.Pitch`), as Review's always was. A Text size change reaches these TBC tables at the
   next `/reload`. Forever's Spells pane re-renders on the offset; TBC's view does in C3.
