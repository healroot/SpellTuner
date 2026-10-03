# T118 -- One UI, W2: the TBC book (`Spells/Book_Model.lua`)

Status: **ready** 2026-10-03, the One UI round (`docs/SPEC-one-ui.md`, version 0.17.0; mockup
`docs/mockups/one-ui.html`). **Wave B, beside T119.** Starts on T117's integrated commit. T120
(the pane) and T121 (the block) read what this task builds.

## The task (docs/SPEC-one-ui.md 3.2, 5.2's first two lines, 10 W2; mockup M1's card, M3's Whole book and picker, M5's How lines)

> **W2, the TBC book.** `Spells/Book_Model.lua`: heals, damage, other, desc, reach. Then retire
> `Families_TBC`.

Forever's `MD.Book` is a spellbook read: every spell, grouped into families of ranks, valued from
its own text. TBC has no such object. It has `RankMath:Compute()` (the druid's heals, valued by the
model), `Engine/DamageMath.lua` (the druid's damage, read from each rank's tooltip) and
`Spells/Families_TBC.lua` (the heal families in Book's shape, for the rail). This task builds
`MD.Book` on TBC out of those, in the contract T117 wrote (`Spells/BookShape.lua`), so the pane
(T120) and the block (T121) can be one file on both lines.

**The numbers do not move.** Every heal value, per mana, per second, casts to OOM, dominance mark
and suggested rank in the TBC book is the RankMath row's, field for field; every damage value is
`DM.Compute`'s. The book is an adapter: it computes nothing twice.

Owned files (the only files edited, apart from this one):

- `Spells/Book_Model.lua` (new)
- `Spells/Families_TBC.lua` (deleted; `git rm`)
- `Spells/Book_TBC.lua`
- `Spells/BookShape.lua` (the new entry fields named below; nothing else)
- `Spells/Tabs.lua`
- `Engine/RankMath.lua`
- `Engine/DamageMath.lua`
- `SpellTuner_TBC.toc`: **one line**, `Spells\Families_TBC.lua` -> `Spells\Book_Model.lua` in place
- `tools/bookshapecheck.lua` (the tbc half)
- `tools/tabscheck.lua`
- `tools/bookcheck.lua` (the tbc half, if a check names `MD.FamiliesTBC`)

T119 (the same wave) owns the Settings files and touches no file above. Its TOC lines are other
lines of the same files (`UI\OptionsFrame.lua` / `UI\Options_About.lua` on TBC); the two edits are
not adjacent, so they merge cleanly.

## What to build

### `Spells/Book_TBC.lua`: a walk every caller can use

`Book_TBC.lua` walks the spellbook for a class book only (`Walk(keyOf)`, the profile's heal
names). The TBC book needs every spell. Two exports, both through `MD.API` as today:

- **`B.WalkAll()`** -> an array of `{ id, name, sub, slot, passive }`, every spell of every tab
  (`SpellBookItemName`, `SpellBookItemKind`; `passive` from `IsPassiveSpell` through the adapter
  when bound, else nil). `Walk(keyOf)` becomes `WalkAll` filtered by `keyOf`; `B:Build()` is
  unchanged in what it returns (the `tbcclasscheck` golden).
- **`B.Read(id)`** -> `{ desc, lines, cost, costFrom, cast, level, cooldown, targets, reach,
  targetsWhy, lockout }`: one rank's text and the reads `B.ReadRank` makes today, without the
  family rules (`DescriptionOf`, `CostOf`, `CastOf`, `LevelOf`, `CooldownOf`, `Reach`, and
  `MD.Parse.Targets` / `Parse.Lockout` on the description). Cached per id per session; a cache
  entry is dropped on `SPELLS_CHANGED` / `LEARNED_SPELL_IN_TAB` (the text is static on TBC, but a
  trained rank is a new id). `B.ReadRank` calls it.

Nothing else in the file changes. `B:Build()` stays the class book's source (`RankMath:Source()`).

### `Engine/RankMath.lua`: three small seams, no number moves

- **`RankMath:Compute(opts)`** passes `opts` to `Context(opts)`. `Compute()` with no argument
  reads `MD.sim` as today (the old dashboard, until T120 / T122 delete it). `Compute({ live =
  true })` ignores it.
- **`RankMath:SuggestedRanks()`** calls `Compute({ live = true })`. A what-if value never fires
  the gear toast (`UI/Advisor.lua`); today it can (the toast compares suggested ranks read under
  `MD.sim`). This is the only behaviour change in the task, and it is a fix.
- **`calc.talentName` and `calc.tickPeriod` on the druid's rows** (`RowFor`, `explain` only):
  `talentName` = `"Gift of Nature, Improved Rejuvenation"` for a HoT, else `"Gift of Nature"`
  (the words `Tip:Spell` hard-codes today); `tickPeriod` = 3, or 1 for Lifebloom. `ClassRow`
  already sets both (T111). The book reads only `calc` fields, never the class.

The T117 golden (`bookshapecheck/tbc` 12-13) is re-based **for these two added calc fields only**:
every other byte equal.

### `Engine/DamageMath.lua`: one reader

- **`DM.Bonus(school)`** -> the +damage of that school (`GetSpellBonusDamage`, the call
  `DM.Compute` already makes, through the same `Live` guard), so the book's `Bonus("damage",
  school)` and the card's `+300 Nature damage` read one place. `DM.Compute` calls it.
- **`DM.SchoolName(family)`** -> `"Nature"` / `"Arcane"` (the table's `schoolName`).

### `Spells/BookShape.lua`: three entry fields more

Declared here first (the T117 rule), all optional:

- `crit` (number): the crit chance the entry's `value` averages in (TBC's heal rows,
  `calc.crit`); nil means the value has no crit in it (Forever, D1). The card's `Heals` pair
  reads it (`3524 - 4003 (4046 with 15% crit)`).
- `castNote` (ASCII string): what the cast time assumes, `"Nature's Grace averaged"` when the
  row's `ng` is true. The header and the card's `Cast` pair print it.
- `school` (string): a damage entry's school name (the family carries it too).

### `Spells/Book_Model.lua` (`MD.Book` on TBC)

TBC TOC, in place of `Spells\Families_TBC.lua` (after `Engine\RankMath.lua` and `Spells\Tabs.lua`,
before `Engine\DamageMath.lua` -- it reads DamageMath only at run time). It calls
`MD.BookShape.CheckMethods(Book, "Spells/Book_Model.lua")` at file end and `BS.Check` at the end
of every build.

**`Book:Get(opts)`** -> the T117 shape `{ families, order, spells, read, generation }`.

- **Live by default.** `Get()` builds from `RankMath:Compute({ live = true })` and caches the
  result until something RankMath reads moves (below). `MD.sim` never reaches it.
- **`Get({ whatIf = true })`** builds from `RankMath:Compute()` (which reads `MD.sim`), uncached,
  never fires `BOOK_CHANGED`, never bumps the generation. It is T122's door; nothing in this task
  calls it but the suite.
- **`generation`** is bumped when a build's signature differs from the last: every family key,
  and per entry `id`, `known`, `value`, `cost`, `cast`, `perMana`, `perSec`, `suggested`,
  `dominated` (the signature `Spells/Book.lua`'s `EntrySig` takes, minus the pool-dependent
  `casts`). The first build counts.
- **Rebuilt on** `SPELLS_REBUILT`, `TALENTS_CHANGED`, `FORM_CHANGED`, `UNIT_INVENTORY_CHANGED`
  (player), `PLAYER_LEVEL_UP`, `OVERHEAL_CHANGED` if it exists (else the 2-s refresh the pane
  already runs reads `Get()` and the signature decides). A rebuild whose signature moved fires
  **`BOOK_CHANGED`** with the book, as Forever's scan does. `Spells/Tabs.lua` already listens
  (line 499) and reconciles, so the job `Families_TBC`'s `SPELLS_REBUILT` hook did moves to the
  event both lines fire.

**Heal families** -- RankMath's (`Compute`'s `results`, in `SD.familyOrder`):

| Book field | From |
|---|---|
| `family.key` | SpellData's family id (`"HealingTouch"`) |
| `family.name` | the family's `label` (`"Healing Touch"`) |
| `family.kind` | `"heal"` |
| `family.shape` | `direct` / `hot` / `hybrid` as SpellData's `type`; `lifebloom` -> `"bloom"`; `channel` -> `"channel"`; `instant` (Swiftmend) -> `"none"` |
| `family.ids`, `ranks` | every id of `SD.all[key]`, lowest rank first, one entry each |
| `family.maxKnown`, `suggested` | the highest known entry; the entry whose id is `suggestedID` |
| `family.gaps` | nil (TBC's table is complete: an unlearned rank is a row, `known = false`) |
| `entry.family` | the key |
| `entry.name` | the spell's name through `MD.API.SpellName(id)`, else the label |
| `entry.rank`, `level`, `known` | the row's |
| `entry.rankText` | `"Rank " .. rank` |
| `entry.icon` | `MD.API.SpellTexture(id)` (as `Families_TBC` read it) |
| `entry.value`, `perMana`, `perSec`, `casts` | `row.heal`, `row.hpm`, `row.hps`, `row.casts` |
| `entry.cost` | `{ amount = row.cost, power = 0 }`; `costState = "ok"`, `"free"` when 0 |
| `entry.cast`, `castKind` | `row.cast`; `"instant"` for a HoT / Lifebloom / Swiftmend, `"channeled"` for Tranquility, else `"cast"` |
| `entry.castNote` | `"Nature's Grace averaged"` when `row.ng` |
| `entry.interval`, `intervalBy` | `row.cast`, `"cast"` (RankMath's per second is per cast time) |
| `entry.dominated`, `suggested` | the row's marks (RankRules ran inside `Compute`) |
| `entry.dominatedBy` | `MD.RankRules.DominatedBy(rows, row, RankMath.RULE_FIELDS)` (the id) |
| `entry.min`, `max`, `crit` | `RankMath:Explain(id, nil, { live = true })`'s `calc.min` / `calc.max` / `calc.crit` (direct and hybrid; nil for a HoT) |
| `entry.over`, `dur` | `calc.hot` / `calc.duration` for a HoT, hybrid, bloom |
| `entry.desc`, `descState` | `B.Read(id).desc`; `"ok"`, `"empty"` when the scan tooltip gave nothing |
| `entry.cooldown`, `targets`, `reach`, `targetsWhy`, `lockout` | `B.Read(id)` (the same `Spells/Parse.lua` readers Forever uses) |
| `entry.bonus` | below |
| `entry.calc` | below |
| `entry.afterOverheal` | `{ value = row.effHeal, perMana = row.effHpm, perSec = row.effHps, frac = row.overheal.frac, scope = row.overheal.scope }` when `row.overheal` |
| `entry.variants` | Lifebloom's rows 2 and 3 (`row.variant`): `{ variant, variantLabel = "x2", value, perMana, perSec, casts, cost, cast, afterOverheal }`; never in `spells` / `ids` |

**`entry.bonus`** (model): `{ counts, from = "model", amount, of, why }` from the explained
row's calc. `counts` is the share of +healing the rank gets, every factor RankMath applies to the
bonus: the coefficient (`calc.coef`; a hybrid's `directCoef + hotCoef`; Lifebloom's `hotCoef +
bloomCoef`), times `calc.penalty`, times `calc.bonusMult`. `of` = `calc.bonus`; `amount` = `of x
counts` (the `bonusOut` / `directBonus + hotBonus` / `hotBonus + bloomBonus` RankMath computed:
read those, never re-multiply). `why` names the factors that are not 1, in M1 / M5's words, joined
with `, `: `x1.20 Empowered Touch` (`bonusMult`, `bonusMultName`), `downrank 0.67`
(`penalty`), `level 18 x0.92` (the sub-20 part when RankMath's calc carries it). Rows with no calc
(none today) leave `bonus` nil.

**`entry.calc`** (array of ASCII strings, M5): the `Tip:Spell` Shift lines, as plain strings,
same numbers:

```
2364 base + 840
  700 healing x 1.000 coef x 1.20 Emp. Touch
  then x 1.10 Gift of Nature
