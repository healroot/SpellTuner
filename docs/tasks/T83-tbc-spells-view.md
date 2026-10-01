# T83 -- the TBC Spells view (plan C3)

Status: **built** 2026-10-01 on branch `plan/C3` (base `03cc1bd`), wave C-c of
`docs/PLAN-refactor-ux.md`. One new file, `UI/SpellsView_TBC.lua`, which needs one TOC line on
`SpellTuner_TBC.toc`. That line, the expected count, the CLAUDE.md rows, TOOLS.md, one DECISIONS
paragraph and a TESTING item are the integrator lines below.

## The task (docs/PLAN-refactor-ux.md section 5.C, C3; review U6; mockup M6, approved 7.1)

> The Forever structure, with TBC's numbers: a header, the chip and one comparison line, the
> table and the card. "Effective" becomes "After overheal", with the measured share, and the
> Simulate strip folds behind *What if...*. The view is built in new `UI/SpellsView_TBC.lua`.
> `UI/Dashboard.lua` keeps the four family views along the top until C5.

Review U6: the TBC Spells view had four lines of prose above the table (the Simulate strip, a
five-colour stats line, a gold callout, and a glossary hint repeated every 2 s), and the table
started at -104. The approved look is mockup M6's Spells view (`docs/mockups/refactor-ux.html`):
the header, the chip and the comparison, After overheal with "31% measured" under it, What if...,
RANKS (Heal, Per mana, Per sec, Casts, with *Casts* reading `inf` / `999+`), and the card for the
rank. The author's answers in 8.1 / 7.1 apply: the selected rank row is a white 2-px bar, and the
suggested row keeps its fill and accent bar.

## What was built

### `UI/SpellsView_TBC.lua` (new, TBC only): the view

`MD.DashboardParts.CreateSpellsView(parent, width, onChange)` builds one family's view, top to
bottom and 12 px apart, inside one scroll frame. It is 720 wide, and it scrolls when 13 ranks and
the card do not fit. Its API: `api.frame`, `api:Render(family)`, `api.rankTable`, `api.whatIf`,
`api:SetWhatIfOpen(on)` and `api:WhatIfOpen()`. The dashboard's Refresh calls `Render` every 2 s,
as it always re-rendered the rank table.

1. **The header.**
   - It shows the family's icon (`GetSpellTexture` of the highest known rank, under `pcall`) and
     the name.
   - The second line names the shape, the rank and the cast, for example "Direct heal - Rank 12
     of 12 known - 2.9 s cast with Nature's Grace averaged". HoTs read "Heal over time" with the
     duration, Regrowth "Heal, hit and over time", Lifebloom "Heal over time and a bloom".
     "not castable in Tree of Life" is added in `bad` when in Tree form and the family has no
     `tol`.
   - At the right sit the mana (`7009 / 7009 mana`) and, under it, `+450 healing`.
   - Every what-if value shows in the accent: the mana as `N mana  what if`, `+N` healing, crit,
     mp5 casting and resting, Tree of Life or caster form, Moonglow. This is M6's "the header
     shows the changed stats in the accent".
   - The old stats line moved into the hover on the +healing line. That covers +healing, the
     Tree of Life aura, crit, both regen rates with the spirit / gear split and the mp5 the API
     omits (Dreamstate, measured), the mana, the relic, and the static-cost note while a form or
     talent is simulated.
2. **The decision strip.**
   - **The chip.** It reads `SUGGESTED` over `Rank N`, or `SIMULATED` while any what-if value is
     set. Its hover gives the suggested rule's sentence.
   - **One comparison with the highest known rank,** made from the rows. An example is "vs Rank 12
     (your highest): 3% more healing per mana, 45% of the heal, the same cast.", and when the
     suggested rank is the highest it reads "Your highest rank is also the best per mana.".
     Lifebloom with tick and bloom overheal measured gets the old callout's roll-or-bloom note as
     a second sentence.
   - **The right column (156 px).**
     - **After overheal** is the old Effective checkbox. It writes `db.effectiveMode`, with the
       same three-line tooltip in the new words.
     - **The measured share** sits under the checkbox: `Overheal:FamilyFraction`, `31% measured`,
       or `not measured yet`.
     - **What if...** unfolds the Simulate strip between the strip and RANKS, and a second click
       folds it. It starts folded, and the values stay set while it is folded.
   - The gold callout and the hint line are gone.
