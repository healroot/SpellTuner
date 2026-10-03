# T123 -- One UI, W6: TBC classes and damage

Status: **ready** 2026-10-03, the One UI round (`docs/SPEC-one-ui.md`, version 0.17.0; mockup
`docs/mockups/one-ui.html`). **Wave D, beside T122.** Starts on the integrated wave C: the shared
pane (T120) and block (T121) already draw any book T118 builds, so what is left of T111's list is
small.

## The task (docs/SPEC-one-ui.md 5, 10 W6; mockup M4 "TBC damage family" and the parity table; T111 "Before the caps are granted"; decision 8 (b))

> **W6, classes.** The T111 swaps and the caps granted.

(and spec 5.2: damage for every TBC class, read from its tooltips, D8)

T111 built the priest, shaman and paladin rank machinery on TBC and left it switched off: the
three profiles grant the clock only, because five places still equated "the rank table" with
`Data/SpellData.lua`. Since T118 / T120 / T121 the Spells view, the rail and the tooltip read the
book, so most of that list is gone. This task does the rest, grants `rankTable` and `tooltip`,
and gives every TBC class -- the druid included since T118 -- damage families read from its own
tooltips.

Owned files (the only files edited, apart from this one):

- `Data/Profile_Priest_TBC.lua`, `Data/Profile_Shaman_TBC.lua`, `Data/Profile_Paladin_TBC.lua`
  (caps; a `damage` table)
- `Spells/Profiles.lua` (the `damage` field and its validation)
- `Engine/DamageMath.lua` (class families)
- `Spells/Book_Model.lua` (class damage; the `MD.FamiliesTBC` alias deleted)
- `Spells/Book_TBC.lua` (`IsMaxKnownRank` and `LiveCost` on the class source)
- `Engine/SpendTracker.lua`, `UI/Summary.lua`, `Diagnostics_TBC.lua` (the max-rank share through
  `RankMath:Source()`)
