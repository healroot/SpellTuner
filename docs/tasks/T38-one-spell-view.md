# T38 -- one spell's view

Status: **built** 2026-09-30 on branch `ui/T38` (base 9a04b62, the integrated head with T30, T36
and T37), for review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T38** | **One spell's view** (3.5): header, the decision strip (`Book:Compare`), the ranks table (T30 options, the bar cell, gap and not-learned rows, tags), the rank card, row hover via `MD.API.SetTooltipSpell` with the fallback, the refresh split, pitches through `UI.Pitch`. `Book` gains `Compare(a, b)`, `shape` (direct / hot / hybrid / none) and `dominatedBy`. | `UI/SpellsPane_Forever.lua`, `Spells/Book.lua`, `Client/API_Forever.lua` | `tools/spellsui.lua` (+8, one asserting no `ffcc00` anywhere in the view), `tools/bookcheck.lua` (+4: Compare's numbers for HT R1 vs R2; shape per family) | T30, T36, T37 |

Spec sections it cites: 3.5 (the view, whole), 4.1 (the palette and text tokens, gold out of the
spell views), 4.2 (the fonts, `UI.Pitch` for every vertical pitch), 4.3 (the metrics: titled pane
0 / -17 / -27, section gap 12, table header 22 plus a 1-px `line` rule, rows 20, chip 150x44, card
pairs 17 in two columns of 262), and 8.1 decision 7 (a rank row's hover is the game's tooltip plus
the block).

## What was built

**`Spells/Book.lua`**

- `family.shape`, set in `GroupFamilies`: `direct` (a range, or an absorb), `hot` (an amount over a
  duration, or a tick every period), `hybrid` (a range and an amount over time) or `none` (no kind).
  Read off the family's own part (heal or damage by its kind), the highest known rank's first, else
  the first rank that has one.
- `entry.dominatedBy`, set in `Rows`: for a dominated rank, the **spell id** of the rank that beats
  it -- the suggested rank when it does, else the one with the best per mana (the tooltip block's own
  rule). An id, a plain number, rather than a second path to a table in the shared cache.
- `Book:Compare(a, b)`: plain numbers in percent, each nil when either side lacks it (never a 0 in
  place of a missing number): `perMana` and `perSec` (a against b, minus one), `value` (a as a
  percent of b), `cast` (a's cast time against b's, minus one; only between two timed casts). nil
  unless both are tables. It says how two ranks differ, never which to cast.

**`Client/API_Forever.lua`**: `MD.API.SetTooltipSpell(tooltip, id)` -- `tooltip:SetSpellByID(id)`
under `pcall`; answers true, or nil plus `absent` (no method, an id that is not a plain number) or
`error`. Recorded as `GameTooltip.SetSpellByID` in the capability table and added to
`tools/adaptercheck.lua`'s `FOREVER_ONLY_NAMES` (22 still: the check counts names against bindings).

