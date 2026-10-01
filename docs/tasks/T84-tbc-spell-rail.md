# T84 -- the spell rail on TBC (plan C5)

Status: **built** 2026-10-01 on branch `plan/C5` (base `1451738`), wave C-d of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. **The branch needs its TOC lines (below).**
The task adds three files: `Spells/Families_TBC.lua` (TBC), `UI/SpellRail.lua` (all three main
TOCs) and `Spells/Tabs.lua` on the TBC TOC. All TOCs are integrator-owned.

- **Without the lines, every Forever suite fails at load.** `UI/SpellsPane_Forever.lua` installs
  `MD.SpellRail` when it loads, and the Forever TOCs do not list `UI/SpellRail.lua` yet. The same
  goes for `probecheck/tbc`, which loads the Forever line inside its run, and for `tabscheck/tbc`,
  which reads `Spells/Tabs.lua` from the TBC TOC.
- **`dashui/tbc` passes either way** (84). It loads the two `Spells/` files itself, with an
  existence guard, when the TBC TOC does not list them.
- **The TOCs were not edited in the worktree.** Every suite was run in a scratch copy of the
  worktree with the TOC lines below applied. The failing-first runs used the parent `1451738`,
  taken with `git archive`, with this branch's two suites copied in.

## The task (docs/PLAN-refactor-ux.md section 5.C, C5; section 7.1; mockup M4 layout B and M6)