3. **RANKS.**
   - **The table.** It is T81's rank table (moved here from `UI/Dashboard.lua`, below), with
     M6's words: `Rank`, `Lvl`, `Mana`, `Heal` (`Total` for a HoT, Regrowth or Lifebloom, as
     Forever's rule), `Per mana` (the bar), `Per sec`, `Cast` and `Casts`.
   - **Casts** reads `inf` when regen keeps up and `999+` past 999. Before, it printed the raw
     count, for example 3895.
   - **Headers.** Each one explains itself in one sentence (T78's shape) instead of
     `Tip:Columns`' glossary. Per mana, Per sec and Heal add the After-overheal sentence while it
     is on. Casts names the mana and the casting mp5 it counts from, so the hint line's numbers
     live there now. Cast names the Nature's Grace `*`.
   - **Selection.** A click selects a rank: the white 2-px bar (`selection = "bar"`), and the card
     follows. The suggested row keeps its fill and accent bar. The selection is kept per family
     (Lifebloom's rolling rows by id and stack count) and defaults to the suggested rank.
   - **The pane's note.** Its right side says `live: gear, talents, downrank rules`, or, while
     simulating, `what if: ...` in the accent.
   - **Tag hovers.** They say Per mana / Per sec where they said HPM / HPS.
4. **The card.**
   - **The title** is `RANK N` (`RANK 1, ROLLED x3` for a rolling row), with
     `learned at L - you are P` (`learn at L` when not learned) at the right.
   - **A base line** from `Data/SpellData.lua`, for example "Base heal 2364 - 2799, before your
     +healing and the rules below."
   - **Label / value pairs in two 300-px columns,** by shape:
     - direct: Heals (the range, `(avg with N% crit)`) and Crit;
     - HoT: Tick (`x4, every 3 s`) and Total;
     - Regrowth: Direct, Crit, Over time and Total;
     - Lifebloom: Tick, Bloom and Total, or Rolled and Tick for a rolling row;
     - then, for every shape, Downrank (`N% of your +healing counts`), Cost, and After overheal
       when the rank has a measurement.
   - **Where the numbers come from.** They are `RankMath:Explain`'s, the same row the derivation
     hover shows.

### `UI/Dashboard.lua` (TBC)

- **The rank table** section (T81's `CreateRankTable` and its helpers) moved to
  `UI/SpellsView_TBC.lua`, unchanged except for the words above and an optional third argument
  (`onClick`, `selection`).
- **The Spells group's one pane** is the view: `CreateSpellsView(content, 912, Refresh)` at
  content -6 to the bottom. It is shared by all four family views, which stay along the top
  until C5.
- **Gone from the window:** the `Effective` checkbox at its top right and the Simulate strip.
- **Refresh.**
  - On Spells it calls `spellsView:Render(currentFamily)`, or shows the non-druid message as
    before.
  - The stats, callout and hint lines and the recap are now Reports' only, with their text as
    before. The regen line moved into `StatsLine()`.
- **Without `UI/SpellsView_TBC.lua` loaded,** the Spells group has no pane. That is the
  `AdoptSimPanel` pattern; `tools/wincheck.lua`'s TBC half loads the dashboard that way.
- **The sizes per group are unchanged** (1036 x 646, fixed). See deviation 1.

### `UI/Dashboard_Simulate.lua` (TBC)

- The strip's title is `What if:`.
- Its greys are token reads (`label` for the labels, `muted` for the placeholders).
- `api:IsShown()` and `api:Active()` (any what-if value set) are new.
- The view places the strip (`ClearAllPoints`, its own anchor and width) and shows it.

### `tools/dashui.lua`

- The view is loaded before `UI/Dashboard.lua`, through a guard that skips a file that does not
  exist. That lets the suite run on the parent and fail check by check.
- Eight existing checks read the view instead of the old hint line (`HPM heal per mana`):
  `ShownText("^RANKS$")`, the `What if...` button, and no `SUGGESTED` / `SIMULATED` over
  Settings. Their names are unchanged.
- T81's header check reads the column's own sentence. T81's Effective check is renamed.
- **Six new checks** (`T83: ...`), each under `pcall`:
  1. the header: the name, the shape / rank / cast line, the mana and +healing, the icon, and
     none of the four prose lines;
  2. the chip says `SUGGESTED` `Rank 6`, the comparison line's exact shape, the After overheal
     box and `not measured yet`, and no `Effective` button;
  3. the suggested row's fill (0.10) and accent bar, selected by default with the white bar and
     its card. A click on R12 moves the white bar and the card (`RANK 12`; Tick, Total,
     Downrank, Cost; the base line), and never the fill;
  4. Casts reads `999+` (R1 at 200000 what-if mana and 0 casting) and `inf` on all 13 rows at
     100000 casting mp5. The chip says `SIMULATED`, and the header's mana and `0 mp5 casting` are
     in the accent;
  5. What if... is folded on first sight. It unfolds (Clear and `What if:` shown, the view 58 px
     taller), a value typed in it turns the chip `SIMULATED` and `+1500` accent, and it folds
     again with the value kept;
  6. After overheal writes `db.effectiveMode` and puts the accent on `Total` and `Per mana`. Off
     again, a HoT's value header is plain `Total` and the last numeric header is `Casts`.

## Failing first (on the parent `03cc1bd`)

The parent tree was taken with `git archive 03cc1bd`, and this branch's `tools/dashui.lua` was
copied into it:

```
=== dashui (tbc) on 03cc1bd     exit 1   67 ok, 13 failed
  FAIL the rank table is built for it
  FAIL the Simulate strip is with the spells
  FAIL going back to Spells restores the rank table
  FAIL the rank table comes back with Spells
  FAIL and so does the what-if strip
  FAIL switching family keeps the table visible
  FAIL T83: the header names the family, ... - attempt to index local 'v' (a nil value)
  FAIL T83: the chip says SUGGESTED Rank 6 ... - attempt to index local 'v' (a nil value)
  FAIL T83: the suggested row keeps its fill and bar; ... - attempt to index local 'api' (a nil value)
  FAIL T83: Casts reads 999+ past 999 and inf ... - attempt to index local 'api' (a nil value)
  FAIL T83: What if... unfolds the Simulate strip ... - attempt to index local 'api' (a nil value)
  FAIL T83: After overheal puts the accent ... - attempt to index local 'v' (a nil value)
  FAIL T81: every header label explains the columns; ... - hits=8 glossary=What the columns mean
```

**Mutations** (a scratch copy of this branch):

- **M1.** `CastsText` loses its `999+` cap. This fails
  `T83: Casts reads 999+ past 999 ...` (`R1=8695`).
- **M2.** The what-if strip starts shown. This fails `T83: What if... unfolds ...` (`shut=false`).
- **M3.** The chip always says `SUGGESTED`. This fails the Casts / SIMULATED check
  (`simulated=false`) and the What if... check (`typed=false`).

## Expected values that changed (`tools/dashui.lua`, tbc)

| Check | Old expectation | New expectation |
|---|---|---|
| `the rank table is built for it` | the hint line `HPM heal per mana` painted | the view's `RANKS` pane shown |
| `the Simulate strip is with the spells` | a `Clear` button exists | `What if...` and `Clear` exist |
| `going back to Spells restores the rank table` | `HPM heal per mana` painted | `RANKS` shown |
| `the rank table's header lines are hidden in Settings` | no shown `HPM heal per mana` | no shown `RANKS`, `SUGGESTED`, `SIMULATED` |
| `no rank-table hint over the simulator` | no shown `HPM heal per mana` | no shown `RANKS` |
| `nor when arriving from Reports` | ... nor `HPM heal per mana` | ... nor `RANKS` |
| `nor over the settings` | no hint, no `Clear` | no `RANKS`, no `Clear`, no `What if...` |
| `the rank table comes back with Spells` | `HPM heal per mana` shown | `RANKS` shown |
| `and so does the what-if strip` | `Clear` shown | `What if...` shown (the strip is folded) |
| `switching family keeps the table visible` | `HPM heal per mana` shown | `RANKS` shown |
| `T81: every header label explains the columns; ...` | the Per mana header's tooltip title `What the columns mean` | title `Per mana`, line 2 `Healing for each point of mana.` |
| `T81: Effective mode puts the accent on Heal/cast, HPM, HPS ...` -> `T81: After overheal puts the accent on Heal, Per mana, Per sec ...` | (renamed only) | the same assertions |

## Suites, before and after

- **Before:** `tools/check.sh` on `03cc1bd` gave **71 runs, all passed**, 66 counted against
  66.
- **After:** `tools/check.sh` on this branch gave **71 runs, all passed**, 66 counted against 66,
  with one note: `dashui/tbc: 80 assertion(s), 74 expected`.

| Suite | Before | After |
|---|---|---|
| `dashui/tbc` | 74 | **80** |
| `wincheck/tbc` | 4 | 4 (it loads `UI/Dashboard.lua` without the view: the Spells group has no pane there, and the sizes are unchanged) |
| every other suite | as `tools/data/expected-counts.json` | equal |
| `apicheck` | 0 findings, 8 Forever TOCs, 59 files, 48 globals | equal (no Forever file changed) |
| `textcheck` | 0 findings, 9 TOCs, 95 files | equal. With the TOC line below added in a scratch copy, it gave 0 findings in 96 files |

`luac -p` passes on `UI/SpellsView_TBC.lua`, `UI/Dashboard.lua`, `UI/Dashboard_Simulate.lua`
and `tools/dashui.lua`. Every changed shipped file is ASCII.

## Integrator lines

**TOC (`SpellTuner_TBC.toc` only):** add `UI\SpellsView_TBC.lua` right before `UI\Dashboard.lua`
(after `UI\BindingsWindow.lua`). It needs `UI\Dashboard_Rows.lua` and `UI\Dashboard_Simulate.lua`
at build time (`MD_READY`), and both are listed earlier. No Forever TOC changes, and no module
TOC changes.

**`tools/data/expected-counts.json`:** `"dashui/tbc": 80`.

**CLAUDE.md:**

- **A new row after `UI/Dashboard_Simulate.lua`:**
  > | `UI/SpellsView_TBC.lua` | **The TBC Spells view** (T83, C3 of `docs/PLAN-refactor-ux.md`,
  > review U6, mockup M6; TBC TOC only, before `UI/Dashboard.lua`): `MD.DashboardParts.CreateSpellsView(parent, width, onChange)`
  > -- one family's view in the Forever structure with RankMath's numbers, inside one scroll
  > frame: the header (icon, name, shape / rank / cast, the mana and +healing at the right, every
  > what-if stat in the accent; the old stats line -- regen, Dreamstate, relic, Tree aura -- is
  > the +healing hover), the strip (the SUGGESTED chip, SIMULATED while a what-if value is set;
  > one comparison with the highest known rank; "After overheal" -- `db.effectiveMode`, the old
  > Effective -- with the measured share; "What if..." unfolding UI/Dashboard_Simulate.lua's
  > strip), RANKS (`MD.DashboardParts.CreateRankTable`, moved from `UI/Dashboard.lua`: Heal /
  > Total, Per mana with its bar, Per sec, Cast, Casts reading `inf` / `999+`, the tags, a
  > sentence on every header; a click selects a rank, the white bar, the card following) and the
  > rank card (base numbers from `Data/SpellData.lua`, then label / value pairs by shape:
  > Heals / Crit, Tick / Total, Direct / Over time, Tick / Bloom, Downrank, Cost, After overheal
  > -- `RankMath:Explain`'s) |
- **The `UI/Dashboard.lua` row:** append
  > **T83 (C3):** the Spells group's one pane is `UI/SpellsView_TBC.lua`'s view (the four
  > families stay along the top until C5); the rank table moved there; the Effective checkbox
  > and the Simulate strip left the window (After overheal and What if... in the view); the
  > stats / callout / hint lines and the recap are Reports' only; without the view loaded the
  > Spells group has no pane.
- **The `UI/Dashboard_Simulate.lua` row:** append
  > **T83 (C3):** folded behind the Spells view's "What if..." (the view places and shows it),
  > titled `What if:`, token greys, `api:Active()` (any what-if value set; the chip then says
  > SIMULATED).
- **The `UI/Dashboard_Rows.lua` row:** in T81's sentence, "the glossary (`Tip:Columns`)" becomes
  "a sentence of its own (T83)". The file's own comment at line 111 says the same about
  `Tip:Columns`; it is not C3's file, so it is fixed when the file is next touched.
- **The `UI/Tooltip.lua` / `UI/Tip_TBC.lua` row,** if it names `Columns` among TBC's builders: add
  "(`Tip:Columns` has had no caller since T83)".

**docs/TOOLS.md** section 1, `dashui.lua`:

- Append: "Since **T83** (80): the TBC Spells view -- the header (shape / rank / cast, mana,
  +healing, no prose lines), the SUGGESTED chip and its comparison line, the suggested row's fill
  and bar with the selection's white bar and the card following a click, Casts reading `999+` /
  `inf` and SIMULATED under a what-if value, What if... folding the Simulate strip, After
  overheal; the old checks read the view's RANKS pane and What if..., not the hint line".
- In T76's sentence, "the TBC rank table's eight labelled columns carry the glossary" becomes
  "carry a sentence each".

**docs/DECISIONS.md**, a paragraph after "One clock look":

> **TBC's Spells view is the Forever structure** (2026-10-01, T83 / C3; review U6, mockup M6,
> decision 10). The four prose lines above the TBC rank table are gone.
> - The stats line splits into the header's mana and +healing (its regen, relic and Tree-aura
>   detail is the +healing line's hover).
> - The gold callout is one comparison line beside a SUGGESTED chip.
> - The glossary hint is a sentence on each column header.
> - The Simulate strip folds behind "What if...". While any what-if value is set, the chip says
>   SIMULATED and the header shows the changed stats in the accent.
>
> "Effective" is "After overheal", with the family's measured share under it. The column words
> are M6's: Heal (Total over time), Per mana, Per sec, Casts. Casts reads `inf` when regen keeps
> up and `999+` past 999, where it printed the raw count. A click selects a rank (the white bar)
> and a card below the table shows that rank's base numbers, its heal and crit, the downrank
> share of +healing and the cost. The window keeps TBC's 1036 x 646 for Spells, and the view
> scrolls inside it. The recap line ("Last fight: ...") stays on Reports only.

**docs/TESTING.md** section 44, after item 32 (TBC, C3), under a "Wave C-c (T83; TBC)" line:

> 33. **TBC Spells view (C3).**
>     - `/md` -> Spells -> Healing Touch: a header with the icon, "Healing Touch", "Direct heal -
>       Rank N of M known - 2.9 s cast ...", your mana and +healing at the right. No stats line,
>       no gold line, no grey hint line above the table.
>     - Point at the +healing line: your regen, crit, relic and Tree aura.
>     - The chip says SUGGESTED / Rank N, and the line beside it compares that rank with your
>       highest (or says your highest is also the best).
>     - The table's headers read Heal (Total on Rejuvenation, Regrowth and Lifebloom), Per mana,
>       Per sec, Casts. Cheap ranks read `inf` or `999+` under Casts. Point at a header: one
>       sentence.
>     - The suggested row has the faint fill and orange bar, and a white bar marks the selected
>       one. Click another rank: the white bar and the card below move to it, and the fill stays.
>       The card: RANK N, "learned at L - you are P", the base heal, then Heals / Crit /
>       Downrank / Cost (Tick / Total on a HoT).
>     - Tick After overheal: the healing headers turn orange (the share under the box says
>       "N% measured" or "not measured yet").
>     - Click What if...: the what-if boxes appear between the strip and the table. Type +heal
>       2000 and leave the box: the chip says SIMULATED and the header's +healing turns orange.
>       Click What if... again: the boxes fold away and the values stay. Clear resets them.
>     - With 13 ranks the view scrolls with the wheel.
>     - Reports -> Waste / Review: the lines above the list and the "Last fight" line at the
>       bottom are as before.

**docs/HISTORY.md**: the integrator's wave entry.

## Deviations

1. **The Spells group keeps the window's 1036 x 646.** M6 drew the view in an 860 x 560 window,
   and C1's `SIZES` comment said "C3 gives Spells its own size". But `tools/wincheck.lua`'s TBC
   check pins every TBC group at 1036 x 646 (fixed), and that suite is not C3's file. The view is
   720 wide inside the 912 content and scrolls, as M6 says. A later task that owns `wincheck` can
   give Spells its own size by changing one row of `SIZES` in `UI/Dashboard.lua`.
2. **The card's first line is not a quoted spell description.** M6 drew the game's text in
   quotes ("Heals a friendly target for 936 to 1121."). The TBC line reads no descriptions; the
   numbers come from `Data/SpellData.lua`. A sentence made to look like the game's would be text
   the game never said. So the line reads "Base heal 936 - 1121, before your +healing and the
   rules below.", in SpellTuner's words, with the same numbers and the same "then the rules"
   sentence.
3. **The rank table moved into the view's file.** `MD.DashboardParts.CreateRankTable` (T81's,
   in `UI/Dashboard.lua`) is now in `UI/SpellsView_TBC.lua`, which C3 owns, with a third optional
   argument (`onClick`, `selection`). `dashui`'s T81 checks build it as before. Its column words
   changed to M6's (T81's deviation 1 left them to C3).
