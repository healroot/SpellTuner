# SPEC: one Spells UI on both lines (0.17)

Status: **approved** 2026-10-03 ("go with your recommendations"). Mockup: `docs/mockups/one-ui.html`.
Tasks: `docs/tasks/T117-*.md` to `T123-*.md` (section 10). The lead's corrections are folded into
the sections below and listed in section 11.

## 1. What the author asked

> "can we make spellbook dashboard in TBC like we did in Forever? and in general have mostly
> similar UI in both"

Answers (2026-10-03):

- **Approach:** "shared pane, I would like to have forever features in TBC and vice versa TBC
  feature (like what if) in forever (but make it well designed)".
- **In scope:** TBC other classes, TBC damage spells, Settings + window sizes, tooltip words.

So the job is one Spells pane and one tooltip block, run by both lines. Each line keeps the
numbers only it can compute. Every feature one line has, the other gets wherever its client
allows. Section 2 lists the rows where the client does not allow it, with the reason.

## 2. Parity: every Spells surface, today and after

| Surface | TBC today | Forever today | After (both lines unless marked) |
|---|---|---|---|
| Rail: MY SPELLS, Overview, one row per family | yes, the druid's 4 heals only | yes, any family | yes, any family: heals, damage, other |
| Picker HEALS / DAMAGE / OTHER | HEALS only, the other two empty | all three | all three |
| Drag a spell from the spellbook onto the rail | no (no `CursorInfo` binding) | yes | yes (TBC gets the binding, T120) |
| Overview -> My spells | yes | yes | yes |
| Overview -> Whole book, Export | no (cut by T84) | yes | yes; one export format |
| Family view: header, strip, RANKS, rank card | C3's own copy | T38's | **one pane**, `UI/SpellsPane.lua` |
| The spell's own text quoted on the card | no (base numbers line) | yes | yes (TBC reads it through the scan tooltip, T111's `SpellTooltipLines`) |
| Card: Cost, Cast, Per mana, Per sec, Casts, Now | Cost only, plus the model's pairs | yes | yes |
| Card: Reach, Cooldown, Lockout | no | yes | yes (TBC reads the same text through `Spells/Parse.lua`) |
| Card: how your +healing counts (downrank) | "Downrank 70%" | no | **+Healing counts N%**: TBC from the model; Forever measured from the text, else estimated (4.3) |
| Card: crit range | in the derivation | yes, x1.5 unverified | yes |
| Rows a spellbook does not list (gap rows) | n/a: TBC's table is complete | yes | Forever only (TBC lists unlearned ranks as `learn at N`) |
| "read before combat" (stale) | n/a: TBC text is static | yes | Forever only |
| Lifebloom rolled x2 / x3 rows | yes | n/a: no Lifebloom | TBC only (the pane draws `variant` rows for any line that sends them) |
| **What if...** | the C3 strip: five boxes, form, Moonglow | **no** | **both**, redesigned (section 4) |
| **After overheal** | yes (combat-log measured) | no | TBC only. Forever has no combat log, so the check is not drawn there (decision D2) |
| Tooltip block | `Tip:Spell`, druid heals, "HPM / HPS" words | `SpellTip:Lines`, any class | **one block** in Forever's words, with TBC's derivation behind the detail key (section 6) |
| Damage tooltips | `Tip:Damage`, druid only | the same block, kind damage | one block, kind damage, every class with a profile |
| Classes | druid; others get the clock only | druid, paladin, shaman, priest | the same four on both (section 5) |
| Settings | 4 columns of 205 px, 1036 x 646 | 2 columns, 860 x 560 | 2 columns, the same views but Modules, 860 x 560 (section 7) |

Things that stay one line's and are not part of this spec: Reports -> Waste and Runs (TBC: the
combat log), Settings -> Modules (Forever: the LoadOnDemand modules), and the advisor (TBC).

## 3. Architecture