> TBC's Spells group becomes a rail group (`layout = "rail"`), as on Forever: **Overview** first,
> then one row per family in the player's own list, with `+ Add`, the Undo line, drag to reorder,
> one `x`, and the right-click row menu (Move up / Move down / Remove; P33's rail). C3's four view
> tabs go.
> (a) **The list model.** `Spells/Tabs.lua` is now on the TBC TOC too, with its rules unchanged.
> Its book comes through one seam, `Tabs.source`, which defaults to `MD.Book:Get()`. On TBC the
> source is new `Spells/Families_TBC.lua` [...] rebuilt on `SPELLS_REBUILT`, which then runs the
> reconcile [...]
> (b) **The rail glue** moves out of `UI/SpellsPane_Forever.lua` into new shared
> `UI/SpellRail.lua` [...] Forever's pane calls it and shows exactly what it shows today.
> (c) **TBC's Overview** is built in `UI/SpellsView_TBC.lua`: the My spells table on C2's table
> options, with TBC's numbers. [...] a row click opens that family. A family's view is C3's view
> for that key. `/md` opens on Overview the first time, then on the remembered row.

The author chose the rail for TBC when approving the mockups (7.1: "TBC gets the spell rail too
... M6's view tabs are replaced by the rail"; rail hover layout B: one `x`, Move up / Move down /
Remove in a right-click menu, drag still reorders).

## What was built

### `Spells/Tabs.lua` (both lines now): one seam

- **`Tabs.source`** is a function that answers the book an edit reads when its caller passes
  none (`Add`, `Reset`, `Resolve`). It defaults to the new `Tabs.BookSource`, which is
  `MD.Book:Get()`, so Forever reads exactly what it read before.
- The file header's "Forever TOCs only" is gone. It explains the seam and that the rules are
  unchanged. No rule changed: the seed, the reconcile, Add / Remove / Move / Undo / Reset and the
  store are the T35 code byte for byte.

### `Spells/Families_TBC.lua` (new, TBC only): the TBC book

`MD.FamiliesTBC` holds the families the TBC rank table has: `SD.familyOrder` without the
excluded Tranquility and Swiftmend, so Healing Touch, Lifebloom, Rejuvenation and Regrowth. They
are in Book's family shape:

- `key` is SpellData's family id (`"HealingTouch"`), `name` its label (`"Healing Touch"`), and
  `kind = "heal"`.
- `ids` lists every rank's id, lowest rank first.
- `ranks` has one entry per rank: `id`, `rank`, `level`, `known` (from SpellData's known-rank
  index), `cost.amount` (the static base cost) and `icon` (read through `MD.API.SpellTexture`).
- `maxKnown` is the highest known entry.
- `spells` maps each id back to its family key. That is what `Tabs:Resolve` looks a renamed key
  up by.

A character that is not a druid gets an empty book, so its rail holds Overview only.

`FT.Source` is installed as `Tabs.source` when the file loads. `FT:Get()` builds the book on
first use. **`SPELLS_REBUILT`** (login, or a rank trained) rebuilds the book and then runs
`Tabs:Reconcile`, the job `BOOK_CHANGED` does on Forever. So on a fresh TBC character the seed is
the known heal families by learn level: Healing Touch, Rejuvenation, Regrowth, Lifebloom. A
family trained later is appended with the new dot (decision 2), and a removed one stays removed.

### `UI/SpellRail.lua` (new, all three main TOCs): the rail's glue

It moved out of `UI/SpellsPane_Forever.lua`. `MD.SpellRail.Install(pane, spec)` puts these
methods on a pane:

- `Views` (Overview, then one row per listed family, or a greyed stale row);
- `RefreshRail` (a repaint in place when the row ids are unchanged, else `nav:SetViews`);
- `ListChanged`, `Remove`, `Undo`, and `RefreshFooter` with its builder (`+ Add`, and the
  `<spell> removed  [Undo]` line);
- `CanDrop` and `Drop` (the spellbook drop, only where `MD.API.CursorInfo` exists);
- the picker (`RefreshPicker`, `OpenPicker`, refused in combat, one ESC entry);
- `RailFontsChanged`;
- `Group` (the rail group's definition: `MY SPELLS`, the row height, the footer, `onMove` /
  `onRemove` for the kit's drag, its `x` and its right-click menu, the drop);
- `Attach`.

The pane keeps its fields where they were (`nav`, `addBtn`, `undoText`, `undoBtn`, `picker`,
`preview`). `spec` gives the parts that differ by line:

- `source()`, the book;
- `row(fam, key, ctx)`, a listed family's text, icon, tag and tooltip; the glue adds `id`, `key`
  and the new dot;
- `prepare()`, optional, computed once per `Views`;
- `label(key)`, optional, how a bare key reads in the Undo line and a stale row;
- `pickerTip`, optional, the picker's tip line, hidden when absent.

`SpellRail.FamilyKey` and `SpellRail.VIEW_PREFIX` (`"fam:"`) are shared too. The code is the
T36 / T77 code, moved; the one addition is that the picker's search also matches a family's
`name` (on Forever the name is the key, so nothing changes there).

### `UI/SpellsPane_Forever.lua` (Forever): installs the glue

The moved code is deleted, along with its metrics and the `AllPassive` / `InCombat` /
`FamilyKey` helpers. The pane installs the glue:

- **the source** is `MD.Book:Get()`;
- **the row** is its icon, `R<suggested rank>` and `RailTip`;
- **the picker's tip** is "Tip: drag a spell from your spellbook onto the list.".

`FontsChanged` calls `RailFontsChanged`. Everything else (Overview, a family's view, the preview,
`/st spell`, `BOOK_CHANGED`) is unchanged. **`spellsui` is byte-identical** (50, every line equal
to the parent's output, timings included).

### `UI/Dashboard.lua` (TBC): the Spells group is the rail

- **The rail.** `MD.SpellsTBC` carries the glue over `MD.FamiliesTBC:Get()`:
  - a row's tag is the suggested rank from `RankMath:Compute()` (computed once per `Views`);
  - its hover gives `Suggested  Rank N of M known` and `Per mana  N.NN`, as on Forever;
  - its label is SpellData's.
  - When the glue is not loaded (`tools/wincheck.lua`'s TBC half loads the dashboard without
    it), the group is a rail with Overview only.
- **`Groups()`** opens with that group. C3's four view tabs are gone.
- **One host frame for every Spells view.** It sits right of the rail and holds the Overview
  pane and C3's family view. `Refresh` shows Overview for `overview` and the family view for
  `fam:<key>`, and keeps the non-druid message.
- **The first open and the remembered row.** `OnShow` opens Overview the first time
  (`nav:Select("spells", nil)`, the rail's first row) and the remembered row after that.
  `DefaultFamily` (the most-cast family) and the unused `userPicked` are gone.
- **Old paths.** A bare family named by a path saved before C5 (`spells / Regrowth`), or by a
  caller (`MD:SelectView("spells", "Regrowth")`), is mapped to its row `fam:Regrowth` in
  `OnShow` and `MD:OpenMainWindow`.
- **The dot.** Opening a family's row clears its new dot (`Tabs:MarkSeen`, then the rail
  repaints).
- **The rail refreshes** on `SPELLS_REBUILT` (after the families reconciled, since they
  registered first), `TALENTS_CHANGED`, `FORM_CHANGED` and a gear change while the window is
  shown, because those move the suggested-rank tags.

### `UI/SpellsView_TBC.lua` (TBC): Overview

`MD.DashboardParts.CreateSpellsOverview(parent, width, onOpen)` builds Overview: the `OVERVIEW`
title, then My spells in one scroll frame.

- **The table** is C2's options set: Arial Narrow numbers right-justified, 20-px rows under a
  22-px header with its rule, zebra, the bar marker, and a sentence on each header.
- **One row per listed family** in the list's order, with TBC's numbers from
  `RankMath:Compute()`:
  - the icon and the name;
  - the suggested rank (in the accent), its Heal, Per mana, Per sec and Casts (`inf` / `999+`,
    C3's words);
  - a rule, then the highest known rank, its Heal and its Per mana.
  - With After overheal on, the healing numbers are the measured ones, as in RANKS.
- **A row** is hovered with the suggested rank's derivation, and a click opens that family's
  view (`MD:SelectView("spells", "fam:<key>")`).
- **A key the families do not have** reads greyed, "not in your spellbook".
- **Under the table:** "Click a row to open that spell.", or "Your list is empty - + Add on the
  left."

### `tools/tabscheck.lua`: declared for both flavours

The Forever half is unchanged (24, byte-identical). Under tbc it adds four checks and ends:

1. **A level 70 druid's families seed in order.** With every rank known, the seed is
   `HealingTouch,Rejuvenation,Regrowth,Lifebloom`, in Book's shape. Tranquility and Swiftmend
   are not in the book, and the store's kind is `heal`.
2. **A removed family stays removed across `SPELLS_REBUILT`.** Regrowth, removed, is still gone
   after two rebuilds, and is marked removed.
3. **A family trained later is appended with the new dot.** Seeded without Lifebloom, then
   Lifebloom trained: `SPELLS_REBUILT` appends it, and it is new while Regrowth is not.
4. **The sources.** On TBC the installed source is `MD.FamiliesTBC`'s. The default source
   (`Tabs.BookSource`) is `MD.Book:Get()`: with a stand-in `MD.Book` and the seam put back on the
   default, `Add` and `Resolve` read the stand-in's family.

### `tools/dashui.lua`

- **`UI/SpellRail.lua` is loaded** after `UI/Dashboard_Rows.lua`. The two `Spells/` files are
  loaded before the UI files when the TOC does not list them (an existence guard each).
- **New helpers:** `SpellsRail`, `RailRow`, `RailIds` and `RailClick`.
- **Seven checks were re-baselined** to the rail (table below).
- **Four new checks** (`T84: ...`), each under `pcall`:
  1. **The Spells group is a rail.** It has no view row and is titled `MY SPELLS`. The rows are
     `overview` (fixed), then `fam:HealingTouch`, `fam:Rejuvenation`, `fam:Regrowth` and
     `fam:Lifebloom`, each tagged with the rank RankMath suggests, and `cdb.spellTabs` is
     seeded.
  2. **Overview lists one row per listed family,** in the list's order. Each row has its
     suggested rank (the same as RankMath's) and its highest; the shown Suggested cell for
     Rejuvenation is `R6`, and the family view is hidden.
  3. **A rail row opens C3's view.** The `fam:Regrowth` row opens the view on Regrowth with
     RANKS shown and Overview hidden. A click on Overview's Lifebloom row opens Lifebloom's
     view. The bare `MD:SelectView("spells", "Rejuvenation")` lands on `fam:Rejuvenation`.
  4. **`x` then Undo puts the row back.** The `x` on Rejuvenation removes it: the row goes,
     `removed` is set, the footer reads `Rejuvenation removed` with Undo, and Overview follows
     (3 rows). Undo puts it back at its old place, the line goes, and Overview has 4 rows again.

## Failing first (on the parent `1451738`)

`git archive 1451738`, with this branch's `tools/tabscheck.lua` and `tools/dashui.lua` copied in:

```
=== tabscheck (tbc) on 1451738   exit 1   0 ok, 4 failed
  FAIL tbc: a level 70 druid's families seed Healing Touch, Rejuvenation, Regrowth and Lifebloom - raised: tools/tabscheck.lua:83: attempt to index upvalue 'Tabs' (a nil value)
  FAIL tbc: a removed family stays removed across SPELLS_REBUILT - raised: ... (the same)
  FAIL tbc: a family trained later is appended with the new dot - raised: ... (the same)
  FAIL tbc: the TBC source is installed; the default source is MD.Book:Get() (Forever's) - raised: tools/tabscheck.lua:156: ...
=== tabscheck (forever) on 1451738   24 ok, 0 failed
=== dashui (tbc) on 1451738      exit 1   76 ok, 8 failed
  FAIL a family rail row exists -
  FAIL clicking a family selects it - HealingTouch
  FAIL going back to Spells shows its first row, Overview
  FAIL Overview comes back with Spells
  FAIL T84: the Spells group is a rail with Overview first, then the seeded families - attempt to index field 'SpellsTBC' (a nil value)
  FAIL T84: Overview lists one row per listed family, with its suggested rank - attempt to index local 'api' (a nil value)
  FAIL T84: a rail row opens C3's view for that family - attempt to index a nil value
  FAIL T84: x removes a rail row and Undo puts it back where it was - attempt to index local 'row' (a nil value)
```

**Mutations** (in the scratch copy, with the TOC lines):

- **M1.** `Spells/Families_TBC.lua`'s `SPELLS_REBUILT` handler stops reconciling. This fails
  `tbc: a family trained later is appended with the new dot` (`now=HealingTouch,Rejuvenation,Regrowth`).
- **M2.** `Spells/Families_TBC.lua` stops installing `Tabs.source`. This fails all four tbc
  checks (`installed=false`, and the seed reads no book).
- **M3.** `UI/SpellRail.lua`'s `Undo` stops calling `ListChanged`. This fails
  `T84: x removes a rail row and Undo puts it back` (`back=false`).
- **M4.** `UI/Dashboard.lua` stops calling `SpellsTBC:Attach(nav)`, so there is no footer and
  no nav on the glue. This fails 8 dashui checks, among them three of the four `T84:` checks.

## Expected values that changed (`tools/dashui.lua`, tbc)

| Check | Old expectation | New expectation |
|---|---|---|
| `the rank table is built for it` | `RANKS` shown on first open (a family view) | the first open is Overview; after a click on the `fam:HealingTouch` rail row, `RANKS` is shown |
| `a family button exists` -> `a family rail row exists` | a `Regrowth` view button | a `fam:Regrowth` rail row |
| `clicking a family selects it` | `uiPath[2] == "Regrowth"` | a click on the rail row; `uiPath[2] == "fam:Regrowth"` |
| `going back to Spells restores the rank table` -> `going back to Spells shows its first row, Overview` | `RANKS` shown | `OVERVIEW` shown and `RANKS` not (the group button opens its first row) |
| `the rank table comes back with Spells` -> `Overview comes back with Spells` | `RANKS` shown | `OVERVIEW` shown |
| `and so does the what-if strip` | `What if...` shown after the group click | `What if...` shown after a click on the `fam:HealingTouch` row |
| `switching family keeps the table visible` | a click on the `Regrowth` view button | a click on the `fam:Regrowth` rail row |

`it opens on a spell` keeps its expectation (`uiPath[1] == "spells"`); its detail now reads
`spells/overview`. The six T83 checks are unchanged: they name a bare family
(`MD:SelectView("spells", "Rejuvenation")`), which the dashboard maps to the family's row.

## Suites, before and after

- **Before:** `tools/check.sh` on `1451738` gave **71 runs, all passed**, 66 counted against
  66.
- **After:** `tools/check.sh` in the scratch copy with the TOC lines gave **72 runs, all
  passed**, 67 counted against 66, with two notes: `dashui/tbc: 84 assertion(s), 80 expected`
  and `tabscheck/tbc: 4 assertion(s), not in the expected counts`.

| Suite | Before | After |
|---|---|---|
| `dashui/tbc` | 80 | **84** |
| `tabscheck/forever` | 24 | 24 (output byte-identical) |
| `tabscheck/tbc` | (not run) | **4** |
| `spellsui/forever` | 50 | 50 (output byte-identical: every string equal) |
| `navui/tbc` | 46 | 46 (byte-identical; the rail kit is untouched) |
| `wincheck/forever`, `wincheck/tbc` | 66, 4 | 66, 4 (byte-identical) |
| `themecheck/forever`, `themecheck/tbc` | 37, 9 | 37, 9 (the token-read count in one detail line 174 -> 179: the new files' `UI.Hex` / `UI.RGB` reads, every token known) |
| `releasecheck` | 21 (tbc 68 files, forever 34) | 21 (tbc **71**, forever **35**) |
| `apicheck` | 0 findings, 59 files | 0 findings, **60** files |
| `textcheck` | 0 findings, 96 files | 0 findings, **98** files |
| every other suite | as `tools/data/expected-counts.json` | equal; the outputs differ only in table addresses and timings |

Without the TOC lines (the committed tree), `tools/check.sh` fails 32 runs. Every Forever suite
fails at load (`MD.SpellRail` is nil when `UI/SpellsPane_Forever.lua` loads), as do
`probecheck/tbc` and `tabscheck/tbc`. `dashui/tbc` passes (84).

`luac -p` passes on all eight changed files. Every changed shipped file is ASCII.

## Integrator lines

**TOCs:**

- **`SpellTuner_TBC.toc`:** after `Engine\RankMath.lua`, add `Spells\Tabs.lua` and then
  `Spells\Families_TBC.lua`. `Families_TBC` sets `MD.Tabs.source` at load, so it must follow
  `Tabs`. After `UI\Dashboard_Rows.lua`, add `UI\SpellRail.lua`. It must come before
  `UI\SpellsView_TBC.lua` and `UI\Dashboard.lua`, which installs it at load.
- **`SpellTuner_Mainline.toc` and `SpellTuner.toc`:** after `UI\Dashboard_Rows.lua`, add
  `UI\SpellRail.lua`, before `UI\SpellsPane_Forever.lua`, which installs it at load.
- No module TOC changes.

**`tools/data/expected-counts.json`:** `"dashui/tbc": 84` and a new `"tabscheck/tbc": 4`.

**`tools/data/import-forever-sv.lua`:** no change needed (nothing it stores changed). The
scratch run's `importcheck` passed against the committed fixture.

**CLAUDE.md:**

- **The `Spells/Tabs.lua` row:** "pure, Forever TOCs only" becomes "pure, both TOCs since T84";
  append
  > **T84 (C5):** the book an edit reads when its caller passes none comes through one seam,
  > `Tabs.source` (default `Tabs.BookSource`, `MD.Book:Get()`); on TBC
  > `Spells/Families_TBC.lua` installs its own; the rules are unchanged. TBC TOC after
  > `Engine/RankMath.lua`.
- **A new row after `Spells/Tabs.lua`:**
  > | `Spells/Families_TBC.lua` | **The TBC spell list's book** (T84, C5 of
  > `docs/PLAN-refactor-ux.md`, section 7.1; TBC TOC only, right after `Spells/Tabs.lua`):
  > `MD.FamiliesTBC` -- the TBC rank table's druid families (`SD.familyOrder` without the
  > excluded Tranquility and Swiftmend) in Book's family shape: `key` (SpellData's family id),
  > `name` (its label), `kind = "heal"`, `ids`, `ranks` (`id`, `rank`, `level`, `known` from the
  > known-rank index, `cost.amount`, `icon` through `MD.API.SpellTexture`), `maxKnown`, and
  > `spells` (id -> family key); empty for another class. Installed as `Tabs.source`; rebuilt on
  > `SPELLS_REBUILT`, which then runs `Tabs:Reconcile` (the job `BOOK_CHANGED` does on Forever:
  > a family trained since appended with the new dot, a removed one kept out) |
- **A new row after `UI/Dashboard_Rows.lua`:**
  > | `UI/SpellRail.lua` | **The Spells rail's glue, both lines** (T84, C5; moved out of
  > `UI/SpellsPane_Forever.lua`; all three main TOCs, right after `UI/Dashboard_Rows.lua`):
  > `MD.SpellRail.Install(pane, spec)` puts `Views` (Overview, then one row per listed family,
  > or a greyed stale row), `RefreshRail` (repaint in place when the row ids are unchanged, else
  > `nav:SetViews`), `ListChanged`, `Remove` / `Undo` and the footer (`+ Add`, the
  > `<spell> removed [Undo]` line), `CanDrop` / `Drop` (the spellbook drop, where
  > `MD.API.CursorInfo` exists), the picker (`RefreshPicker`, `OpenPicker`: refused in combat,
  > one ESC entry), `RailFontsChanged`, `Group` (the rail group: `MY SPELLS`, the kit's drag,
  > `x` and right-click menu through `onMove` / `onRemove`) and `Attach` on a pane; `spec` is
  > `source()` (the book), `row(fam, key, ctx)`, `prepare()`, `label(key)` and `pickerTip`.
  > `SpellRail.FamilyKey`, `SpellRail.VIEW_PREFIX` (`"fam:"`, both lines) |
- **The `UI/SpellsPane_Forever.lua` row:** append
  > **T84 (C5):** the rail's rows, the footer and Undo line, the drop, the picker and the group's
  > definition moved to `UI/SpellRail.lua`, installed here with the book as the source, this
  > pane's row (icon, `R<suggested>`, `RailTip`) and the picker's tip; the pane shows exactly
  > what it showed (`tools/spellsui.lua` byte for byte).
- **The `UI/SpellsView_TBC.lua` row:** append
  > **T84 (C5):** `MD.DashboardParts.CreateSpellsOverview(parent, width, onOpen)` -- Overview, the
  > rail's first row: My spells on C2's table options with RankMath's numbers, one row per listed
  > family in the list's order (icon and name; the suggested rank in the accent, its Heal, Per
  > mana, Per sec, Casts `inf` / `999+`; a rule; the highest known rank, its Heal and Per mana;
  > After overheal honoured), a row's hover the suggested rank's derivation, a click opening
  > the family's view; a stale key greyed "not in your spellbook".
- **The `UI/Dashboard.lua` row:** append
  > **T84 (C5, section 7.1):** the Spells group is the rail (`MD.SpellsTBC`, `UI/SpellRail.lua`
  > over `Spells/Families_TBC.lua`: a row's tag the suggested rank, its hover the rank and its
  > per mana); C3's four view tabs are gone; one host right of the rail holds Overview and C3's
  > view (`fam:<key>`); `/md` opens on Overview the first time, then on the remembered row; a
  > bare family (a path saved before C5, `MD:SelectView("spells", "Regrowth")`) opens its row;
  > opening a row clears its new dot; the rail refreshes on `SPELLS_REBUILT`, talents, form and
  > gear; without the glue the group is a rail with Overview only.
- **The `tools/` row:** in the Forever suites' list, `tabscheck` becomes `tabscheck` (forever /
  tbc).

