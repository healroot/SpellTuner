# SpellTuner on Forever: your spells, one look, one tooltip, windows that take turns -- UI spec

**This is the document to implement from.** The author, 2026-09-29, after installing 0.16.1 on
build 70058:

> "Also we would need to improve UI:
> * I want spell dashboard to be at least separate tabs, but ideally the tabs(or list) should be
>   contructed by user - so user can select spells he want to see in dashboards, and each spell is
>   a separate view\tab
> * also I want to make it look better, now it looks really dirty
> * then the tooltips (it should be better designed, and also I dont see updated tooltip on marcos)
> * then when we open separate window it weirdly overlap with the main one, lets somehow manage
>   this too"

And, in the same message: "I've tested practice, there is lifebloom present, which is weird (we
need to adjust to spells the player really has)".

Read first: `UI/Style.lua` (the kit: `CreateMovableFrame` 129-171, `UI.CreateNavFrame` 348-476,
the dropdowns 556-700), `UI/Dashboard_Forever.lua` (the Spellbook pane, the grow at 748-750),
`UI/Dashboard_Rows.lua`, `UI/SpellTip_Forever.lua`, `UI/DebugConsole.lua` 138 and 193,
`UI/Dashboard_Review.lua`, `UI/Tooltip.lua`,
`Client/API_Forever.lua` 86-192 (both tooltip hooks), `Spells/Book.lua` (`BuildEntry`,
`GroupFamilies`, `Rows`), `UI/ReplayWindow.lua` 1120-1140 and 1470-1474, `UI/PracticePanel.lua`,
`Engine/Practice.lua` 131-245 and 919-958. Reference only: `Cell/Widgets/Widgets.lua` (frames,
buttons, titled panes, `CreateMask`), `Cell/Modules/Indicators/Indicators.lua` (the list),
`Cell/Widgets/Tooltip.lua`, and ElvUI's `Tooltip.lua` 999-1109 and 1049-1055 (its spacer
convention and the Macro-type spell read).

Screenshots: `4.webp` (Spells -> Spellbook), `5.png` (the block on Healing Touch), `6.png` (Practice
with the replay window over it), `7.png` (a practice replay, two columns). Mockups of everything
below: `ui-mockup.html` beside this file.

Conventions as always: Lua 5.1, no libraries, ASCII-only rendered text and no bare `|`, every client
call through `MD.API`, `.toc` order, both harness loops green before every commit. **The TBC line's
look does not change** in anything scheduled here (section 7).

---

## 1. What is wrong today

**The Spellbook pane (4.webp) is one long table of everything.** Heals, damage and "Other" sit in one
620-px table inside a 1036-px window. The right 400 px are empty, and `Export` floats at the far
edge. Four things make it look dirty:

- **Gold.** Every suggested rank is painted `#FFCC00` across the whole row. At level 10 that is
  most rows (R1 wins almost every family), and the gold clashes with the druid-orange accent.
- **Mixed type.** Cells use `GameFontHighlightSmall` (about 10 pt); the lines above use the kit's
  13/11. All numbers are left-justified, so `25`/`55` and `1.5s`/`inst` do not line up.
- **The same fact said three times:** `suggested: Rank 1` in the family header, `*` on the rank,
  and the gold row. A legend line explains all three.
- **Things that are not in columns.** "Other" rows are one free-text string, and a note column
  overflows the row's own hover rectangle (row 560 wide, columns to 638).

Also: the window fill is 0.9 alpha, so nameplates show through the table. The hover tooltip
anchors to the window's right edge, not to the row.

**The tooltip block (5.png) reads as part of the game's description.** It is added with bare
`AddDoubleLine(l, r)`, so its left side comes out gold and its right side white, the same colours
as the gold description above it. There is no spacer. It repeats the description's range and the
cast line. It puts "1.5x, unverified" on every crit line. It has 7 lines where 4 answer the question.

**No block on macros.** T25 shipped the Macro-type hook in 0.16.1. It rests on four retail shapes
that are **unconfirmed on Forever**, and any one of them failing gives exactly what the author saw.
Section 5.5 names them and adds the fallback and the diagnostic.

**Windows interleave (6.png).** The dashboard, the replay window and the bindings window are all
`HIGH` strata at frame level 1, all anchored at `CENTER`, and none has `SetToplevel`. Inside one
strata the client draws by frame level, not by window. The dashboard's deep children (edit boxes,
the bindings text, the "Edit bindings" button) out-level the replay's shallow regions and draw
through its unit frames. Raising a window on click would not fix this. **Two big windows must not
share a strata and a spot on screen.**

**Lifebloom in practice.** T24 (in 0.16.1) drops the TBC defaults only when the saved list is
*exactly* the shipped defaults. The list is kept whole in two cases: the author imported Cell's
bindings on 0.16.0, since an import *adds* on top; or he edited one row. The author's TBC Cell
click-casting names Lifebloom, and an import does not filter by the book. Either way Lifebloom
stays, now marked `(not in your spellbook)`. 6.png shows `(not trained)`, which is 0.16.0's wording,
so 6.png probably predates the install; the only evidence for that is the wording, and §10 step
1 has to confirm it on 0.16.1. Either way, marking the row is not what the author asked for: "adjust
to spells the player really has" means a binding for a spell you do not have is not shown and not
cast. Task T27 does that (decision 9).

---

## 2. The shape

The Forever window keeps its four groups. **The Spells group loses its top view row and gains a
list rail**, a second column that you build yourself. Every row in the rail is one view.

```
+---------------------------------------------------------------------------------------+
| SpellTuner                                                                          x |   header 20, hung ABOVE the frame
+==========+====================+=======================================================+   <- the 860 x 560 frame starts here
| Spells   | MY SPELLS          | [ic] Healing Touch                     ~364 / 364 mana |
| Reports  |  Overview          | [ic] Direct heal - Rank 2 of 2 known - 2.0 s cast      |
| Simulate |--------------------|                                                        |
| Settings |#[i] Healing Touch R1| +-SUGGESTED---+  vs Rank 2 (your highest):            |
|          | [i] Rejuvenation  R1| | Rank 1      |  2% more healing per mana, 47% of the |
|          | [i] Moonfire      R1| +-------------+  heal, a 25% shorter cast.            |
|          | [i] Wrath         R1|                                                        |
|          |                    | RANKS ------------------------------------------------ |
|          |                    |  Rank  Lvl  Mana  Heal  Per mana          Per s Cast OOM |
|          |                    | |R1      1    25    48  ##########  1.90  31.7 1.5s  14 best
|          |                    |  R2      8    55   103  #########   1.86  51.2 2.0s   6 max
|          |                    |                                                        |
|          |                    | RANK 1 ----------------------------------- learned at 1 |
|          |                    |  "Heals a friendly target for 40 to 55."               |
|          |                    |  Heals     40 - 55 (avg 48)    Crit   60 - 83 (x1.5 assumed)
|          |                    |  Cost      25 mana             Cast   1.5 s            |
|          |                    |  Per mana  1.90                Per s  31.7             |
|          | [ + Add ]          |  To OOM    14 casts from full                          |
+----------+--------------------+-------------------------------------------------------+
   108 nav        172 rail                        556 view (540 table + 8 each side)
```

The window's size is the frame's: `CreateMovableFrame` hangs the 20-px header above the frame
(BOTTOM to TOP, -1), so an 860 x 560 window is 579 px tall on screen. Every height in this spec
excludes the header.

- `#` at the rail's left edge is the 2-px accent bar of the selected row.
- Healing Touch and Rejuvenation are the seed (3.3); the author added Moonfire and Wrath himself.
  No row carries the "new" dot at level 10, because the reconcile adds only heals and none has been
  learned since the seed. Mockup 2 shows the dot on Regrowth as it will look at level 12.
- `|` at the table's left edge is the suggested rank's 2-px accent bar.
- `ui-mockup.html` mockup 1 is the same screen in colour, at 1:1.

Reports, Simulate and Settings keep their top view row, exactly as today.

---

## 3. (A) Your spells: the rail, the list, one view per spell

### 3.1 Where it lives

- `UI.CreateNavFrame` gains a per-group option `layout = "rail"` (shared file, additive: a group
  without it renders as today). A rail group draws no top view row, and a 172-px rail sits at the
  content's left edge.
