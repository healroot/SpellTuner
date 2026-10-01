# T96 -- engine seams: the kit carries its profile, a channel lands its ticks

Status: **built** 2026-10-01 on branch `next/T96` (base `231525d`), wave N2, awaiting the
integrator. Spec: `docs/SPEC-next.md` section 11 row T96; 2.1 (the profile, "two readers, two
profiles"); section 3 (principles 1, 8, 9, 10); 4.5 (who a group heal reaches: T101's, not this
task's); decision 11 (Tranquility heals in the engine; the author: as recommended, 9.1). Research:
`docs/research/next/R-arch.md` 3.2-3.4, `R-classes.md` 141-146, `CRITIQUE-next.md` point 2 (the
engine's tables come from the kit, never the logged-in player). Needs T89 (profiles) and T90
(per-family cooldowns), both in the base. Integrator-owned files were **not** edited; their lines
are below. No TOC change: every file touched is already listed.

## What was built

- **`Engine/Kit.lua`** -- `Kit.TOP.profile = "string"` (declared first, as the file's rule asks);
  `Kit.DEFAULT_PROFILE = "DRUID"`; `Kit.Snapshot` carries the kit's `profile` -- written only when
  it is not the default, because a snapshot without one IS the druid's (every snapshot stored before
  T96), so a druid's snapshot stays byte for byte what it was (the committed import fixture, every
  stored `rec.kit` / `cdb.kit`); `Kit.Restore` gives the kit `snap.profile`, else `"DRUID"`.
- **`Engine/RankMath.lua`** (TBC's builder) -- stamps `kit.profile = "DRUID"` (SpellData is the
  druid's whoever is logged in) and copies each family's `cooldown` from the druid profile, named
  (`MD.Profiles.byClass.DRUID`): Swiftmend's entries carry `cooldown = 15`.
- **`Modules/SpellTuner_Replay/Kit_Forever.lua`** -- the entry's value fields are filled by the
  family's **kit type**, not its name: `KitEntryFor[def.kit](e, be, crit, def)` (`direct`, `hot`,
  `hybrid`, `channel`; `instant` has none -- Swiftmend is priced off the HoTs it eats, as before),
  published as `RM.KitEntryFor`; a family's profile `cooldown` copied onto every rank (Swiftmend 15);
  the channel entry also carries `tickPeriod` (the text's own period, "98 every 2 sec": the engine
  needs it to time the ticks); the kit is stamped with the profile its families come from
  (`DRUID.class`, the profile T89 derives `FAMILY_KEY` from, by name); and
  **`MD:Provide("KitLive", fn)`** -- `MD.KitLive()` -> `true, n` (n ranks priced) or
  `false, "kit"`: whether the live kit prices at least one heal (not excluded, not unpriced, not
  `dataMissing`). Provided only in the LoadOnDemand Replay module, beside `PracticePolicy`, so with
  the module off there is no provider (2.1: T99's `Can("coach")` then answers `false, "module"`).
- **`Engine/SimModel.lua`**
  - `SM.HotSlots(kit)` -> `{ index, name, lifebloom, families, profile }`: the HoT slots of the
    **kit's** profile (`MD.Profiles.ForKit`), derived once per profile (weak cache, read only). A
    slot the profile leaves empty keeps `SM.HOT_INDEX`'s family, so the druid's map is
    `SM.HOT_INDEX` exactly on **both** lines (Forever's druid profile has no Lifebloom slot; slot 3
    is still Lifebloom's) and every trace keeps its slot numbers. `families` is the profile's
    `planner.families`, else its `order` (nil: the solver's `SV.FAMILIES`).
  - `SM.HotSlotOf(slots, e)` (the entry's family's slot, else the druid's slot for its kit type,
    `SM.HOT_TYPE_FAMILY` -- what every kit did before) and `SM.HotFamilyOf(kit, e)`.
  - `SM:Run` derives the slots **per run** from its scenario's kit and publishes `S.hotSlots` /
    `S.hotIndex`; `LandCast` rolls a HoT into `SM.HotSlotOf`'s slot (was: hybrid -> 2, hot -> 1,
    lifebloom -> 3 by type), Lifebloom's stacking, bloom and end-of-fight pending bloom key on the
    profile's `lifebloom` slot, Swiftmend eats through the run's map (`SM.SwiftmendEats(e, row,
    index)`, the third argument optional), a pre-pull aura takes its kit entry's slot (was:
    MD.SpellData's family through `SM.HOT_INDEX` -- the same slot for every druid kit), and the
    per-target HoT reset walks the row instead of slots 1-3.
  - **A channel lands its ticks** (decision 11): `SM.ChannelShape(e)` -> `tick, ticks, period`
    (`channelTick`, `channelTicks`, the period from `tickPeriod`, else `duration` or `cast` over the
    ticks; none, or no `channelTick`, -> nil: it lands nothing, the period never guessed -- TBC's
    Tranquility is `dataMissing` with no `channelTick`, so TBC is unchanged). A channel cast on a
    target lands one tick per period from its success (a channel's SUCCEEDED is its start) on that
    target, until the count runs out, the target dies, another own cast succeeds or a recorded
    CASTSTART of another spell begins. One channel at a time, kept on the pool slot (`S.chan`),
    ticked as `E_TICK` events on slot 0 (`CHANNEL`); the start lives outside `Run`, so a run builds
    no new closure (`simcheck`'s per-run allocation line is byte-identical: 3.57 / 3.58 KB).
  - `SM.HOT_INDEX`, `SM.HOT_NAME`, `SM.SPELL_CD` stay literal: the druid's fallback (2.1).
- **`Engine/SimSolver.lua`** -- `Solver:Best` and rule 8 read the slots and the candidate families
  of the run (`S.hotSlots`), else of the plan's own kit (a state built by hand); `SV.FAMILIES` stays
  as the fallback for a profile naming none.
- **`Engine/ReplayTrace.lua`** -- `State:HotSlots()` (the scenario kit's profile's) and
  `State:HotFamily(fi)`.
- **`UI/ReplayWindow.lua`** -- the HoT icons are named by `st:HotSlots()` (was `SM.HOT_NAME`), the
  Lifebloom stack / white border by its `lifebloom` slot, the loop over the frame's own icons.
- **`Engine/Practice.lua`** -- the session's kit copy keeps `profile`; "Nothing to consume" finds
  Regrowth and Rejuvenation in the run's slots (`S.hotIndex`).
- **`Modules/SpellTuner_Replay/Scenario_Forever.lua`** -- the hot map (`SlotOf`, R28's Swiftmend
  bookkeeping and the HoT cutoffs) is `SM.HotFamilyOf(kit, e)`, the kit's profile's; a channel the
  engine lands (`SM.ChannelShape`) claims its ticks on its target (one per period from the cast,
  until the next own cast or cast start), so they are the engine's own healing and are **not**
  replayed a second time as foreign healing (a Tranquility tick was foreign before, every one).
- **`tools/kitcheck.lua`** (forever +5, tbc +2) and **`tools/scenariocheck.lua`** (+3), below.

## Failing first (the parent `231525d` with the new suites, `git archive` export)

- `kitcheck/forever`: **11 ok, 5 failed** -- `KitEntryFor fills each kit type` (no fillers;
  Tranquility's `tickPeriod` nil), `Swiftmend's kit entry carries the profile's 15 s cooldown`
  (nil), `kit.profile is stamped and round-trips` (nil), `a snapshot without a profile restores as
  the druid's` (nil), `MD.KitLive is provided` (not provided).
- `kitcheck/tbc`: **3 ok, 2 failed** -- `RankMath stamps the druid profile and emits Swiftmend's
  15 s cooldown` (profile nil, cooldown nil), `a druid kit's snapshot ... restores as the druid's`
  (restored nil).
- `scenariocheck/forever`: **14 ok, 3 failed** -- `a recorded Tranquility lands its ticks as own`
  (healed 0, ownTick 0, foreign 5), `the hot map is the kit's profile's` (no `SM.HotSlots`),
  `a test class's kit replays in its own slots` (test `2:2 4:1`, the druid's, want `2:1 4:2`).

## The new assertions

`kitcheck` (forever): 12 `KitEntryFor` has a filler for every non-instant kit type the druid
profile names, each filler's fields on a hand-made book entry (a hybrid missing its HoT half is
`dataMissing`), Tranquility's kit entry is `channel` 98 x 5 every 2 s; 13 Swiftmend's entry carries
`cooldown = 15` from the profile, no other entry has one, `SM.CooldownOf` answers `Swiftmend, 15`;
14 `kit.profile == "DRUID"` and validates, a druid snapshot names none and restores `"DRUID"`, a
`"PRIEST"` kit's snapshot carries it and restores it, a number refused by `Kit.Validate`; 15 a
pre-T96 snapshot (no profile) restored through `RankMath.KitRestore` is the druid's
(`ForKit`, `SM.HotSlots` = `SM.HOT_INDEX`); 16 `MD.KitLive()` -> `true, 5` on the stub's book.
`kitcheck` (tbc): RankMath stamps `"DRUID"`, Swiftmend's 15 from the profile and nothing else has a
cooldown, `SM.CooldownOf` -> `Swiftmend, 15`; a druid snapshot names no profile and restores
`"DRUID"`.

`scenariocheck`: 15 a recorded Tranquility (a channel entry shaped as Kit_Forever builds it) lands
5 x 98 on its target, the attribution claims the five ticks as own (none foreign), the replay's
health equals the reconstruction (max deviation 0), and a Healing Touch at t = 8 breaks it after two
ticks; 16 the hot map is the kit's profile's (a registered test class `T96HEALER` with its hybrid in
slot 1 and its HoT in slot 2: `SM.HotSlots`, `SM.HotFamilyOf`; a kit naming none is the druid's,
`SM.HOT_INDEX`); 17 **a kit whose profile is the test class replays with that class's slots while
the logged-in profile is the druid's** (`MD.ClassProfile` asserted the druid's; the trace's HoT
events `2:1 4:2`, the same entries in a kit naming no profile `2:2 4:1`; the replay state names slot
1 `Riptide` and slot 2 `Renew`).

## Suites, before and after

`tools/check.sh`: **77 run(s), all passed**; 72 counted against 72 expected, three NOTEs until the
counts line below is applied. apicheck **0 findings** (63 files, 48 distinct globals, unchanged);
textcheck **0 findings** (102 files); `luac -p` clean on the eleven changed files. No default
registered (`defaultscheck` unchanged: forever 52, tbc 49).

| suite | before | after |
|---|---|---|
| `kitcheck/forever` | 11 | **16** (+5) |
| `kitcheck/tbc` | 3 | **5** (+2) |
| `scenariocheck/forever` | 14 | **17** (+3) |
| every other suite | as `expected-counts.json` | unchanged |

**Byte-identical** (every `tools/.lua/check/*.out` of the parent run against this run, table
addresses replaced): `replaycheck`, `practice`, `practiceui`, `solvercheck`, `restcheck`, `simcheck`
(its "run cost is flat" line included: 3.57 / 3.58 KB per run), `practiceforever`, `importcheck`,
`profilecheck` (both), `slashcheck`, `verifycheck`, `replayforever`, `reviewforever`, `gatecheck`,
`recordcheck`, `bookcheck`, `tipcheck`, `spellsui`, and every other suite -- except the timing lines
of the frame-sliced searches (`coachforever`'s `frames=` / `progress=`, `reccheck`'s `N frames, M ms`,
`replayui` / `reviewui`'s `[sim] search N evaluations` and `opened ... N ms`, `runcheck` /
`simwindow`'s `N frames`), which differ between two runs of the **parent** in the same lines
(checked: the parent export run twice against the base outputs gives the same kind of diff in
`coachforever`, `reccheck`, `replayui`, `reviewui`, `simwindow`). Every evaluation count, plan and
score in them is identical.

**The author's recordings** (decision 11, X11): the strategies report on the eight TBC anniversary
recordings (`tools/strategies.lua --file`, the `_anniversary_` SavedVariables copied 2026-10-01) is
**identical before and after**, every row; `tools/import.lua coach N force` and `replay N` on all
eight: identical (only the "search ran across N stub frames" timing line moves); Healroot's eight
Forever pulls and four practice fights (`tools/import.lua report N` / `pN`): identical. **No fight
changes**: TBC's Tranquility kit entry carries no `channelTick` (Data/SpellData.lua has no
measured value, `dataMissing`), so it still lands nothing on TBC; Healroot (level 11) has no
Tranquility, and no Forever recording carries one. Decision 11 takes effect on Forever for a druid
who knows Tranquility (its text gives the tick and the period).

## Integrator lines

**`tools/data/expected-counts.json`:** `"kitcheck/forever": 16,` (was 11), `"kitcheck/tbc": 5,`
(was 3), `"scenariocheck/forever": 17,` (was 14).

**`docs/DECISIONS.md`**, a new entry:

> ## A channel lands its ticks; the engine reads the kit's profile (2026-10-01, T96, decision 11)
>
> A `channel` kit entry now heals in the engine (`SM.ChannelShape`: `channelTick` every
> `tickPeriod` -- Kit_Forever reads both from the spell's own text --, `channelTicks` times) on
> the cast's target, from the success until the count runs out, the target dies or the healer
> casts something else; an entry the engine cannot time (no `channelTick` or no period: TBC's
> Tranquility, `dataMissing`) lands nothing, never a guessed period. Scenario_Forever claims those
> ticks as the healer's own, so a Forever Tranquility is no longer replayed as foreign healing.
> Tranquility stays out of plans (`exclude`); who a group channel reaches is 4.5's `group` type
> (T101). And the engine's HoT slots, the solver's families and the per-family cooldowns come from
> the KIT's profile (`kit.profile`, stamped by both builders and carried by `Kit.Snapshot` /
> `Restore`; none = the druid's), never the logged-in player's, so `tools/import.lua` replays any
> character's recording on any machine. The author accepted decision 11 as recommended. The
> strategies report on the author's eight TBC recordings, the eight coach cards and replays, and
> Healroot's twelve Forever reports are **identical before and after**: TBC's Tranquility has no
> measured tick (it still lands nothing there) and no Forever recording has a Tranquility yet.

**`CLAUDE.md`**, append to these rows:

- `Engine/SimModel.lua`: **T96 (decision 11):** the HoT slots are the KIT's profile's --
  `SM.HotSlots(kit)` (`index`, `name`, `lifebloom`, `families`, `profile`; from
  `MD.Profiles.ForKit`, a slot the profile leaves empty keeping `SM.HOT_INDEX`'s family, so the
  druid's map is `SM.HOT_INDEX` on both lines), `SM.HotSlotOf(slots, e)`, `SM.HotFamilyOf(kit, e)`,
  derived per run and published as `S.hotSlots` / `S.hotIndex`; `SM.SwiftmendEats(e, row, index)`;
  `SM.HOT_INDEX` / `SM.HOT_NAME` / `SM.SPELL_CD` stay as the druid's fallback; **a channel lands its
  ticks** (`SM.ChannelShape(e)` -> tick, ticks, period; on the cast's target, broken by the next own
  cast or a recorded cast start; nothing without a `channelTick` and a period -- TBC's Tranquility).
- `Engine/SimSolver.lua`: **T96:** `Best` and rule 8 read the run's slots and families
  (`S.hotSlots`, else the plan's kit's); `SV.FAMILIES` is the fallback.
- `Engine/Kit.lua`: **T96:** `Kit.TOP.profile`, `Kit.DEFAULT_PROFILE = "DRUID"`; `Snapshot` writes
  `profile` only when it is not the druid's (a druid snapshot is byte-identical), `Restore` gives
  it back (none -> `"DRUID"`).
- `Engine/RankMath.lua`: **T96:** `SpellKit` stamps `kit.profile = "DRUID"` and copies each
  family's profile `cooldown` (Swiftmend 15).
- `Engine/ReplayTrace.lua`: **T96:** `State:HotSlots()` / `State:HotFamily(fi)`, the scenario
  kit's profile's.
- `UI/ReplayWindow.lua`: **T96:** the HoT icons named by `st:HotSlots()`, not `SM.HOT_NAME`.
- `Engine/Practice.lua`: **T96:** the session's kit copy keeps `profile`; "Nothing to consume" reads
  the run's slots.
- the `Modules/<Name>/` row: **T96:** `Kit_Forever.lua` fills an entry by its family's kit type
  (`RM.KitEntryFor[type]`), copies the profile's `cooldown` (Swiftmend 15), gives a channel its
  `tickPeriod`, stamps `kit.profile`, and provides **`MD.KitLive()`** (`true, n` | `false, "kit"`:
  the live kit prices a heal -- T99's Forever `Can("coach")`; no provider with the module off);
  `Scenario_Forever.lua`'s hot map is the kit's profile's (`SM.HotFamilyOf`) and a channel the
  engine lands claims its ticks as own.

**`docs/TOOLS.md`**, section 1: the `kitcheck.lua` row, append: "Since **T96** (forever 16, tbc 5):
`KitEntryFor` per kit type, Swiftmend's `cooldown` 15 from the profile (both builders), `kit.profile`
stamped and round-tripped by `Snapshot` / `Restore` (a druid snapshot names none), a snapshot
without one restores as the druid's, `MD.KitLive`." The `scenariocheck.lua` row, append: "Since
**T96** (17): a recorded Tranquility lands its ticks as own and a later cast breaks it; the hot map
is the kit's profile's; a test class's kit replays in its own slots while the druid is logged in."

**`docs/TESTING.md`** (section 46, optional): on a Forever druid who knows Tranquility, record a pull
with one (`/st rec`), `/st replay N`: the Tranquility's target's bar rises on the tick, and
`/st validate N`'s gate 8 counts the ticks as own.

**`docs/HISTORY.md`**: the integrator's wave entry. No TOC, `tools/check.sh` or
`tools/defaultscheck.lua` change.

## Deviations from the spec

1. **The builders stamp the profile their families come from, not `MD.ClassProfile`'s key.** Both
   builders still make the druid's families (RankMath from Data/SpellData.lua; Kit_Forever from
   T89's `FAMILY_KEY`, derived from the druid profile by name), so the stamp says `"DRUID"`
   whoever is logged in -- the profile whose slots match the kit's family keys. T101, which builds
   the Forever kit from the logged-in profile's families, stamps that profile.
2. **`Kit.Snapshot` writes `profile` only when it is not the druid's.** "None -> DRUID" is the
   convention, so this is lossless, and it keeps every druid snapshot byte-identical -- the
   committed `tools/data/import-forever-sv.lua` (importcheck's "the fixture is what the code writes
   today") and every stored `rec.kit` / `cdb.kit`. `Restore` always gives the kit a profile.
3. **`kitcheck` grew by 5 on forever and 2 on tbc**, not 4: `MD.KitLive` got its own assertion, and
   the TBC builder's stamp and cooldown are held on tbc too ("RankMath emits Swiftmend's").
4. **A channel lands on the cast's target only**, and a target-less channel cast lands nothing:
   who a group channel (Tranquility) reaches is 4.5's `group` assumption, the type T101 adds. The
   kit's channel entry gained `tickPeriod` (a declared field) because the engine needs the period
   and Kit_Forever had it in hand; an entry without it falls back to `duration` or `cast` over the
   ticks, else lands nothing.
5. **`SM.HotSlots` fills the slots a profile leaves empty with `SM.HOT_INDEX`'s families**, so a
   profile without Lifebloom (Forever's druid) still maps slot 3 to Lifebloom and every druid kit's
   map equals `SM.HOT_INDEX` exactly; a HoT whose family has no slot falls back to the druid's slot
   for its kit type. `SM.HOT_INDEX`, `SM.HOT_NAME` and `SM.SPELL_CD` stay literal (not derived
   from the druid profile at load): Forever's druid profile has no Lifebloom and the profile
   carries no spell ids; `profilecheck` keeps them equal to the profile's values.
6. `SimPlanner.lua`'s own `local HOT_INDEX` (the threshold rules, the druid's strategy) is not this
   task's file and is unchanged; its slots equal the druid's `SM.HotSlots` on both lines.