**docs/TOOLS.md** section 1:

- **The `tabscheck.lua` row:** "(T35, forever, 24)" becomes "(T35, forever 24 / tbc 4)"; append
  "Since **T84** (tbc, 4): the list over `Spells/Families_TBC.lua` -- a level 70 druid's
  families seed Healing Touch, Rejuvenation, Regrowth, Lifebloom in Book's shape; a removed
  family stays removed across `SPELLS_REBUILT`; a family trained later is appended with the new
  dot; the TBC source is installed and the default source is `MD.Book:Get()`".
- **The `dashui.lua` row:** append "Since **T84** (84): the TBC Spells group is the rail --
  Overview first and the seeded families with their suggested-rank tags, no view row; Overview's
  one row per listed family with its suggested rank; a rail row (and an Overview row, and a bare
  family name) opening C3's view; `x` then Undo putting the row back; the old family-tab checks
  click rail rows, and the Spells group button lands on Overview".

**docs/DECISIONS.md**, a paragraph after "TBC's Spells view is the Forever structure":

> **TBC's Spells group is the rail** (2026-10-01, T84 / C5; section 7.1, the author's choice when
> approving the mockups, decision 10). TBC's Spells group is Forever's rail: MY SPELLS,
> Overview first, then one row per family of the player's own list, with `+ Add` and its picker,
> the "<spell> removed [Undo]" line, drag to reorder, one `x` on hover and the right-click menu
> (Move up / Move down / Remove; layout B). C3's four view tabs are gone.
> - **The list** is `Spells/Tabs.lua`'s, with its rules unchanged. It reads the TBC druid's
>   four heal families (`Spells/Families_TBC.lua`, from `Data/SpellData.lua`) through one
>   seam, `Tabs.source`. A fresh character's list is the known heal families by learn level.
>   A family trained later is appended with the new dot. A removed family stays removed until
>   Undo, the picker or "Reset to my heals". The list is kept per character in
>   `cdb.spellTabs`, as on Forever.
> - **Overview** is My spells with TBC's numbers: the suggested rank, its heal, per mana, per
>   sec and casts, then the highest known rank. A row opens the family's view (C3's).
> - **`/md` opens on Overview the first time,** then on the remembered row. A path saved before
>   C5 opens its family's row.
> - **The rail glue is one shared file** (`UI/SpellRail.lua`), and Forever shows exactly what it
>   showed.
> - **There is no spellbook drop on TBC.** The adapter has no cursor read there, so a spell is
>   added with `+ Add`.