- **The nav's shared content frame is re-anchored per group.** Today it is anchored once, at
  `-(NAV_TOP + NAV_PAD)` (`Style.lua` 376). From now on `nav:Select` re-anchors its TOPLEFT whenever
  the group changes: `-NAV_PAD` (8 px below the frame's top) for a rail group,
  `-(NAV_TOP + NAV_PAD)` for any other.
- Every rail row is a real nav view. `nav:SetViews("spells", views)` is called whenever the list
  changes, so `db.uiPath` remembers `{ "spells", "fam:Healing Touch" }` and
  `MD:SelectView("spells", "fam:Rejuvenation")` works.
- **`nav:SetViews` on a rail group skips `BuildViews`** and only refreshes the rail. Today
  `BuildViews` creates new buttons on every call and hides the old ones (a leak, `Style.lua`
  396-411); a rail group would both leak and draw the top row. `BuildViews` itself also moves to a
  button pool (hidden buttons are reused by index), which fixes the leak for Reports -> Runs too and
  looks the same.
- `/st spell <name>` opens that view (a prefix match on the family name, case-insensitive). If the
  family is not in the list, it opens as a **preview** (section 3.6).

Why a rail and not top tabs: the top row chains buttons left to right and neither wraps nor
scrolls (`Style.lua` 396-409). Six spell names at about 110 px each run off a 736-px content area.
A vertical list scales, and it is the list the author already uses in Cell's Indicators tab.

### 3.2 The rail

Top to bottom:

1. `MY SPELLS`: 11 px, `muted`, 8 px inset, 18 tall.
2. **Overview**: always first, followed by a 1-px `#2A2A2A` rule.
3. One row per family in the list, in your order. Rows are 20 tall, overlapping by 1 px:
   - a 16x16 icon at x=4 (`entry.icon`, texcoord 0.08-0.92, 1-px black frame);
   - the name at x=24, 13 px, `text`, truncated;
   - on the right at -6, the suggested rank (`R1`) in `NumSmall`, `muted`;
   - a 6x6 accent dot left of the rank while the family is new (3.3);
   - a family the book no longer has: name in `disabled`, no rank, tooltip "not in your
     spellbook".
4. On hover, three 14x14 controls replace the rank at the right: `^` move up, `v` move down, and
   `x` remove (red-hover, as Cell's delete).
5. Pinned at the bottom: **[ + Add ]**, 164x20, `accent-hover`. After a removal, the line above it
   reads `Wrath removed  [Undo]` (11 px) until the next change.

| Action | How |
|---|---|
| **Add** | **[+ Add]** opens the picker sheet (3.4). Or drag a spell from the spellbook onto the rail: the rail's `OnReceiveDrag` / `OnMouseUp` reads `MD.API.CursorInfo()` (new binding, `GetCursorInfo`, which answers the spell id only when plain) and inserts the family at the drop row. **The rail never clears the cursor.** Picking a spell off an action bar takes it off the bar, and the client cannot tell the rail where a cursor spell came from; clearing it would delete the player's button. So the spell stays on the cursor after the drop: the player puts it back on the bar, or right-clicks it away as after any drag. The hint and the docs say "from your spellbook". **UNVERIFIED on Forever**: `GetCursorInfo`'s shape for a spell. If it does not resolve, the drop does nothing, and the picker still works. |
| **Reorder** | Drag a row. It lifts on mouse-down to alpha 0.5, and a 2-px accent insertion line shows the drop point. Or use the hover `^` / `v`. Or right-click for a kit dropdown: *Move up / Move down / Remove from list*. |
| **Remove** | Hover `x`, right-click Remove, or untick in the picker. No confirm: Undo, and the picker, bring it back. |
| **Reset** | The picker's footer has **Reset to my heals**. |

The judged designs also had an "Edit mode" button. It is dropped: the hover controls and the
right-click menu already give a non-drag route, and one more mode is one more thing to explain.

### 3.3 The list: storage, the seed and the reconcile

Kept per character, because spellbooks differ by class and level:

```lua
MD.cdb.spellTabs = {
  order   = { "Healing Touch", "Rejuvenation" },  -- family keys, your order
  removed = { ["Moonfire"] = true },              -- never re-added by the reconcile
  seen    = { ["Healing Touch"] = true, ... },    -- viewed once: no "new" dot
  seeded  = true,
}
```

- **The key is the family name** as `Book:GroupFamilies` groups it. The addon is enUS only, and a
  family has no single stable id. `ids = { <any rank id> }` is stored beside each key as a fallback
  should the name ever change.
- **The seed** runs on first open. It takes every family with `kind == "heal"` that has a known
  rank, ordered by the lowest learn level of its known ranks. For the author at level 10 that is
  Healing Touch and Rejuvenation. With no heals (a warrior), it takes the `damage` families that
  cost mana. With neither, the list is empty and the rail says `Add the spells you want to watch.`
- **The reconcile** runs whenever `Book` marks itself dirty (`SPELLS_CHANGED`, a level-up). A newly
  known family of the seeded kind that is neither in `order` nor in `removed` is **appended once**,
  with the new dot until you open it. Regrowth at 12 therefore appears on its own. Damage and
  utility families are never added by the reconcile.
- **A family the book no longer has** (a respec, an alt copied by hand) stays in the list, greyed.
  Its view says `Healing Wave is not in this character's spellbook.` with a **[Remove]** button. It
  is never dropped silently.

### 3.4 The picker sheet

A sheet (section 6.4) over the spell view, 300x400, anchored TOPLEFT to the rail's TOPRIGHT +4.
**Its mask covers the view, not the rail.** The rail stays live while the picker is open: a spell
can be dragged onto it (the picker's own hint says so), rows can be reordered or removed, and the
picker's ticks follow every change the rail makes.

```
+- ADD SPELLS ------------------------------+
| [ search...                            ]  |
|                                           |
|  HEALS ---------------------------------  |
|  [x] [i] Healing Touch        R1 - R2     |
|  [x] [i] Rejuvenation         R1 - R2     |
|  DAMAGE --------------------------------  |
|  [ ] [i] Entangling Roots     R1          |
|  [x] [i] Moonfire             R1 - R2     |
|  [x] [i] Wrath                R1 - R2     |
|  OTHER ---------------------------------  |
|  [ ] [i] Mark of the Wild     R1 - R2     |
|  [ ] [i] Thorns               R1          |
|                                           |
|  Tip: drag a spell from your spellbook    |
|  onto the list.                           |
|-------------------------------------------|
| [Reset to my heals]              [ Done ] |
+-------------------------------------------+
```

- The check buttons are the kit's 14x14 (accent 0.7 fill when checked). Rows are 20 tall, with
  16-px icons.
- Section titles use Cell's titled-pane style: 14 px accent over a 1-px accent rule at 0.6.
- Ticking appends to the end of the rail. Unticking removes, and records the family in `removed`.
  Changes apply at once; **Done** only closes the sheet.
- The search box filters by substring as you type.
- Passives are not listed. Free spells are listed under Other.

### 3.5 One spell's view (556 wide; scrolls when taller than the pane)

Top to bottom. Gaps between blocks are 12 px.

**1. Header, 48 tall.**
- A 32x32 icon with a 1-px black border.
- The family name in `FONT_HEAD` (16, white).
- Under it, in 11-px `text2`: `Direct heal - Rank 2 of 2 known - 2.0 s cast`. A HoT reads
  `Heal over time - 12 s`, a hybrid `Damage - hit and over time - Arcane`, and a family with no
  value `Utility - 50 mana`.
- Right-aligned: `~364 / 364 mana`, where the current pool `~364` is in `mana` blue and the max is
  plain `text`. **The `~` is only on the modelled current pool**, never on the max, which is plain.
  The pool comes from `MD.Clock:Pool()`; with no pool the text is `mana not modelled yet`, in `muted`.

**2. Decision strip, 44 tall.** This is the "which rank now" answer. It is kept from the winning
design, but it does not repeat the table's numbers.
- On the left, a 150x44 chip with a `pane` fill, a 2-px accent left bar and a 1-px black border.
  `SUGGESTED` is 11 px accent; `Rank 1` is `FONT_BIG` (18, white) under it.
- Hovering the chip shows the rule (kit tooltip): "Highest heal per mana among the ranks nothing
  beats on both per mana and per second, with at least 40% of your highest rank's heal."
- To the right, one factual comparison, 13 px `text2`, at most two lines:
  `vs Rank 2 (your highest): 2% more healing per mana, 47% of the heal, a 25% shorter cast.`
  It is computed from the two rows by `Book:Compare(a, b)` and never tells the player what to do.
- When the suggested rank is the highest known, the chip reads `Rank 2`, and the line reads
  `Your highest rank is also the best per mana.`
- With one known rank there is no strip.

**3. RANKS**: a titled pane (14-px accent title, 1-px rule at -17, first row at -27). One row per
rank from 1 to the highest rank the book lists, gaps included. Header 22 tall with a 1-px `#2A2A2A`
rule under it; rows 20 tall; zebra on even rows.

| Column | Width | Justify | Content |
|---|---|---|---|
| Rank | 52 | left | `R1` |
| Lvl | 34 | right | learn level |
| Mana | 46 | right | cost; `free` for a free spell |
| Heal / Dmg | 58 | right | average value (`Total` for a HoT) |
| Per mana | 116 | right | a 72-px bar, 4-px gap, then the 40-px number (`1.90`) |
| Per s | 54 | right | `31.7` |
| Cast | 46 | right | `1.5s`, `inst`, `chan` |
| To OOM | 58 | right | casts from a full pool |
| Tag | 60 | left | see below |
| **Total** | **524** | | plus 8 px padding each side = 540, inside the 556 view |

- **The per-mana bar** is a Texture scaled to `perMana / max(perMana in this family)`: accent at 0.5
  alpha, 8 px tall, on a `#FFFFFF` 0.05 track, vertically centred. Numbers are right-justified in
  `FONT_NUM` (ARIALN 13), so the digits line up.
- **Tags**, in 11 px: `best` (accent) on the suggested rank; `max` (`text2`) on the highest known;
  `dominated` (`muted`); `learn at 14` (`disabled`) on a listed rank not yet learned.
- **A gap**, a rank the book does not list, is one `disabled` row: `R3` then, across the rest,
  `not in your spellbook - untrained, or hidden by "show all ranks"`. The book does not say which,
  and nothing is filled in.
- **Other-kind families** (no value) get only Rank / Lvl / Mana / Cast / Tag.
- **Row states**:

| State | Look |
|---|---|
| Suggested | `suggested` fill (accent 0.10), 2-px accent bar at the left, `best` tag |
| Selected (drives the card) | `selected` fill (accent 0.28). With suggested: 0.28 plus the bar |
| Hover | `hover` fill (accent 0.12), and the tooltip (below) |
| Dominated | all cells `muted`, bar at 0.25 alpha |
| Not learned | all cells `disabled` |
| Gap | one spanning `disabled` line |

- There is no `*`, no gold and no legend line: the fill, the bar and the tag say it once.
- **Row hover** shows the game's own spell tooltip for that rank. A new `MD.API.SetTooltipSpell(tt,
  id)` wraps `GameTooltip:SetSpellByID`, and the SpellTuner block is appended by the same post-call.
  The pane and the action bar then read exactly the same.
  - If the block is not there after the call (`tt._spellTipId ~= id`, since the post-call firing for
    `SetSpellByID` is **UNVERIFIED on Forever**), the row appends `SpellTip:Lines(id)` itself.
  - Anchor: the tooltip's TOPLEFT at the row's TOPRIGHT +6. If that runs off the screen's right
    edge, the tooltip's TOPRIGHT goes at the row's TOPLEFT -6. Nothing anchors to the window edge.
  - Gap and not-learned rows show the kit tooltip (`SpellTunerTooltip`) with the reason instead.

**4. The rank card**: a titled pane named after the selected rank, `RANK 1`. On its right, 11-px
`text2`: `learned at 1`. By default the suggested rank is selected; clicking a row selects another.
- The spell's own text, in quotes, 12 px `text2`: `"Heals a friendly target for 40 to 55."`
- Label/value pairs in two columns (262 each; labels `label` 12 px, values `text` in `FONT_NUM`):

```
Heals     40 - 55 (avg 48)        Crit    60 - 83 (x1.5 assumed)
Cost      25 mana                 Cast    1.5 s
Per mana  1.90                    Per s   31.7 over a 1.5 s cast
To OOM    14 casts from full      Now     ~14 from ~364 mana
```

- A HoT shows `Heals 48 over 12 s` in place of the range, and no crit. It shows `Ticks` only when
  `Parse` read a tick and a period from the text; no tick is ever derived.
- A hybrid shows `Hit 11 - 15`, `Over time 24 over 12 s` and `Total 37`.
- A stale entry adds `Text read before combat - may be out of date` in `bad`.
- One footer line under the card, 11 px `muted`:
  `Values come from the spell's own text. ~ = modelled.`

**Refresh.** Today every 2-s tick releases and re-acquires every row. From now on the 2-s
`MD:OnTick` updates only the header's mana text, the `Now` value and the To OOM cells, in place. A
full render happens only on a book change (`Book` dirty), a change in the bonus-healing reading, a
change in the pool's max, or a view switch.

### 3.6 Overview

The first rail row. It shows one row per listed family, so spells can be compared at a glance.

```
 OVERVIEW                                         [My spells][Whole book]   [Export]
 Spell               Suggested  Value  Per mana  To OOM | Highest  Value  Per mana
 [i] Healing Touch   R1            48      1.90      14 | R2         103      1.86
 [i] Rejuvenation    R1            32      1.28      14 | R2          48      1.20
 [i] Moonfire        R1            23      0.90      14 | R2          37      0.74
 [i] Wrath           R1            17      1.83      40 | R2          26      1.42
```

- Clicking a row opens that family's view.
- **[My spells] [Whole book]** is a two-button group. *Whole book* is today's Spellbook table under
  the new look, not the Overview row format: sections Heals / Damage / Other; per family a header
  row (icon, name, a 16x16 `+` or a grey `listed`); under it **one row per rank** in the RANKS
  columns of 3.5 (Rank, Lvl, Mana, Value, Per mana, Per s, Cast, To OOM, Tag), gaps and not-learned
  rows included. Every per-rank number today's pane shows is therefore still one click from the
  rail, without opening each family. This view replaces today's Spellbook pane.
- Other's rule is kept from T10c: it lists only kindless spells cast for mana, and one grey line
  counts the rest. Export still lists everything.
- Opening a family from *Whole book* that is not in the list opens its view as a **preview**: a
  one-line banner at the top, `Not in your list.  [+ Add to my spells]`.
- **[Export]** (70x20) moves here and keeps its exact format (the probe dump format that
  `tools/refcheck.py` reads) and its scope, the whole book.

---

## 4. (B) The visual system (Forever)

One new file, `UI/Theme_Forever.lua`, is listed by the Forever TOCs right after `UI/Style.lua`. At
load, before any frame is built, it writes these values into `UI.PALETTE` and the kit's font
objects. The TBC TOC does not list it.

### 4.1 Palette

| Token | Value | Use |
|---|---|---|
| `bg` | `#161616`, alpha 0.96 | Window body. Near-opaque, so nameplates no longer show through |
| `pane` | `#1C1C1C`, alpha 1 | Rail, chip, cards, sheets |
| `nav` | `#1D1D1D`, alpha 1 (Cell's 0.115) | Header bar, left nav, buttons |
| `border` | `#000000` | 1-px edges, pixel-snapped (4.3) |
| `rule` | accent, alpha 0.6 | The line under a pane title |
| `line` | `#2A2A2A` | Table header rule, rail separators |
| `rowAlt` | `#FFFFFF`, alpha 0.03 | Zebra on even rows |
| `hover` | accent, alpha 0.12 | Row and list hover |
| `selected` | accent, alpha 0.28, plus a 2-px accent bar | Selected rail row, selected rank |
| `suggested` | accent, alpha 0.10, plus a 2-px accent bar | The suggested rank's row |
| `mask` | `#262626`, alpha 0.7 | Behind a sheet |
| `accent` | Class colour from `RAID_CLASS_COLORS` (druid `#FF7C0A`); fallback `#B2B2B2` | Titles, rules, selection, bars, chip |
| `text` | `#FFFFFF` | Values |
| `text2` | `#B3B3B3` | Secondary lines, comparison, spell text |
| `label` | `#9D9D9D` | Labels in cards and the tooltip block |
| `muted` | `#7A7A7A` | Dominated, footers, table headers, hints |
| `disabled` | `#4D4D4D` | Gaps, not learned, disabled buttons |
| `mana` | `#4D99FF` (the clock bar's 0.3/0.6/1) | Modelled mana figures |
| `good` / `bad` | `#5CCB6E` / `#E0605A` | Measure verdicts and the stale warning only |
| `close` | (0.6, 0.1, 0.1, 0.6), 1 on hover | The x button, as in Cell |

**Blizzard gold (`#FFCC00`, `#FFD100`, `{1, 0.82, 0}`) leaves every SpellTuner window and tooltip on
Forever except the debug console (below)**, once the tasks that own each surface have landed:

| Surface | Gold today | Task |
|---|---|---|
| Spell views, rail, Overview, Whole book | `Dashboard_Rows.lua` 172, 214, 248, 250 (the suggested row and its note) | T30, T38, T39 |
| Tooltip block | bare `AddDoubleLine` | T37 |
| Practice panel | `PracticePanel.lua` 178 (role rows), 282 (key labels) | T40 |
| Bindings sheet | `BindingsWindow.lua` 105 (`press a key...`), 165 (notes) | T40 |
| Review | `Dashboard_Review.lua` 379 (the run line); `GameFontHighlightSmall` at 108, 113, 137, 280 | T43 |
| Replay window text | `ReplayWindow.lua` 1432 (run strip), 1656 (header `#n`), 1852 (`paused`), 1903 (`PRACTICE`) | T43 |
| Replay and Review hover tooltips | `UI/Tooltip.lua` 24 (`GOLD`) | T43 |

The one exception is the debug console's category colours (`DebugConsole.lua` 14, `tto` is gold):
they are a legend for a developer tool, not decoration, and stay. Shared files read colours through
`UI.TEXT.<token>` and fall back to their current literals when `UI.TEXT` is nil, so TBC is
unchanged.

### 4.2 Fonts

Each is built once with `CreateFont`: no outline, a black shadow at (1, -1). The face is
`GameFontNormal:GetFont()` (Friz Quadrata on enUS), except for the number fonts.

| Object | Face | Size | Use |
|---|---|---|---|
| `UI.FONT_TITLE` (exists) | Friz | 14 | Nav buttons, pane titles (the accent variant) |
| `UI.FONT_HEAD` (new) | Friz | 16 | The spell name in a view header |
| `UI.FONT_BIG` (new) | Friz | 18 | The rank in the SUGGESTED chip |
| `UI.FONT` (exists) | Friz | 13 | Rail names, buttons, the picker |
| `UI.FONT_SMALL` (exists) | Friz | 11 | Sub-lines, tags, hints |
| `UI.FONT_NUM` (new) | `Fonts\\ARIALN.TTF` | 13 | Every table and card number |
| `UI.FONT_NUM_SMALL` (new) | `Fonts\\ARIALN.TTF` | 11 | The rail's `R1`, header numbers |

- Arial Narrow's digits are narrow and even-width, so right-justified columns line up.
- `db.ui.fontOffset` (**-2 to +2**, Settings -> General) shifts every size above, as Cell's
  `UpdateOptionsFont` does. `UI.ApplyFonts(offset)` calls `SetFont` on the font objects, so every
  FontString built from them follows at once.
- **The pitches grow with it.** `UI.Pitch(n)` returns `n + max(0, offset)`, and every vertical
  pitch the Forever-only panes use goes through it: rail rows (20), table rows (20), the table
  header (22), card pairs (17), the view header (48) and the chip (44). A negative offset leaves the
  pitches alone. Widths do not change: at +2 the widest cell text (`40 - 55 (avg 48)` in a card
  value, `Healing Touch` in the rail) still fits its column, and the rail truncates a longer name.
  A change to the offset re-renders the Spells pane at once. Shared panes (Review, Practice) keep
  their fixed pitches; +2 is the cap because their 20-px rows still hold a 15-px font, and +4 would
  not.
- The spell table no longer uses `GameFontHighlightSmall`.

### 4.3 Metrics

All heights exclude the window header, which the kit hangs above the frame. Vertical pitches are
given at font offset 0; 4.2 says how they grow.

| Element | Value |
|---|---|
| Main window, Spells and Settings | 860 x 560 default, resizable (6.7) |
| Header | 20, above the frame (BOTTOM to the frame's TOP, -1); title in the accent 14 font; x 20x20 at the right |
| Left nav | 108 wide; buttons 106x22; selected: accent 0.3 fill plus a 2-px accent bar |
| Content inset | 8 |
| Rail | 172 wide; rows 20 at -1 overlap; icon 16 at x=4, name at x=24, right tag at -6 |
| Titled pane | title at 0, rule at -17, first control at -27 (Cell) |
| Section gap | 12 |
| Table | header 22 plus a 1-px `line` rule; rows 20; cell padding 6; the row frame spans the full table width (fixing today's 560-vs-638 hover overflow) |
| Chip | 150x44 |
| Card pairs | line pitch 17, two columns of 262 |
| Check button | 14x14 (Cell) |
| Sheet | inside the pane, at content level +50; its mask at +30 |

**Pixel-perfect edges.** `UI.px(n, frame)` returns
`n * (768 / physicalHeight) / frame:GetEffectiveScale()`, with `physicalHeight` from a new
`MD.API.PhysicalScreenSize()` (`GetPhysicalScreenSize`, in the 69893 baseline). `UI.StylizeFrame`
uses `UI.px(1)` for its edge and insets **only when `UI.PIXEL` is true**, and only the theme sets
it. Without this, 1-px borders blur or vanish at a non-integer effective scale such as 0.71.

`UI.px` is evaluated when a frame is styled, so a later scale change would leave stale edges.
`StylizeFrame` therefore records each frame it styles under `UI.PIXEL` in a weak-keyed registry, and
`UI.RestylePixels()` re-applies the backdrop's edge size and insets to every frame in it. The
window manager calls it on `UI_SCALE_CHANGED`, on `DISPLAY_SIZE_CHANGED` and after a change to
`db.ui.scale`, so borders stay one pixel without a reload.

**Window scale.** A Settings -> General slider, 70-120 % (`db.ui.scale`), is applied with
`SetScale` to the main, replay and practice windows, the console and the copy box. Sheets inherit
it. A saved position is stored in the frame's own units, so on a scale change the manager converts
it (`x * old / new`) before re-anchoring.

### 4.4 Other surfaces under the theme

- **Practice panel** (shared, gated on `UI.TEXT`):
  - The role rows `every tank ...` use `text2`, not gold; the bindings' key labels (282) use
    `accent`.
  - `you` becomes a small accent tag after the name, instead of a wrapped Role cell.
  - The fight fields wrap onto a second row when the pane is narrower than their width.
  - The bindings list becomes one summary line, `6 bindings  [Edit bindings]`, with the list in
    its hover. Bindings for spells not in your spellbook are not counted or listed (decision 9).
- **Bindings sheet** (shared, gated): `press a key or button...` in `accent`, notes in `text2`.
- **Clock**: a pixel-snapped 1-px border and the `bg` fill. The 160x4 mana bar gets a 1-px black
  backing, so it reads on bright ground. The text is unchanged.
- **Replay window** (7.png): its chrome changes (the header's back button, strata, position;
  section 6) and its text colours (T43): the header's `#n` and `PRACTICE`, the run strip's name and
  `paused` take `accent` instead of gold. Its unit frames are the author's Cell layout and stay as
  they are.
- **Review** (shared, gated; T43): the run line takes `accent`, and its four
  `GameFontHighlightSmall` strings take `UI.FONT_SMALL`. Its layout is not in this spec.
- **Hover tooltips** of the replay and Review (`MD.Tip`, `UI/Tooltip.lua`): `GOLD` reads
  `UI.TEXT.accent` when the theme is loaded (T43).

---

## 5. (C) The tooltip block

### 5.1 Rules

- **A spacer first.** `tt:AddLine(" ")` (ElvUI's convention for its own blocks) separates the block
  from the game's gold description.
- **Header**: `AddDoubleLine("SpellTuner", right, accent, text)`. `right` is `Rank 2 of 2`. After it
  comes the detail key hint in `disabled`, written inline as `|cff4d4d4dShift|r`; the escape is
  closed, so no bare pipe is left.
- **Pairs**: `AddDoubleLine(label, value, 0.62,0.62,0.62, 1,1,1)`. The colours are passed as
  arguments, so the default gold is never inherited.
- **Decision first, and factual.** The first pair is `Suggested`, whose value is `Rank 1 (1.90 per
  mana)` in accent. When this rank is the suggested one it reads `this rank`; when it is dominated,
  `Dominated by` / `Rank 1`. It says which rank; it never says "press".
- **Plain block: the header plus at most 4 fact lines, plus at most one warning line.** The only
  warning is the stale one (`Text read before combat`, in `bad`), and it goes in the plain block,
  last, because a number read before combat is the one thing the player must see without a key.
  So the plain block is at most 6 lines with the header, and at most 5 when nothing is stale.
  Everything assumed or derived goes behind the detail key, and so does the gap line.
- **Nothing the game already printed**: no description range on the plain block, and no
  `(2.0 sec cast)`.
- Short labels: `Per mana`, `Per second`, `Casts to OOM`.
- `~` only on the modelled current pool. `~N now` appears only when the modelled pool is below its
  max; at full it would only repeat the first number.
- "Assumed" (the 1.5x crit) appears once, and only in the detail lines.
- Still once per showing, still under `pcall`, still `db.spellTooltip`.

### 5.2 Direct heal: Healing Touch, Rank 2 (level 10, +heal 0, pool ~290 of 364)

Plain:

```
Healing Touch
55 Mana                                  40 yd range          <- the game's lines
2 sec cast
Heals a friendly target for 90 to 115.
Press F6 to submit an issue for this Spell
                                                              <- spacer
SpellTuner                              Rank 2 of 2  Shift    accent | white + disabled
Suggested                          Rank 1 (1.90 per mana)     label  | accent
Per mana                                            1.86      label  | white
Per second                                          51.2      label  | white
Casts to OOM                               6 full, ~5 now     label  | white + mana blue
```

With the detail key held (default Shift), after `Casts to OOM`:

```
Average                                   103 (90 - 115)
Crit                                           135 - 173
Crit multiplier                        x1.5, not measured     label | muted
Rank 1                           48   1.90 per mana   14      label | text2
Rank 2 (this)                   103   1.86 per mana    6      label | white
```

A gap adds `Not in your book    Rank 3` in `muted` to the **detail** lines (it is about other ranks,
not this one). A stale entry adds `Text read before combat` in `bad` as the last **plain** line
(5.1).

### 5.3 HoT: Rejuvenation, Rank 2

```
Heals the target for 48 over 12 sec.
                                                              <- spacer
SpellTuner                              Rank 2 of 2  Shift
Suggested                          Rank 1 (1.28 per mana)
Per mana                                            1.20
Per second                                   4.0 over 12 s
Casts to OOM                               9 full, ~7 now
```

The detail lines are the `Rank 1` / `Rank 2 (this)` rows, and `Ticks` only when `Parse` read them
from the text. There is no crit line for a HoT.

### 5.4 Damage, hybrid: Moonfire, Rank 2

```
Burns the enemy for 11 to 15 Arcane damage and then an additional 24 damage over 12 sec.
                                                              <- spacer
SpellTuner                              Rank 2 of 2  Shift
Suggested                          Rank 1 (0.90 per mana)
Per mana                                            0.74
Per second                                          24.7
Casts to OOM                               7 full, ~5 now
```

Detail lines: `Hit` `avg 13, crit 17 - 23`, `Over time` `24 over 12 s`, `Total` `37`, the
multiplier line, and the rank rows. The author's measure dump shows Moonfire R2 landing 21 on a
crit, inside the 17-23 the 1.5x assumption gives.

When a spell has no family numbers (`Book:ReadSpell`, a spell outside the book), the block shows
only the header, `Per mana` and `Per second`. A description the parser cannot read adds nothing, as
today.

### 5.4b Other: Mark of the Wild, Rank 2 (no value)

A spell whose text carries no heal and no damage (`kind == nil`: buffs, forms, crowd control) has
no per mana, no per second and no suggested rank. Its block is only what the pool says:

```
SpellTuner                              Rank 2 of 2
Casts to OOM                              7 full, ~5 now
```

There is no `Shift` hint, because there are no detail lines. A free spell of this kind (no cost)
gets **no block at all**: SpellTuner would add nothing the game has not said.

### 5.5 Macros

**Why the block is not on the author's macros yet.** 0.16.1 carries T25. T25 fires only if every
one of these holds, and none is confirmed on 70058:

1. `Enum.TooltipDataType.Macro` exists. If it is nil, `OnMacroTooltip` returned `absent` and
   nothing was registered. `/st dump`'s capability table shows this.
2. A macro on an action button fires the **Macro** post-call. The tooltip may instead be set by a
   path that fires none, or only the Spell one.
3. The data carries a Spell-typed line, or the owner gives a slot (`owner.action`, or the `action`
   attribute; LibActionButton / ElvUI sets the attribute through its secure snippet). **T25 misses
   one read here**: ElvUI's own Macro handler (`Tooltip.lua` 1051-1055) takes
   `self:GetTooltipData().lines[1].tooltipID` **without checking the line's type**. If Forever
   gives the macro's first line a type other than Spell (or none), T25 finds nothing while ElvUI's
   read would find the id.
4. The resolved id is one `SpellTip:Lines` knows. A `/cast Healing Touch` macro may resolve to an id
   that is neither a book rank nor readable by `Book:ReadSpell`, so `Lines` returns nil and the
   block is silently empty.

T25a's probe lines (`== shapes`, `macro ...`) answer 1-3 from the author's next probe. Two
additions make this robust and self-diagnosing (task T28):

- **The untyped first-line read.** In the Macro post-call, after the Spell-typed line search and
  before the owner's slot, the adapter reads `data.lines[1].tooltipID` whatever the line's type (the
  post-call's own `data`; `tt:GetTooltipData()` only when `data` is nil), as ElvUI does. It is used
  only when it is a plain number, like every id T25 reads.
- **A third path: `SetAction`.** `hooksecurefunc(GameTooltip, "SetAction", function(tt, slot) ...)`
  in the adapter. Every Blizzard and LibActionButton bar calls `GameTooltip:SetAction(slot)`
  (`LibActionButton-1.0.lua` 3088), whatever data type the client then assigns. **The hook uses the
  slot it is handed**, not an owner lookup: `MD.API.ActionInfo(slot)`, then `MD.API.MacroSpell` for
  a macro (T25's own order), then the same `OnSpell`. The once-per-showing guard is shared, so a
  showing that also fires the Macro or Spell post-call gets the block once.
- **`/st tooltip why`.** It prints what the last macro hover did, as plain strings recorded by the
  adapter: which path fired (`macro post-call`, `SetAction hook`, `none`), what each step answered
  (`spell line: none`, `first line: type 0 id 5188`, `slot 61 -> macro 3 -> GetMacroSpell 5188`),
  and what `Lines` said (`block`, `not in book`, `no value`). The next report then says in one line
  why a macro shows nothing.

**What the block shows for a macro.** It is the same block as for the spell, but the header's right
side reads `Rank 2 of 2 - macro`. A wrong-rank resolution, such as `/cast Healing Touch(Rank 1)`
coming back as R2, is therefore visible at a glance.

- **The rank written in the macro (decision 12).** Once T25a shows whether `GetMacroSpell` returns
  the written rank, trust a `(Rank N)` in the macro's own text over a max-rank id. The parse moves
  from `Engine/Practice.lua` (`PR.MacroSpell`) into `Spells/`, so the base Forever TOC has it.
- **Not reachable: Cell click-casts.** Hovering a unit frame shows a unit tooltip; there is no spell
  tooltip to extend. The spell's view in the rail is where those spells are read.

### 5.6 The detail key

`db.spellTooltipDetail = "SHIFT"` (default), `"ALT"`, `"CTRL"`, `"ALWAYS"` or `"NEVER"`, set in
Settings -> General. It is a setting because a `[mod:shift]` macro changes the spell under Shift,
and such a player wants Alt.

- On `MODIFIER_STATE_CHANGED`, while a tooltip holds `_spellTipId`, the adapter calls
  `tt:RefreshData()` (new `MD.API.RefreshTooltip(tt)`, guarded by `if tt.RefreshData`). The refresh
  clears the tooltip and re-runs the post-calls.
- The guard is keyed by `(id, detail)`, so the refresh is allowed to rebuild the block once.
- **UNVERIFIED on Forever:** that `RefreshData` re-runs the post-calls. If it does not, the detail
  lines show on the next hover, which is today's behaviour.

---

## 6. (D) Window management

### 6.1 The rules

1. **Only one big window is on screen at a time.** The replay and the practice session take the
   main window's place and give it back (decision 3). Pair mode, where the main window moves aside
   to make room, is the alternative (6.3b) and is built only on the author's yes.
2. **The replay window is in a different strata from the main window.** It is `DIALOG` against
   `HIGH`. Even in pair mode, or a replay dragged over a main window someone reopened, the two
   cannot interleave.
3. **Editors are sheets, not windows.** The bindings editor and the spell picker are children of
   the main window's pane, with a mask. They move, scale and hide with it.
4. **Tools float, each in a strata of its own.** The debug console is in `FULLSCREEN`; the copy box
   and the dropdown lists are in `FULLSCREEN_DIALOG`. No tool shares a strata with a big window.
5. **The main window is anchored TOPLEFT.** A group with another size grows right and down, so the
   left nav stays under the cursor.
6. **The clock is a HUD.** The manager never touches it.

### 6.2 Every window

| Window | Role | Strata / level | Position | ESC | Entering combat |
|---|---|---|---|---|---|
| Main `SpellTunerDashboard` | host | HIGH / 10, `SetToplevel` | TOPLEFT at `db.ui.win.main` (x, y from UIParent's BOTTOMLEFT, in the frame's units), plus a size per group; clamped; `SetUserPlaced(false)`, so the client's layout cache no longer fights the manager | closes it (last) | hides when `db.ui.combat = "hide"` (default) and reopens on the same view after |
| Replay (review) | takeover | DIALOG / 10, `SetToplevel` | the main window's spot (6.3); `db.ui.win.replay` once dragged | back: closes it and reshows what it came from | hides as today; reopens after combat if it was open |
| Practice session | takeover | DIALOG / 10 | the main window's spot, or `db.ui.win.practice` once dragged | 1st: pause; 2nd, while paused: end (kept) | ends and keeps (today's rule) |
| Bindings editor | sheet on Simulate -> Practice | pane +50, mask +30 over the whole pane | centred in the pane, 440x460 | closes the sheet | hides with its owner |
| Spell picker | sheet on Spells | pane +50, mask +30 over the spell view only | the rail's TOPRIGHT +4 | closes the sheet | hides with its owner |
| Debug console | tool | **FULLSCREEN** / 10, `SetToplevel` (today DIALOG / 1, the replay's new strata) | `db.ui.win.console`, no longer re-centred on every open | closes it | stays |
| Copy box | tool | FULLSCREEN_DIALOG / 20 | centred on the window that asked | closes first | stays |
| Dropdown lists | popup | FULLSCREEN_DIALOG / 10 (`UI.LIST_STRATA`, below) | under their button; closed when their owner hides | closes first | -- |
| `SpellTunerTooltip` / GameTooltip | -- | TOOLTIP | beside the hovered row (3.5) | -- | -- |
| Clock | HUD | MEDIUM | `db.clock.point` | never | never |

**Dropdown lists move up a strata.** Today `UI.CreateDropdown`'s list and `UI.CreateTreeDropdown`'s
first list are in `DIALOG` (`Style.lua` 570, 652). Once the replay is in `DIALOG`, its strategy
dropdown's list would share its parent's strata and could draw under the replay's deeper children,
the same interleaving as 6.png. The kit therefore reads the list strata from `UI.LIST_STRATA`
(default `"DIALOG"`, today's value), and the theme sets it to `"FULLSCREEN_DIALOG"`. The tree
dropdown's second list, already `FULLSCREEN_DIALOG`, is then in the same strata as its first, so it
takes the first list's level +10. Opening the copy box closes any open list. TBC keeps `DIALOG`
(T31, section 7).

On TBC every shared window keeps today's behaviour: each shared call site is written
`if MD.Win then MD.Win:... end`, and `UI/Windows_Forever.lua` is not in the TBC TOC.

### 6.3 Takeover

**Why not beside.** On the author's screen the UI space is about 1923 x 1080 units (1920 x 1080 at
UI scale 0.71). Replays open from Reports -> Review and from Practice, and both groups are 1036
wide. With the main window centred, each side has about 443 units free: less than even the
one-column 492 replay, let alone the coached 968. Beside the main window, where it stands, would
almost never fit, so a fit check would be code for a case that seldom happens.

On `Open` of a replay (Review's **Play**, `/st replay`, or a practice session's End):

1. **The main window is shown.** It hides and remembers its path (`MD.Win.returnPath`). The replay
   opens at `db.ui.win.replay` if it was ever dragged, else with its top centre at the main
   window's top centre. That point is computed in screen pixels, because the two frames need not
   share an effective scale:
   `cx = (main:GetLeft() + main:GetWidth() / 2) * main:GetEffectiveScale()`,
   `top = main:GetTop() * main:GetEffectiveScale()`, then
   `replay:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx / rs, top / rs)` with
   `rs = replay:GetEffectiveScale()` (a point's offsets are in the anchored frame's own units, and
   UIParent's BOTTOMLEFT is the screen's origin). Clamped.
   Its header gains **`< SpellTuner`** (84x20, `accent-hover`) at the left.
2. **The main window is not shown** (a replay opened from chat): it opens at `db.ui.win.replay` or
   centred, with no back button.
3. The back button, the x, ESC and `End` close the replay and show the main window on the
   remembered path.

- The main window stays hidden while the replay is open, wherever the replay has been dragged.
  Dragging the replay's header saves `db.ui.win.replay`; from then on it opens there (clamped),
  until `/st ui reset`.
- **The practice session always takes over**: it wants the keyboard and the player's full
  attention. When it ends, its replay opens **directly**, by the same rule, with the main window
  still hidden (it is never shown in between, so nothing flashes). That replay's back button
  returns to Simulate -> Practice.
- `db.replayPos` is migrated into `db.ui.win.replay` once, then deleted.

**Showing the main window during a takeover.** `/st`, `/st spell <name>`, `/st options` and every
other caller of `MD:SelectView` go through `MD.Win:ShowMain(group, view)` when `MD.Win` exists.

- During a **review replay** takeover, the replay closes as if its back button were pressed, and
  the main window opens on the **requested** view (not the remembered one). The two are never shown
  together by a command.
- During a **practice session**, the request is refused with one chat line:
  `Practice is running: ESC pauses, ESC again ends it.` Nothing is queued.

Mockup 5 draws the states.

### 6.3b Pair mode (the alternative in decision 3; not scheduled)

`db.ui.replayPlace = "pair"`. On `Open`, the manager measures the width the replay **can grow to**:
968 when auto-coach is on (two columns, `COL_W 460`, `GUTTER 16`), else 492, so the window never
jumps when the suggested column fills in.

- **The fit test is in screen pixels.** With `ms`, `rs` and `us` the effective scales of the main
  window, the replay and UIParent:
  `(main:GetWidth() + 8) * ms + w * rs <= UIParent:GetWidth() * us`.
  It tests the widths, not the main window's current right edge, because the manager may move the
  main window.
- **If it fits, the main window moves aside**: the manager slides it left so the pair is centred,
  keeping its top. Its own saved position is not overwritten, and it goes back there when the replay
  closes.
- **The replay is anchored to the main window**: `replay:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)`
  (offset in the replay's units). Dragging the main window carries the replay with it.
- **On the main window's `OnSizeChanged`** (a group switch or the grip) the fit test runs again. If
  the pair no longer fits, it becomes a takeover (6.3).
- Dragging the replay itself detaches it: it floats where it was dropped (DIALOG, so it cannot
  interleave) and saves `db.ui.win.replay`.
- If it does not fit, it is a takeover (6.3).

On the author's screen: Review or Practice (1036) with a one-column replay fits (1536); with a
coached two-column replay it does not (2012), so that is still a takeover. Spells (860) with a
coached replay fits (1836).

### 6.4 Sheets

`UI.CreateSheet(pane, maskRegion, w, h, title)` is a child of the pane at pane level +50. It has a
20-px title row, the `pane` fill, and a 1-px accent border (Cell's popups). Behind it
`UI.CreateMask(maskRegion)`, at pane level +30, covers **`maskRegion`** with `mask` and swallows
mouse and wheel input (Cell's `CreateMask`, `Widgets.lua` 1700-1733). The caller chooses what is
masked:

- **Spell picker**: the spell view (everything right of the rail). The rail stays live, so a
  spellbook spell can be dropped onto it and rows reordered while the picker is open (3.4).
- **Bindings sheet**: the whole Practice pane.

Only one sheet is open at a time.

On Forever, `/st binds` and "Edit bindings" open Simulate -> Practice with the bindings sheet.
`UI/BindingsWindow.lua` gains `BW:Build(parent)`; on TBC it is still its own window.

### 6.5 ESC

WoW's `CloseSpecialWindows` hides **every** shown frame named in `UISpecialFrames` in one press.
That is why ESC closes everything today. So, on Forever:

- The main window, the replay window, the sheets, the copy box and the debug console leave
  `UISpecialFrames` (the console joins the stack; if it kept its own entry, one ESC would close the
  console and the top of the stack together).
- One invisible proxy frame, `SpellTunerEscProxy`, is in it. It is shown while the manager's stack
  is not empty.
- **The stack.** An entry is `{ frame, onEsc }`, pushed by `MD.Win:Push` when a managed frame
  shows. It is last in, first out: a dropdown list or the copy box, opened last, is on top.
- **Every close removes its own entries, however it happens.** The manager hooks the `OnHide` of
  every frame it pushes (`HookScript`), and the hook removes that frame's entries wherever they are
  in the stack. So the x button, the combat hide, a takeover hiding the main window, End, back, and
  a parent hiding its child all leave the stack correct.
- **An ESC press**: the client hides the proxy. The proxy's `OnHide` runs the top entry's `onEsc`
  (default: hide its frame). An `onEsc` that returns true keeps its entry: practice's first ESC
  pauses and stays. If entries remain, the proxy re-shows itself on the next frame
  (`MD.API.After(0)`).
- **A hide from code is quiet.** When the stack empties by code (the last entry's frame hid on its
  own), the manager sets `proxy.quiet = true` and then hides the proxy. `OnHide` starts with
  `if proxy.quiet then proxy.quiet = nil; return end`, so only a hide that ESC caused pops an entry.
- Because the client saw a special frame close, the game menu does not open on that press.
- **Dropdown lists** join the stack through a kit hook: the kit calls `UI.OnPopup(list, shown)` when
  it shows or hides a list, if the hook is set; the manager sets it.
- **UNVERIFIED on Forever**: re-showing a special frame from its own `OnHide` in the next frame.
  `/st probe` records `esc=stack` or `esc=all` after one test press. If it fails, the fallback is
  today's per-window entries (`db.ui.escStack = false`, Settings -> General).

### 6.6 Combat

None of these frames is secure, so nothing here is forced by taint. These are comfort rules.

- `db.ui.combat = "hide"` (default) or `"keep"`, in Settings -> General.
  - *hide*: entering combat hides the main window and a review replay, and remembers them.
    `PLAYER_REGEN_ENABLED` reopens them where they were, on the same view. During a takeover only
    the replay hides and comes back; the main window stays hidden, as it was.
  - *keep*: nothing changes. The judged "fade" mode is dropped: it needs `EnableMouse(false)` on
    every interactive child, which is easy to leave incomplete.
- Unchanged rules: practice ends and keeps its recording on combat; nothing auto-opens in combat;
  the picker and the bindings sheet refuse to open in combat.
- The tooltip block works in combat. A description that is secret in combat uses the stale reading,
  marked as such.

### 6.7 Size

The main window is resizable (a 16x16 grip at the bottom-right corner, `SetResizable`,
`SetResizeBounds`). **Each group keeps its own size**, since the panes were built for different
widths:

| Group | Default | Minimum | Why |
|---|---|---|---|
| Spells | 860 x 560 | 860 x 480 | 8 + 108 nav + 8 + 172 rail + 8 + 540 table + 16. The table and card are fixed width, so the minimum is the default width |
| Settings | 860 x 560 | 860 x 480 | Its titled panes are fixed width too |
| Reports | 1036 x 646 | 1036 x 600 | Review is laid out for this width; its reflow is not in this spec |
| Simulate | 1036 x 646 | 1036 x 600, then 900 x 560 once T40 lands | T40 wraps the fight fields; its test asserts that at 900 nothing extends past the pane's right edge |

- A wider window never scrolls sideways and never drops a column. In Spells, the table and the card
  stay 540 wide at the view's left; the header's mana text and Overview's Export anchor to the
  view's right.
- The window is anchored TOPLEFT (6.1), so a group switch that changes the size grows right and
  down. If the bigger group would run off the screen, the clamp pulls it back in; only then does the
  nav move.
- The late grow on `MODULE_LOADED`, which moved the window under the cursor, goes away.

---

## 7. Forever-only, shared, and TBC

| Change | Where | TBC effect |
|---|---|---|
| Theme: palette, `UI.TEXT`, fonts, `UI.px`, `UI.PIXEL`, font offset, `UI.Pitch`, `UI.LIST_STRATA = "FULLSCREEN_DIALOG"`, `UI.OnPopup` | new `UI/Theme_Forever.lua`, Forever TOCs only | none |
| Kit additions: `layout = "rail"` and the per-group content anchor, `UI.CreateRail`, `UI.CreateSheet` / `CreateMask(region)`, `CreateMovableFrame` `opts.back` / `opts.resizable`, the pixel registry and `UI.RestylePixels` | `UI/Style.lua`, additive | none: TBC never passes them, and `UI.PIXEL` is nil there |
| Kit behaviour: dropdown lists read `UI.LIST_STRATA` (default `"DIALOG"`, today's) and call `UI.OnPopup` if set; the tree dropdown's second list sits at the first's level +10; `BuildViews` reuses a button pool | `UI/Style.lua` | none visible: TBC keeps `DIALOG`, has no `OnPopup`, and the pool draws the same buttons (`tools/navui.lua` 25 holds it) |
| Table options: `font`, `justify` per column, `rowHeight`, `zebra`, `bar` cell, `rowWidth`, `marker = "bar"` | `UI/Dashboard_Rows.lua`, additive | none: `opts == nil` is today's table (`tools/dashui.lua` 56 holds it) |
| Window manager `MD.Win` | new `UI/Windows_Forever.lua`, Forever TOCs only | none: shared windows call it behind `if MD.Win` |
| Spell list, rail pane, spell view, overview, tooltip block, macro path | Forever-only files | none |
| Practice panel tokens and wrap, bindings sheet, hidden not-in-book bindings | shared files, gated on `UI.TEXT` / `MD.Win` / the Forever book | none |
| Review, replay text and `MD.Tip` colours; the console's strata, saved place and stack entry | `UI/Dashboard_Review.lua`, `UI/ReplayWindow.lua`, `UI/Tooltip.lua`, `UI/DebugConsole.lua`, gated on `UI.TEXT` / `MD.Win` | none |
| **Proposed, not scheduled:** list the theme (renamed `UI/Theme_Flat.lua`) and `UI/Windows_Forever.lua` (renamed `UI/Windows.lua`) in `SpellTuner_TBC.toc` | `SpellTuner_TBC.toc` (the harness reads its file list from the TOC since T5) | TBC gets the flat palette and the window rules, which would fix the same overlap there. Its dashboard layout stays. Only on the author's yes (decision 10) |

---

## 8. Decisions for the author

Each has a recommendation. The tasks in section 9 implement the recommendation unless the author
says otherwise.

1. **Spell views as a rail, not top tabs.** *Recommend the rail*: it scales past six spells and is
   Cell's Indicators list. The alternative is top tabs with a `>>` overflow menu.
2. **When you learn a new heal after editing the list:** append it with a "new" dot unless you
   removed it once, or only offer it (`New: Regrowth [+]`)? *Recommend appending*: removal is
   remembered, so the list never re-grows a spell you took out.
3. **Replay placement:** take the main window's place, with `< SpellTuner` to go back (6.3)? Or
   pair mode (6.3b): the main window slides aside and the replay docks to it whenever both fit? Or
   float freely in DIALOG strata? *Recommend takeover.* On your screen Review and Practice are 1036
   wide and the replay opens coached (968), so a pair never fits there and only a takeover
   happens; pair mode would only help a one-column replay. Takeover is also the only mode in which
   the two windows can never be on screen together. Pair mode is fully specified, so it can be
   added later without redesign.
4. **Main window in combat:** hide and reopen after (`hide`), or leave it (`keep`)? *Recommend hide*
   as the default: a 860x560 panel mid-screen in a pull is in the way. It comes back on the same view.
5. **Tooltip detail key:** Shift (default), Alt, Ctrl, Always or Never. *Recommend Shift*, changing
   it if you use `[mod:shift]` macros.
6. **Main window size:** resizable with a size per group, or fixed? *Recommend resizable*, with the
   per-group defaults in 6.7.
7. **Rank-row hover:** the game's own spell tooltip plus the block, or a SpellTuner-only tooltip?
   *Recommend the game's*: one tooltip design everywhere, with a fallback if the post-call does not
   fire for `SetSpellByID`.
8. **A "Measured" line** in the rank card and the tooltip, fed by `/st measure`: *recommend
   deferring it* until measure's attribution is shown right on real casts. Your dump today has a
   Healing Touch "landed 12 BELOW" that is a Rejuvenation tick, and a fact line must not repeat that.
9. **Practice bindings for spells not in your book** (Lifebloom from a Cell import): *recommend
   hiding them automatically* on Forever. They stay in saved data, but the panel and the bindings
   sheet never list them, practice never casts them, and they do not count in `6 bindings`. When
   you learn the spell, the binding reappears on its own. An import skips them and names them in
   its report (`skipped (not in your spellbook): Lifebloom`), so nothing vanishes unexplained, and
   the bindings sheet's footer keeps one `muted` line, `1 binding kept for a spell you have not
   learned  [Forget]`, whose hover names it. The alternatives are a visible `[Remove them]` line in
   the panel (the list stays cluttered until you press it) or deleting them on load (a TBC import
   would lose them for good).
10. **TBC opt-in** to the flat theme and the window rules: *recommend not now*. Revisit after a few
    weeks on Forever.
11. **Today's Spellbook table:** kept as Overview -> *Whole book*, or only reachable through the
    picker? *Recommend keeping it as Whole book*, still one row per rank under each family (3.6):
    every per-rank number it shows today stays one click away, and Export stays whole.
12. **A macro that names a rank** (`/cast Healing Touch(Rank 1)`) but resolves to R2: trust the
    text? *Recommend: decide after T25a's probe lines show what `GetMacroSpell` returns.* Until
    then, the `- macro` marker makes a mismatch visible.
13. **Font offset range:** -2 to +2 (4.2), or up to +4 with every shared pane re-laid out? *Recommend
    -2 to +2*: the Spells pane's pitches follow the offset, but Review and Practice have fixed 20-px
    rows that a +4 font would overflow, and re-laying them out is not in this spec.

---

### 8.1 The author's answers (2026-09-29)

The author, on the mockup (`docs/mockups/forever-ui.html`): "rail, takeover, hide in combat, shift
-- go with recommendations". So **every decision in section 8 is taken as recommended**: 1 rail;
2 append new heals with a dot unless removed once; 3 the replay and the practice session take the
main window's place (beside mode 6.3b stays unscheduled); 4 the main window hides in combat and
reopens on the same view; 5 Shift is the detail key; 6 resizable, a size per group; 7 rank-row hover
is the game's tooltip plus the block; 8 no "Measured" line yet; 9 practice bindings for spells not
in the book hidden automatically; 10 TBC does not opt in now; 11 today's table kept as Whole book;
12 a macro naming a rank decided after T25a's probe; 13 font offset -2 to +2.

## 9. Implementation tasks, in dependency order

Each task is one implementer's work. Each ends with: `luac -p` on every changed shipped file; the
file listed in its TOC(s) (the harness reads its file list from the TOC since T5, so a new file
needs no harness edit); the Forever suites loop in `docs/TOOLS.md` §1; `python3 tools/apicheck.py`
with 0 findings; and the sixteen TBC suites whenever a shared file (`Style.lua`, `Dashboard_Rows.lua`,
`Dashboard_Review.lua`, `Tooltip.lua`, `ReplayWindow.lua`, `PracticePanel.lua`, `BindingsWindow.lua`,
`DebugConsole.lua`, `Engine/Practice.lua`) is touched. New adapter bindings also go into
`tools/adaptercheck.lua`'s `FOREVER_ONLY_NAMES` (T25's lesson).

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T27** | **Practice: bindings for spells not in the book** (decision 9). On Forever: `PR.ApplyImport` skips families `PR.InBook` rejects and returns them by name, and the import report prints `skipped (not in your spellbook): Lifebloom`; `PR.Binds()` (what the panel, the sheet and the session read) leaves out a binding whose family is not in the book, **without deleting it**, so it comes back when the spell is learned; `PR.HiddenBinds()` lists them for the sheet's footer line and its `[Forget]`. TBC unchanged. | `Engine/Practice.lua`, `UI/PracticePanel.lua`, `UI/BindingsWindow.lua` (the report line, the footer line) | `tools/practiceforever.lua` (+5: an import skips and names Lifebloom; an existing Lifebloom binding is not listed, not counted, not cast; it is still in `db.practiceBinds`; learning the spell brings it back; Forget deletes it); `tools/practice.lua`, `tools/practiceui.lua` unchanged | -- |
| **T28** | **Macro block: the untyped first-line read, the `SetAction` path and `/st tooltip why`** (5.5). Adapter: in the Macro post-call, `data.lines[1].tooltipID` whatever its type, after the Spell-typed search and before the owner's slot; `hooksecurefunc(GameTooltip, "SetAction", function(tt, slot) ...)` using the **slot argument** (`ActionInfo(slot)`, then `MacroSpell`); a last-hover record (strings only: path, each step's answer); a shared once-per-showing guard. `SpellTip`: records `Lines`' outcome (`block` / `not in book` / `no value`). Core: the `tooltip why` command. | `Client/API_Forever.lua`, `UI/SpellTip_Forever.lua`, `Core_Forever.lua`, `tools/wowstub.lua` (`hooksecurefunc` on the stub tooltip, `S.SetActionTooltip(slot)`, a Macro data whose first line is not Spell-typed), `tools/adaptercheck.lua` | `tools/tipcheck.lua` (+5: the untyped first line gives the block; the SetAction path gives it from the slot argument with no owner; Macro plus SetAction on one showing gives it once; `why` names each step and outcome; a raising owner adds nothing) | -- |
| **T29** | **Theme** (4.1-4.3): `UI/Theme_Forever.lua` (palette, `UI.TEXT`, new fonts, `UI.ApplyFonts`, `db.ui.fontOffset` clamped to -2..+2, `UI.Pitch`, `UI.PIXEL`, `UI.LIST_STRATA`); `UI/Style.lua` additive (`UI.px`, `StylizeFrame` honours `UI.PIXEL` and records the frame in a weak registry, `UI.RestylePixels()`); `MD.API.PhysicalScreenSize`; `Core_Forever.lua` defaults `ui = { fontOffset = 0, scale = 1, combat = "hide", escStack = true, win = {} }` | `UI/Theme_Forever.lua` (new), `UI/Style.lua`, `Client/API_Forever.lua`, `Core_Forever.lua`, `SpellTuner_Mainline.toc`, `SpellTuner.toc` | new `tools/themecheck.lua` (forever: gold absent from `UI.TEXT`, fonts built, an offset of +4 clamped to +2, `UI.Pitch(20)` at -2 / 0 / +2, `px` at scales 0.64 / 0.71 / 1, `RestylePixels` re-applies a new edge to a registered frame); `tools/navui.lua` 25 and `tools/dashui.lua` 56 unchanged | -- |
| **T30** | **Table options** in `Dashboard_Rows.lua`: `font`, per-column `justify`, `rowHeight` (read through `UI.Pitch` by the caller), `zebra`, `rowWidth` (full width), a `bar` cell type, `marker = "bar"`, `onUpdateCells` for in-place refresh. All nil gives today's table, gold included. | `UI/Dashboard_Rows.lua` | `tools/dashui.lua` (56 unchanged, +6 for the options, one asserting no `ffcc00` in a row built with `marker = "bar"`) | T29 |
| **T31** | **Kit: rail, sheet and lists.** `UI.CreateRail(parent, w, opts)` (rows, selection bar, hover `^ v x`, drag reorder with the insertion line, right-click menu, new dot, footer slot); nav `layout = "rail"`, **the content frame re-anchored per group in `nav:Select`** (-8 for a rail group, -32 otherwise), **`nav:SetViews` skipping `BuildViews` for a rail group**, `BuildViews` on a button pool; `UI.CreateSheet(pane, maskRegion, ...)` and `UI.CreateMask(region)`; dropdown lists read `UI.LIST_STRATA`, the tree dropdown's second list at the first's level +10, and `UI.OnPopup(list, shown)` called when set. | `UI/Style.lua` (additive) | `tools/navui.lua` (25 unchanged, +10: a rail group has no top row and its content starts at -8; switching back to a view-row group puts it at -32; `SetViews` on a rail group creates no button; calling `SetViews` five times on Reports leaves the same number of button frames; rail rows are views; reorder fires once; a mask swallows clicks on its region and not outside it; a list takes `UI.LIST_STRATA`; the second list is above the first) | T29 |
| **T32** | **Window manager, core**: `MD.Win:Register(frame, {key, role})`, strata/level/toplevel per 6.2, TOPLEFT anchoring, saved positions with `SetUserPlaced(false)`, clamping, `db.ui.scale` with the position converted on a change, `UI.RestylePixels` on `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED` / a scale change, per-group size and minimum and the resize grip (`CreateMovableFrame opts.resizable`), `MD.Win:ShowMain(group, view)` with `MD:SelectView` routed through it, `/st ui reset`. The dashboard registers; the late grow goes. | `UI/Windows_Forever.lua` (new), `UI/Style.lua` (opts), `UI/Dashboard_Forever.lua`, `Core_Forever.lua`, both Forever TOCs | new `tools/wincheck.lua` (forever: strata; a per-group size restored; switching Spells -> Reports keeps the TOPLEFT; a clamp; a scale change converts the saved position; a scale event restyles) | T29 |
| **T33** | **ESC stack and combat** (6.5, 6.6): the proxy, `Push`, the `OnHide` hook that removes a frame's entries however it hides, the `quiet` flag, `onEsc` returning true to stay, `UI.OnPopup` wired, the `db.ui.escStack` fallback; hide/keep in combat with reopen; the debug console to `FULLSCREEN`, its remembered place, and its stack entry instead of `UISpecialFrames` (guarded, TBC unchanged); the copy box to FULLSCREEN_DIALOG / 20 and closing open lists; the probe's `esc=` line. | `UI/Windows_Forever.lua`, `UI/Dashboard_Forever.lua` (drop its `UISpecialFrames` entry), `UI/DebugConsole.lua`, `Client/Probe.lua` | `tools/wincheck.lua` (+8: one ESC closes one entry; the proxy re-arms; a window closed by its x leaves no entry; a code hide of the proxy pops nothing; practice's entry stays on its first ESC; the console is one entry; combat hides and restores the path; during a takeover only the replay comes back); `tools/probecheck.lua` (+1); `tools/consolecheck.lua` | T32 |
| **T34** | **Replay and practice takeover** (6.3): the main window hidden with its path, the replay at the main window's top centre in screen pixels (or its saved place), the `< SpellTuner` back button (`opts.back`), DIALOG strata, `ShowMain` during a takeover (closes a review replay and opens the requested view; refused during practice), practice ESC pause then end, End -> replay directly -> back to Practice, the `replayPos` migration. Guarded by `if MD.Win`. | `UI/ReplayWindow.lua`, `UI/Windows_Forever.lua`, `UI/Style.lua` (`opts.back`) | `tools/wincheck.lua` (+7: the main window hides and back restores the path; a replay from chat has no back button; the placement at scales 0.71 and 1 lands on the main window's top centre; `/st` during a replay takeover closes it and opens the requested view; `/st` during practice is refused and nothing shows; End opens the replay without showing the main window; `replayPos` migrated once); `tools/replayui.lua` 98 unchanged (tbc); `tools/replayforever.lua` | T32, T33 |
| **T35** | **Spell list model, pure** (3.3): `Spells/Tabs.lua`: `Seed(book)`, `Get`, `Add`, `Remove` (records `removed`), `Move`, `Undo`, `Reconcile(book)`, `Reset`, `Resolve(key)` giving a family or `stale`. `Book` gives each family `key` and `ids`. `cdb.spellTabs` initialised. | `Spells/Tabs.lua` (new), `Spells/Book.lua`, `Core_Forever.lua`, both Forever TOCs | new `tools/tabscheck.lua` (seed = known heals by learn level; fallback to damage with a mana cost; reconcile appends a new heal once and never a removed one or a damage spell; stale entries kept; undo) | -- (parallel with T29) |
| **T36** | **Spells pane: rail and picker**: `UI/SpellsPane_Forever.lua` split out of `Dashboard_Forever.lua`; the Spells group in `layout = "rail"`; views from `Tabs`; the picker sheet with search, masking the view only; drag-in from the spellbook (`MD.API.CursorInfo`; **the cursor is never cleared**); `/st spell <name>` through `ShowMain` when present; the preview banner; pitches through `UI.Pitch`, and a re-render when the font offset changes. | `UI/SpellsPane_Forever.lua` (new), `UI/Dashboard_Forever.lua`, `Client/API_Forever.lua`, `Core_Forever.lua`, `tools/wowstub.lua`, both Forever TOCs, `tools/adaptercheck.lua` | `tools/spellsui.lua` rewritten (the rail lists the seeded families; a tick adds a view; `/st spell` selects one; a drop adds at the row and leaves the cursor as it was; the rail takes a drop while the picker is open; at offset +2 the rail rows are 22 apart) | T31, T35 |
| **T37** | **Tooltip block redesign** (5.1-5.4b, 5.6): `SpellTip:Lines(id, detail, source)` returns `{l, r, lr,lg,lb, rr,rg,rb}`; the spacer, colours as arguments, the plain/detail split (the stale line last in the plain block, the gap line in the detail), `Suggested` first, `~N now` only below max, the Other-kind block and no block for a free one, `- macro` from `source`; `db.spellTooltipDetail`; `MD.API.RefreshTooltip` on `MODIFIER_STATE_CHANGED`; the guard keyed `(id, detail)`; its dropdown in Settings -> General. | `UI/SpellTip_Forever.lua`, `Client/API_Forever.lua`, `Core_Forever.lua`, `UI/Dashboard_Forever.lua` (the dropdown) | `tools/tipcheck.lua` (existing line assertions rewritten to the new shapes; + ASCII, no bare pipe, at most 5 plain lines when fresh and 6 when stale, the stale line last, the gap line only with the key, no range on the plain block, detail lines only with the key, an Other spell's two lines and no hint, no block for a free Other spell, the macro marker) | T28, T29 |
| **T38** | **One spell's view** (3.5): header, the decision strip (`Book:Compare`), the ranks table (T30 options, the bar cell, gap and not-learned rows, tags), the rank card, row hover via `MD.API.SetTooltipSpell` with the fallback, the refresh split, pitches through `UI.Pitch`. `Book` gains `Compare(a, b)`, `shape` (direct / hot / hybrid / none) and `dominatedBy`. | `UI/SpellsPane_Forever.lua`, `Spells/Book.lua`, `Client/API_Forever.lua` | `tools/spellsui.lua` (+8, one asserting no `ffcc00` anywhere in the view), `tools/bookcheck.lua` (+4: Compare's numbers for HT R1 vs R2; shape per family) | T30, T36, T37 |
| **T39** | **Overview** (3.6): My spells; Whole book as today's table under the new look, one row per rank under each family header, with `+` / `listed`; Export moved (format unchanged); the old Spellbook view removed. | `UI/SpellsPane_Forever.lua`, `UI/Dashboard_Forever.lua` | `tools/spellsui.lua` (+3: Whole book has a row per known rank of every family; a gap row; `+` adds); `python3 tools/refcheck.py` on an Export from the stub (format unchanged) | T38 |
| **T40** | **Practice under the theme and the manager**: the bindings sheet (`BW:Build(parent)` on Forever, its ESC entry, its footer line from T27), the panel's `UI.TEXT` colours (role rows 178, key labels 282), the sheet's (105, 165), the wrapping fields row, the `you` tag, the one-line bindings summary, the Simulate minimum lowered to 900. | `UI/BindingsWindow.lua`, `UI/PracticePanel.lua`, `UI/Windows_Forever.lua` (the Simulate minimum), `Modules/SpellTuner_Practice/Commands_Forever.lua` | `tools/practiceui.lua` 49 unchanged (tbc); `tools/practiceforever.lua` (+4: no `ffcc00` in the panel or the sheet; ESC closes the sheet and not the window; at 900 wide no fight field extends past the pane's right edge; the summary does not count a hidden binding) | T27, T31, T32, T33 |
| **T41** | **Clock under the theme** (4.4). | `UI/Clock_Forever.lua` | `tools/clockcheck.lua` | T29 |
| **T42** | **Settings -> General: appearance and windows.** An APPEARANCE titled pane: the font offset slider (-2..+2, `UI.ApplyFonts`, then the Spells re-render), the window scale slider (70-120 %, through `MD.Win`). A WINDOWS pane: combat `hide` / `keep` (kit dropdown), `Close one window per ESC` (`db.ui.escStack`), `Reset window positions` (`/st ui reset`). T37's tooltip detail dropdown sits in the same pane. | `UI/Dashboard_Forever.lua`, `UI/Windows_Forever.lua` | `tools/wincheck.lua` (+4: each control writes its `db` field and applies it; reset clears `db.ui.win`) | T29, T32, T33 |
| **T43** | **Review and replay text under the theme** (4.1, 4.4): Review's run line (379) in `accent` and its four `GameFontHighlightSmall` strings in `UI.FONT_SMALL`; the replay's run strip (1432), header (1656, 1903) and `paused` (1852) in `accent`; `MD.Tip`'s `GOLD` from `UI.TEXT.accent`. All gated on `UI.TEXT`. | `UI/Dashboard_Review.lua`, `UI/ReplayWindow.lua`, `UI/Tooltip.lua` | `tools/reviewui.lua` 23 and `tools/replayui.lua` 98 unchanged (tbc); `tools/replayforever.lua` (+2: no `ffcc00` in the header or the run strip under forever) | T29 |
| **T44** | **Docs**: `CLAUDE.md` rows for the new files, `docs/TESTING.md` §42 (section 10), `docs/ROADMAP-FOREVER.md`, `docs/HISTORY.md`, one `docs/tasks/` file per task. | docs | -- | T27-T43 |
| *(later)* | Structured measure records and a "Measured" line (decision 8). | `Spells/Measure.lua`, `UI/SpellsPane_Forever.lua`, `UI/SpellTip_Forever.lua` | `tools/measurecheck.lua` | T38, the author's call |
| *(not scheduled)* | Pair mode (6.3b, decision 3). | `UI/Windows_Forever.lua`, `UI/ReplayWindow.lua` | `tools/wincheck.lua` (fit by screen pixels at two scales; the main window slides and returns; a group switch that breaks the fit turns into a takeover) | T34, the author's yes |
| *(not scheduled)* | TBC opt-in (decision 10). | `SpellTuner_TBC.toc` | all sixteen TBC suites | the author's yes |

**Parallel tracks:**
- T27 and T28 go first, alone: they answer this report's two bugs.
- T29 and T35 then run in parallel.
- T30, T31, T32, T41 and T43 each need only T29.
- T33 follows T32; T34 and T42 follow T33.
- T37 needs T28 and T29.
- T40 needs T27, T31 and T33.
- T38 is the join point for the Spells pane.

---

## 10. In-game checks (for `docs/TESTING.md` §42)

On the beta client, out of combat unless a step says otherwise. Paste back as in §41.

1. **Practice (T27).** First, before installing T27: on 0.16.1, open Simulate -> Practice and note
   the wording beside Lifebloom (`(not in your spellbook)` confirms 6.png predates the install;
   `(not trained)` means 0.16.1 did not load). Then on T27: Lifebloom is not listed and not counted
   in `N bindings`. Open the bindings sheet: its footer reads `1 binding kept for a spell you have
   not learned [Forget]`, and its hover names Lifebloom. Import from Cell again: the report names
   Lifebloom as skipped. Start a fight and press Lifebloom's key: nothing is cast.
2. **Macro block (T28).** Hover a macro that casts Healing Touch on a Blizzard bar, then on an ElvUI
   bar. The block appears once, and its header ends `- macro`. Whatever happens, type
   `/st tooltip why` and paste the line (it names the path and each step). Try
   `/cast Healing Touch(Rank 1)`: note which rank the header names.
3. **The look (T29, T30, T41, T43).** Nameplates no longer show through the window. No gold text in
   Spells, Practice, the bindings sheet, Review, the replay's header and run strip, or their hover
   tooltips (the debug console keeps its category colours). Borders are one crisp pixel at your UI
   scale; change the game's UI scale, and they are still one pixel without a `/reload`.
4. **Settings (T42).** Settings -> General -> font offset +2: every SpellTuner text grows; in Spells
   the rail rows, the table rows and the card lines move apart, and nothing overlaps. The slider
   stops at +2. Window scale 90 %: the main window shrinks and stays where it was.
5. **The rail (T31, T35, T36).** Spells shows `MY SPELLS` with Healing Touch and Rejuvenation. Add
   Wrath with **+ Add**; with the picker still open, drag Moonfire from your spellbook onto the rail
   (report if nothing happens) and right-click Moonfire off the cursor. Drag Wrath above
   Rejuvenation, and remove it with the hover `x`; press **Undo**. `/reload`: the order is kept.
   Train a new heal (Regrowth at 12): it appears with a dot. A new damage spell does not appear.
6. **One spell (T38, T39).** Healing Touch: the chip says Rank 1; the line compares it with Rank 2;
   the R1 row has the orange bar and `best`. Click R2: the card shows 90 - 115 and crit 135 - 173.
   Hover a row: the game's own Healing Touch tooltip, with the SpellTuner block under it, beside the
   row. Cast a heal: the header's `~` mana changes within 2 s, and the table does not flicker.
   Overview -> Whole book: every rank of every family has its own row.
7. **Tooltip (T37).** Hover Healing Touch R2 on your bar: a blank line, `SpellTuner Rank 2 of 2
   Shift`, then 4 lines. Hold Shift without moving the mouse: the detail lines appear (report if
   they only appear on the next hover). Hover Mark of the Wild: two lines, no Shift. Settings ->
   tooltip detail -> Alt: the hint now says Alt.
8. **Windows (T32-T34).** Reports -> Review -> Play: the main window hides and the replay opens in
   its place with `< SpellTuner`. Type `/st`: the replay closes and the main window opens. Play
   again and press ESC once: only the replay closes, and the main window is back on Review. Start a
   practice fight: the main window hides; type `/st`: a chat line refuses. ESC pauses the fight; ESC
   again ends it and opens the replay without the main window flashing. Back returns to Simulate ->
   Practice. Drag the replay, close it, reopen: it is where you left it. Open the debug console and
   a replay together: neither draws through the other. Enter combat with the main window open: it
   hides, and it comes back after. Type `/st probe` after one ESC test: paste the `esc=` line.
9. **Resize (T32).** Drag the corner of Spells narrower: it stops at 860. Switch to Reports: it keeps
   its own width, and the left nav stays where it was. `/st ui reset` puts every window back.
