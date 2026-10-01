# T101 -- the generic Forever kit: families by shape, heals that reach several targets

Status: **built** 2026-10-01 on branch `next/T101` (base `25748e3`), wave N3, awaiting the
integrator. Spec: `docs/SPEC-next.md` section 11 row T101; 4.2 P2 (a generic Forever kit); 4.3
(classes by shape); 4.5 (what the solver assumes for heals that reach several targets); section 3
principles 8 (a heal the plan cannot choose is replayed as recorded), 9 (no value from memory), 10
(TBC changes only by decision); decision 12 (the author: as recommended, 9.1) and decision 11
(Tranquility). Research: `docs/research/next/R-classes.md` 1.3 (the mechanics table), 4, 5 (P2).
Needs T95 (the book's `targets` / `reach` / `cooldown`, `tools/stub_books.lua`) and T96 (kit
profiles, `SM.HotSlots`, `KitEntryFor`, the channel), both in the base. Owned files only;
integrator-owned files (TOCs, CLAUDE.md, docs, `tools/data/expected-counts.json`,
`tools/check.sh`) were **not** edited -- their lines are below. No TOC change (every file touched is
already listed, `Engine/Kit.lua` before `Scenario_Forever.lua` in the Replay module), no default
registered (`defaultscheck` unchanged: forever 52, tbc 49).

## What was built

### `Engine/Kit.lua` (the shape first)

- `Kit.FIELDS` gains `jumps`, `falloff` (a chain) and `party` (a channel whose text reaches the
  caster's party), each documented as 4.5's assumption.
- `Kit.TYPES` gains **`group`** (`cost`, `cast`), **`chain`** (`cost`, `cast`, `castBase`,
  `direct`, `directCrit`, `jumps`, `falloff`) and **`selfAndTarget`** (`cost`, `cast`, `castBase`,
  `direct`, `directCrit`).
- `Kit.ANY_OF.group`: a group entry owes one WHOLE part -- the direct one (`castBase`, `direct`,
  `directCrit`: Prayer of Healing, Holy Nova) or the HoT one (`tick`, `ticks`, `tickPeriod`,
  `duration`: Wild Growth); `Kit.Validate` says so by name.
- `Kit.MULTI_TARGET` and `Kit.ReachesMany(e)` (the three types, and a channel with `party`).

### `Modules/SpellTuner_Replay/Kit_Forever.lua` (families by shape)

- The kit is the **logged-in** player's (2.1: the live builder is one of the logged-in profile's
  three readers): the registered profile of `MD.player.class`, else the generic one
  (`LiveProfile`; the file never names `MD.ClassProfile`, which `profilecheck`'s scan forbids in a
  deriving file). Families the profile names are built by name with the profile's type -- the
  druid's exactly as before (`FAMILY_KEY` / `FAMILY_TYPE` stay the druid's, derived by name, for
  `profilecheck`). **Every other heal family is built by shape** (`ShapeOf`), from its highest known
  rank's own text and reach (T95's `entry.targets` / `entry.reach`): single target -> `direct` /
  `hot` / `hybrid` (or `channel`); the party -> `group` (a channel over the party stays a channel
  with `party`); a chain -> `chain` (jumps and falloff from the text); target and caster ->
  `selfAndTarget`. Keyed by its name without spaces or punctuation (`RM.KeyOf`: "Prayer of Healing"
  -> `PrayerOfHealing`), labelled by its name. What no type models is named in `SD.skipped`: an
  absorb (T109), a heal on the caster alone, one only below a health line or with charges, a reach
  the parser refused.
- `KitEntryFor.group` / `.chain` / `.selfAndTarget`; a HoT whose duration is no multiple of 3 s
  ticks every whole second (`FINE_TICK_PERIOD`; Wild Growth's 7 s: 7 uniform ticks, VERIFY -- the
  front-loaded curve is not in the text, so none is invented); every druid HoT duration (12, 15,
  21 s) keeps 3 s.
- Each entry carries the profile's cooldown (Swiftmend 15), else **the book's** (T95's tooltip
  line: Holy Shock 10 s, Riptide 6 s, Wild Growth 6 s).
- The kit is stamped with the logged-in class (`"DRUID"` for a druid, as before); the cache keys on
  the profile too; `SD.familyOrder` is the profile's order then the by-shape families; the crit
  school the profile's.