**docs/TESTING.md** section 44:

- The heading gains "and C-d".
- After item 33, under a "Wave C-d (T84; TBC)" line:

> 34. **TBC spell rail (C5).**
>     - `/md` (first time since the update, or after `/reload` with the window on Spells): the
>       Spells group has no row of tabs. On its left is a list: `MY SPELLS`, `Overview`, a
>       rule, then your heal families in learn-level order, Healing Touch, Rejuvenation,
>       Regrowth, Lifebloom, each with an `R<n>` tag (its suggested rank).
>     - **Overview** shows one row per family: the suggested rank in orange, its Heal, Per
>       mana, Per sec and Casts, then the highest rank. Click a row: that family's view (C3's)
>       opens and its rail row is marked.
>     - **Point at a rail row** for half a second: its tooltip says "Suggested  Rank N of M
>       known", "Per mana", and "Drag to reorder. Right-click for more.".
>     - **Hover a row:** one red `x`. Click it: the row goes, and "Rejuvenation removed  [Undo]"
>       appears above `+ Add`. Click Undo: it is back where it was.
>     - **Drag a row** to another place, and `/reload`: the order is kept. Right-click a row:
>       Move up / Move down / Remove.
>     - **`+ Add`:** the picker lists your four heals under HEALS, ticked when listed. Untick
>       one and tick it back. "Reset to my heals" restores the learn-level order. ESC closes the
>       picker, not the window. In combat the picker refuses with a chat line.
>     - **The window remembers the row:** open Regrowth, close the window, `/md`: it opens on
>       Regrowth again.
>     - **(If you can)** On a druid alt below level 64, train Lifebloom: it appears at the end
>       of the list with a dot, and the dot goes once you open it.