4. **Column tooltips are per column.** Each header gives one sentence of its own, as on
   Forever, instead of `Tip:Columns`' glossary. The glossary named the old words, and
   `UI/Tip_TBC.lua` is not C3's file. `Tip:Columns` now has no caller, and
   `UI/Dashboard_Rows.lua`'s comment at line 111 still names it. Both are left for the task that
   next owns those files (integrator line above).
5. **The old stats line moved into a hover.** M6 says regen moves to the clock's tooltip, which
   C4 did behind Shift. The view also keeps every term of the old line (regen, the spirit / gear
   split, Dreamstate / measured mp5, relic, Tree aura, the static-cost note) in the +healing
   line's hover, so nothing the author could read before is lost.
6. **The recap line is on Reports only.** "Last fight: ..." sat under the rank table. The view
   fills the pane and scrolls, and M6 has no recap, so it shows on Reports (where it also was)
   and not on Spells.
7. **The card's pairs by shape.** M6 drew Healing Touch's four (Heals, Crit, Downrank, Cost). The
   other shapes take the spell tooltip's parts (`Tip:Spell`'s words): Tick / Total, Direct / Crit
   / Over time / Total, Tick / Bloom / Total, and Rolled for Lifebloom's rolling rows. Every shape
   adds After overheal when the rank has a measurement.
8. **The Lifebloom roll note** (the old callout's "keep the stack rolling / let it bloom", shown
   when tick and bloom overheal are both measured) is a second sentence on the comparison line,
   so it is not lost with the callout.
9. **No in-place refresh split.** Forever's view updates the live numbers in place on its 2-s
   tick. TBC's view re-renders fully every 2 s, as the TBC rank table always did (RankMath hands
   out fresh rows on every `Compute`). The pitch (20 / 22) is read when the table is built, as in
   T81.
10. **`dashui` loads its UI files through an existence guard,** so the suite runs on the parent
    and fails check by check (T81's fallback did the same for `CreateRankTable`). The six new
    checks run under `pcall` for the same reason.
11. **The view's `width` argument is accepted but not used.** The view is laid out at 720, M6's
    width. C5 may size it from the argument when the rail takes the left edge.