- `RM.KitRestore` indexes every entry under its own type (a priest's or a Wild Growth snapshot
  keeps its families; a druid snapshot restores exactly as before), labels the druid's keys by name
  and any other key in words.

### `Engine/SimModel.lua` (landing several targets)

- `SM.HotSlots(kit)` is the profile's slots plus, per kit (weak-keyed, derived once): a slot of its
  own after the profile's for a `group` HoT (Wild Growth beside a Rejuvenation) and for every HoT
  of a profile with no slots (the generic one), and `slots.extras` / `slots.families` -- the kit's
  families the profile's planner list does not name (not excluded, not unpriced, not a channel)
  appended, so the solver's candidates are the kit's. A kit with neither gets the profile's table.
- `S.party` / `S.caster` per run: the scenario target with `caster = true` and every tracked
  target of its `group` (no caster or no groups: every tracked target). `SM.InParty(S, i)`.
- `SM.LandMulti` (outside `Run`: no new closure; the run-cost line stays 3.57 / 3.58 KB): a
  **group** heal lands on every living party member (direct part, then the HoT in its slot), with
  no living target of its own required (Holy Nova); a **chain** heal on its target, then
  `SM.ChainTargets` -- the most injured living party members other than the target **at the
  landing** (missing health now, ties by roster order, each one missing something) -- at falloff,
  falloff^2; **selfAndTarget** on the target and the caster (once). A channel with `party` lands
  each tick on every living party member.
- `SM.IsInstant(e)`: the older types exactly as before; the three new ones when their cast is 0.
- `SM.K.OWNREPLAY = 16`, a scenario kind (never recorded): an own heal no kit entry claims, landed
  as recorded under the family `"recorded"` (never `"foreign"`).
- `ScenarioV2` marks the caster (a TBC roster's `player` unit; a practice fight's one member with a
  guid) and the raid subgroup on its targets -- nothing reads them on a druid kit.

### `Engine/SimSolver.lua` (the sums)

`Best` prices a `chain` cast on its target plus what its jumps save (`SM.ChainTargets` at the
decision, at falloff), a `selfAndTarget` cast plus the caster, and a **group** cast once, summed
over every living member of the caster's party (`SavedOn`, its own buffers so the primary target's
lists are never overwritten), named on the member it saves most on. Rule 8 never offers a group heal
for a target outside the party. Cooldowns (T90) and the regen price apply unchanged. Everything is
read from the present; the causality test holds (solvercheck).

### `Engine/SimPlanner.lua`

`SP.Bindable()` -- `SP.BINDABLE` plus the installed kit index's other families (none on TBC or for a
Forever druid without Wild Growth: `SP.BINDABLE` itself comes back); `BindsFromRecording`,
`MaxRankBinds` and `BestHPM` read it. The card's **Bind** line appends the other bound families;
**`SP.GROUP_ASSUMPTION`** -- `group heals assume everyone in range (no positions recorded): an
upper bound` -- is said (a note line before the caveat) whenever the plan binds or the recording
casts a heal `Kit.ReachesMany` (`SP.GroupAssumed`). TBC's kit has none, so no TBC card changes.

### `Modules/SpellTuner_Replay/Scenario_Forever.lua` (attribution)

N same-instant claims: a group cast one direct claim per party member (and each member's HoT ticks),
a channel over the party each tick on every member, a chain its target plus `jumps` claims on any
other member (each taking the heal nearest its own share, one per member), a self-and-target heal
its target and the caster. **An own cast of a heal the kit does not carry** (`MD:ClassifyCast` ->
heal; on the caster when its text heals only the caster) claims the heal landing with it: own,
counted `recorded`, pushed as `SM.K.OWNREPLAY` -- replayed exactly as recorded, never foreign.
`SM.AttributeHeals` returns a third value (the replayed set). The v3 caster is roster index 1 (the
`player` token the recorder lists first) when its max was read plain and not through a bar.

### `Modules/SpellTuner_Replay/Gates_Forever.lua`

Gate 8's text adds `; N of them from spells the kit does not price, replayed as recorded` when N > 0.

### `Engine/Practice.lua`

Family names from the kit: `PR.FamilyLabel` is the kit index's label, then the druid list (for a
family a book lacks), then the key in words; a session's kit copy takes the real cast bar for the
three new types too; a cast start is written unless `SM.IsInstant`; the practice scenario marks you
as the caster.

## Tests

### Failing first (commit `ad3e9d5`: the tests on the parent's code)