**docs/HISTORY.md**: the integrator's wave entry.

## Deviations

1. **The branch needs its TOC lines** (above). Forever's pane installs the shared glue at load,
   so without `UI\SpellRail.lua` on the Forever TOCs every Forever suite fails at load. This is
   the same situation as T76, T79 and T80. A fallback in the pane would hide a packaging bug, so
   the dependency fails loudly instead. `dashui/tbc` does not need the lines: it loads the two
   `Spells/` files itself when the TOC lacks them.
2. **A family's key on TBC is SpellData's id** (`HealingTouch`), and its `name` is the label.
   Forever's key is the spell's name, which is its label too. The TBC id is what C3's view,
   RankMath and the old `uiPath` already use, so the TBC list store (`cdb.spellTabs`, per
   character on its own client) keys by it. The Undo line and a stale row read the label
   (`spec.label`), and the picker's search matches both the key and the label.
3. **The view ids are `fam:<key>` on both lines.** A bare family (an old saved path, or
   `MD:SelectView("spells", "Regrowth")`) is mapped to its row in `UI/Dashboard.lua`, so C3's
   checks and paths saved before C5 keep working. A `uiPath` saved before C5 opens that family's
   row and not Overview: that is "the remembered row". Only a character with no saved path gets
   Overview on the first open.