- `UI/Dashboard.lua` (only if wave C left a `MD.SpellData.families` read on the bare-key path:
  T111's lines 53 and 87)
- `UI/Tip_TBC.lua` (delete `Tip:Row`)
- `tools/tbcclasscheck.lua`, `tools/capscheck.lua`, `tools/profilecheck.lua`,
  `tools/bookshapecheck.lua` (tbc), `tools/tabscheck.lua` (its `MD.FamiliesTBC` read)

No TOC line: every file is already listed. T122 (the same wave) owns `Spells/Book.lua`,
`Spells/WhatIf*.lua`, `UI/SpellsPane.lua`, `UI/Dashboard_Simulate.lua`, `tools/dashui.lua`,
`tools/spellsui.lua`, `tools/bookcheck.lua` and the TOC lines; it reads the TBC book only through
`MD.Book:Get({ whatIf = true })`. **`tools/dashui.lua:21`'s `MD.FamiliesTBC` need is T122's to
drop** (named in T122's dashui edit by the integrator if T122 missed it).

## What to build

### The swaps (T111 "Before the caps are granted", what is left)

- **`Engine/SpendTracker.lua`**: `GetCost` (line 32), `IsMaxKnownRank` (49) and the family lookups
  (57, 87) read `local SD = MD.RankMath and MD.RankMath:Source() or MD.SpellData` at call time
  (SpendTracker loads before RankMath; it only calls it). For the druid every read is
  `MD.SpellData`'s, unchanged.
- **`Spells/Book_TBC.lua`**: the class source gains `IsMaxKnownRank(id)` (`maxRank[spells[id].
  family] == id`) and `LiveCost(id)` (the client cost it already reads), the two `Data/SpellData.
  lua` methods the readers above and below call.
- **`UI/Summary.lua`** (the max-rank share, 498) and **`Diagnostics_TBC.lua`** (`/md profile`'s
  "costs of known max ranks", 229): `SD` through `RankMath:Source()`; `static` prints `--` for a
  class source with no `StaticCost` answer.
- **`UI/Dashboard.lua`**: if the bare-key path (an old `db.uiPath` holding a family key) still
  reads `MD.SpellData.families`, read `MD.Book:Get().families` instead. Nothing else in the file.
- `calc.talentName` / `calc.tickPeriod` (T111's druid-only words) were T118's; check they hold.

### The caps

`caps = { clock = true, rankTable = true, tooltip = true }` in the three TBC profiles, and each
file's header comment rewritten (the "not granted yet" paragraph replaced by one line naming
T123). **Coach, practice, simulate and advisor stay the druid's on TBC** (decision 8 (b): the TBC
kit is the druid's); `Can` answers `false, "class"` and the existing refusal words show.
`RankMath:SpellKit` is unchanged.

### Damage families for every TBC class

**`Spells/Profiles.lua`**: a profile field `damage` (table: name -> definition) with
`P.DAMAGE_FIELDS = { names = "table", school = "number", kind = "string", baseCast = "number",
tick = "number", aoe = "boolean" }`; `Validate` refuses a `kind` outside `direct` / `hybrid` /
`dot` / `channel`, a `school` outside 1-7, and a name that is also a heal family's.

**The three profiles' `damage`** -- names, schools and the rule inputs only, never a number a
tooltip prints (the `Data/SpellData.lua` rule), every row VERIFY:

| Class | Family | School | Kind | baseCast | tick |
|---|---|---|---|---|---|
| Priest | Smite | Holy (2) | direct | 2.5 | |
| Priest | Holy Fire | Holy (2) | hybrid | 3.5 | 2 |
| Priest | Mind Blast | Shadow (6) | direct | 1.5 | |
| Priest | Shadow Word: Pain | Shadow (6) | dot | 1.5 | 3 |
| Priest | Mind Flay | Shadow (6) | channel | 3.0 | 1 |
| Shaman | Lightning Bolt | Nature (4) | direct | 3.0 | |
| Shaman | Chain Lightning | Nature (4) | direct | 2.5 | |
| Shaman | Earth Shock | Nature (4) | direct | 1.5 | |
| Shaman | Flame Shock | Fire (3) | hybrid | 1.5 | 3 |
| Shaman | Frost Shock | Frost (5) | direct | 1.5 | |
| Paladin | Exorcism | Holy (2) | direct | 1.5 | |
| Paladin | Holy Wrath | Holy (2) | direct | 2.0 | (aoe) |
| Paladin | Consecration | Holy (2) | dot | 1.5 | 1 (aoe) |

A row whose fixture text `DM.Parse` cannot read is dropped from the profile with a comment naming
the text it could not read (deviation 1), rather than a parser rule guessed for it.

**`Engine/DamageMath.lua`**:

- `DM.FamiliesFor(class)` -> the druid's `DM.families` for `"DRUID"`, else the class profile's
  `damage` (through `MD.Profiles.Get(class).damage`), else `{}`.
- `DM.Family(name, class)`, `DM.Parse(family, text, class)`, `DM.Compute(spellID, family, base,
  class)` take the family from `FamiliesFor(class or MD.player.class)`; the druid's calls, which
  pass no class, are unchanged byte for byte.
- The Balance `TALENTS` apply only to the druid's families; a class family's `calc` carries one
  line `talents not modelled` (VERIFY), so the card and the block say so.

**`Spells/Book_Model.lua`**: the damage section walks `DM.FamiliesFor(MD.player.class)` instead
of `DM.families` -- the druid's book unchanged, a priest's gaining Smite ... Mind Flay -- with
T118's field map, and `order` = heals (`RankMath:Source().familyOrder`), damage in the profile's
order, then Other. A class with no `rankTable` (none after this task, but the generic profile)
keeps Other only.

**`MD.FamiliesTBC` deleted** (T118's alias): its readers are gone after wave C but for
`tools/tbcclasscheck.lua` (351, 541) and `tools/tabscheck.lua` (97), re-based here onto
`MD.Book:Get()`, and `tools/dashui.lua:21` (T122's).

### `UI/Tip_TBC.lua`

Delete `Tip:Row` and the locals only it used. `Tip:Mana`, `Tip:Fights`, `Tip:Clock*` stay.
`tools/replayforever.lua:303`'s comment names `Tip:Row`: it is a comment, left (no code reads
it).

## The checks (fail first on the parent, then green)

**`tools/tbcclasscheck.lua`** (52): "as shipped a non-druid sees what it saw before" becomes "as
shipped a priest / shaman / paladin has the rank table and the tooltip": the caps granted by the
files, not by the suite (`caps.rankTable, caps.tooltip = true, true` at 365 removed); the book's
heal families equal `Compute`'s rows over `RankMath:Source()`; the block's lines (T121's
`SpellTip:Lines`) replace the `Tip:Row` / `Tip:Spell` derivation check at 483-506, with the same
numbers; coach / practice still refused with `not modelled for Priest yet`. New: a priest's Smite
and Shadow Word: Pain, a shaman's Lightning Bolt and Flame Shock, a paladin's Exorcism from the
fixture texts -- `value` / `perMana` / `perSec` equal `DM.Compute`'s, `bonus.why` ends in
`VERIFY`, `calc` names `talents not modelled`; the picker's DAMAGE section lists them; a damage
role's list seeds with them (`Tabs:SeedList`, T110's rule, unchanged).

**`tools/capscheck.lua`** (tbc): a priest's `Can("rankTable")` and `Can("tooltip")` true;
`Can("coach")` false, `"class"`; the `isDruid` source scan unchanged.

**`tools/profilecheck.lua`** (tbc 45): the `damage` field validated (a bad kind, school, a name
shared with a heal family each refused); the three profiles pass.

**`tools/bookshapecheck.lua`** (tbc): check 26 (the alias golden) becomes "`MD.FamiliesTBC` is
nil"; new: each class book passes `BS.Validate` with its damage families; the druid's book equal
to the parent's byte for byte (a golden).

**`tools/tabscheck.lua`** (tbc): the `FamiliesTBC` read becomes `MD.Book:Get()`; counts unchanged.

**SpendTracker / Summary / Diagnostics**: a priest's max-rank Greater Heal counted as max rank
(tbcclasscheck); the druid's summary and `/md profile` byte-identical (`slashcheck`'s and
`verifycheck`'s goldens unchanged).

**Unchanged**: `slashcheck`, `verifycheck`, `ttocheck`, `kitcheck`, `spelltip` (the druid's),
`apicheck` 0, `textcheck` 0. `make check` green.

### Counts

| Suite | Before | After |
|---|---|---|
| `tbcclasscheck/tbc` | 52 | measured (the flipped checks, five damage checks new) |
| `capscheck/tbc` | today's | +2 |
| `profilecheck/tbc` | 45 | **48** |
| `bookshapecheck/tbc` | T118's 16 | **18** |
| `tabscheck/tbc` | T118's | unchanged |

## Integrator lines

- **`tools/data/expected-counts.json`**: the rows above.
- **`CLAUDE.md`**: `Data/Profile_Priest_TBC.lua` / `_Shaman_` / `_Paladin_`: `**T123:**` (the rank
  table and the tooltip granted; `damage` families, VERIFY; coach / practice the druid's).
  `Spells/Profiles.lua`: `damage` and `P.DAMAGE_FIELDS`. `Engine/DamageMath.lua`: `DM.FamiliesFor
  (class)`, the class argument, talents the druid's only. `Spells/Book_Model.lua`: class damage;
  the alias deleted. `Spells/Book_TBC.lua`: `IsMaxKnownRank`, `LiveCost`. `Engine/SpendTracker.lua`,
  `UI/Summary.lua`, `Diagnostics_TBC.lua`: `Source()`. `UI/Tip_TBC.lua`: `Row` deleted (the file is
  `Mana`, `Fights`, `Clock`). Update the `Spells/Profiles.lua` row's `isDruid` sentence if the
  count moved.
- **`docs/TOOLS.md`**: the `tbcclasscheck` row (caps shipped, damage).
- **`docs/DECISIONS.md`**: under "The TBC book is live" (T118's) one paragraph: the TBC classes'
  rank table and tooltip are on; their damage rules are the druid's coefficient rules with no
  talents, VERIFY.
- **`docs/TESTING.md`** section 49: a priest, shaman or paladin on TBC opens `/md`, reads a heal
  and a damage family, hovers a spell with and without Shift, and checks one cast's number in the
  combat log.
- **`docs/tasks/T111-tbc-other-classes.md`**: one line under its Deviations 1: "Switched on by
  T123."

## Deviations allowed

1. A damage row whose fixture text `DM.Parse` cannot read (Holy Wrath's and Consecration's area
   wording, Mind Flay's channel) is dropped, with its text quoted in the profile's comment; the
   rest ship.
2. If a class damage spell needs a parser shape `DM.Parse` lacks and it is a one-line pattern in
   the same style as the existing ones (`Causes N to M <School> damage`), add it to
   `Engine/DamageMath.lua` with a fixture text; anything larger is a follow-up.

## Out of scope

- A class kit for Review / Play / the coach on TBC (decision 8 (b)); class damage talents; the
  either-or split of a TBC heal with a damage half (Holy Shock stays a heal family).