| suite | on the parent | after |
|---|---|---|
| `kitcheck/forever` | 15 ok, 4 failed (Wild Growth skipped; the three class books stamped DRUID with no families) | **19 ok** |
| `solvercheck/tbc` | 89 ok, 6 failed (no group or chain landing, no sums, no line) | **95 ok** |
| `scenariocheck/forever` | 17 ok, 2 failed (one PoH claim of three; the own heal foreign) | **19 ok** |
| `practiceforever/forever` | 29 ok, 2 failed (no paladin families; every press "You can't cast that here") | **31 ok** |

### The new assertions

- `kitcheck` (forever 16 -> 19): item 4 rewritten -- Wild Growth is in the kit, a `group` HoT, 7 x 97
  every 1 s, labelled "Wild Growth", and Tranquility's channel reaches the party; **17** a paladin's
  level 60 book (`tools/stub_books.lua`, logged in as PALADIN) is a valid kit stamped PALADIN --
  Holy Light direct 1580 (2.5 s cast and castBase), Flash of Light direct, Holy Shock direct with
  its book cooldown 10, no Light's Vigil, `MD.KitLive` true, the snapshot round-trips the profile
  and restores the families' types; **18** a shaman's -- Chain Heal `chain` 506, 2 jumps at 0.5,
  Riptide `hybrid` 841 + 5 x 3 s ticks with its 6 s cooldown, Healing Wave and Lesser Healing Wave
  direct; **19** a priest's -- Prayer of Healing `group` 649 (3 s), Holy Nova `group` 311, Binding
  Heal `selfAndTarget` 841, Renew `hot` 5 x 3 s, Greater Heal direct; Power Word: Shield, Desperate
  Prayer, Divine Grace and Contingency Plan skipped by name; the snapshot keeps PRIEST.
- `solvercheck` (tbc 89 -> 95): **PoH beats Greater Heal only with 3+ hurt** (picks by hurt count
  1..5: GH GH PoH PoH PoH); **Chain Heal's jumps go to the most injured at the cast** (`A:1000 B:500
  D:250`; a burst on C after the cast moves nothing, one before it makes C the first jump); **the
  falloff** 1, 0.5, 0.25 in the engine, and the solver's saving equals the three gap reductions
  (17500); **a group cast sums over living party members only** (the engine heals Me, Tank, Rogue --
  not the dead one, not another group's member -- and the solver's saving is the living members'
  sum, 14250); **the card carries the assumption line** (absent from the druid's card of the fake
  pull, present when the plan binds a Prayer of Healing); **causality unchanged** with group and
  chain heals (a burst at 40 s changes nothing cast before it).
- `scenariocheck` (forever 17 -> 19): **three same-instant claims for one PoH** (three own, one
  foreign heal left foreign, the replay heals 900); **an unclaimed own heal is replayed as
  recorded** (a Desperate Prayer the kit skips: own, `recorded` 1, an `OWNREPLAY` event of 320 at
  its time, no FHEAL, the engine lands 320 under `recorded`). Item 16 (T96) now compares the hot
  map (`.index`) rather than the slots table, which carries the kit's extra families since T101.
- `practiceforever` (forever 29 -> 31): **a paladin binds Holy Light** (`PR.Binds` shows both
  binds, `SpellFor` the top rank 25292, `FamilyLabel` "Holy Light", `ParseSpellText("Holy
  Light(Rank 9)")` -> HolyLight, 9); **Holy Shock on cooldown is refused** (a press at 1 s, one at
  4 s refused "Spell is not ready yet", one at 12 s cast: two casts recorded).

### Everything else

