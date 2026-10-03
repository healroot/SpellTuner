# T117 -- One UI, W1: the book contract, the coefficients, the words on TBC

Status: **ready** 2026-10-03, the One UI round (`docs/SPEC-one-ui.md`, version 0.17.0; mockup
`docs/mockups/one-ui.html`). **Wave A, alone.** Starts on the commit that adds this file. Every
later task of the round (T118-T123) builds on it.

## The task (docs/SPEC-one-ui.md 3.1, 3.4's last line, 4.3 "Else estimated", 10 W1; mockup M1's +Healing pair, M2's estimated hover, M5's How lines)

> **W1, the contract.** `Spells/BookShape.lua`; `Spells/Coefficients.lua` (moved out of RankMath;
> byte-identical numbers); `Spells/Words.lua` on TBC; the new entry fields on Forever's book.

The pane and the tooltip block become shared files in W3 / W5. They can only be shared if both
books answer the same questions in the same shape. This task writes the shape down
(`Spells/BookShape.lua`, the way `Engine/Kit.lua` holds the kit's), moves the +healing
coefficient rules where both lines can read them (`Spells/Coefficients.lua`), and makes Forever's
book send the four new fields. It also does the two file moves the later waves need
(`UI/SpellsPane_Forever.lua` -> `UI/SpellsPane.lua`, `UI/SpellTip_Forever.lua` -> `UI/SpellTip.lua`),
so that no task of waves C / D renames a TOC line beside another task's line.

Owned files (the only files edited, apart from this one):

- `Spells/BookShape.lua` (new)
- `Spells/Coefficients.lua` (new)
- `Engine/RankMath.lua`
- `Engine/DamageMath.lua`
- `Spells/Book.lua`
- `Spells/Words.lua`
- `UI/SpellsPane_Forever.lua` -> `UI/SpellsPane.lua` (`git mv`; the header comment only)
- `UI/SpellTip_Forever.lua` -> `UI/SpellTip.lua` (`git mv`; the header comment only)
- `SpellTuner_TBC.toc`, `SpellTuner_Mainline.toc`, `SpellTuner.toc`: **only the lines named in
  "TOC lines" below**
- `tools/bookshapecheck.lua` (new, forever / tbc)
- `tools/restylecheck.lua` (the `OWNED` path of the renamed pane, nothing else)

## What to build

### `Spells/BookShape.lua` (`MD.BookShape`, pure, every main TOC)

The book contract, the way `Engine/Kit.lua` declares the kit's: a table of fields with their
types, `Validate`, `Check`. Lua's library only: no `MD.API`, no `MD.db`, no frame.

- **`BS.TOP`**, the table `Book:Get()` returns:
  `families` (table, family key -> family), `order` (array of family keys), `spells` (table,
  spell id -> entry), `read` (table or nil: Forever's walk counts), `generation` (number).
  This corrects the spec's `{ families, byId, generation }`: the map is `spells`, as both books
  already call it (Lead's correction 1).
- **`BS.FAMILY`**: `key` (string, required), `name` (string, required), `kind`
  (`"heal"` / `"damage"` / nil for Other), `altKind`, `shape` (`"direct"`, `"hot"`, `"hybrid"`,
  `"bloom"`, `"channel"`, `"none"`; `bloom` and `channel` are new, for TBC's Lifebloom and
  Tranquility / Hurricane), `ranks` (array of entries, required), `ids` (array of numbers,
  required), `maxKnown` (entry or nil), `suggested` (entry or nil), `gaps` (array of rank numbers
  or nil), `school` (string or nil: a damage family's school, `"Nature"`), `noSeed` (boolean or
  nil: offered by the picker, never seeded or reconciled into a list -- TBC's Tranquility and
  Swiftmend, Lead's correction 5).
- **`BS.ENTRY`**: every field `Spells/Book.lua` writes today (`id`, `name`, `rank`, `rankText`,
  `level`, `known`, `lowRank`, `passive`, `slot`, `skillLine`, `icon`, `desc`, `descState`,
  `parsed`, `cast`, `castKind`, `cost`, `costState`, `cooldown`, `cooldownFrom`, `targets`,
  `reach`, `targetsWhy`, `lockout`, `stale`, `value`, `min`, `max`, `over`, `dur`, `interval`,
  `intervalBy`, `perMana`, `perSec`, `casts`, `alt`, `suggested`, `dominated`, `dominatedBy`,
  and the `half` / `of` / `kind` a `Half` or `ReadSpell` entry carries), each with its type. The
  suite fails on any field an entry carries that `BS.ENTRY` does not declare, so the list is
  complete by construction: read `Spells/Book.lua`'s `BuildEntry`, `Numbers`, `Rows`,
  `DamageHalf` and `ReadSpell` and declare what they write.
- **The new entry fields** (spec 3.1, with Lead's corrections 1, 3, 4):
  - **`family`** (string, required): the key of the family the entry belongs to. On Forever it
    equals `name`; on TBC it is SpellData's id (`"HealingTouch"`) while `name` is the spell's name
    (`"Healing Touch"`). Every shared reader looks a family up by `book.families[e.family]` from
    W2 on; until then `e.family or e.name` (Tabs, SpellRail and SpellTip read `e.name` today).
  - **`variants`** (array or nil): rows the pane draws under the rank, never ranks of their own
    -- not in `spells`, not in `ids`, not in Pareto, not in `CastsFor`. Each one
    `{ variant = 2, variantLabel = "x2", value, perMana, perSec, casts, cost, cast, afterOverheal }`
    (TBC's Lifebloom rolled x2 / x3). The spec's flat `variant` / `variantLabel` on the entry
    becomes this list (correction 4).
  - **`bonus`** (table or nil): `{ counts, from, amount, of, why, at }` --
    `counts` (number: the share of +healing, or +damage, the rank gets, 0.70; above 1 with a
    talent, 1.20), `from` (`"model"` / `"measured"` / `"estimated"`), `amount` (number or nil: the
    +healing the rank gets now, 840), `of` (number or nil: the player's bonus it is a share of,
    700), `why` (ASCII string or nil: `"x1.20 Empowered Touch"`, `"cast 1.5 / 3.5 x 0.29"`,
    `"group rule, VERIFY"`), `at` (number or nil: `time()` of a measurement). These are the card's
    `+Healing` pair (M1 `840 of your 700 (x1.20 Empowered Touch)`, M2 `31% measured: your gear
    change, 2 Oct`, M4 `~43% group rule, VERIFY`) and the What if's coefficient (T122).
  - **`calc`** (array of ASCII strings or nil): the line's own derivation, plain words, no colour
    codes, no `|`. The block prints the first behind `How` and the rest under it (M5). TBC fills
    it from `RankMath:Explain` (T118); Forever fills `{ "read from the spell's text" }`.
  - **`afterOverheal`** (table or nil): `{ value, perMana, perSec, frac, scope }`, `scope` one of
    `"rank"`, `"family"`, `"kind"` (RankMath's `overheal.scope`). Only where overheal is measured
    (TBC, T118).
- **The methods every book has** (correction 2): `Get()`, `Entry(id)`, `ReadSpell(id)`,
  `Rows(family, pool)`, `CastsFor(entry, pool)`, `Compare(a, b)`, `DefaultPool()`, `Half`,
  `HalfOf`, `GCD` (number), `IntervalFor`, and two new ones:
  - **`Pool()`** -> `{ max, mana, regenCasting, modelled }`: the pool the pane's Casts / Now and
    the block's `~N now` count from. Forever: `MD.Clock:Pool()` when the clock answers (modelled =
    true), else `DefaultPool()` with `mana = max`. It replaces `SpellsPane`'s local `Pool()` and
    `SpellTip`'s `PoolBelowMax` in W3 / W5, so `MD.SpellsLine.poolWord` is not needed (the `~`
    follows `pool.modelled`).
  - **`Bonus(kind, school)`** -> `amount, stale`: the header's second line (spec 3.3).
    Forever, heal: `MD.API.SpellBonusHealing()` read plain out of combat and kept;
    in combat (`MD.inCombat`) or when the read is secret, the last plain reading with
    `stale = true`; nil before any reading. Forever, damage: nil (no `GetSpellBonusDamage` binding
    on this line yet; the header then draws one line).
- **`BS.Validate(book)`** -> `true` or `false, problems` (an array of ASCII strings naming the
  family key / spell id and the field): declared fields only, of their types; `family` names a
  key of `families`; every id in `ids` is in `spells`; `order` lists every key once; a variant row
  is never in `spells`. **`BS.Check(book, who)`** raises with `who` and the first five problems
  when `Validate` fails (what `Kit.Check` does).
- **`BS.METHODS`**: the method names above; `BS.CheckMethods(Book, who)` raises naming a missing
  one. Each book calls it once at file end.

### `Spells/Coefficients.lua` (`MD.Coefficients`, pure, every main TOC)

The rules `Engine/RankMath.lua` and `Engine/DamageMath.lua` repeat today, in one place. **Every
number RankMath and DamageMath return is byte-identical before and after** (the goldens below).

- `Coef.Direct(cast)` = `min(max(cast, 1.5), 3.5) / 3.5`.
- `Coef.Hot(duration)` = `duration / 15`.
- `Coef.Hybrid(cast, duration, directAmount, hotAmount)` -> `directCoef, hotCoef, share`: the
  amount-weighted split RankMath's comment explains (`share = direct / (direct + hot)`,
  `Direct(cast) * share`, `Hot(duration) * (1 - share)`). DamageMath's Moonfire uses the same.
- `Coef.Channel(duration, aoe)` = `duration / 3.5`, halved when `aoe` (Hurricane).
- `Coef.Sub20(level)` = `1 - (20 - level) * 0.0375` below 20, else 1.
- `Coef.Downrank(level, playerLevel)` = `min(1, (level + 11) / max(playerLevel, 1))` -- TBC's rule.
- `Coef.Penalty(level, playerLevel)` = `Downrank * Sub20` (RankMath's local `Penalty`, removed).
- `Coef.GROUP = 0.5` (VERIFY); `RankMath.GROUP_COEF` stays as an alias of it.
- `Coef.Estimate(e, shape)` -> `counts, why` or `nil, reason`: Forever's estimate (spec 4.3, D3),
  **no downrank** (that is TBC's rule, not this client's): `direct` -> `Direct(e.cast or GCD) *
  Sub20(e.level)`; `hot` -> `Hot(e.dur) * Sub20`; `hybrid` -> `Hybrid(...)` over the parsed parts,
  the two summed as one share of the value; a group reach (`e.targets` names party) times `GROUP`.
  `why` names each factor in M2's words: `"cast 1.5 / 3.5 x 0.29"` (the sub-20 factor only when
  below 1, two decimals), `"over 12 s / 15"`, `"group rule"`. No rule -> `nil, "no rule for <shape>"`.

`Engine/RankMath.lua` (druid rows and `ClassRow`) and `Engine/DamageMath.lua` call these and keep
their own `calc` fields unchanged. A coefficient's literal appears only in `Spells/Coefficients.lua`
(the suite greps for `/ 3.5`, `/ 15` and `0.0375` in the two engine files).

### `Spells/Book.lua` (Forever): the new fields

- `entry.family = entry.name` on every entry `BuildEntry` and `ReadSpell` make (the `Half` copies
  keep the source's).
- `entry.bonus` on every entry with a `value` and a kind: `Coef.Estimate(entry, family.shape)` ->
  `{ counts, from = "estimated", why, amount = counts x Book:Bonus(kind) when known, of = that
  bonus }`. A `nil` estimate leaves `bonus` nil. (`"measured"` is T122's, from `cdb.bonusCounts`.)
- `entry.calc = { "read from the spell's text" }` on every entry with a value.
- `EntrySig` (the generation's signature) does not include `bonus.amount` / `of`: a +healing
  reading moving does not bump `Book.generation` (the text moving does, as today).
- `Book:Pool()` and `Book:Bonus(kind, school)` as above; `BS.Check(book, "Spells/Book.lua")` at
  the end of `Scan`; `BS.CheckMethods(Book, ...)` at file end.

### `Spells/Words.lua` on TBC

- `W.GCD = (MD.Book and MD.Book.GCD) or 1.5` (TBC loads Words before its book exists until T118).
- Nothing else in Words reads a Forever-only value at load; confirm by loading it under
  `--flavour tbc` in the suite.
- Two new words for the later waves, both pure:
  - `W.Bonus(e, style)`: `"card"` -> `840 of your 700 (x1.20 Empowered Touch)` (model, amount
    known), `counts ~86% estimated (cast / 3.5)` (estimated), `31% measured: your gear change,
    2 Oct` (measured; the date from `bonus.at` through `date("%d %b")` with the leading zero
    dropped); `"how"` -> `+Healing counts 31%, measured 2 Oct` / `+Healing counts ~12%,
    estimated`; `"tip"` -> the percentage alone. The label is `+Healing` for a heal and `+Damage`
    for a damage family (`W.BonusLabel(kind)`).
  - `W.Signed(pct)` -> `+5%` / `-3%` (the What if footer, T122).

### The two moves

`git mv UI/SpellsPane_Forever.lua UI/SpellsPane.lua` and `git mv UI/SpellTip_Forever.lua
UI/SpellTip.lua`. Only the header comment changes (the new name, "Forever only until T120 / T121").
Both stay on the Forever TOCs only in this task.

### TOC lines (this task edits only these)

- `SpellTuner_TBC.toc`: `Spells\Coefficients.lua` and `Spells\BookShape.lua` right after
  `Spells\Book_TBC.lua` (they read nothing at load; both before `Engine\RankMath.lua` and
  `Engine\DamageMath.lua`, which call Coefficients at run time); `Spells\Words.lua` right after
  `Spells\RankRules.lua`.
- `SpellTuner_Mainline.toc` and `SpellTuner.toc`: `Spells\Coefficients.lua` and
  `Spells\BookShape.lua` right before `Spells\Book.lua`; `UI\SpellsPane_Forever.lua` ->
  `UI\SpellsPane.lua`, `UI\SpellTip_Forever.lua` -> `UI\SpellTip.lua` in place.

## The checks (fail first on the parent, then green)

**`tools/bookshapecheck.lua`** (new, `HARNESS_FLAVOUR = { "forever", "tbc" }`). On the parent it
fails at load (no `MD.BookShape`), which is the expected failure.

Under forever:

1. `MD.BookShape`, `MD.Coefficients` and `MD.Words` load; the book passes `BS.Validate` on the
   stub's druid book, then on each of `tools/stub_books.lua`'s priest, shaman and paladin books
   (alone and beside the druid's).
2. An undeclared field on one entry, a wrong type, an `ids` entry missing from `spells` and a
   variant row placed in `spells` are each refused, naming the id and the field.
3. Every entry has `family == name` and `book.families[e.family]` is its family.
4. Healing Touch Rank 1 at level 1 (stub cast 1.5): `bonus.counts` = 1.5 / 3.5 x 0.2875,
   `from = "estimated"`, `why = "cast 1.5 / 3.5 x 0.29"`; Rejuvenation by `Hot(dur)`; a free
   spell and an Other spell carry no `bonus`.
5. `calc` is `{ "read from the spell's text" }` on valued entries, nil elsewhere.
6. `Book:Bonus("heal")`: plain out of combat; in combat the last reading with `stale = true`; a
   secret read keeps the last plain one; nil before any; `"damage"` nil.
7. `Book:Pool()` with the clock (`modelled = true`, the clock's numbers) and without
   (`DefaultPool`, `mana = max`, `modelled = false`).
8. A +healing change with the text unchanged leaves `Book.generation` unchanged.
9. `BS.CheckMethods(MD.Book)` passes; removing `Pool` raises naming it.
10. `W.Bonus` in its three styles over the three `from` values, ASCII, no `|`.

Under tbc:

11. `Spells/Coefficients.lua`, `Spells/BookShape.lua` and `Spells/Words.lua` load from the TBC
    TOC; `W.GCD == 1.5` with no `MD.Book`.
12. **The golden:** every row of `RankMath:Compute()` (druid at levels 40, 64, 70; the stub's
    gear; Tree of Life on and off; every Lifebloom variant) and of `RankMath:Explain` for each id,
    and `DamageMath.Compute` for every druid damage rank over its fixture text, serialised with
    `%.17g` -- captured on the parent with `--golden` before the first edit and equal byte for
    byte after.
13. `ClassRow` for the three `tbcclasscheck` class fixtures: the same golden, with the caps
    granted in the suite as `tbcclasscheck` does.
14. The coefficient literals (`/ 3.5`, `/ 15`, `0.0375`, `GROUP_COEF = `) appear in neither
    `Engine/RankMath.lua` nor `Engine/DamageMath.lua`.

**Unchanged** (no count moves): `bookcheck` (both), `spellsui/forever`, `tipcheck/forever`,
`spelltip/tbc`, `tbcclasscheck/tbc`, `dashui/tbc`, `profilecheck`, `capscheck`, `kitcheck`,
`simcheck`, `verifycheck/tbc`, `restylecheck` (the renamed path only), `apicheck` 0, `textcheck`
0. `make check` green.

### Counts

| Suite | Before | Failing tests on the parent | After |
|---|---|---|---|
| `bookshapecheck/forever` | -- | fails at load | **10** |
| `bookshapecheck/tbc` | -- | fails at load | **4** |

Record the measured numbers here when done (the house rule: the table is the implementer's).

## Integrator lines

- **TOCs:** already edited by the task (the lines above); check `release.sh`'s package lists the
  two new files in both packages and the renamed files in the Forever one (`releasecheck`).
- **`tools/data/expected-counts.json`:** `bookshapecheck/forever`, `bookshapecheck/tbc`.
- **`CLAUDE.md`:** new rows `Spells/BookShape.lua` (`**The book contract** (T117, SPEC-one-ui
  3.1): MD.BookShape -- BS.TOP / FAMILY / ENTRY / METHODS, Validate, Check, CheckMethods; the new
  entry fields family, variants, bonus, calc, afterOverheal; Book:Pool, Book:Bonus. Pure; every
  main TOC`) and `Spells/Coefficients.lua` (`**The +healing rules, once** (T117): Direct, Hot,
  Hybrid, Channel, Sub20, Downrank, Penalty, GROUP, Estimate (Forever's, no downrank); RankMath
  and DamageMath call it, their numbers byte-identical`). Append `**T117:**` to `Spells/Book.lua`
  (family, bonus estimated, calc, Pool, Bonus, the shape checked at scan end),
  `Spells/Words.lua` (on TBC; W.Bonus, W.Signed), `Engine/RankMath.lua` / `Engine/DamageMath.lua`
  (the rules are Coefficients'), and rename the two rows `UI/SpellsPane_Forever.lua` /
  `UI/SpellTip_Forever.lua` to their new names. The `tools/` row: `bookshapecheck`.
- **`docs/TOOLS.md`** section 1: the `bookshapecheck` row.
- **`docs/DECISIONS.md`**, one entry:

  > ## One book contract (2026-10-03, T117, SPEC-one-ui 3.1)
  >
  > Both lines' books answer one contract, `Spells/BookShape.lua`, checked at the end of every
  > scan the way the kit is. An entry names its family by key (`family`), so a TBC family keeps
  > SpellData's key while its spells keep their names. Lifebloom's rolled rows hang off their rank
  > (`variants`) and are never ranks. The +healing rules live once, in `Spells/Coefficients.lua`;
  > Forever's estimate uses them without TBC's downrank rule and says "estimated".

- **`docs/HISTORY.md`:** the round's entry names T117.

## Deviations allowed

- Field names inside `BS.ENTRY` may follow what `Spells/Book.lua` really writes, if it differs
  from the list above; the suite's "undeclared field" check is the rule.
- `Coef.Estimate`'s `why` wording may change if M2's words do not fit a shape, as long as the
  factors are named and the word `estimated` is the caller's.

## Out of scope

- The TBC book (T118), the pane (T120), the block (T121), the What if and the measured
  coefficients (T122).
- A `GetSpellBonusDamage` binding on Forever.