```

One `term` per part (direct; HoT; a hybrid's direct and HoT; Lifebloom's HoT and bloom): the
`"%d base + %d"` line, then `"  %d healing x %.3f coef"` with ` x %.2f downrank` when the penalty
is below 0.999 and ` x %.2f <short name>` when the bonus multiplier is above 1.0001 (the `SHORT`
table moves here), then `"  then x %.2f <calc.talentName>"` when `talentMult > 1.0001`, then
`"  +healing includes %d Tree of Life aura"` when the context's `treeAura > 0`. The block prints
the first line behind `How` and the rest under it (T121). `Tip:Spell` itself is T121's to delete;
this task copies its wording into the book, and `bookshapecheck/tbc` holds the two equal.

**Tranquility and Swiftmend** (`exclude` in SpellData): heal families with `noSeed = true`
(T117's field), offered by the picker (M3) and never seeded or reconciled into a list. Their
entries carry `level`, `known`, `cost`, `cast`, `castKind`, `desc`, `icon`, no `value` (RankMath
prices neither). Swiftmend's `calc` carries `Tip:Spell`'s two `Eats` lines as strings
(`"Eats Rejuvenation  1176  (12s of its ticks)"`, `"Eats Regrowth  ..."`), computed exactly as
`Tip:Spell` does (the highest known rank of each, `RowFor(id, ctx, nil, true)`), so the block can
show them for a spell with no value (T121).

**Damage families** (the druid's, `DM.families`): walk the spellbook (`B.WalkAll()`), keep the ids
whose name `DM.Family` accepts, read each rank's text (`B.Read(id).desc`), `DM.Parse(family,
desc)`, `DM.Compute(id, family, parsed)`. A rank whose text does not parse is listed with no
value (its `descState` says why), as Forever lists a spell it cannot read.

| Book field | From |
|---|---|
| `family.key`, `name` | the spell name (`"Wrath"`), as `DM.families` keys it |
| `family.kind`, `school` | `"damage"`, `DM.SchoolName(family)` |
| `family.shape` | `direct` -> `"direct"`, `hybrid` -> `"hybrid"`, `dot` -> `"hot"`, `channel` -> `"channel"` |
| `entry.value` | `c.expected` (crit-averaged, as the heal rows are: D1 keeps TBC's meaning) |
| `entry.perMana`, `perSec` | `c.dpm`, `c.dps` |
| `entry.min`, `max`, `crit` | `c.min`, `c.max`, `c.crit` |
| `entry.cost`, `cast` | `c.cost`, `c.cast` |
| `entry.casts` | `RankMath:CastsToOOM(c.cost, c.cast, pool.max, pool.regenCasting)` |
| `entry.known`, `level` | in the spellbook (`WalkAll` lists only known spells: every damage rank is known), `c.level` |
| `entry.bonus` | `{ counts = (c.coef or 0) + (c.dotCoef or 0) times c.penalty, from = "model", of = c.bonus, amount = c.add + (c.dotAdd or 0), why = "cast 2.0 / 3.5, VERIFY" }` -- the rule named, VERIFY always (M4) |
| `entry.calc` | `Tip:Damage`'s VERIFY lines as strings (coefficient, talents, penalty when known), same numbers |
| `dominated`, `suggested`, `dominatedBy` | `MD.RankRules.Pareto` / `Suggested` / `DominatedBy` over the family's rows with the book's field map (`perMana`, `perSec`, `value`), as `Spells/Book.lua`'s `Rows` does |

**Other**: every `WalkAll` spell that is not passive, is in no heal or damage family, and costs
mana (`B.Read(id).cost > 0`): one family per spell name, `kind = nil`, `shape = "none"`, entries
with `cost`, `cast`, `level`, `known = true`, `desc`, `cooldown`. (Innervate, Mark of the Wild,
Rebirth.) Free and passive spells are not listed (Forever's Other rule, T10c).

**`order`**: the heal families in `SD.familyOrder` (Tranquility and Swiftmend last), then damage in
`DM.families`' order (Wrath, Starfire, Moonfire, Insect Swarm, Hurricane), then Other by name.

**A class book** (`RankMath:IsClassBook()`; false on every shipped profile until T123): the heal
families come from `Compute` over `RankMath:Source()` exactly as above (the rows are `ClassRow`'s,
`calc.talentName` / `tickPeriod` already the class's). Damage for a class is T123's; until then a
class book has heals and Other only.

**A class with no rank table** (every non-druid as shipped): `Get()` returns Other only
(`families` holds no heal and no damage family). The rail then holds Overview and what the player
adds from Other, which is what `Families_TBC` gave (nothing) plus Other.

**The other methods** (T117's list):

- `Entry(id)` -> `Get().spells[id]`; `ReadSpell(id)` -> the same (TBC's book holds every spell a
  tooltip can name; an id outside it is nil).
- `Rows(family, pool)` -> `family.ranks` with `casts` recounted for `pool` (`CastsFor`), copies,
  never the book's own entries.
- `CastsFor(entry, pool)` -> `RankMath:CastsToOOM(entry.cost.amount, entry.interval, pool.max or
  pool.mana, pool.regenCasting)`.
- `Compare(a, b)`, `Half`, `HalfOf`, `IntervalFor` -> `Spells/Book.lua`'s functions, which are
  pure: move them into `Spells/BookShape.lua` as `BS.Compare` / `BS.Half` / `BS.HalfOf` /
  `BS.IntervalFor` if they read nothing of Forever's book, and point both books at them; else
  copy them here with a comment naming the twin. (`Half` on TBC: no family has `altKind` yet, so
  it returns the family.)
- `GCD` = 1.5. `DefaultPool()` -> `{ mana = max, max = UnitPowerMax("player", 0),
  regenCasting = ctx.castingRegen }` (the shared adapter names). `Pool()` -> the same with
  `mana = MD.API.UnitPower("player", 0)` and `modelled = false` (TBC reads its pool: no `~`).
- `Bonus("heal")` -> `RankMath.info.bonus` of the last live build (never stale: TBC reads it in
  combat). `Bonus("damage", school)` -> `DM.Bonus(school)`.

**`MD.FamiliesTBC`, an alias until T123.** `MD.FamiliesTBC = { Get = ..., Build = ..., Source =
... }` returning a view of the book that holds only the heal families with a value and not
`noSeed` (what `Families_TBC` returned: `book.families.HealingTouch`, `order`, `spells`, each
entry's `name` = the key as before). It keeps `UI/Dashboard.lua`, `UI/SpellsView_TBC.lua`,
`tools/dashui.lua` and `tools/tbcclasscheck.lua` working, unchanged, until T120 (the pane) and
T123 delete the last readers. A comment above it names T120 and T123.

### `Spells/Tabs.lua`

- **`Resolve`** looks an entry's family up by `e.family or e.name` (line 447): a TBC entry's
  `name` is the spell's, its `family` the key.
- **`noSeed`**: `Seed`, `SeedList`, `Candidates` and `Reconcile` skip a family with `noSeed`;
  `Add` accepts one (the picker offers it, M3).
- **The TBC source**: `Tabs.source` keeps its default, `Tabs.BookSource` (`MD.Book:Get()`), which
  now answers on TBC. `Families_TBC`'s install line goes with the file. A comment in the header
  says the seam is now the same on both lines.
- The reconcile now runs on `BOOK_CHANGED` on both lines; the TBC `SPELLS_REBUILT` reconcile goes
  with `Families_TBC`.

## The checks (fail first on the parent, then green)

**`tools/bookshapecheck.lua`, tbc half** (T117 wrote 11-14; this task adds 15-26). On the parent
15 fails at load (no `MD.Book` on TBC).

15. `MD.Book` exists on TBC; `BS.CheckMethods` passes; `Get()` passes `BS.Validate` for the
    harness druid at levels 40, 64 and 70, in caster form and Tree of Life.
16. **Every heal entry equals its RankMath row**: `value == row.heal`, `perMana == row.hpm`,
    `perSec == row.hps`, `casts == row.casts`, `cost.amount == row.cost`, `cast == row.cast`,
    `known`, `suggested`, `dominated` -- every rank of every family, `==` on the numbers (they are
    the same numbers, not recomputed). Lifebloom's `variants` equal rows 2 and 3.
17. `afterOverheal` equals the row's `eff*` fields when overheal is seeded in `MD.Overheal`, and
    is nil when it is not.
18. `bonus` for Healing Touch R12 at +700 with Empowered Touch 5/5: `counts == 1.0 x 1.2`,
    `of == 700`, `amount == 840`, `why == "x1.20 Empowered Touch"`; a downranked rank names
    `downrank 0.67` from `calc.penalty`.
19. `calc` equals `Tip:Spell(id, true)`'s Shift lines, line for line, as plain text (the suite
    strips the tip's colours), for one rank of each shape.
20. Tranquility and Swiftmend are families with `noSeed`; Swiftmend's `calc` equals `Tip:Spell`'s
    two `Eats` lines.
21. Damage: with the stub's Wrath and Moonfire texts, each entry's numbers equal
    `DM.Compute(id, family, DM.Parse(family, desc))`'s `expected` / `dpm` / `dps`; the family's
    suggested rank is `RankRules.Suggested` over the rows; `bonus.why` ends `VERIFY`.
22. Other: Innervate and Mark of the Wild are listed with a cost; a passive and a free spell are
    not.
23. **Live**: with `MD.sim.heal = 150`, `Get()`'s numbers are unchanged and `Get({ whatIf = true
    })`'s equal `Compute()`'s under `MD.sim`; neither call bumps the generation through the
    what-if; `RankMath:SuggestedRanks()` is the live map.
24. `BOOK_CHANGED` fires once when gear moves a value, not at all on an unchanged rebuild; the
    generation follows.
25. A non-druid without the rank table: Other only, `BS.Validate` passes.
26. `MD.FamiliesTBC:Get()` equals what `Families_TBC` returned on the parent (a golden, captured
    with `--golden` before the file is deleted: keys, order, ids, ranks' `id` / `rank` / `level`
    / `known` / `cost.amount`, `maxKnown.id`).

**`tools/tabscheck.lua`, tbc** (4 today): the four checks read `MD.Book:Get()` instead of
`MD.FamiliesTBC:Get()`; the "Tranquility and Swiftmend are not seeded" check now asserts
`noSeed` keeps them out of `Seed` and `Reconcile` while `Add` takes one; a new check that
`Resolve` finds `HealingTouch` from an entry whose `name` is `"Healing Touch"`. 4 -> **6**.

**Unchanged**: `dashui/tbc`, `navui/tbc`, `spelltip/tbc`, `tbcclasscheck/tbc` (the alias),
`capscheck`, `profilecheck`, `verifycheck/tbc`, `slashcheck/tbc`, every forever suite, `apicheck`
0, `textcheck` 0. `make check` green.

### Counts

| Suite | Before | After |
|---|---|---|
| `bookshapecheck/tbc` | 4 (T117) | **16** |
| `tabscheck/tbc` | 4 | **6** |

Measured (2026-10-03, branch `oneui/T118`):

| Suite | On the parent (535cff4, the tests first) | After |
|---|---|---|
| `bookshapecheck/tbc` | 5 ok / 11 failed (16 checks; 11-14 and 26 pass) | **16** ok |
| `tabscheck/tbc` | 2 ok / 4 failed | **6** ok |
| `bookshapecheck/forever` | 10 | 10 |
| `tabscheck/forever` | 27 | 27 |

Every other suite unchanged (`dashui/tbc` 84, `navui/tbc` 46, `spelltip/tbc` 49,
`tbcclasscheck/tbc` 52, `verifycheck/tbc` 14, `slashcheck/tbc` 10, `releasecheck` 38). `make check`:
96 runs green (the counts step notes the two new counts for the integrator); `apicheck` 0 findings;
`textcheck` 0 findings.

The druid golden (check 12) was re-based for `calc.talentName` / `calc.tickPeriod` only: the
`--print` transcript compared line by line with the e93d367 one, 351 of 900 lines differ, and every
difference is those two fields (0 lines differ once they are removed).

## Deviations (as built)

1. **The TOC line.** `SpellTuner_TBC.toc` line 41, `Spells\Families_TBC.lua` -> `Spells\Book_Model.lua`,
   is this task's edit to an integrator-owned file (the one line the task names).
2. **Compare / Half / HalfOf / IntervalFor copied, not moved.** `Spells/Book.lua`'s `Compare` and
   `IntervalFor` are copied into `Book_Model.lua` with the twin named (moving them into
   `Spells/BookShape.lua` would touch Forever's book, outside this task's files). `Half` / `HalfOf`
   return the family / entry (no TBC family has `altKind`); Forever's need its private `Numbers`.
3. **`passive`** comes from the adapter's `SpellIsPassive` when a TOC binds it, else from the rank
   text the client prints ("Passive"). No TBC binding exists yet; the integrator may bind
   `IsPassiveSpell` in `Client/API_TBC.lua`.
4. **`Book:Refresh()`**, a method beyond the contract: rebuild now, bump and announce on a moved
   signature. The event handlers and `Get()`'s 2-s cache call it; the suite uses it for what moves
   without an event (the harness's level and form).
5. **`RankMath.info` is put back** after the book's `Compute`, so a book build never changes what
   other readers take as the last Compute's context.
6. **A damage entry's `interval` is `c.cast`** (and `casts` counts over it, from `DefaultPool`, as
   the task's table says); `perSec` stays `DM.Compute`'s `dps` over the Nature's Grace average,
   with `castNote` saying so when it differs.
7. **`CastsFor` counts from `pool.mana or pool.max`**, Forever's twin, not `pool.max or pool.mana`:
   `Pool()`'s `mana` is the current pool, the "~N now" count.
8. **The `why` words.** Heals: `x1.20 Empowered Touch` (with ` (HoT)` on a hybrid, where the
   multiplier is the HoT part's), `downrank 0.70`, `level 14 x0.78` -- from
   `Coefficients.Downrank` / `Sub20` of the rank's level, whose product is `calc.penalty`. Damage:
   the rule (`cast 2.0 / 3.5`, `split by amount`, `duration 12 / 15`, `channel, halved for an
   area`), `+0.10 coef from talents`, `downrank 0.50`, then `VERIFY`.
9. **`B:Build()` calls `B.Forget()`** first, and `B.Forget` also runs on `SPELLS_CHANGED` /
   `LEARNED_SPELL_IN_TAB`; the book's own `SPELLS_REBUILT` handler forgets first too
   (`Data/SpellData.lua` fires it before Book_TBC's `SPELLS_CHANGED` handlers run).
10. **No `OVERHEAL_CHANGED`** exists: the 2-s cache catches a moved overheal; the signature leaves
    `afterOverheal` (measured, not the spell's) and `casts` out.
11. **Event rebuilds wait for a first read**: before anything has read the book an event only
    leaves the next `Get()` to build it (no build at login nobody asked for).
12. **The alias** `MD.FamiliesTBC` keeps `Families_TBC`'s builder (from `RankMath:Source()`) rather
    than a view of the book, so a class book's families come through it as before
    (`tbcclasscheck`'s priest list) and check 26 holds byte for byte; it is forgotten on
    `SPELLS_REBUILT` and rebuilt on the next `Get()`.
13. **Check 25** revokes the priest's `rankTable` / `tooltip` for its run: check 13's class transcript
    grants them and leaves them granted.

## Integrator lines

- **TOC:** `Spells\Families_TBC.lua` -> `Spells\Book_Model.lua` (the task's own edit); check
  `releasecheck` (the TBC package lists the new file and not the old).
- **`tools/data/expected-counts.json`:** `bookshapecheck/tbc`, `tabscheck/tbc`.
- **`CLAUDE.md`:** a new row `Spells/Book_Model.lua` (`**The TBC book** (T118, SPEC-one-ui 3.2):
  MD.Book on TBC -- heal families from RankMath:Compute({ live = true }) (the rows' own numbers),
  damage from Engine/DamageMath.lua over the spellbook, Other from the walk; desc / cooldown /
  reach / lockout from the scan tooltip through Spells/Parse.lua; bonus (model), calc (the Shift
  derivation's lines), afterOverheal, Lifebloom's variants; Tranquility and Swiftmend noSeed;
  Get({ whatIf = true }) the only door MD.sim reaches; BOOK_CHANGED on a moved signature;
  MD.FamiliesTBC an alias until T123`). Delete the `Spells/Families_TBC.lua` row. Append
  `**T118:**` to `Spells/Book_TBC.lua` (`B.WalkAll`, `B.Read`), `Spells/Tabs.lua` (`e.family`,
  `noSeed`, the reconcile on BOOK_CHANGED on both lines), `Engine/RankMath.lua`
  (`Compute(opts)`, `SuggestedRanks` live, `calc.talentName` / `tickPeriod` on the druid's
  rows), `Engine/DamageMath.lua` (`DM.Bonus`, `DM.SchoolName`), `Spells/BookShape.lua` (`crit`,
  `castNote`, `school`).
- **`docs/TOOLS.md`**: the `bookshapecheck` row's tbc half.
- **`docs/DECISIONS.md`**, one entry:

  > ## The TBC book is live (2026-10-03, T118, SPEC-one-ui 3.2)
  >
  > TBC's `MD.Book` is an adapter over the model: every number is RankMath's or DamageMath's
  > row, never recomputed. It reads the live context only; the What if reaches it through one door,
  > `Get({ whatIf = true })`, which is never cached and never announced. The gear toast's suggested
  > ranks are the live ones, so a what-if can no longer fire it.

## Deviations allowed

- If `Compare` / `Half` / `HalfOf` / `IntervalFor` read Forever-only state, copy them into
  `Book_Model.lua` (with the twin named) instead of moving them; say which in this file.
- The rebuild triggers may be narrower if the signature check on the pane's 2-s refresh is
  enough to catch every change; the check 24 must hold either way.
- The `why` words may follow what RankMath's calc carries, as long as each factor that is not 1 is
  named.

## Out of scope

- The pane (T120), the block (T121), the What if (T122), class damage and the caps (T123).
- Any change to a number RankMath or DamageMath returns.