`tools/check.sh`: **81 run(s), all passed**, 76 counted against 76 expected, four NOTEs (the four
counts above) until the counts line below is applied; apicheck **0 findings**; textcheck **0 findings** (9 TOCs, 105
files); `luac -p` clean on every changed file. Compared byte for byte with the parent's own run
(an export of `25748e3` checked with its own `tools/check.sh`): every suite output is identical but
the four above and the lines that differ between two runs of the parent itself (table addresses,
the frame-sliced searches' `N evaluations` / `N frames` timing lines in `replayui`, `reviewui`,
`runcheck`, `simwindow`, `coachforever`, and `releasecheck`'s worktree path); `simcheck`'s run-cost
line is `3.57 KB/run with 1500 events, 3.58 KB/run with none`, as before.

**The author's recordings**: `tools/strategies.lua --file` on the eight TBC anniversary recordings
(the `_anniversary_` SavedVariables copied 2026-10-01) is **identical** before and after; Healroot's
twelve Forever reports (`tools/import.lua report 1..8`, `p1..p4`, the `_classic_beta_` file) are
**identical** (only the file path line differs). No druid fight changes: no recording carries a Wild
Growth, a Tranquility or a heal of a family the kit lacks.

## Integrator lines

**`tools/data/expected-counts.json`:** `"kitcheck/forever": 19,` (was 16),
`"practiceforever/forever": 31,` (was 29), `"scenariocheck/forever": 19,` (was 17),
`"solvercheck/tbc": 95,` (was 89).

**`docs/DECISIONS.md`**, a new entry:

> ## Heals that reach several targets; the Forever kit by shape (2026-10-01, T101, decision 12)
>
> On Forever the kit is the logged-in player's and every heal family its profile does not name is
> built from the book by shape: `group` (every living tracked member of the caster's party: Prayer
> of Healing, Holy Nova, Wild Growth), `chain` (its target, then the most injured party members at
> the cast at 50 %, 25 %: Chain Heal), `selfAndTarget` (Binding Heal), a channel with `party`
> (Tranquility now ticks on the whole party). No positions are recorded, so each reach is an
> optimistic assumption marked VERIFY; the coach card says `group heals assume everyone in range
> (no positions recorded): an upper bound` whenever one is bound or cast, and the solver sums what
> a cast saves over everyone it reaches. Wild Growth is in the druid's kit with its total in uniform
> 1 s ticks (VERIFY: its front-loaded curve is not in the text). A kit entry carries the book's own
> cooldown when the profile names none. On Forever an own cast of a heal the kit does not carry
> claims the heal landing with it, which is replayed as recorded and counted as the healer's own
> (gate 8 says how many) instead of foreign. TBC is unchanged: its kit has none of these types, and
> the v2 road (TBC fights, practice fights) does not yet replay unclaimed own heals -- that would
> move the author's TBC replays and needs its own decision. The strategies report on the author's
> eight TBC recordings and Healroot's twelve Forever reports are identical before and after.

**`CLAUDE.md`**, append to these rows:

- `Engine/Kit.lua`: **T101:** types `group` (`Kit.ANY_OF`: a whole direct part or a whole HoT part),
  `chain` (`jumps`, `falloff`), `selfAndTarget`; field `party` (a channel over the party);
  `Kit.MULTI_TARGET`, `Kit.ReachesMany(e)`.
- `Engine/SimModel.lua`: **T101 (4.5):** `SM.HotSlots(kit)` adds, per kit, a slot for a group HoT
  (and every HoT of a profile with no slots) and `extras` / `families` (the kit's families the
  profile's list lacks); `S.party` / `S.caster` from the targets' `caster` / `group`
  (`SM.InParty`); `SM.LandMulti` (group on the living party, chain on `SM.ChainTargets` -- most
  injured at the landing -- at falloff, selfAndTarget on the caster too), a `party` channel ticking
  on the party; `SM.IsInstant`; `SM.K.OWNREPLAY = 16` (a scenario kind: an own heal replayed as
  recorded, family `recorded`).
- `Engine/SimSolver.lua`: **T101:** a chain's jumps and a self-and-target's caster added to the
  saving; a group heal scored once over the living party (`SV.SavedOn`); rule 8 offers a group heal
  only for a party member.
- `Engine/SimPlanner.lua`: **T101:** `SP.Bindable()` (SP.BINDABLE + the kit index's other
  families); the card's Bind line lists them; `SP.GROUP_ASSUMPTION` / `SP.GroupAssumed(rec, plan)`.
- `Engine/Practice.lua`: **T101:** `PR.FamilyLabel` from the kit (then the druid list, then the key
  in words); castBase for the three new types; `SM.IsInstant`; you are the scenario's caster.
- the `Modules/<Name>/` row: **T101:** `Kit_Forever.lua` builds the logged-in player's kit
  (`MD.player.class`'s profile, else the generic one), every heal family the profile does not name
  by shape (`ShapeOf`, `RM.KeyOf`; group / chain / selfAndTarget / a party channel; absorbs, caster-
  only and conditional heals skipped by name), the book's cooldown when the profile has none, 1 s
  uniform ticks for a duration no multiple of 3 s, the stamp the logged-in class;
  `RM.KitRestore` indexes every entry by its own type; `Scenario_Forever.lua` makes N same-instant
  claims for a heal reaching several targets and replays an own heal of a spell the kit lacks as
  recorded (`SM.K.OWNREPLAY`, `counts.recorded`); `Gates_Forever.lua`'s gate 8 counts them.

**`docs/TOOLS.md`** section 1: `kitcheck.lua` -- "Since **T101** (forever 19): Wild Growth a group
HoT; a paladin, a shaman and a priest book (`tools/stub_books.lua`) become valid kits by shape."
`solvercheck.lua` -- "Since **T101** (95): PoH against Greater Heal by hurt count, Chain Heal's
jumps and falloff, a group sum over the living party, the card's group line, causality with group
and chain heals." `scenariocheck.lua` -- "Since **T101** (19): three same-instant PoH claims; an
own heal of a spell the kit lacks replayed as recorded." `practiceforever.lua` -- "Since **T101**
(31): a paladin's practice: Holy Light bound, Holy Shock refused on its cooldown."

**`docs/TESTING.md`** (section 46, in-game check 11 "Other healers"): on a Forever paladin, shaman
or priest alt, Simulate -> Practice binds the class's heals by name and Holy Shock / Riptide refuse
a second press inside their cooldown; record a pull with Prayer of Healing or Chain Heal
(`/st rec`), `/st validate N`: gate 8 counts the group heal's heals as own (one per member); a
Desperate Prayer counts as "from spells the kit does not price, replayed as recorded". On the
druid, a pull with Wild Growth or Tranquility: `/st replay N` heals the whole party.

**`docs/HISTORY.md`**: the integrator's wave entry ("T101: the generic Forever kit -- families by
shape, group / chain / selfAndTarget, the solver's sums under 4.5, N same-instant claims, own heals
replayed as recorded, Wild Growth in; kitcheck 16 -> 19, solvercheck 89 -> 95, scenariocheck 17 ->
19, practiceforever 29 -> 31").

No TOC, `tools/check.sh` or default change.

## Deviations and notes

1. **Tranquility stays a `channel`** (the druid profile, not this task's file, says so) with the
   new `party` field when its text reaches the party, rather than becoming a `group` entry; it
   lands each tick on the whole party (4.5 lists it under `group`). It stays out of plans.
2. **"The caster's party" for every group heal**, as 4.5 says, although Prayer of Healing's text
   reads "the target and their party" (in a five-man the same people).
3. **Unclaimed own heals are replayed as recorded on the v3 road only.** On the v2 road (TBC fights,
   practice fights) an `OWNHEAL` of a spell outside the kit is still dropped: doing it there would
   move the author's TBC replays (potions, anything not in the kit) and needs a decision of its own
   (principle 10). A v3 heal carries no spell id, so the claim is the heal landing in the cast's
   direct window on its target (on the caster for a caster-only text) -- a PoM jump or a totem tick
   later stays foreign, replayed as recorded either way.
4. **The tick period rule is generic**, not per spell: 3 s, or 1 s when the duration is no multiple
   of 3 (only Wild Growth among the texts read). A per-family period belongs in a profile (T106).
5. **A chain jumps only to members missing health** ("up to" `jumps`), VERIFY with the client's real
   jump rule.
6. **The v3 caster** is roster index 1 when its max was read plain and not through a bar -- the
   recorder lists `player` first; with that not so a self-and-target heal reaches its target only.
7. **Not owned, not changed:** `Stream_Forever.lua`'s `FAMILY_KEY` (a recording's `initial.known`)
   stays the druid's names, so `MaxRankBinds(known)` binds a by-shape family only when the fight
   cast it; the replay window draws three HoT icons, so Wild Growth's fourth slot is not drawn.
   T106 / the integrator may want both.
8. **`SM.IsInstant`** extends to the three new types only; Holy Shock (`direct`, cast 0) keeps the
   older path (it still lands at once; a practice press writes a cast start), so no older type's
   trace changes.
9. `tools/stub_books.lua` needed no change: `Books.Install(data, { alone = true, MD = MD })` serves
   the class books as T95 built it. The card's group line is said when a group heal is bound, not
   only cast (a threshold plan binds without casting).
10. A Forever druid's live kit on a real client now carries the tooltip's cooldowns for Tranquility
    (5 min) and Wild Growth (6 s): a second press inside them is refused in practice, a recorded cast
    is never refused (T90).
