# T111 -- TBC other classes (P5)

Status: **built** 2026-10-02 on branch `next/T111`, base `4ff42bf` (wave N4 integrated);
**revised the same day** after the review's five rejections (section "The review, and what changed").
Wave N5 of `docs/SPEC-next.md`. Decision 8 (b): **tables and tooltips only**. The TBC coach stays
the druid's. Waiting for the integrator.

**As shipped, nothing a TBC priest, shaman or paladin sees changes** (principle 10). Their profiles
grant the clock only, as the generic profile did; the class book, the class rules and the class kit
are built and held by `tools/tbcclasscheck.lua` and `tools/wclcheckkit.lua --fit`, and switch on in
the game by one documented change -- granting `rankTable` / `tooltip` in the three profiles -- once
the swaps listed under "Before the caps are granted" have landed in the files that are not this
row's.

## The task (docs/SPEC-next.md section 11, row T111; 4.2 P5; 4.4)

> **TBC other classes (P5)**, only on decision 8 (b) / (c). Tooltip-read bases; per-class VERIFY
> rules; WCL fit with a class argument; `Spells/Parse.lua` on the TBC TOC; the two "druid until
> T111" reads (4.4) become `Can("rankTable")`.

The task owns these files, and they are the only ones edited apart from this one:

- `Spells/Book_TBC.lua` (new)
- `Engine/RankMath.lua`
- `Spells/Families_TBC.lua`
- `Client/API_TBC.lua`
- `tools/adaptercheck.lua`
- `tools/capscheck.lua`
- `Data/Profile_{Priest,Shaman,Paladin}_TBC.lua` (new)
- `tools/wclconvert.py`
- `tools/wclcheckkit.lua`
- `tools/tbcclasscheck.lua` (new)

The task adds no TOC line, since the TOCs are the integrator's. The new suite loads the five new
files itself until the integrator adds them, and so does `wclcheckkit`.

## What was built

### The bases: `Spells/Book_TBC.lua` (`MD.BookTBC`)

The TBC client prints every rank's **base** heal in its tooltip, without +healing or talents. The
book turns that text into numbers.

**The walk.** `GetNumSpellTabs`, `GetSpellTabInfo` and `GetSpellBookItemName` /
`GetSpellBookItemInfo` are read through `MD.API`. A spellbook entry belongs to a family when its
name is one of the class profile's families.

**Each rank is read through the adapter**, and every read falls back to the spell's own tooltip
lines (`MD.API.SpellTooltipLines`, a hidden scan tooltip):

| Read | From the client | Fallback |
|---|---|---|
| Description | `GetSpellDescription` | the tooltip's last line that `Parse.Description` reads with a heal |
| Cost | `GetSpellPowerCost`, mana entry | `N Mana` |
| Cast | `GetSpellInfo`'s cast in ms | `Parse.Cast` |
| Learn level | `GetSpellLevelLearned` | `Requires level N` |
| Cooldown | `GetSpellBaseCooldown` | `Parse.Cooldown` on the tooltip line |

**The shape** comes from the profile's kit type:

- direct, group, chain and selfAndTarget need a heal range;
- a HoT needs an amount over a duration;
- Holy Shock's either-or sentence gives its heal half;
- Chain Heal's count and falloff come from TBC's wording ("Heals N total targets", "reduces the
  effectiveness of the heal by N%"). Prayer of Healing's reach comes from "party members within N
  yards". Both are in `B.Reach`, because `Parse.Targets` reads Forever's wording.

**A rank no read can price is refused, never guessed.** The reason is kept in
`source.refused[id]` ("no heal range in its text", "no cast time", "no learn level", "chain
without its count or falloff"). A rank whose learn level neither `GetSpellLevelLearned` nor a
`Requires level N` line gives is refused (rejection 2): it has no downrank penalty to compute and
no level for the table to print.

**The source has `Data/SpellData.lua`'s shape**: `families`, `familyOrder`, `spells`, `all`,
`known`, `knownSet`, `maxRank`, `GetCost`, `StaticCost`, `Relic`, `Resolve`. `GetCost` is live
first, then the cost read at login, then the tooltip's. The source is built at `MD_READY`,
`SPELLS_CHANGED`, `LEARNED_SPELL_IN_TAB` and `PLAYER_LEVEL_UP`, and each build fires
`SPELLS_REBUILT`. It is built only for a logged-in class whose profile grants the rank table and
which is not `B.TABLE_CLASS` ("DRUID"). The druid keeps `Data/SpellData.lua`. **No TBC class
profile grants the rank table yet**, so in the game the book builds nothing and fires nothing.

### The rules: `Engine/RankMath.lua`

**`RankMath:IsClassBook()`** is true only for a logged-in class other than the druid whose
profile **grants `rankTable`** (`MD.ClassProfile:Can("rankTable")`) while `MD.BookTBC` is loaded.
**`RankMath:Source()`** answers `MD.BookTBC:Source()` for a class book and `MD.SpellData`
otherwise. As shipped, `IsClassBook()` is false for every class, so every class reads what it read
before T111.

**Three entry points dispatch to the class path only for a class book**, so the druid's path is
unchanged byte for byte:

- `Context` goes to `RankMath.ClassContext`: the profile's crit school, no Tree, relic or Nature's
  Grace, and the Simulate strip's stats as for the druid. The druid's body moved, unchanged, into
  `RankMath:DruidContext`.
- `RowFor` goes to `RankMath.ClassRow` (when `ctx.class` is set).
- `Compute` / `SuggestedRanks` read `RankMath:Source()`.

**`SpellKit` is the druid's for every class** (rejection 5; decision 8 (b)): it is built from
`Data/SpellData.lua` over `RankMath:DruidContext`, stamped `DRUID`, whoever is logged in -- what a
priest's Review validation and replay ran on before T111, and still run on. `RankMath.ClassKit`
builds a class's own kit; only the offline tools call it, by name. A TBC class kit for Review and
Play would need its own decision.

**`Compute`'s `isDruid` gate** is now `MD.ClassProfile:Can("rankTable")` over `RankMath:Source()`.

**The class rules** (every one VERIFY):

- **Direct coefficient** is `clamp(base cast, 1.5, 3.5) / 3.5`. The base cast is the client's
  cast plus a talent's `castAdd`: Divine Fury and Improved Healing Wave shorten the cast the
  client reports, but not the coefficient.
- **HoT coefficient** is `duration / 15`, with ticks every 3 s (1 s when the duration is not a
  multiple of 3).
- **Group heals** take `RankMath.GROUP_COEF` = 0.5.
- **The downrank penalty** is `min(1, (level + 11) / player level)` times the sub-20 malus.
  `ClassRow` answers nil for a rank without a positive learn level (the book refuses it first).
- **Crit** is `1 + 0.5 x crit` in the school's crit chance.
- **The interval** is `max(cast, cooldown)`; Holy Shock's per-second is over its 15 s.

`RankMath.CLASS_RULES` holds the class talents:

| Class | Talents |
|---|---|
| Priest | Spiritual Healing (+2% per rank); Improved Renew (+5% per rank, Renew); Empowered Healing (+4% / +2% / +2% coefficient per rank on Greater Heal / Flash Heal / Binding Heal); Divine Fury (0.1 s per rank back on Heal and Greater Heal) |
| Shaman | Purification (+2% per rank); Improved Chain Heal (+10% per rank, Chain Heal); Improved Healing Wave (0.1 s per rank back); Tidal Mastery (+1% crit per rank) |
| Paladin | Healing Light (+4% per rank, Holy Light and Flash of Light); Sanctified Light (+2% crit per rank, Holy Light) |

`ClassRow`'s `calc` carries the fields `UI/Tip_TBC.lua`'s spell tooltip and `Tip:Row` read, plus
the cooldown, interval, jumps, falloff, the talent's name and the tick period. A family no talent
touches has `bonusMultName = ""` and `talentName = ""`, never nil (rejection 1: `Tip:Row` formats
them with `%s`).

`ClassContext` reads the school's crit and the mana through the adapter (`MD.API.SpellCritChance`,
`MD.API.UnitPower`), never the raw globals; an absent answer is 0.

`ClassKit` (the tools' only, see above) builds a kit by type:

- chain entries get `jumps` / `falloff`;
- hot entries get `ticks` / `tickPeriod` / `duration` / `tick`;
- a rank without a row is marked `dataMissing`;
- every entry carries the cooldown, and the kit is stamped with the class's `profile`.

It ends with `MD.Kit.Check`.

### The profiles: `Data/Profile_{Priest,Shaman,Paladin}_TBC.lua`

Each profile has the cap `clock` only, as the generic profile it replaces had, so the refusals'
words are unchanged ("Rank analysis: not modelled for Priest yet"). `rankTable` and `tooltip` are
written out in a comment beside `caps`, with what has to land first. There is no coach, practice or
planner, per decision 8 (b). Each profile lists its families with kit types, the order, the HoT
slots, the crit school and the unmodelled spells by name:

| Class | Families | Unmodelled |
|---|---|---|
| Priest | Greater Heal, Heal, Flash Heal, Lesser Heal (direct); Renew (hot); Prayer of Healing, Circle of Healing (group); Binding Heal (selfAndTarget) | Power Word: Shield, Desperate Prayer, Prayer of Mending, Holy Nova, Lightwell, Inner Focus, Power Infusion |
| Shaman | Healing Wave, Lesser Healing Wave (direct); Chain Heal (chain) | Earth Shield, Healing Stream Totem, Nature's Swiftness |
| Paladin | Holy Light, Flash of Light, Holy Shock (direct) | Lay on Hands, Divine Favor |

Names and rules only; no numbers.

### The adapter: `Client/API_TBC.lua`

**New bindings:** `SpellTabCount`, `SpellTabInfo`, `SpellBookItemName`, `SpellBookItemKind`,
`SpellInfoList`, `SpellDescription`, `SpellPowerCost` (copy 2), `SpellLevelLearned`,
`BaseCooldown`, `SpellBonusHealing` and `SpellCritChance`.

**`MD.API.SpellTooltipLines(id)`** reads `{ { l, r } }` through the hidden
`SpellTunerScanTooltip`, or answers `nil, "absent" / "error"`. All twelve names are in
`adaptercheck`'s `TBC_ONLY_NAMES`.

### The spell list: `Spells/Families_TBC.lua`

The list builds from `RankMath:Source()` under `Can("rankTable")`. Its `isDruid` read is gone. As
shipped only the druid passes the gate, so every other class lists nothing, as before T111.

### `capscheck`: four reads in three files

`ALLOWED` lost `Engine/RankMath.lua` and `Spells/Families_TBC.lua`. Four kept reads remain:
`Core.lua` x2 (the definition), `Core_TBC.lua` x1 (InTreeForm) and `Data/SpellData.lua` x1. The
check's name says so.

### The WCL fit with a class: `tools/wclconvert.py`, `tools/wclcheckkit.lua`

**`wclconvert.py`** now handles every healing class:

- It takes the healer's class from the log (`subType`), reads that class's families
  (`CLASS_FAMILIES`) and infers its healing talents from the tree split (`infer_talents`, every
  threshold VERIFY).
- It writes `"class"` into the profile.
- `--observed FILE` writes the per-rank non-crit gross medians:
  - the druid's through `tools/wclrules.py`'s `observed_table`, unchanged;
  - a class's through `class_observed`, with Chain Heal's jumps left out (only the heal on the
    cast's own target counts).
- The `known` keys are each word capitalised (`CircleOfHealing`), which leaves the druid's names
  unchanged.
- **A druid's records are byte-identical to the parent's** (`cmp` on Cycloo + Ffcuck).

**`wclcheckkit.lua`** holds a non-druid profile after every druid:

- It installs `tbcclasscheck.lua`'s fixture as the class's spellbook (library mode), logs the
  class in, grants its profile `rankTable` / `tooltip` for the run, and builds the class's kit by
  name (`RankMath.ClassKit` over `MD.BookTBC:Rebuild()`). Each row is labelled with the class
  book's family name and the rank's id (`Greater Heal #2060`).
- It holds each row against the rank's `direct` / `tick`. With `--fit` it solves each row alone
  for +healing and prints the families' answers and their spread.
- A spell the kit does not price is listed, not compared.
- **Its druid output is identical to the parent's** (`diff` of `--fit` on the same files).

## The fit (public TBC Anniversary parses, `.logs/wcl/`, gitignored)

To reproduce:

```
python3 tools/wclconvert.py .logs/wcl/gcxGp84ZftKNB23w-117.json --healer Oldgrabli \
  .logs/wcl/wqkcLfh1Y2QrJCGX-110.json --healer 등짝에개문신 .logs/wcl/rt1AxNCPGnKvF4Ry-42.json \
  --healer Deepfriedrat .logs/wcl/2yVhvFzN1CpBcjm4-14.json --healer Simzò \
  .logs/wcl/2yVhvFzN1CpBcjm4-14.json --healer Scum .logs/wcl/2yVhvFzN1CpBcjm4-14.json \
  --healer Glazedholez --out .logs/wcl-class-records.lua --observed .logs/wcl-class-observed.lua
tools/run.sh --flavour tbc tools/wclcheckkit.lua .logs/wcl-class-records.lua .logs/wcl-class-observed.lua --fit
```

Each family's answer is the +healing its best-sampled row asks for. The spread is (max - min)
over the middle of the range.

| Parse | Class (trees) | Families: implied +healing | Spread |
|---|---|---|---|
| Simzò | Priest 20/41/0 | Renew 2165, Circle of Healing 2190, Flash Heal 2310 | **6%** |
| Scum | Shaman 0/7/54 | Healing Wave 2400, Lesser Healing Wave 2505, Chain Heal 2575 | **7%** |
| Deepfriedrat | Priest 20/41/0 | Greater Heal 2400 (n 3), Circle of Healing 2615, Flash Heal 2635, Renew 2645 | 10% (1% without the 3-cast Greater Heal) |
| Oldgrabli | Priest 20/41/0 | Greater Heal 1815, Renew 2040, Circle of Healing 2070 | 13% |
| Glazedholez | Shaman 0/5/56 | Healing Wave 2160, Chain Heal 2490 | 14% (two families) |
| 등짝에개문신 | Priest 42/19/0 | Renew 3165, Greater Heal 5960, Flash Heal 6000 (the scan's cap) | **62%: does not agree** |

**Three families agree on one +healing** on Simzò, Scum and Deepfriedrat, within 10% (1% for
Deepfriedrat's three well-sampled families). The rules hold for the holy priest and the
restoration shaman: the coefficients by shape, the group coefficient on Circle of Healing, the
HoT coefficient, Improved Renew and Chain Heal's first target.

Three findings are measurements without a mechanism, so nothing was changed for them:

- **Greater Heal asks 8-12% less +healing than the other priest families** (Oldgrabli,
  Deepfriedrat). The model's Greater Heal is about 4% high, possibly from Empowered Healing's
  coefficient or Divine Fury's cast-back.
- **The discipline priest (42/19/0, a Korean realm) does not fit.** Its direct heals are 1.8-1.9x
  the model at any +healing up to the scan's cap. Power Infusion (+20%) does not explain it.
  Inferring its talents from the split (Divine Fury and Improved Renew only) cannot either.
- **No paladin parse with enough heals was found** in the corpus. The paladin rules (Healing
  Light, Sanctified Light, Holy Shock over its cooldown) are held by `tbcclasscheck` only, and
  stay VERIFY.

## The review, and what changed

The first build (`503dace`) was rejected on five points. Each is fixed here and held by
`tools/tbcclasscheck.lua`:

1. **`Tip:Row` raised on a class row** (`UI/Tip_TBC.lua:183`, `bad argument #6 to 'format'`): a
   family no talent touches left `calc.bonusMultName` nil. `ClassRow` now writes `""` for
   `bonusMultName` and `talentName` in both the direct and the HoT calc. The suite renders
   `MD.Tip:Row(RankMath:Explain(id))` and `MD.Tip:Spell(id)` (plain and Shift) for **every rank of
   every priest, shaman and paladin family** and asserts that nothing raises and every line is
   printable ASCII with no pipe. Against `503dace` these three checks fail on 30 of 47 priest
   ranks, 24 of 24 shaman ranks and 19 of 19 paladin ranks.
2. **A rank with no learn level would make a level concat raise.** It is now refused: the book
   refuses it (`no learn level`) and `ClassRow` answers nil for it, so no row without a printable
   level reaches a table. `calc.levelMissing` is gone. The suite reads the shaman with neither
   `GetSpellLevelLearned` nor a `Requires level` line: every rank is refused for that reason and
   the table is empty. With the line in the tooltip, Chain Heal 5 reads level 68 from it. Every
   Compute row carries a numeric level, rank and cost.
3. **The TBC Spells pane would have been half-working** for these classes: the rail would list
   the class's families from the class book while the family view and Overview still read
   `Data/SpellData.lua`. **The class families are kept off the rail**: no profile grants
   `rankTable`, so `Spells/Families_TBC.lua` lists nothing for these classes, as before T111.
4. **Granting `rankTable` changed two TBC prints**: `UI/Summary.lua:498` (the fight line's
   "max-rank casts 0%") and `Diagnostics_TBC.lua:229` (an empty max-rank section in `/md
   profile`). Both are gated on `Can("rankTable")` and read `Data/SpellData.lua`. With the cap
   not granted, both skip their line for these classes, as before T111.
5. **`RankMath:SpellKit` returned the class kit**, which changed Review validation and replays for
   non-druids. `SpellKit` is the druid's again for every class (`RankMath:DruidContext`, stamped
   `DRUID`, held by the suite with and without the cap granted). `RankMath.ClassKit` is reached
   only by name, from the tools.

Also from the review's notes: `ClassContext` reads crit and mana through `MD.API`, not the raw
globals, and `wclcheckkit` labels a class row with the class book's family name.

## Counts (`tools/run.sh --flavour <f> tools/<suite>.lua`)

| Suite | Parent `4ff42bf` | Rejected `503dace` | Here |
|---|---|---|---|
| `tbcclasscheck` tbc (new) | **0 ok, 6 failed, then raises** (exit 1: no class files) | **41 ok, 11 failed** (exit 1) | **52 ok, 0 failed** |
| `capscheck` tbc / forever | 34 / 32 | 34 / 32 | 34 / 32 (the kept list is four reads in three files) |
| `adaptercheck` tbc / forever | 16 / 24 | 16 / 24 | 16 / 24 |
| `verifycheck` tbc | 14 | 14 | 14 (the goldens unchanged) |
| `kitcheck` tbc / `slashcheck` tbc | 5 / 10 | 5 / 10 | 5 / 10 |
| `profilecheck` tbc / forever | 45 / 64 | 45 (51 with the TOC lines) / 64 | 45 / 64; **51** / 64 with the TOC lines below |

`make check` (`tools/check.sh`) is green here: 92 runs, apicheck 0 findings, textcheck 0
findings, and NOTE `tbcclasscheck/tbc: 52 assertion(s), not in the expected counts`. It is also
green in a scratch copy with the TOC lines below applied: 92 runs, `releasecheck` included, textcheck 116 files, 0 findings, NOTE `profilecheck/tbc: 51 assertion(s), 45 expected` and NOTE `tbcclasscheck/tbc: 52`. `profilecheck/forever`
needs `tools/.cache/talentsforever.json` (`python3 tools/refcheck.py --fetch`) for its 64; without
the cache it is 59, here as on the parent.

The fit table above is unchanged (`wclcheckkit --fit` now builds the class kit by name; the same
implied +healing per family, `#2060` labelled `Greater Heal`). The druid's `--fit` output is
identical to the parent's.

## Integrator lines

### `SpellTuner_TBC.toc`

1. After `Data\Profile_Druid_TBC.lua`, add `Data\Profile_Priest_TBC.lua`,
   `Data\Profile_Shaman_TBC.lua` and `Data\Profile_Paladin_TBC.lua`.
2. After `Data\SpellData.lua`, add `Spells\Parse.lua` and `Spells\Book_TBC.lua`.

No other TOC changes.

### `tools/data/expected-counts.json`

Add `"tbcclasscheck/tbc": 52`, and change `"profilecheck/tbc"` from 45 to 51 (with the TOC
lines). `tools/check.sh` needs no edit: the suite is found by its file name.

### `CLAUDE.md`

Add new rows for:

- `Spells/Book_TBC.lua`: `MD.BookTBC`, a TBC class's ranks read from its spellbook and its
  tooltips into `Data/SpellData.lua`'s shape, a rank no read prices (no range, no cast, no learn
  level) refused with its reason; built only for a class whose profile grants `rankTable` -- none
  yet.
- `Data/Profile_{Priest,Shaman,Paladin}_TBC.lua`: families, kit types, crit school and unmodelled
  spells; caps `clock` only until the swaps below land.

Add a **T111** note to these rows:

- `Engine/RankMath.lua`: `IsClassBook` (a non-druid whose profile grants `rankTable`) /
  `Source`; `Context` -> `ClassContext` for a class book, else `DruidContext` (the old body);
  `ClassRow`, `CLASS_RULES`, `GROUP_COEF` (VERIFY); `Compute` on `Can("rankTable")` over
  `Source()`; **`SpellKit` the druid's for every class** (decision 8 (b)), `ClassKit` the tools'
  only.
- `Spells/Families_TBC.lua`: built from `RankMath:Source()` under `Can("rankTable")`.
- `Client/API_TBC.lua`: the eleven bindings and `MD.API.SpellTooltipLines`.
- `Spells/Profiles.lua`: the `isDruid` list, now four reads in three files.
- `tools/`: `tbcclasscheck` (tbc, 52), plus `wclconvert` / `wclcheckkit --fit` with a class.

### Docs

- **`docs/TOOLS.md` section 1**: the `tbcclasscheck` row, and the class fit invocation above.
- **`docs/TESTING.md`**: on a TBC priest, shaman or paladin nothing changes with T111. `/md`
  shows the rail with Overview only, the Spells refusal reads "Rank analysis: not modelled for
  Priest yet", the fight line has no max-rank share, and Review / Play behave as before. Test
  again once the caps are granted.
- **`docs/DECISIONS.md`**, "TBC other classes read their bases from the tooltip" (decision 8 (b)
  as built), recording:
  - The machinery is in and is held offline.
  - **A TBC priest, shaman or paladin sees nothing new until their profiles grant `rankTable` /
    `tooltip`.** That grant is a decision of its own, taken once the swaps below have landed.
  - The TBC kit, and so Review and Play, stays the druid's for every class. A class kit there is a
    further decision.
  - The fit table above, and the Greater Heal and discipline priest findings.

### Before the caps are granted (files outside this row)

Granting `rankTable` and `tooltip` in the three profiles (`caps = { clock = true, rankTable = true,
tooltip = true }`) is the switch. Before it, these files have to stop equating "the rank table" with
`Data/SpellData.lua`. None of them is this row's.

**The ranks' source.** Each read below has to become
`local SD = MD.RankMath and MD.RankMath:Source() or MD.SpellData`; for the druid all of them still
read `MD.SpellData`:

- `UI/SpellTooltip.lua:62`: `local isHeal = MD.SpellData and MD.SpellData.spells[id]`.
- `UI/Tip_TBC.lua:268`: `local SD, RM = MD.SpellData, MD.RankMath`.
- `UI/SpellsView_TBC.lua`: lines 290, 315, 392, 462, 805 and 1020.
- `UI/Dashboard.lua`: lines 53 and 87.

**The druid-only words.** `UI/Tip_TBC.lua`'s spell tooltip:

- hard-codes `"Gift of Nature"` as the Shift detail's talent name; it should read
  `calc.talentName`.
- words a HoT's ticks as `every 3s`; it should read `calc.tickPeriod`.

**The max-rank share.**

- `UI/Summary.lua:498` and `Engine/SpendTracker.lua`'s `IsMaxKnownRank` count max-rank casts
  against `Data/SpellData.lua`. They have to read `RankMath:Source()`, or ask
  `RankMath:IsClassBook()` and skip the share.
- `Diagnostics_TBC.lua:229`'s max-rank section of `/md profile`: the same.

**What the grant then changes by itself.** `Engine/DamageMath.lua:204`'s
`RankMath:Context({ live = true })` then answers the class context. Its damage rows read only
`crit` / `bonus` / `playerLevel`, which the class context carries.

## Deviations

1. **As shipped, the class book, rules and kit are not reachable in the game.**
   - The three profiles grant the clock only.
   - On TBC a priest, shaman or paladin sees exactly what they saw before T111: no rail families,
     the same refusal, no tooltip block, no max-rank share, the druid's kit in Review and Play.
     The druid is unchanged byte for byte.
   - The machinery (`MD.BookTBC`, `ClassContext` / `ClassRow` / `ClassKit`, the Families book
     under the cap) is held by `tools/tbcclasscheck.lua` with the cap granted in the suite, and by
     `tools/wclcheckkit.lua --fit`.
   - Switching it on is the one-line cap change per profile, after the list above.
   - Switched on by T123.
2. **`RankMath:SpellKit` stays the druid's for every class, even with the cap granted** (decision
   8 (b)). A class kit for Review / Play / the coach is not built in the game.
3. **TBC's reach sentences are read in `Spells/Book_TBC.lua` (`B.Reach`), not in
   `Spells/Parse.lua`**, which is not this row's. `Parse.Targets` is still asked first.
4. **Only the ranks the spellbook lists are in a class source.** An untrained rank is not on the
   table, and neither is a rank whose learn level no read gives. This differs from the druid's
   static table, which lists every rank, and a gap between ranks is not shown for these classes.
5. **Not modelled for these classes:**
   - spells: Holy Shock's heal-effect ids (the log credits a different id from the cast, and no
     alias is kept); Healing Way, Blessing of Light and Illumination;
   - talents: Spiritual Guidance (+healing from Spirit), which the fit does not need on the
     parses above.
   - Every class rule and `GROUP_COEF` is VERIFY.
6. **The `wclcheckkit` fit reads the fixture's texts as the class's spellbook** (wowhead's TBC
   tooltips, typed into `tbcclasscheck.lua`). It does not read a client. The fit therefore tests
   the rules over those texts, the same texts the suite holds.