4. **No spellbook drop on TBC.** The plan's list for C5 does not name it, and `MD.API.CursorInfo`
   is a Forever binding (`Client/API_Forever.lua`, not this task's file). `CanDrop` answers false
   on TBC, so a click selects, as before. The picker's "drag a spell from your spellbook" tip is
   Forever's only (`spec.pickerTip`); on TBC the line is hidden.
5. **Overview has no Whole book and no Export on TBC.** The TBC book is the four families the
   rank table has: every one is in the picker, and an unlisted one is added there. Forever's
   preview (a family's view while it is not listed) does not exist on TBC, so `pane.preview`
   stays nil there.
6. **The Overview columns.** The plan names "its suggested rank, per mana, per sec and casts".
   Overview also shows the suggested rank's Heal, and the highest known rank with its Heal and
   Per mana, as Forever's My spells has the highest beside the suggested.
7. **The rail tags refresh on events, not on the 2-s tick.** They change on a gear, talent, form
   or rank change, and those events refresh them. Repainting the rail every 2 s would reset a
   hover or a drag under the pointer. The view and Overview still re-render every 2 s, as the
   rank table always did.
8. **`DefaultFamily` is gone.** The dashboard opened on the most-cast family. With the rail it
   opens on Overview the first time, as the plan says, and on the remembered row after that.
9. **Not installed.** This task works in an isolated worktree, and the branch is green only
   with the integrator's TOC lines. The install the author asked for ("install current version
   in both beta and TBC") belongs after the wave merges, from the integrated tree, so it is left
   to the integrator.
