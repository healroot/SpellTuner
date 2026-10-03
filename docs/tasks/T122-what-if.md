# T122 -- One UI, W4: What if, on both lines

Status: **ready** 2026-10-03, the One UI round (`docs/SPEC-one-ui.md`, version 0.17.0; mockup
`docs/mockups/one-ui.html`). **Wave D, beside T123.** Starts on the integrated wave C (T120's
pane, T121's block).

## The task (docs/SPEC-one-ui.md 4, 10 W4; mockup M2 "What if open, +150 healing typed" and its caption; D1, D3)

> **W4, What if.** The pane, both providers, the Forever coefficient store, "What changes".

"What would this change for my ranks?" -- a gear swap, a talent or form, a long fight. It is a
**lens on the Spells pane: nothing else reads it** (spec 4.1). The clock, the advisor, the
tooltip block, the coach and practice keep the live numbers. Since T120 TBC has no What if at all
(its old strip, `UI/Dashboard_Simulate.lua`, is on the TOC but unplaced); this task gives both
lines M2's pane and deletes the strip.

Owned files (the only files edited, apart from this one):

- `Spells/WhatIf.lua` (new; every main TOC): the session state and the shared arithmetic
- `Spells/WhatIf_TBC.lua` (new; TBC TOC): TBC's provider
- `Spells/WhatIf_Forever.lua` (new; the two Forever main TOCs): Forever's provider
- `Spells/Book.lua` (Forever): the measured coefficients
- `UI/SpellsPane.lua`: the WHAT IF pane and the what-if drawing
- `UI/Dashboard_Simulate.lua` (deleted)
- `SpellTuner_TBC.toc`: `UI\Dashboard_Simulate.lua` removed; `Spells\WhatIf.lua` and
  `Spells\WhatIf_TBC.lua` right after `Engine\DamageMath.lua` (after the book and RankMath they
  call at run time; T123 edits no TOC line)
- `SpellTuner_Mainline.toc`, `SpellTuner.toc`: `Spells\WhatIf.lua` and `Spells\WhatIf_Forever.lua`
  right after `Spells\Words.lua`
- `tools/whatifcheck.lua` (new), `tools/spellsui.lua`, `tools/dashui.lua` (its what-if strip
  checks), `tools/bookcheck.lua` (forever: the measured counts)

T123 (the same wave) owns `Spells/Book_Model.lua`, `Spells/Book_TBC.lua`, `Spells/Profiles.lua`,
`Engine/DamageMath.lua`, `Engine/RankMath.lua` and the profiles. This task reads TBC's book only
through `MD.Book:Get({ whatIf = true })` (T118's door) and `MD.sim` (which `RankMath:Context`
already reads); it edits none of T123's files.

## What to build

### `Spells/WhatIf.lua` (`MD.WhatIf`, every main TOC, pure but for the event)

The session's what-if values, never saved (not in `db` / `cdb`; a `/reload` clears them):

```lua
WI.STATS = {   -- the M2 STATS rows, in order; both lines
  { key = "heal",    label = "+Healing",           step = 25,  bigStep = 100 },
  { key = "crit",    label = "Crit %" },
  { key = "mana",    label = "Mana",               step = 250, bigStep = 1000 },
  { key = "casting", label = "Regen while casting", unit = "mp5" },
  { key = "base",    label = "Regen resting",       unit = "mp5" },
}
WI:Get(key) / WI:Set(key, v)   -- v nil clears; a number is clamped to >= 0 (crit 0..100)
WI:Clear()                     -- every key, one WHATIF_CHANGED
WI:Active()                    -- any key set
WI:Values()                    -- a copy
WI:Summary()                   -- "+150 healing, +500 mana" (the RANKS note, the header), ASCII
```

- `Set` fires `WHATIF_CHANGED` through `MD:Fire` when the value moved (never on an equal write).
- The class rows are the provider's (`WI.provider.classRows`, below); `WI:Set` accepts any key a
  provider declares.
- **`WI.provider`** is installed by the line (`MD:Provide("WhatIfProvider", ...)` or the same
  value pattern T120 uses for `MD.SpellsLine`): `Live()` (the live value of each key, for the grey
  placeholder), `Book()` (the what-if book: same shape as `MD.Book:Get()`, never cached by the
  caller, never fires `BOOK_CHANGED`), `classRows` (list or nil), `ranksNote(fam)` (the RANKS
  note's suffix or nil), `classNote` (the sentence where a line has no class row, or nil).
- **`WI.Changes(liveFam, whatFam)`** -> the footer line, pure, `MD.Words`' numbers:
  `Suggested: Rank 12 -> Rank 6. Rank 12 per mana 6.09 -> 6.41 (+5%).` (`W.Signed`) when the
  suggested rank moved, else `No change to the suggestion. Rank 12 per mana 6.09 -> 6.41 (+5%).`,
  else `No change to the suggestion.` The rank named is the live suggested one.
- **`WI.Diff(liveEntry, whatEntry)`** -> the set of fields that changed (`value`, `perMana`,
  `perSec`, `casts`, `cost`, `cast`), compared after the pane's own rounding (`MD.Words`' cell
  words), so a change below the shown digit is not drawn as a change.

### `Spells/WhatIf_TBC.lua` (TBC's provider)

- `Book()` writes the what-if values into `MD.sim` (`heal`, `crit`, `mana`, `casting`, `base`;
  `tree` from Form `Caster` / `Tree of Life`, nil for `Live`; `moonglow` 0-3), calls
  `MD.Book:Get({ whatIf = true })`, and leaves `MD.sim` set while the what-if is active (so
  `UI/Advisor.lua:61`'s "simulation active: not real gear" guard keeps working). `WI:Clear()`
  wipes `MD.sim` (the provider subscribes to `WHATIF_CHANGED`).
- `MD.sim` stays the one table `RankMath:Context` reads; nothing else in the addon writes it once
  `UI/Dashboard_Simulate.lua` is gone (the whatifcheck source scan holds that).
- `classRows` = Form (`Live` / `Caster` / `Tree of Life`, a button group) and Moonglow (0-3, a
  box) **only when the book is the druid's**: `MD.ClassProfile:Can("rankTable")` and not
  `MD.RankMath:IsClassBook()` (no `isDruid` read: capscheck's list stays as it is). Another class
  gets no class row and no sentence.
- `ranksNote(fam)`: `costs from the static table` while Form or Moonglow is set (spec 4.3: they
  price costs from `SD:StaticCost`, not the client).
- `Live()`: `RankMath.info`'s live inputs (the `Compute({ live = true })` context: bonus, crit,
  mana, casting and base regen as mp5), the live form and Moonglow rank.

### `Spells/WhatIf_Forever.lua` (Forever's provider)

`Book()` builds a what-if book from `MD.Book:Get()` without touching it: a deep copy of the
families with entries copied (`BS` fields only), then per entry with a value and a `bonus`:

- `value' = value + counts x dHeal` (`dHeal` = the typed +Healing minus the live bonus, for heal
  families; nothing for damage on this line -- no +damage row; D3: no downrank penalty),
  `min' / max'` moved by the same amount;
- `perMana' = value' / cost`, `perSec' = value' / interval` (`MD.Book.IntervalFor`), `casts' =
  MD.Book:CastsFor(entry, pool')` with `pool' = { max = mana or live max, regenCasting = casting /
  5 or live }`;
- crit moves only the card's crit line and the block's (D1: the text's value has no crit in it):
  the entry carries `crit = typed crit / 100` when set;
- then `MD.RankRules.Pareto` / `Suggested` / `DominatedBy` over each family with the book's field
  map, as `Spells/Book.lua`'s `Rows` does, so the suggestion is the what-if's.

`classRows` = nil; `classNote` = `Your talents are already in the spells' text, so there is no
class row.` (M2). `ranksNote(fam)` = `- N of M ranks measured, K estimated` from the family's
entries' `bonus.from` (an entry with no `bonus` counts in M only).

### `Spells/Book.lua` (Forever): the measured coefficients (spec 4.3)

- On every scan **out of combat** with a plain bonus (`Book:Bonus("heal")` not stale), remember
  per spell id the last `{ value, bonus }` (`Book._lastRead`, memory only).
- When a later plain scan has a different bonus **and** a different value for the same id:
  `counts = (value - last.value) / (bonus - last.bonus)`, kept only when finite and in `[0, 2]`
  (a talent above 1 is legal; outside is a text change for another reason). Stored in
  `MD.cdb.bonusCounts[id] = { counts, at = time(), bonus }` (the newest measurement wins).
- `BuildEntry` then sets `entry.bonus = { counts, from = "measured", at, amount, of, why = nil }`
  from `cdb.bonusCounts[id]` when present, else T117's estimate. The measurement never changes a
  value the book shows (Calibration's rule: it only feeds the what-if and the card's word).
- `EntrySig` unchanged (a measurement does not bump `Book.generation`).

### `UI/SpellsPane.lua`: the pane (M2)

- **What if...** in the strip (both lines) opens the **WHAT IF** pane between the strip and
  RANKS; it replaces nothing on Forever and fills TBC's gap since T120. The pane's open state is
  per session.
- **Rows** of label, box, live value: the box empty with the live value in grey (`WI.provider.
  Live()`) until typed; a typed value shows its change in the accent beside it (`+150`). STATS
  (`WI.STATS`), then CLASS (`classRows`) or the `classNote` sentence in `muted`.
- **Steps**: `-` / `+` beside +Healing and Mana by `step`, Shift by `bigStep`.
- **Clear** at the pane's right (`WI:Clear()`).
- **Footer**: `WI.Changes` for the family on screen.
- **While `WI:Active()`**:
  - the chip reads **WHAT IF** in the accent with `live: R12` under the rank (the live suggested);
  - the header's changed stats in the accent (`WI:Summary()`'s keys: the pool's max for Mana, the
    bonus line for +Healing);
  - RANKS' note `what if: ` .. `WI:Summary()` .. the provider's `ranksNote(fam)`;
  - every cell `WI.Diff` names drawn in the accent, its hover `live 6.09, what if 6.41`; the
    per-mana bar keeps the live fill with a 1-px white mark at the what-if value;
  - the rail's row tags and Overview's rows read the what-if book, Overview's title gains a small
    `what if` tag in `muted`;
  - the card reads the what-if entry.
- The pane redraws on `WHATIF_CHANGED`, and on `BOOK_CHANGED` while active (the live book moved
  under it).
- `MD.SpellsLine.whatIf` (T120 left it nil) is not used: the provider is `WI.provider`. The
  dashboards are not this task's files, so the field stays until the integrator removes it.

### `UI/Dashboard_Simulate.lua`

Deleted with its TOC line. `tools/dashui.lua`'s strip checks (478-524: `MD.sim` typed through the
strip, `SIMULATED`, `WhatIfOpen`) are re-based onto the WHAT IF pane (`WHAT IF`, the footer).
Its load-time need for `MD.FamiliesTBC` (line 21) goes too: T123 deletes that alias in this wave.

## The checks (fail first on the parent, then green)

**`tools/whatifcheck.lua`** (new, `HARNESS_FLAVOUR = { "tbc", "forever" }`):

1. `MD.WhatIf` loads; `Set` / `Get` / `Clear` / `Active`; an equal write fires nothing; `Clear`
   fires once; nothing is in `db` or `cdb` after a `Set`.
2. *(tbc)* `+150` healing: the what-if book's Healing Touch R12 equals `RankMath:Compute()` under
   `MD.sim.heal = live + 150`, field for field; `MD.Book:Get()` is unchanged and its generation
   too.
3. *(tbc)* Form Tree of Life and Moonglow 2: the costs equal `SD:StaticCost` with that context;
   the RANKS note names `costs from the static table`.
4. *(tbc)* A priest with the rank table granted in the suite: no class row, no sentence.
5. *(forever)* A measured id: two out-of-combat scans with +healing 100 then 200 and the text
   moving by 30 -> `cdb.bonusCounts[id].counts == 0.3`; a scan in combat, a stale bonus or an
   unchanged text measure nothing; `counts` outside `[0, 2]` is refused.
6. *(forever)* `+150` healing: a measured rank moves by `counts x 150`, an estimated one by its
   `Coefficients` estimate; per mana / per sec / casts recomputed; the suggested rank equals
   `RankRules.Suggested` over the what-if rows.
7. *(forever)* Crit 30: values unchanged, the card's crit line changed.
8. `WI.Changes`: the three footer sentences, ASCII, no bare pipe.
9. **Nothing else reads it** (both flavours): with a what-if active, the clock face
   (`ClockFace.Current`), the tooltip block (`SpellTip:Lines`), the kit (`RankMath:SpellKit` /
   the Forever kit), the advisor's suggested ranks and `MD.Book:Get()` equal their values with no
   what-if, byte for byte.
10. A source scan: no file but `Spells/WhatIf_TBC.lua` writes `MD.sim` (`MD.sim.x =`, `wipe(MD.sim)`
    outside the suites); `UI/Dashboard_Simulate.lua` is absent from every TOC.

**`tools/spellsui.lua`** (both): the pane opens from What if...; a typed +150 draws the chip
`WHAT IF` / `live: R12`, the accent cells and their hovers, the white mark, the RANKS note, the
footer; Clear restores every cell; Shift steps; Forever's sentence in place of the class rows;
TBC's Form row for the druid.

**`tools/bookcheck.lua`** (forever): `entry.bonus.from == "measured"` after check 5's scans, with
`at`; the value shown unchanged.

**`tools/dashui.lua`**: the strip's checks re-based on the pane (its count stays or drops; the
removed checks named in the suite's comment).

**Unchanged**: `tipcheck`, `spelltip`, `clockcheck`, `ttocheck`, `kitcheck`, `capscheck`,
`apicheck` 0, `textcheck` 0. `make check` green.

### Counts

| Suite | Before | After |
|---|---|---|
| `whatifcheck/tbc` | -- | **8** (1-4, 8-10 and the TBC half of 9 counted once) |
| `whatifcheck/forever` | -- | **7** (1, 5-10) |
| `spellsui` (both) | T120's | measured |
| `bookcheck/forever` | today's | +1 |
| `dashui/tbc` | T120's | measured |

(If the suite's counting differs from this split, the integrator records what it prints.)

## Integrator lines

- **TOCs**: the task's own lines; `releasecheck` (the TBC package lists `Spells/WhatIf.lua` and
  `Spells/WhatIf_TBC.lua`, no `UI/Dashboard_Simulate.lua`; the Forever package
  `Spells/WhatIf_Forever.lua`).
- **`tools/data/expected-counts.json`**: `whatifcheck` both, `spellsui` both, `bookcheck/forever`,
  `dashui/tbc`.
- **`CLAUDE.md`**: new rows `Spells/WhatIf.lua` (**One What if** (T122): session-only values,
  `WHATIF_CHANGED`, the provider, `Changes`, `Diff`; nothing outside the Spells pane reads it),
  `Spells/WhatIf_TBC.lua` (`MD.sim` written here only; the druid's Form / Moonglow rows; the
  static-cost note), `Spells/WhatIf_Forever.lua` (`value + counts x delta`, the rules re-run,
  the measured / estimated note). `Spells/Book.lua`: `**T122:**` (`cdb.bonusCounts`, out of
  combat, plain bonus, `[0, 2]`, never changes a shown value). `UI/SpellsPane.lua`: `**T122:**`
  (the WHAT IF pane, M2). Delete the `UI/Dashboard_Simulate.lua` row. `MD.SpellsLine.whatIf`
  removed from both dashboards (one line each) if still nil.
- **`docs/TOOLS.md`**: the `whatifcheck` row.
- **`docs/DECISIONS.md`**: "What if, one lens" -- the values are session-only, nothing outside the
  Spells pane reads them, Forever's coefficient is measured from the player's own gear changes
  before it is estimated, and a measurement never changes a shown value.
- **`docs/TESTING.md`** section 49: open What if..., type +150 healing, read the footer; on
  Forever change a piece of +healing gear out of combat, reopen, read `measured` on the card.

## Deviations allowed

- If `time()` is refused by `apicheck` on Forever, store `at = nil` and let `W.Bonus` drop the
  date (`31% measured`); name it in the task's closing note.
- The class rows may be a button group or a dropdown, whichever fits the pane at 860 px (T120's
  width), as long as `Live` stays the first choice.

## Out of scope

- A +damage what-if row (no line can price it from what it reads yet); class rows for a class
  other than the TBC druid; saving a what-if.
