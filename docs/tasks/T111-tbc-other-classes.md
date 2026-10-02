# T111 -- TBC other classes (P5)

Status: **built** 2026-10-02 on branch `next/T111`, base `4ff42bf` (wave N4 integrated). Wave N5
of `docs/SPEC-next.md`. Decision 8 (b): **tables and tooltips only**. The TBC coach stays the
druid's. Waiting for the integrator.

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
`source.refused[id]` ("no heal range in its text", "no cast time", "chain without its count or
falloff").

**The source has `Data/SpellData.lua`'s shape**: `families`, `familyOrder`, `spells`, `all`,
`known`, `knownSet`, `maxRank`, `GetCost`, `StaticCost`, `Relic`, `Resolve`. `GetCost` is live
first, then the cost read at login, then the tooltip's. The source is built at `MD_READY`,
`SPELLS_CHANGED`, `LEARNED_SPELL_IN_TAB` and `PLAYER_LEVEL_UP`, and each build fires
`SPELLS_REBUILT`. It is built only for a logged-in class whose profile grants the rank table and
which is not `B.TABLE_CLASS` ("DRUID"). The druid keeps `Data/SpellData.lua`.

### The rules: `Engine/RankMath.lua`

**`RankMath:Source()`** answers `MD.SpellData` for the druid (and for no class at all), otherwise
`MD.BookTBC:Source()`. `RankMath:IsClassBook()` tells which.

**Four entry points dispatch to the class path only for a class book**, so the druid's path is
unchanged byte for byte:

- `Context` goes to `RankMath.ClassContext`: the profile's crit school, no Tree, relic or Nature's
  Grace, and the Simulate strip's stats as for the druid.
- `RowFor` goes to `RankMath.ClassRow` (when `ctx.class` is set).
- `SpellKit` goes to `RankMath.ClassKit`.
- `Compute` / `SuggestedRanks` read `RankMath:Source()`.

**`Compute`'s `isDruid` gate** is now `MD.ClassProfile:Can("rankTable")` over `RankMath:Source()`.

**The class rules** (every one VERIFY):

- **Direct coefficient** is `clamp(base cast, 1.5, 3.5) / 3.5`. The base cast is the client's
  cast plus a talent's `castAdd`: Divine Fury and Improved Healing Wave shorten the cast the
  client reports, but not the coefficient.
- **HoT coefficient** is `duration / 15`, with ticks every 3 s (1 s when the duration is not a
  multiple of 3).
- **Group heals** take `RankMath.GROUP_COEF` = 0.5.
- **The downrank penalty** is `min(1, (level + 11) / player level)` times the sub-20 malus. With
  no learn level read, the penalty is 1 and `calc.levelMissing` is set.
- **Crit** is `1 + 0.5 x crit` in the school's crit chance.
- **The interval** is `max(cast, cooldown)`; Holy Shock's per-second is over its 15 s.

`RankMath.CLASS_RULES` holds the class talents:

| Class | Talents |
|---|---|
| Priest | Spiritual Healing (+2% per rank); Improved Renew (+5% per rank, Renew); Empowered Healing (+4% / +2% / +2% coefficient per rank on Greater Heal / Flash Heal / Binding Heal); Divine Fury (0.1 s per rank back on Heal and Greater Heal) |
| Shaman | Purification (+2% per rank); Improved Chain Heal (+10% per rank, Chain Heal); Improved Healing Wave (0.1 s per rank back); Tidal Mastery (+1% crit per rank) |
| Paladin | Healing Light (+4% per rank, Holy Light and Flash of Light); Sanctified Light (+2% crit per rank, Holy Light) |

`ClassRow`'s `calc` carries the fields `UI/Tip_TBC.lua`'s spell tooltip reads, plus the cooldown,
interval, jumps, falloff, the talent's name and the tick period. `ClassKit` builds a kit by type:

- chain entries get `jumps` / `falloff`;
- hot entries get `ticks` / `tickPeriod` / `duration` / `tick`;
- a rank without a row is marked `dataMissing`;
- every entry carries the cooldown, and the kit is stamped with the class's `profile`.

It ends with `MD.Kit.Check`.

### The profiles: `Data/Profile_{Priest,Shaman,Paladin}_TBC.lua`

Each profile has the caps `clock`, `tooltip` and `rankTable`. There is no coach, practice or
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

The list builds from `RankMath:Source()` under `Can("rankTable")`. Its `isDruid` read is gone.

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
  class in and builds its kit.
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

## Counts (`tools/run.sh --flavour <f> tools/<suite>.lua`)

| Suite | Parent `4ff42bf` | Here |
|---|---|---|
| `tbcclasscheck` tbc (new) | **5 ok, 34 failed** (exit 1) | **39 ok, 0 failed** |
| `capscheck` tbc / forever | 34 / 32 | 34 / 32 (the kept list is four reads in three files) |
| `adaptercheck` tbc / forever | 16 / 24 | 16 / 24 |
| `verifycheck` tbc | 14 | 14 (the goldens unchanged) |
| `profilecheck` tbc / forever | 45 / 64 | 45 / 64; **51** / 64 with the TOC lines below |

`make check` (`tools/check.sh`) is green here: 92 runs, apicheck 0 findings, textcheck 0
findings, and NOTE `tbcclasscheck/tbc: 39 assertion(s), not in the expected counts`. It is also
green with the TOC lines below applied in a scratch copy: 92 runs, textcheck 116 files,
`releasecheck` included, and NOTE `profilecheck/tbc: 51`. The TOC was restored afterwards.
`profilecheck/forever` needs `tools/.cache/talentsforever.json` (`python3 tools/refcheck.py
--fetch`) for its 64; without the cache it is 59, here as on the parent.

## Integrator lines

### `SpellTuner_TBC.toc`

1. After `Data\Profile_Druid_TBC.lua`, add `Data\Profile_Priest_TBC.lua`,
   `Data\Profile_Shaman_TBC.lua` and `Data\Profile_Paladin_TBC.lua`.
2. After `Data\SpellData.lua`, add `Spells\Parse.lua` and `Spells\Book_TBC.lua`.

### `tools/data/expected-counts.json`

Add `"tbcclasscheck/tbc": 39`, and change `"profilecheck/tbc"` from 45 to 51 (with the TOC
lines). `tools/check.sh` needs no edit: the suite is found by its file name.

### `CLAUDE.md`

Add new rows for `Spells/Book_TBC.lua` and `Data/Profile_{Priest,Shaman,Paladin}_TBC.lua`. Add a
**T111** note to these rows:

- `Engine/RankMath.lua`: `Source` / `IsClassBook`, the class path, `CLASS_RULES`, `GROUP_COEF`,
  and `Compute` on `Can("rankTable")`.
- `Spells/Families_TBC.lua`: built from `RankMath:Source()`.
- `Client/API_TBC.lua`: the twelve bindings and `SpellTooltipLines`.
- `Spells/Profiles.lua`: the `isDruid` list, now four reads in three files.
- `tools/`: `tbcclasscheck`, plus `wclconvert` / `wclcheckkit` with a class.

### Docs

- **`docs/TOOLS.md` section 1**: the `tbcclasscheck` row, and the class fit invocation above.
- **`docs/TESTING.md`**: on a TBC priest, shaman and paladin, run `/md`. The Spells rail should
  list the class's families and every rank should be on the table. `/md verify`, `/md regentest`
  and `/md calibrate` show whether the numbers hold.
- **`docs/DECISIONS.md`**: "TBC other classes read their bases from the tooltip" (decision 8 (b)
  as built), the fit table above, and the Greater Heal and discipline priest findings.

### Two one-line edits outside this row

The tooltip half of "tables and tooltips" needs two edits outside this row, in files this task
does not own:

- `UI/SpellTooltip.lua:62`: replace `local isHeal = MD.SpellData and MD.SpellData.spells[id]` with
  `local SD = MD.RankMath and MD.RankMath:Source() or MD.SpellData` and
  `local isHeal = SD and SD.spells[id]`.
- `UI/Tip_TBC.lua:268`: replace `local SD, RM = MD.SpellData, MD.RankMath` with
  `local RM = MD.RankMath` and `local SD = RM and RM:Source() or MD.SpellData`.

For the druid both still read `MD.SpellData`. Without them, a priest's tooltip gets no SpellTuner
block. Hovering a heal falls to the damage path, which adds nothing.

The same swap is needed in the TBC Spells view, so that a family's view and Overview read the
class source:

- `UI/SpellsView_TBC.lua`: lines 290, 315, 392, 462, 805 and 1020.
- `UI/Dashboard.lua`: lines 53 and 87.

Those files are not this row's.

## Deviations

1. **The class tooltip and the class Spells view are not reachable until the swaps above.** The
   files that read `MD.SpellData` directly (`UI/SpellTooltip.lua`, `UI/Tip_TBC.lua`,
   `UI/SpellsView_TBC.lua`, `UI/Dashboard.lua`) are not this row's.
   - **Works now:** the rank math (`Compute`, `RowFor`, `Explain`, `SuggestedRanks`, `SpellKit`)
     and the spell list's book.
   - **Waits for the swaps:** the two panes.
2. **TBC's reach sentences are read in `Spells/Book_TBC.lua` (`B.Reach`), not in
   `Spells/Parse.lua`**, which is not this row's. `Parse.Targets` is still asked first.
3. **Only the ranks the spellbook lists are in a class source.** An untrained rank is not on the
   table. This differs from the druid's static table, which lists every rank, and a gap between
   ranks is not shown for these classes.
4. **Not modelled for these classes:**
   - spells: Holy Shock's heal-effect ids (the log credits a different id from the cast, and no
     alias is kept); Healing Way, Blessing of Light and Illumination;
   - talents: Spiritual Guidance (+healing from Spirit), which the fit does not need on the
     parses above.
   - Every class rule and `GROUP_COEF` is VERIFY.
5. **The `wclcheckkit` fit reads the fixture's texts as the class's spellbook** (wowhead's TBC
   tooltips, typed into `tbcclasscheck.lua`). It does not read a client. The fit therefore tests
   the rules over those texts, the same texts the suite holds.