### 3.1 One book contract

The Forever pane reads only a small surface of `MD.Book`:

- `Get()` -> `{ families, order, spells, read, generation }` (`spells` is id -> entry; a family
  is found from an entry as `families[entry.family]`, never by the display name)
- `CastsFor(entry, pool)`, `Compare(a, b)`, `DefaultPool()`, `Half`, `HalfOf`, `IntervalFor`, `GCD`
- new: `Pool()` -> `{ max, mana, regenCasting, modelled }` (the pane's pool: Forever the clock's
  model, `modelled = true`; TBC the client's, `modelled = false`) and `Bonus(kind, school)` ->
  `{ amount, stale }` or nil (the header's +healing / +damage). Both replace the pane's own client
  reads.
- the family fields: `key`, `name`, `kind`, `altKind`, `shape`, `ranks`, `maxKnown`, `ids`
- the entry fields: `id`, `rank`, `rankText`, `level`, `known`, `value`, `perMana`, `perSec`,
  `cost` (`amount`, `power`), `costState`, `cast`, `castKind`, `interval`, `intervalBy`, `parsed`,
  `desc`, `suggested`, `dominated`, `dominatedBy`, `cooldown`, `reach`, `targets`, `lockout`,
  `alt`, `stale`

**`Spells/BookShape.lua`** (new, pure, both TOCs) declares this contract the way
`Engine/Kit.lua` declares the kit's. It holds every field with its type and `Validate(book)`.
Each book ends its scan with `BookShape.Check`. A new field is declared there first.

Five entry fields are new, and both books may send them:

- **`family`**: the key of the entry's family (`families[entry.family]`).
- **`variants`**: a list of rows the pane draws under the rank, each `{ variant, variantLabel,
  value, perMana, perSec, casts, cost, cast, afterOverheal }`; never in `spells`, `ids`, Pareto or
  `CastsFor`. TBC's Lifebloom rolled x2 / x3.
- **`bonus`**: `{ counts = 0.70, from = "model" | "measured" | "estimated", amount, of, why, at }`.
  How much of +healing (or +damage) the rank gets, what that is now (`amount` of the player's
  `of`), the rule or talent that says so (`why`) and when it was measured (`at`). It is the card's
  "+Healing" pair and the What if's coefficient.
- **`calc`**: an array of ASCII strings, the line's own derivation for the detail key. TBC fills it
  from `RankMath:Explain` / `Tip:Spell`'s Shift lines (and `Tip:Damage`'s VERIFY lines). Forever
  fills it with "read from the spell's text".
- **`afterOverheal`**: `{ value, perMana, perSec, frac, scope }`. Present only where overheal is
  measured (TBC).

T118 adds three optional ones TBC sends: `crit` (the crit chance the value averages in), `castNote`
(`with Nature's Grace averaged`) and `school` (a damage entry's).

### 3.2 The TBC book: `Spells/Book_Model.lua` (TBC TOC)

`MD.Book` on TBC, built from what TBC already computes:

| Kind | Source | Notes |
|---|---|---|
| heal | `RankMath:Compute()` rows (druid: `Data/SpellData.lua`; another class: `MD.BookTBC`, T111) | `value` = heal, `perMana` = hpm, `perSec` = hps; dominance and the suggested rank are RankMath's own, so nothing is computed twice |
| damage | `Engine/DamageMath.lua` (druid) and the same rules over `MD.BookTBC`'s parsed damage text (other classes) | bases read from each rank's tooltip, as `Tip:Damage` does; Pareto and the suggested rank through `Spells/RankRules.lua` |
| other | the spellbook walk (`MD.BookTBC`'s reader) for spells cast for mana with no value | e.g. Innervate, Mark of the Wild, Rebirth |

`desc` comes from the scan tooltip (`MD.API.SpellTooltipLines`). `reach`, `cooldown` and
`lockout` come from `Spells/Parse.lua` on that text, the same readers Forever uses.
**The TBC book is always live.** `Get()` builds from `RankMath:Compute({ live = true })` and never
sees `MD.sim`; the What if reaches RankMath only through `Get({ whatIf = true })`, which is never
cached, never bumps `generation` and never fires `BOOK_CHANGED`. `generation` follows a signature
of the book (gear, talents, form, the spellbook) and `BOOK_CHANGED` fires when it moves, as on
Forever. After overheal is drawn from `entry.afterOverheal` and does not rebuild the book.

Tranquility and Swiftmend are heal families with no value (Swiftmend carries its `Eats` lines in
`calc`) and `noSeed`: the list never seeds or reconciles them in; the picker offers them.

`Spells/Families_TBC.lua` is retired. `Spells/Tabs.lua` reads the book through its existing
`Tabs.source` seam, so the list, its seeding by role (T110) and its reconcile work unchanged.
`MD.FamiliesTBC` survives as an alias over the book from T118 until T123 removes its last reader.

### 3.3 One pane: `UI/SpellsPane.lua` (every main TOC)

- `UI/SpellsPane_Forever.lua` becomes `UI/SpellsPane.lua` and is listed by all three main TOCs.
- `UI/SpellsView_TBC.lua`'s view and overview are deleted. Its rank table is no longer needed,
  because the pane's table already takes C2's options.
- **A shared file never branches on the client** (apicheck rule 10). What differs is a value the
  line installs, `MD.SpellsLine`:

```lua
MD.SpellsLine = {
  footer        = "Values come from the spell's own text. ~ = modelled.",
                  -- TBC: "Values from the model: your gear, talents and the downrank rules."
  ranksNote     = function(fam) end,     -- RANKS' title-row note (TBC: "live: gear, talents, downrank rules")
  critNote      = "x1.5, unverified",    -- the card's Crit suffix; TBC: nil (the model's crit)
  afterOverheal = nil,                   -- TBC: { get, set, word(fam) } over db.effectiveMode; Forever: nil (D2)
  overviewNote  = function() end,        -- a muted line on Overview (TBC: a class without the rank table)
}
```

`poolWord`, `gaps` and `export` are not line values: the `~` follows `Book:Pool().modelled`, a
book with no gap rows sends none, and the export is the pane's one function (D6). The What if's
provider is `MD.WhatIf.provider` (section 4), not a field here.

- The header's right side becomes two lines on both clients: the mana (`Book:Pool()`), then
  +healing (or +damage on a damage family) from `Book:Bonus(kind, school)`. Forever reads its
  bonus out of combat (`MD.API.SpellBonusHealing`, T12) and keeps the last plain reading in
  combat, marked stale.

### 3.4 One tooltip block: `UI/SpellTip.lua` (every main TOC)

- `UI/SpellTip_Forever.lua`'s `Lines` / `Render` become shared.
- Each line hooks its own tooltip:
  - Forever keeps `MD.API.OnSpellTooltip` / `OnMacroTooltip` / `OnActionTooltip`, registered by
    the block where the adapter has them.
  - TBC keeps its `OnTooltipSetSpell` hook in `UI/SpellTooltip.lua` (TBC TOC only), which now hands
    the id to `SpellTip.OnSpell` (once per showing, `pcall`); its modifier watcher follows the
    detail mode's key. Moving that hook into `Client/API_TBC.lua` is a follow-up.
- `Tip:Spell`, `Tip:Damage` and `Tip:Columns` in `UI/Tip_TBC.lua` are deleted by T121 once the
  block reproduces their numbers; `Tip:Row` by T123. `tools/spelltip.lua` holds that the numbers
  are equal to the kit's.

`Spells/Words.lua` joins the TBC TOC (T117).

## 4. What if, on both lines

### 4.1 What it is for

"What would this change for my ranks?" Typical cases:

- a gear swap (+healing, mana, regen)
- a talent or form (TBC druid: Tree of Life, Moonglow)
- a fight long enough that only casts to OOM matter

It is a lens on the Spells pane. **Nothing else reads it**: the clock, the advisor, the tooltip,
the coach and practice keep the live numbers. This is the old rule from
`UI/Dashboard_Simulate.lua`, kept.

### 4.2 The design (mockup M2)

**What if...** in the strip opens a **WHAT IF** pane between the strip and RANKS. It replaces the
old one-line strip of bare boxes.

- **Rows of label, box, live value.** The box is empty and shows the live value in grey until you
  type. A typed value shows its change in the accent beside it (`+150`).
  - **STATS** (both lines): +Healing, Crit %, Mana, Regen while casting (mp5), Regen resting (mp5).
  - **CLASS** (the profile's, only where the line can price it): TBC druid has Form
    (Live / Caster / Tree of Life) and Moonglow 0-3. Forever has none, because the text already
    carries every talent (Book.adjust is empty).
- **Steps.** `- +` buttons beside +Healing and Mana step by a round amount (25 healing, 250 mana).
  Shift steps by 100 / 1000.
- **Clear** at the pane's right. A what-if lasts the session only; it is never saved.
- **What changes**, one line in the pane's footer, so you don't have to diff the table:
  `Suggested: Rank 12 -> Rank 6. Rank 12 per mana 6.09 -> 6.41 (+5%).` or `No change to the
  suggestion.`
- **While any value is set:**
  - The chip reads **WHAT IF** in the accent, with `live: Rank 12` under the rank.
  - The header shows the changed stats in the accent.
  - RANKS' note reads `what if: +150 healing`.
  - Every cell the what-if changed is drawn in the accent. Its hover gives `live 6.09, what if
    6.41`.
  - The rail and Overview show the what-if numbers, with a small `what if` tag on Overview's
    title, so a list of families can be compared under one swap.

### 4.3 How each line computes it

**TBC.** As today: `MD.sim` is read by `RankMath:Context()` only, and only
`Spells/WhatIf_TBC.lua` writes it. Its book is `MD.Book:Get({ whatIf = true })`. Form and Moonglow
price costs from the static table, and the RANKS note says so (`costs from the static table`). The
Form and Moonglow rows show only when the book is the druid's (the rank table without a class
book). Between T120 and T122 TBC has no What if: the old strip is unplaced.

**Forever.** The values come from the spell's own text, so a what-if needs to know how much of
+healing each rank gets: `value' = value + counts x delta`.

- **Measured first.** The book remembers each rank's value and the bonus it was read at. When the
  bonus changes (a gear swap) and the text changes with it, `counts = dValue / dBonus`. This is
  stored per spell id in `cdb.bonusCounts` and needs nothing from the player. Q1 of the probe
  showed that the descriptions follow bonus healing.
- **Else estimated.** The rules TBC uses are moved out of `Engine/RankMath.lua` into
  `Spells/Coefficients.lua` (pure, both TOCs; RankMath calls it, its numbers unchanged):
  - cast / 3.5 for a direct heal, duration / 15 for a HoT, the hybrid split;
  - the sub-level-20 penalty;
  - no TBC downrank penalty (that is TBC's rule, not this client's; D3).
- **Every estimated number says so.**
  - The card's pair reads `+Healing counts ~86% estimated (cast / 3.5)`.
  - RANKS' note reads `what if: +150 healing - 5 of 7 ranks measured, 2 estimated`.
- **Crit** changes only the crit line and the card. Forever's value is the text's average, which
  has no crit in it (D1).
- **Mana and regen** change Casts and Now, the same on both lines.

## 5. TBC: other classes and damage

### 5.1 Other classes

- Do the swaps T111 lists under "Before the caps are granted":
  - the ranks' source through `RankMath:Source()` in the five places it names;
  - `calc.talentName` / `calc.tickPeriod` in the derivation;
  - the max-rank share through `Source()`.
- Then grant `rankTable` and `tooltip` in `Data/Profile_{Priest,Shaman,Paladin}_TBC.lua`.
- Most of the swap list's UI lines disappear with the shared pane: `UI/SpellsView_TBC.lua` and
  `Tip_TBC`'s builder are deleted, and the book adapter is the one reader of `Source()`.
- **Coach and practice stay the druid's on TBC** (the TBC kit, decision 8 (b)). The caps say so
  with the existing refusal words.

### 5.2 Damage

- Every family `DamageMath` (druid) or the class book (others) prices becomes a damage family in
  the TBC book, so the picker's DAMAGE section fills and a damage role's list seeds with damage
  (T110's `SeedList`, unchanged).
- The values are read from each rank's own tooltip, so nothing is typed from memory (the
  `Data/SpellData.lua` rule).
- The coefficient rules are `Spells/Coefficients.lua`'s, marked VERIFY on the card's detail as
  `Tip:Damage` does today. The druid keeps its Balance talents; another class's damage carries
  `talents not modelled` (T123).
- Each class's damage families are a `damage` table in its TBC profile (names, school, kind, the
  cast the coefficient is taken from, tick), read by `DM.FamiliesFor(class)`; the header's +damage
  is `Book:Bonus("damage", school)`.

## 6. The tooltip block, one vocabulary

Plain block (both lines), from Forever's T37 / T78 / T95:

```
SpellTuner  Rank 12 of 12                                  Shift: detail
Suggested   Rank 6 (+1% per mana)
Per mana    6.09
Per sec     1383
Casts to OOM  9 from full, 7 now
```

Behind the detail key (`db.spellTooltipDetail`, now on TBC too; TBC's default is Shift, as today;
the block registers the three tooltip settings' defaults itself):

- the crit range;
- Reach / Cooldown / Lockout;
- the comparison with the highest rank;
- **the derivation** (`entry.calc`): on TBC, RankMath's lines (base, coefficient, +healing and the
  downrank share, talents, crit), as `Tip:Spell`'s Shift view has them; on Forever, "read from the
  spell's text";
- After overheal, where measured.

TBC's "HPM" / "HPS" words go. The block's numbers on TBC are the model's (live values, no `~`).
`db.spellTooltipDamage` becomes the block's damage half on both lines.

## 7. Settings and window sizes

- **Sizes:** TBC's Spells and Settings groups become 860 x 560, fixed, as on Forever. Reports and
  Simulate stay 1036 x 646 on both lines. Settings' size is T119's; Spells' is T120's (the TBC
  Spells view stays 1036 x 646 until the shared pane replaces it).
- **Views** (mockup M6):
  - TBC: **General, Clock, Review, About**.
  - Forever: **General, Clock, Review, Modules, About**.
  - Review is new on both lines and takes the review / recording panes out of General.
- **General**, two columns on both lines:
  - Left: SPELL TOOLTIPS, APPEARANCE, WINDOWS.
  - Right: MANA CLOCK, ALERTS (TBC: mute, drink reminder, calibration drift), TOOLS.
  - TBC's OOM Widget pane becomes MANA CLOCK: lock, reset, show now, tooltip on the clock,
    Customise.... TBC has no "Show the mana clock" switch (its clock is shown by the visibility
    rule alone; none is added). Show rest time and Show mana cooldown are already the Clock view's
    Text tab (T116) and leave General.
  - TOOLS (TBC, mockup M6): debug console, copy profile, verify spell data. Forever: debug console,
    copy /st dump.
  - INTEGRATIONS goes under TOOLS.
- **Review** (both lines):
  - Left: RECORDING (record fights, allow run recording on TBC, coach a fight when it opens,
    next pull follows, snapshot ticks, let Coach change ranks, full health, danger line).
  - Right: MODEL.
    - TBC: spend half-life, OOM digits, Tree of Life aura, Nature's Grace, reset overheal data,
      regen test. (Verify spell data and copy profile are General's TOOLS, mockup M6.)
    - Forever: Measure, plus one line on what `~` means.
- **About:** the same page on both lines; TBC's stale blurb is replaced with the Forever text.

## 8. Tests

- **`tools/spellsui.lua`** runs under both flavours.
  - Forever: today's goldens, re-based only for the additions (the What if button, the header's
    +healing line). Every re-based line is listed in the task.
  - TBC: new goldens over the stub druid at level 64, plus a priest with the cap granted.
- **`tools/bookshapecheck.lua`** (new, tbc / forever): both books pass `BookShape.Validate`. On
  TBC each entry's numbers equal `RankMath:Compute()`'s row, and `calc` equals the old
  `Tip:Spell` lines (goldens once that builder is deleted).
- **`tools/settingscheck.lua`** (new, tbc / forever): the views, the two columns, the controls
  each writing its setting.
- **`tools/whatifcheck.lua`** (new, tbc / forever):
  - TBC: the pane's numbers equal `MD.sim`'s.
  - Forever: a measured coefficient from two scripted readings, the estimate's rule, the words
    `estimated` / `measured`, "What changes".
  - Both: nothing outside the pane changes (clock face, tooltip, kit).
- **`tools/spelltip.lua`** (tbc) and **`tools/tipcheck.lua`** (forever) on the one block: each
  suite keeps its flavour, since each drives its own line's hook.
- **`tools/tbcclasscheck.lua`** with the shipped caps instead of the suite's grant.
- **`tools/wincheck.lua`** (tbc) for the new sizes, and **`tools/slashcheck.lua`**'s About rows.
- `make check` green, apicheck 0, textcheck 0.

## 9. Decisions for the author

**Answered 2026-10-03:** "go with your recommendations" -- every decision below takes its
Recommended column. The mockup is `docs/mockups/one-ui.html` (M1-M6).

| # | Question | Recommended | Alternative |
|---|---|---|---|
| D1 | What does the Heal column mean? TBC averages crits in; Forever's is the text's average. | **Keep each line's meaning.** The header's hover says which. Changing TBC's moves its suggested ranks; changing Forever's needs a crit multiplier nobody has verified. | Make both crit-averaged |
| D2 | After overheal on Forever | **Not drawn.** Forever gives no overheal (no combat log) | A disabled check that says why; or overheal from replayed fights, marked modelled |
| D3 | Forever's +healing what-if before a coefficient is measured | **Estimate from the rule, marked "estimated"** | Offer +healing only after a gear swap measured it |
| D4 | TBC window sizes | **Spells and Settings 860 x 560** | Keep 1036 x 646 everywhere |
| D5 | Settings views | **General, Clock, Review, (Modules), About** | Keep TBC's one General page |
| D6 | Export | **One format, the probe's dump**, so one tool reads both | TBC exports a plain table |
| D7 | Other classes on TBC | **rankTable and tooltip granted; coach and practice stay the druid's on TBC** | Also build a class kit for TBC (larger, its own spec) |
| D8 | Damage for TBC non-druids | **Read from their tooltips, rules marked VERIFY** | Druid damage only for now |
| D9 | The What if pane | **Inline pane between the strip and RANKS** | A sheet over the view |

## 10. Waves (after approval; Opus, worktrees, one integrator)

1. **W1, the contract** (T117).
   - `Spells/BookShape.lua`
   - `Spells/Coefficients.lua` (moved out of RankMath; byte-identical numbers)
   - `Spells/Words.lua` on TBC
   - the new entry fields on Forever's book
2. **W2, the TBC book** (T118). `Spells/Book_Model.lua`: heals, damage, other, desc, reach. Then retire
   `Families_TBC`.
3. **W3, one pane** (T120).
   - `UI/SpellsPane.lua` on both lines, with `MD.SpellsLine`
   - the TBC rail, picker, drop (`CursorInfo`), Overview with Whole book and Export
   - delete `UI/SpellsView_TBC.lua`'s view and overview
4. **W4, What if** (T122). The pane, both providers, the Forever coefficient store, "What changes".
5. **W5, one tooltip block** (T121). On TBC, deleting `Tip:Spell` / `Tip:Damage`.
6. **W6, classes** (T123). The T111 swaps, the caps granted, every class's damage families.
7. **W7, Settings** (T119). The views, the two columns, TBC's sizes, About.

W1 comes first (wave A: T117). Then W2 and W7 side by side (wave B: T118, T119); then W3 and W5
(wave C: T120, T121; W5's shared block reads the TBC book, so it needs W2); then W4 and W6 (wave D:
T122, T123; both need W3). Wave-mates own disjoint files; a TOC is shared by line, never two
adjacent lines in one wave. The renames (`UI/SpellsPane_Forever.lua` -> `UI/SpellsPane.lua`,
`UI/SpellTip_Forever.lua` -> `UI/SpellTip.lua`) happen in W1 so no later wave renames a line
beside another task's.
The version is 0.17.0. `docs/TESTING.md` gets a section for it.

## 11. Lead's corrections (2026-10-03)

Found while splitting the spec into T117-T123; each is folded into the section named.

1. **`Get()`'s shape** is `{ families, order, spells, read, generation }`, and every entry carries
   `family`; the pane finds a family by `entry.family`, never by its display name (3.1).
2. **`Book:Pool()` and `Book:Bonus(kind, school)`** are book methods; they replace the pane's
   client reads and the spec's `poolWord` (3.1, 3.3).
3. **`bonus`** gains `amount`, `of`, `why`, `at`; **`calc`** is an array of ASCII strings (3.1).
4. **`variants`** is a list on the entry, not flat `variant` / `variantLabel` fields (3.1).
5. **Tranquility and Swiftmend** are heal families with no value and `noSeed` (3.2).
6. **`MD.SpellsLine`** is `{ footer, ranksNote, critNote, afterOverheal, overviewNote }`;
   `poolWord`, `gaps`, `export` and `whatIf` are not line values (3.3).
7. **The TBC book is always live**; the What if reaches it through `Get({ whatIf = true })` only,
   and the gear toast's suggested ranks read `Compute({ live = true })` (a fix: they read `MD.sim`
   before) (3.2, 4.3).
8. **The two renames happen in W1** and a TOC is owned by line (10).
9. **TBC's `CursorInfo` / `SetTooltipSpell` bindings are T120's**; the TBC tooltip hook stays in
   `UI/SpellTooltip.lua`, calling the shared block (2, 3.4).
10. **`Tip:Columns` and `Tip:Row` are deleted too** (T121, T123); the `MD.FamiliesTBC` alias lives
    from W2 to W6 (3.2, 3.4).
11. **Mockup M6 wins for TBC Settings**: copy profile and verify spell data in General's TOOLS,
    calibration drift in ALERTS, the regen test in Review MODEL (7).
12. **`tipcheck` stays Forever's, `spelltip` TBC's** (8).
13. **"T-o5" is T120** (2).
14. **A Form / Moonglow what-if notes `costs from the static table`** (4.3).
15. **The damage header reads `Book:Bonus("damage", school)`** (3.3, 5.2).
16. **T119 changes only the Settings size; the Spells size is T120's** (7).
17. **No "Show the mana clock" switch on TBC** (7).
18. **`BookShape` gains `crit`, `castNote`, `school`** (T118) (3.1).
19. **TBC has no What if between W3 and W4** (4.3).
20. **Class damage families are profile data** (`damage` in each TBC profile, `DM.FamiliesFor`),
    with no class talents modelled (5.2).
21. **The three tooltip settings' defaults are registered by the block** on both lines (6).