**`UI/SpellsPane_Forever.lua`**: a family's view is now 3.5's, all inside one scroll frame under the
preview banner (T36's), 540 wide (524 of columns plus 8 each side):

1. **Header** (`UI.Pitch(48)`): the 32x32 icon on a 1-px black edge, the name in `FONT_HEAD`, the
   shape line in 11-px `text2` -- `Direct heal - Rank 2 of 2 known - 2.0 s cast`,
   `Heal over time - Rank 2 of 2 known - 12 s`, `Damage - hit and over time - Arcane - Rank 1 of 1
   known`, `Utility - 30 mana` (`Absorb`, `Direct damage`, `Damage over time` likewise) -- and at the
   right `~364 / 364 mana`, the `~` and the `mana` colour on the modelled current pool only, the max
   plain; `mana not modelled yet` in `muted` with no pool.
2. **Decision strip** (`UI.Pitch(44)`), only with two or more known ranks that have a value: the
   150-px chip (`pane` fill, 1-px black edge, a 2-px accent bar; `SUGGESTED` 11-px accent, the rank in
   `FONT_BIG`), its hover the kit tooltip with the rule; beside it one line, 13-px `text2`, at most
   two lines, from `Book:Compare(suggested, highest known)`:
   `vs Rank 2 (your highest): 2% more healing per mana, 46% of the heal, a 25% shorter cast.`
   (`less`, `the same`, `longer`, `damage` for a damage family), or
   `Your highest rank is also the best per mana.` when the suggested rank is the highest.
3. **RANKS**, a titled pane (the rule in the theme's `rule`, 0.6): `UI/Dashboard_Rows.lua`'s table
   with T30's options -- `FONT_NUM` cells, right-justified numbers, `rowHeight = UI.Pitch(20)`,
   `headerHeight = UI.Pitch(22)`, the header rule, zebra, full-width rows, `marker = "bar"` (the
   `suggested` fill and 2-px bar, the `selected` fill for the card's rank, the `hover` fill), the
   per-mana `bar` cell scaled to `perMana / max(perMana in this family)`, 0.25 on a dominated or
   not-learned row. Columns exactly 3.5's widths (Rank 52, Lvl 34, Mana 46, Heal/Dmg 58, Per mana
   116, Per s 54, Cast 46, To OOM 58, Tag 60). One row per rank from 1 to the highest listed; a gap
   is one `disabled` row, `R3` and across the rest `not in your spellbook - untrained, or hidden by
   "show all ranks"`; unranked entries follow, one row each. Tags in 11 px: `best` (accent) on the
   suggested rank, `learn at 14` (`disabled`) on a rank not learned, `max` (`text2`) on the highest
   known, `dominated` (`muted`). A family with no value gets a second table with Rank / Lvl / Mana /
   Cast / Tag only. No `*`, no gold, no legend line.
4. **The rank card**, a titled pane named `RANK 1` with `learned at 1` (or `learn at 14`) at its
   right in 11-px `text2`: the spell's own text in quotes (12-px `text2`), then label / value pairs
   in two columns of 262 at `UI.Pitch(17)` (labels `label` 12 px, values `FONT_NUM`):
   `Heals 40 - 55 (avg 48)` / `Crit 60 - 83 (x1.5 assumed)`, `Cost`, `Cast`, `Per mana`,
   `Per s 31.7 over a 1.5 s cast` (`over the 1.5 s global cooldown`, `over its 12 s`,
   `over the N s channel`), `To OOM 14 casts from full`, `Now ~14 from ~364 mana` (mana colour).
   A HoT: `Heals 56 over 12 s`, no crit, `Ticks` only when the text states a tick and a period. A
   hybrid: `Hit`, `Crit`, `Over time`, `Total`. An absorb: `Absorbs`. A stale entry adds `Text read
   before combat - may be out of date` in `bad`. The suggested rank is selected by default (else the
   highest known); a click on a rank row selects another (the fills repaint in place, the card
   re-renders). Under the card, 11-px `muted`: `Values come from the spell's own text. ~ = modelled.`

**Row hover** (decision 7): a known rank shows the game's own tooltip through
`MD.API.SetTooltipSpell(GameTooltip, id)`; the Spell post-call appends the block. The tooltip's
guard (`_spellTipId`) is cleared first, so "the block is there" is read from this showing alone;
when it is not (`_spellTipId ~= id`: the post-call did not run for `SetSpellByID`, UNVERIFIED on
Forever), the row adds the spacer and `SpellTip:Lines(id, detail)` itself; when the method is
absent, the rank's name first. Anchor: TOPLEFT at the row's TOPRIGHT +6, or TOPRIGHT at the row's
TOPLEFT -6 when that would run off the screen's right edge (compared in screen pixels). A gap row
and a rank not learned show the kit tooltip with the reason (`Not in your spellbook: ...`,
`Not learned yet: learn at level 20.`), every colour passed.

**The refresh split.** The view's own 2-s tick (while shown) calls `Book:Get()` and compares what
the view was drawn from -- the key, the preview, the book's generation (bumped on `BOOK_CHANGED`),
the last plain bonus-healing reading, the pool's max, the pitch -- with its last full render. Same:
only the header's mana, the card's To OOM and Now, and the To OOM cells change, in place
(`api:UpdateCells`); nothing released or re-acquired. Different: a full render. A view switch and a
font offset (T36's `FontsChanged`) render at once. The table's row height is fixed at creation
(T30), so the two tables are built once per pitch.

## Tests first

`tools/bookcheck.lua` (+4, at the end, with three fixtures of their own: the probe's Moonfire R1
text, talentsforever's Tranquility R4 and Power Word: Shield R1), against the base's `Book.lua`:

```
Compare: Healing Touch R1 against R2, in percent                         FAIL - raised: ...bookcheck.lua:598: attempt to call method 'Compare' (a nil value)
Compare leaves out what either side lacks, and never raises              FAIL - raised: ...bookcheck.lua:611: attempt to call method 'Compare' (a nil value)
shape per family: direct, hot, hybrid, none                              FAIL - Healing Touch=nil, HybridSpell=nil, PassiveSpell=nil, Rejuvenation=nil, ShieldSpell=nil, TickSpell=nil, Wrath=nil
dominatedBy names the rank that beats a dominated one                    FAIL - ht1=nil rj1=nil ht2=nil sub=nil/nil
17 ok, 4 failed
```

`tools/spellsui.lua` (+8, before the ASCII walk so it covers the view; fixtures `Nourish` R1 / R2 /
R4 not learned with 3.5's own numbers, `Starfall` with the Moonfire text; Rejuvenation and Bearform
from the stub), against the base's pane:

```
T38 the header and the decision strip: which rank, and one factual line  FAIL - raised: ...attempt to index field 'strip' (a nil value)
T38 the ranks table: every rank to the highest listed, the gap, the bar and the tags FAIL - order=familynil,notenil,entrynil,entrynil,entrynil ...
T38 the rank card: the suggested rank by default, a click selects another FAIL - raised: ...attempt to index field 'card' (a nil value)
T38 row hover: the game's tooltip through MD.API.SetTooltipSpell, the block once, beside the row FAIL - raised: ...attempt to index local 'rowFrame' (a nil value)
T38 row hover: the block added when no post-call runs, flipped at the edge, a reason for gap rows FAIL - raised: ...attempt to index local 'rowFrame' (a nil value)
T38 a HoT, a hybrid and a spell with no value: header, strip, columns and card by shape FAIL - raised: ...attempt to index field 'activeTable' (a nil value)
T38 the refresh split: mana, Now and To OOM in place; a book change re-renders; pitches at +2 FAIL - raised: ...attempt to compare number with nil
T38 no ffcc00 anywhere in the view or its tooltips                       FAIL - raised: ...attempt to index local 'rowFrame' (a nil value)
35 ok, 8 failed
```

Two of the eight were corrected while building, both on the test's side: the stub's casting regen
(28.33 a second) keeps up with every cheap rank, so the card's To OOM and Now for Nourish read
`never - regen keeps up` (item 3 now expects that), and the in-place item (7) runs on `BigSpell` (300
mana, already in the suite for the same reason), where both counts are finite. Item 7 also sets the
clock model's `lastSpend` after draining it, as a cast would, or the clock's own "regen had time to
fill it" re-anchors the pool to full on the first tick.

After: `bookcheck 21 ok, 0 failed`, `spellsui 43 ok, 0 failed`.

`tools/wowstub.lua` gained one hunk, tagged `-- T38`: `GameTooltip:SetSpellByID(id)` clears (firing
`OnTooltipCleared`), writes the spell's name as the game's first line, runs the Spell post-calls
unless `S.setSpellByIdNoPostCall`, and records each id in `S.setSpellByIdCalls` when a script set it
to a table. Without it the stub's frame fallback made `SetSpellByID` a silent no-op.

## The full check

The loop in `docs/TOOLS.md` section 1 plus the suites since added (themecheck, wincheck, tabscheck):
every count as on the base except `bookcheck` 17 -> 21 and `spellsui` 35 -> 43 (this task's). TBC
suites unchanged (simcheck PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44,
navui 35, dashui 63, regencheck 27, simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice
74, practiceui 49, migrate 7; adaptercheck/tbc 15, corecheck/tbc 8, svcheck/tbc 1, consolecheck/tbc
1); no shared file touched. Forever: probecheck 87, forevercheck 13, modulecheck 14, kitcheck 7,
recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 14, reviewforever 11, coachforever 18,
practiceforever 20, bindscheck 6, parsecheck 12, tipcheck 37, clockcheck 20, measurecheck 30,
releasecheck 13, themecheck 23, wincheck 39, tabscheck 24, adaptercheck/forever 22, corecheck/forever
10, svcheck/forever 6, consolecheck/forever 17. `python3 tools/apicheck.py`: 0 findings;
`--selftest`: 10 of 10; `python3 tools/refcheck.py --selftest`: ok. `luac -p` on every changed Lua
file.

## Deviations

- **Files outside the row**: `tools/adaptercheck.lua` (`SetTooltipSpell` in `FOREVER_ONLY_NAMES`,
  the rule for a new binding) and `tools/wowstub.lua` (`SetSpellByID`), each hunk tagged `-- T38`.
- **Words the spec leaves open**, chosen here: the value column's header is `Heal` / `Dmg` for a
  direct family and `Total` for a HoT or a hybrid; the header line keeps `Rank N of M known` for every
  shape (the spec's HoT and hybrid examples leave it out); a damage family's card says `Damage` where
  a heal's says `Heals`; a hybrid's card keeps a `Crit` pair for its hit beside `Hit` / `Over time` /
  `Total`; a rank that regen keeps up with reads `inf` in the table and `never - regen keeps up` in
  the card; a family with no value's card is its text, `Cost` and `Cast`; an unranked entry's card
  is titled by its rank text (`PASSIVE`), else `SPELL`.
- **The Tag column** starts 8 px into its 60 (x 480, 52 wide), so a tag never touches the
  right-justified To OOM number beside it; the other widths are 3.5's.
- **`dominatedBy` is an id**, not the entry: a plain number, no cycle in the book's shared cache
  (anything that copies or walks an entry stays finite).
- **`Book:Compare` answers percentages** (`perMana`, `perSec`, `value`, `cast`), which the strip
  rounds; the spec names the function, not its shape.
- **The tooltip guard is cleared before the call** (`GameTooltip._spellTipId = nil`), so a stale id
  from an earlier showing of the same rank cannot pass for this one.
- **A family the book no longer has** (T36's greyed view with `[Remove]`) now draws inside the
  scroll frame under the header, the strip, table and card hidden.
- **Overview is untouched** (T39): its table and its hover are still T36's interim ones.
