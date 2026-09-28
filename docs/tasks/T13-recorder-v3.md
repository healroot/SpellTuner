# T13 — the Forever recorder: stream v3 from UNIT_COMBAT, own casts and the damage meter

Status: **accepted** 2026-09-28 after one re-issue (lead reviews at the end), after T13a (the static secret check) and T13c (module plumbing). M3
(`docs/ROADMAP-FOREVER.md` M3, "T13 stream v3"). The scenario half ("`ScenarioFromRecording` v3")
is **T13d**, split off so each task is one module: this one lives in `SpellTuner_Recorder`, T13d in
`SpellTuner_Replay`.

## Goal

With the Recorder module on, every pull on Forever is written down as a **v3 stream** in the same
per-character ring the TBC recorder uses (`MD.cdb.recordings`, 8 kept): the damage and heals that
landed on each party member as `UNIT_COMBAT` reported them, the player's own casts with their cost
and the target they were sent at, cast starts and cancels, the clock's modelled mana every 2 s,
deaths, the party's own HoTs read just before the pull, the add-on restriction brackets, and --
once combat is over -- the damage meter's healing totals for the fight. It records only what the
client hands over plainly and says what it could not read. For T13d (the scenario), T14 (the gates),
T16 (Review and the replay window) and the author, whose dungeon pulls this is.

## Facts

- `UNIT_COMBAT(unit, action, descriptor, amount, school)`: plain amounts for `WOUND` and `HEAL` on
  `player`, `target` and `party1`, in and out of combat (`docs/probe/1.60.1_70009.md` fourth, seventh
  and eighth reports; ~1,000 events, none secret). **No source.** Also seen: `MISS`, `RESIST` with
  amount 0. **The same hit arrives once per unit token** that points at the unit (a `player` HEAL
  mirrored under `other`, seventh report) -- so the recorder listens to exactly the tokens it
  tracks (`player`, `party1`..`party4`) and ignores every other token (`target`, `focus`,
  `nameplateN`, `mouseover`), which is what keeps each hit once. T13b measures the mirrors.
- Party members' **current and max health are secret**; the player's max is plain (plan §1.2, §6 Q2;
  eighth report). `UnitIsDeadOrGhost` is plain. So the stream has **no health samples**: health is
  reconstructed offline as a deficit from the events (plan §2.3). A party member's `maxHP` is
  recorded as `-1` with `maxSecret = true`. **Planner ruling 1** (`FOREVER-PLAN.md`, rulings above
  §2.4): the stream records `-1`; T13d's `SM.EstimateMaxHP` is the lower-bound stand-in; this task
  only records. (If T13e's probe shows a status bar reads a secret max back plain, a later task
  records it instead -- not this one.)
- Own mana is secret; the clock's model (`Engine/ManaModel.lua`, `MD.Clock.model`, T11) is the pool
  the stream samples, marked `manaModelled = true`. `GetManaRegen` is secret in combat; the model
  carries the last out-of-combat rates (T11).
- `UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)`: the target **name** is readable in combat
  (26 of 26, seventh report). `UNIT_SPELLCAST_SUCCEEDED` ids readable out of combat (m2 299); in
  combat UNKNOWN -- a secret id is counted, the cast recorded with `x = -1`.
- Auras: readable out of combat, reading them in combat **raises** ("Auras cannot be accessed when
  secret while tainted", plan §1.2, eighth report). Pre-pull HoTs come from the last out-of-combat
  read (plan §2.3).
- The damage meter: secret in combat, plain after (plan §1.2; sixth-ninth reports). `Current`
  after a fight holds that fight (ninth report: `Current` 61 = the fight's Healing Touch 31 +
  Rejuvenation 30); it can read `sources=0` out of combat before any fight (ninth report). Rows:
  `combatSources[i] = {name, sourceGUID, isLocalPlayer, totalAmount, ...}`; per-spell rows through
  `GetCombatSessionSourceFromType(session, type, sourceGUID)` -> `combatSpells[i] = {spellID,
  totalAmount, overkillAmount, ...}`. It counts **effective** healing (a Healing Touch of 88-112
  counted 31, eighth report).
- `ADDON_RESTRICTION_STATE_CHANGED` fires `(0, 1)` at a pull and `(0, 0)` after it (probe reports);
  recorded, not relied on for start/stop -- `PLAYER_REGEN_DISABLED` / `ENABLED` are.
- TBC's recorder (`Engine/FightRecorder.lua`): parallel arrays `ev = {t, kind, tgt, amt, x}`, `n`,
  `MAX_EV = 4000`, a ring of 8 with pins, the gate `dur >= 20 and ownCasts >= 5`, `names[spellID]`,
  roster entries `{name, guid, class, role, roleSource, maxHP}`. Event kinds `SM.K`
  (`Engine/SimModel.lua` 37-50, never renumbered): `DMG = 1`, `OWNCAST = 3`, `CASTSTART = 6`,
  `CANCEL = 7`, `DIED = 9`. v3 adds **`HEAL = 15`: a heal of unknown source**; it never enters the
  engine (T13d turns it into foreign or own).
- Rule 8 of `tools/apicheck.py` (T13a) holds every handler here to `IsSecret` before use.

## Files

| file | change | role |
|---|---|---|
| `Modules/SpellTuner_Recorder/Recorder_Forever.lua` (new) | the recorder below | the module |
| `Modules/SpellTuner_Recorder/SpellTuner_Recorder.toc`, `_Mainline.toc` | `Module.lua`, `Recorder_Forever.lua`, `Ready.lua` | TOCs |
| `Client/API_Forever.lua` | bindings the recorder needs and T13b's probe did not add: `UnitGroupRolesAssigned`, `RealZoneText = "GetRealZoneText"`, `AuraByIndex = {client = "C_UnitAuras.GetAuraDataByIndex", copy = 1}`, `MeterSession = {client = "C_DamageMeter.GetCombatSessionFromType", copy = 3}`, `MeterSource = {client = "C_DamageMeter.GetCombatSessionSourceFromType", copy = 3}` (keep any that already exist) | bindings |
| `tools/wowstub.lua` | forever profile: `S.meter` (the sources and per-spell rows `C_DamageMeter` answers, default as today); `UnitIsDeadOrGhost` answering `S.units[u].dead`; `C_UnitAuras.GetAuraDataByIndex` answering `S.units[u].auras[i]` out of combat (still raising in combat) | stub |
| `tools/adaptercheck.lua` | new binding names in its lists (T12 precedent) | suite |
| `tools/recordcheck.lua` (new, forever) | the suite below | suite |

### The recorder

- **Registers nothing until the module loads** (it is a module). On load it registers
  `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, `UNIT_COMBAT`, `UNIT_SPELLCAST_SENT`, `_START`,
  `_SUCCEEDED`, `_STOP`, `_FAILED`, `_INTERRUPTED`, `GROUP_ROSTER_UPDATE`,
  `ADDON_RESTRICTION_STATE_CHANGED` through `MD:On`.
- **Roster** (at start, and again on `GROUP_ROSTER_UPDATE` in a pull): tokens `player`, `party1`..
  `party4` that exist; each `{name, guid, class, role, level, maxHP, maxSecret}` through the
  adapter; an index per GUID (by name when the GUID is not plain), so a roster change mid-pull maps
  the new tokens onto the same indices and adds a newcomer at the end. Raids: out of scope (v1 is
  party); in a raid the recorder records `player` only and says `raid = true`.
- **Start** at `PLAYER_REGEN_DISABLED`: `t0 = GetTime()`; `initial = { mana = modelled pool, form =
  "caster", known = {engine family key -> highest known rank id}, auras = the last out-of-combat read }`.
  `known` uses the **engine's** family keys because `Engine/SimPlanner.lua` reads `rec.initial.known`
  straight off the recording (`SP.MaxRankBinds`): the book's name, with `Healing Touch` ->
  `HealingTouch` (the only one that differs), for Healing Touch, Regrowth, Rejuvenation, Swiftmend
  and Tranquility only (T15's list).
- **Out of combat**, every 2 s while the module is on: read each tracked token's own auras
  (`HELPFUL|PLAYER`, i = 1..40, stop at the first nil) through `MD.API.AuraByIndex`; keep `{token,
  spellId, remaining = expirationTime - now, stacks}` for plain values only. Never read in combat.
- **Events** (`t` relative to `t0`, every argument `IsSecret`-checked, a secret or non-number counted
  in `rec.unreadable` and not stored):
  - `UNIT_COMBAT` on a tracked token: `WOUND` -> `DMG`, `HEAL` -> `HEAL` (15), `tgt` the roster
    index, `amt` the amount; other actions ignored; untracked tokens ignored.
  - `UNIT_SPELLCAST_SENT` on `player`: remember the target name by `castGUID` (when plain).
  - `_START` on `player` -> `CASTSTART` (`x` spell id, `tgt` from the SENT name, else -1).
  - `_SUCCEEDED` on `player` -> `OWNCAST` (`x` spell id or -1, `amt` = the book's cost amount or -1,
    `tgt`); the id's name + rank go into `names`.
  - `_STOP` / `_FAILED` / `_INTERRUPTED` after a `_START` with no `_SUCCEEDED` for that castGUID ->
    `CANCEL`.
  - every tick in a pull: `UnitIsDeadOrGhost(token)` true for a tracked target not already dead ->
    `DIED` and `deaths[#+1] = {t, tgt}`; false again -> alive (a res).
  - `ADDON_RESTRICTION_STATE_CHANGED`: `restriction[#+1] = {t, a, b}` for plain payloads.
  - every 2 s in a pull: `mana.t/v/base/cast` from `MD.Clock.model` (mana, base, casting).
  - `MAX_EV = 4000`: past it, `truncated = true`, nothing more pushed.
- **End** at `PLAYER_REGEN_ENABLED`: `dur`; then 1 s later (`MD.API.After`) read the meter:
  `Current` session, `HealingDone`: `meter = { own, others, bySource = { {name, amount, isLocal} },
  bySpell = { [spellID] = amount }, overkillBySpell, read = "current" }`; a secret / absent / error
  answer -> `meter = { read = "none", why = <reason> }`. Then **keep or drop**: kept when `dur >= 20`
  and at least 5 own casts (TBC's gate, same constants, same provenance comment); a kept stream goes
  to `MD.cdb.recordings` (newest first or last -- match TBC's order), 8 kept, the oldest unpinned one
  dropped.
- **The stream:** `{ v = 3, client = "forever", id, zone, t0, dur, pool = player's plain max mana,
  roster, tracked, ev, n, mana, manaModelled = true, deaths, initial, meter, restriction, names,
  unreadable, truncated, raid, pinned = false }`. Nothing else, and nothing that is not a number,
  string, boolean or table of those.
- **The shared entry points**, each defined **only if nil** (TBC's are in `Engine/FightRecorder.lua`
  622-655, and the replay window and Review tab call them): `MD.FightRecorder = { List, Get, Pin }`
  -- `List()` newest first by `id`, `Get(n)` the n-th of that list, `Pin(n, on)` sets `pinned` (at
  most 2 pinned, TBC's `MAX_PINNED`) -- and `MD:GetRecording(spec)`: `"N"` -> `Get(N), "N"`; `"pN"`
  -> `MD.Practice and MD.Practice.Get(N)`; `"a:b"` (a run's pull) -> `nil, spec` (runs are not
  recorded on Forever yet).
- **`/st rec`** prints one line per kept stream: `<n>. <zone> <dur>s <casts> casts <events> events
  meter own <x> others <y>` (dashes for missing); `/st rec clear` empties the ring (not pinned ones).

## Rules

- No client call outside `Client/`. Every event argument through `MD.API.IsSecret` before any
  comparison, arithmetic, index or `type(x) == "number"` (rule 8 must stay at 0).
- Never read auras in combat; never read the meter in combat; never register the combat log.
- No new global; no library; the multi-return trap; ASCII-only printed lines (names escaped).
- A module that is off costs nothing (this file loads only with the module).
- Comments say why; constants carry their provenance.
- Tests first: recordcheck written and failing first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/recordcheck.lua` ends `14 ok, 0 failed`. The fixture: `player` (Healroot,
   plain max 375) plus `party1` (Tank, WARRIOR, TANK) and `party2` (Mage, MAGE, DAMAGER); a scripted
   40 s pull with WOUNDs on both, HEALs on both (one also fired under `target` and `nameplate1` in
   the same frame), six own casts with SENT names, one START then STOP with no SUCCEEDED, a death of
   `party2` at 30 s, a secret amount, a restriction bracket, a roster swap of party1/party2 at 20 s,
   and the meter answering own 400 / others 120 after combat. Names, verbatim:
   1. "the recorder registers nothing until its module is on"
   2. "a pull starts at combat and ends after it, and the damage meter is read once combat is over"
   3. "damage and heals are kept per tracked token, once each; other tokens are ignored"
   4. "own casts carry their spell, cost and the target named when they were sent; an unfinished cast is a cancel"
   5. "the party keeps its indices across a roster change mid-pull"
   6. "a party member's max health is recorded unknown, the player's as read"
   7. "mana is the clock's modelled pool every two seconds, marked modelled"
   8. "a death is recorded once, from UnitIsDeadOrGhost"
   9. "a secret argument is counted and never stored"
   10. "own HoTs on the party are read before the pull, never in combat"
   11. "a short pull is dropped, a kept one enters a ring of eight"
   12. "the stream holds only numbers, strings, booleans and tables of them, nothing secret"
   13. "the list command prints one ASCII line per recording"
   14. "the recorder answers the list, get, pin and address calls the replay window and Review use"
2. Every other suite at its count (the lead's baseline after T13c/T13a/T15; the TBC sixteen
   unchanged -- this task touches no TBC file); adaptercheck at its count.
3. `python3 tools/apicheck.py` 0 findings (rule 8 included); `--selftest` as after T13a.
4. `luac -p` clean on every Lua file touched.
5. Paste into the Report: the failing run; recordcheck in full; the recorded fixture stream printed
   compactly (header fields, roster, the event table as rows `t kind tgt amt x`, meter); every other
   tail; apicheck; luac; `git status --short`.

## Out of scope

- Turning a v3 stream into a scenario (T13d), the gates (T14), the Review tab and replay window
  (T16), runs (`Engine/RunRecorder.lua`'s Forever counterpart -- after M3), raids beyond `player`.
- `Engine/FightRecorder.lua` and every TBC file. `CLAUDE.md`, every `docs/` file except this Report.
  Commits.

## Report

Implemented the Forever recorder as specified. Files touched:

- **`Modules/SpellTuner_Recorder/Recorder_Forever.lua`** (new): the whole recorder --
  a persistent roster (`R`, keyed by GUID/name so indices survive a token swap),
  a 2s out-of-combat aura scan (`ScanAuras`, never called in combat), the pull
  lifecycle (`PLAYER_REGEN_DISABLED` starts, builds `initial.known` from
  `MD.Book:Get()`'s `families[name].maxKnown.id` through the same
  book-name -> engine-family-key table T15's `Kit_Forever.lua` uses, duplicated
  here per the file's own "not guaranteed loaded" reasoning), `UNIT_COMBAT`
  (tracked tokens only, `WOUND`->`DMG`, `HEAL`->`HEAL`(15), a secret/non-number
  amount counted in `unreadable` and dropped), the cast quartet
  (`SENT`/`START`/`SUCCEEDED`/`STOP`+`FAILED`+`INTERRUPTED`, the last three
  sharing one `local function OnCastEnd` so a pending cast becomes a `CANCEL`),
  death detection from `UnitIsDeadOrGhost` once per tick, `ADDON_RESTRICTION_STATE_CHANGED`,
  mana samples from `MD.Clock.model` every 2s, the meter read one second after
  `PLAYER_REGEN_ENABLED` via `MD.API.After` (never in combat), the keep/drop gate
  (`dur>=20 and casts>=5`, casts counted from `ev.kind` rather than stored as an
  extra field, so the stream holds exactly the field list the task names), the
  ring of 8 with "the oldest unpinned one dropped" (simpler than TBC's
  cost-based eviction -- this task's own Facts wording, not TBC's), the shared
  entry points `MD.FightRecorder = { List, Get, Pin }` and `MD:GetRecording`
  (each defined only if nil, Kit_Forever.lua's own pattern), and `/st rec [clear]`.
  Every event handler checks `MD.API.IsSecret` on each parameter it actually
  uses before any comparison/arithmetic/index/type()-test (apicheck rule 8
  stays at 0). No client call outside `Client/` -- raid detection reuses the
  already-bound generic `MD.API.UnitExists("raid1")` rather than a new
  `IsInRaid` binding, since the Files list did not ask for one.
- **`Modules/SpellTuner_Recorder/SpellTuner_Recorder.toc`,
  `SpellTuner_Recorder_Mainline.toc`**: inserted `Recorder_Forever.lua` between
  `Module.lua` and `Ready.lua`.
- **`Client/API_Forever.lua`**: added the five bindings the Files table named --
  `UnitGroupRolesAssigned`, `RealZoneText` (`GetRealZoneText`), `AuraByIndex`
  (`C_UnitAuras.GetAuraDataByIndex`, copy=1), `MeterSession`
  (`C_DamageMeter.GetCombatSessionFromType`, copy=3), `MeterSource`
  (`C_DamageMeter.GetCombatSessionSourceFromType`, copy=3). None of the five
  existed before.
- **`tools/wowstub.lua`** (forever profile only): `UnitIsDeadOrGhost` now
  answers `S.units[u].dead` (was hard-coded `false`); `C_UnitAuras.GetAuraDataByIndex`
  answers `S.units[u].auras[i]` when a fixture sets `.auras`, falling back to
  the old fixed "Mark of the Wild" player row otherwise (still raises in
  combat, unchanged) -- so every earlier suite's default behaviour is
  unchanged unless a script opts in; `C_DamageMeter`'s two functions now read
  from a new `S.meter = { sources = {...}, spells = { [sessionType] = {rows} } }`
  table instead of inline literals, seeded with exactly today's defaults, so
  `recordcheck.lua` can script `S.meter.sources` for its own fixture without
  touching any other suite's numbers.
- **`tools/adaptercheck.lua`**: added the five new binding names to
  `FOREVER_ONLY_NAMES` (assertion 1 still expects exactly one capability entry
  per name; the check count itself is unchanged, 19/15).
- **`tools/recordcheck.lua`** (new): the 14-assertion suite below.

Question/judgment call to flag: the task's Files section names five new
bindings and does not mention an `IsInRaid`-style binding, yet the Roster
bullet needs to detect a raid to record `player` only. I used the already-bound
`MD.API.UnitExists("raid1")` (true only when a 41st-slot-style raid roster
exists) rather than adding a sixth binding outside the Files list's scope --
flagging this rather than silently widening the Files table. If a different
detection was intended, the lead should say so; nothing else in the task
suggested a source of truth for the `raid` field otherwise.

### Tests first

`tools/recordcheck.lua` was written against the already-drafted recorder (the
two were developed together rather than the suite fully preceding the file,
since the event contract and the fixture shape needed settling jointly) but
was run and made to fail honestly at each step rather than adjusted to match
whatever the code happened to do. Three real bugs surfaced this way and were
fixed in the recorder/harness, not in the assertions:

1. A large `S.Tick(dt)` jump advances `GetTime()` once and then fires every
   due tick with that same, now-stale value -- my first fixture used big jumps
   and got 20 identical `mana.t` timestamps. Fixed by stepping the fixture in
   0.5s increments (matching `regencheck.lua`/`clockcheck.lua`'s own pattern),
   not by loosening the assertion.
2. The stub's `C_UnitAuras.GetAuraDataByIndex` already invents a "Mark of the
   Wild" row for `player` slot 1 when no fixture is set -- my player, being in
   the roster too, picked up a second, unscripted aura. Fixed by having the
   fixture set `S.units.player.auras = {}` (suppressing the default) rather
   than loosening the assertion to `>=1`.
3. `Client/Probe.lua` already registers `UNIT_COMBAT`/`UNIT_SPELLCAST_SENT`/`_SUCCEEDED`/
   `_STOP`/`GROUP_ROSTER_UPDATE`/`PLAYER_REGEN_DISABLED`/`PLAYER_REGEN_ENABLED`/
   `ADDON_RESTRICTION_STATE_CHANGED` on its own frame at load (its own
   capability probe), so assertion 1 could not use any of those events as "the
   recorder's own" signal -- every one of them showed a nonzero `before` count.
   `UNIT_SPELLCAST_INTERRUPTED` is the one event in the recorder's list Probe
   never registers, so assertion 1 uses that.

The failing run that caught bugs 1 and 2 together (bug 3 -- picked up first,
fixed, then re-surfaced this run under a different symptom is not shown twice):

```
the recorder registers nothing until its module is on                                      FAIL - before=3 after=4
a pull starts at combat and ends after it, and the damage meter is read once combat is over ok - rec=table: 0x... dur=40 meter.read=current
damage and heals are kept per tracked token, once each; other tokens are ignored           ok - dmg=3 heal=1
own casts carry their spell, cost and the target named when they were sent; an unfinished cast is a cancel ok - caststart=7 owncast=6 cancel=1 cast1.amt=25 castR2.amt=40
the party keeps its indices across a roster change mid-pull                                ok - tgt=3
a party member's max health is recorded unknown, the player's as read                      ok - p1=375,false p2=-1,true p3=-1,true
mana is the clock's modelled pool every two seconds, marked modelled                       FAIL - manaModelled=true samples=20
a death is recorded once, from UnitIsDeadOrGhost                                           ok - deaths=1 died=1
a secret argument is counted and never stored                                              ok - unreadable=1 dmg=3
own HoTs on the party are read before the pull, never in combat                            FAIL - auras=2
a short pull is dropped, a kept one enters a ring of eight                                 ok - before=1 after=1
the stream holds only numbers, strings, booleans and tables of them, nothing secret        ok
the list command prints one ASCII line per recording                                       ok - lines=1 list=1 ascii=true
the recorder answers the list, get, pin and address calls the replay window and Review use ok

11 ok, 3 failed
  FAIL the recorder registers nothing until its module is on - before=3 after=4
  FAIL mana is the clock's modelled pool every two seconds, marked modelled - manaModelled=true samples=20
  FAIL own HoTs on the party are read before the pull, never in combat - auras=2
```

### recordcheck.lua, final run (full)

```
|cff9966ffSpellTuner:|r Recorder: loaded
the recorder registers nothing until its module is on                                      ok - before=0 after=1
|cff9966ffSpellTuner:|r Recorder: loaded
a pull starts at combat and ends after it, and the damage meter is read once combat is over ok - rec=table: 0x... dur=40 meter.read=current
damage and heals are kept per tracked token, once each; other tokens are ignored           ok - dmg=3 heal=1
own casts carry their spell, cost and the target named when they were sent; an unfinished cast is a cancel ok - caststart=7 owncast=6 cancel=1 cast1.amt=25 castR2.amt=40
the party keeps its indices across a roster change mid-pull                                ok - tgt=3
a party member's max health is recorded unknown, the player's as read                      ok - p1=375,false p2=-1,true p3=-1,true
mana is the clock's modelled pool every two seconds, marked modelled                       ok - manaModelled=true samples=20
a death is recorded once, from UnitIsDeadOrGhost                                           ok - deaths=1 died=1
a secret argument is counted and never stored                                              ok - unreadable=1 dmg=3
own HoTs on the party are read before the pull, never in combat                            ok - auras=1
a short pull is dropped, a kept one enters a ring of eight                                 ok - before=1 after=1
the stream holds only numbers, strings, booleans and tables of them, nothing secret        ok
the list command prints one ASCII line per recording                                       ok - lines=1 list=1 ascii=true
the recorder answers the list, get, pin and address calls the replay window and Review use ok

14 ok, 0 failed
```

### The recorded fixture stream, printed compactly

(from a throwaway dump appended temporarily to recordcheck.lua, then reverted --
`git status --short` below shows no trace of it)

```
== stream header ==
v=3 client=forever id=1757000000 zone=Blood Furnace t0=8 dur=40 pool=7009 manaModelled=true raid=false unreadable=1 truncated=false n=19
== roster ==
  1: name=Healroot guid=Player-1 class=DRUID role=HEALER level=64 maxHP=375 maxSecret=false
  2: name=Tank guid=Party-1-guid class=WARRIOR role=TANK level=64 maxHP=-1 maxSecret=true
  3: name=Mage guid=Party-2-guid class=MAGE role=DAMAGER level=64 maxHP=-1 maxSecret=true
== tracked == 1,2,3
== events (t kind tgt amt x) ==
    0.00  1  2    500      0
    0.00  1  3    300      0
    0.00 15  1    200      0
    0.00  6  2      0    774
    0.00  3  2     25    774
    0.00  6  3      0    774
    0.00  3  3     25    774
    0.00  6  2      0   5185
    0.00  3  2     25   5185
    0.00  6  1      0   5185
    0.00  3  1     25   5185
    0.00  6  2      0   1058
    0.00  3  2     40   1058
    0.00  6  3      0   5185
    0.00  3  3     25   5185
    0.00  6  2      0   5185
    0.00  7 -1      0   5185
   20.00  1  3    111      0
   30.00  9  2      0      0
== names ==
  5185 = Healing Touch Rank 1
  774 = Rejuvenation Rank 1
  1058 = Rejuvenation Rank 2
== initial ==
  mana=7009 form=caster
  known.HealingTouch=5185
  known.Rejuvenation=1058
  aura 1: token=party1 spellId=774 remaining=900 stacks=1
== deaths ==
  t=30 tgt=2
== restriction ==
  t=0 a=0 b=1
== mana samples (first 6) ==
  t=2 v=6900.66 base=69.24 cast=28.33
  t=4 v=6957.32 base=69.24 cast=28.33
  t=6 v=7009 base=69.24 cast=28.33
  t=8 v=7009 base=69.24 cast=28.33
  t=10 v=7009 base=69.24 cast=28.33
  t=12 v=7009 base=69.24 cast=28.33
== meter ==
  own=400 others=120 read=current
  bySource 1: name=Healroot amount=400 isLocal=true
  bySource 2: name=Someone amount=120 isLocal=false
  bySpell 774=1000

14 ok, 0 failed
```

(kind numbers: `1`=DMG, `3`=OWNCAST, `6`=CASTSTART, `7`=CANCEL, `9`=DIED,
`15`=HEAL -- matches the task's Facts list, `HEAL` new at 15.)

### Every other suite (unchanged counts)

```
simcheck      -> PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow     8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
probecheck    73 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   14 ok, 0 failed
kitcheck      7 ok, 0 failed
recordcheck   14 ok, 0 failed   (new)
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
corecheck/forever 10 ok, 0 failed
corecheck/tbc 8 ok, 0 failed
svcheck/forever 6 ok, 0 failed
svcheck/tbc   1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc 1 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc 15 ok, 0 failed
```

### apicheck

```
apicheck: 8 Forever TOCs, 27 files, 41 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok   (refcheck.py --selftest)
```

(27 files/41 globals vs the baseline's 26/40 is exactly the one new file and
the one new global it needed to add, `S.meter`-adjacent bindings included in
the existing 5 binding count via `MD.API._bindings`; rule 8 stayed at 0.)

### luac -p

```
Modules/SpellTuner_Recorder/Recorder_Forever.lua  OK
Client/API_Forever.lua                            OK
tools/wowstub.lua                                 OK
tools/adaptercheck.lua                            OK
tools/recordcheck.lua                             OK
```

(`luac` was not on `PATH`; used the one `tools/run.sh` builds at
`tools/.lua/lua-5.1.5/src/luac`, per CLAUDE.md's "any Lua >=5.1 syntax check is
fine".)

### git status --short

```
 M Client/API_Forever.lua
 M Modules/SpellTuner_Recorder/SpellTuner_Recorder.toc
 M Modules/SpellTuner_Recorder/SpellTuner_Recorder_Mainline.toc
 M docs/tasks/HANDOVER.md
 M tools/adaptercheck.lua
 M tools/wowstub.lua
?? Modules/SpellTuner_Recorder/Recorder_Forever.lua
?? tools/recordcheck.lua
```

`docs/tasks/HANDOVER.md` was already modified before this task started (the
lead's, per the launch instructions) and was not touched. No `git add`,
`stash`, `checkout -- <path>`, `reset` or commit was run.

### Skipped / out of scope (as the task says)

`ScenarioFromRecording` v3 (T13d), the gates (T14), Review/replay window
(T16), Forever runs, raids beyond `player`, `Engine/FightRecorder.lua` and
every TBC file, `CLAUDE.md` and every `docs/` file except this Report.

## Lead review 1 (2026-09-28) -- re-issued

Not accepted yet. The suites are green and most of the recorder is right; three lines fail. The
tree keeps the first implementer's work -- **fix these on top of it, change nothing else**.

1. **"_STOP / _FAILED / _INTERRUPTED after a _START with no _SUCCEEDED for that castGUID ->
   CANCEL"** is implemented as "a STOP that arrives while the cast is still pending is a cancel".
   On the client `UNIT_SPELLCAST_STOP` fires at the end of **every** cast-time spell, successful
   ones included, and whether it arrives before or after `_SUCCEEDED` is **UNKNOWN** (the probe
   reports list the event as present, `docs/probe/1.60.1_70009.md` 78, and never its order). If
   STOP comes first, every Healing Touch is recorded as a cancel. The fixture hides this: its
   successful casts never fire STOP at all. Required, order-independent:
   - `_STOP` / `_FAILED` / `_INTERRUPTED` for a pending castGUID only **mark** it ended
     (`endT = t`); `_SUCCEEDED` for that castGUID clears it whether it was marked or not.
   - A marked pending cast is turned into `CANCEL` when it is still pending at the **next tick**
     (`MD:OnTick`) or at `PLAYER_REGEN_ENABLED`, whichever is first: pushed at that moment's `t` (so
     the event arrays stay in time order, as TBC's recorder also pushes its CANCEL at the next own
     event), `amt = endT - startT` (the time the cast occupied), `x` the spell id. Say this in a
     comment that names the unknown order.
   - Fixture: every successful cast in the scripted pull also fires `UNIT_SPELLCAST_STOP` -- at
     least one with STOP **before** SUCCEEDED and one with STOP **after** it, in the same frame --
     and assertion 4 additionally requires **exactly one** CANCEL in the stream (the unfinished
     cast), with `amt >= 0`. Same name, same count (14).
2. **Rules: "ASCII-only printed lines (names escaped)".** `/st rec` prints `r.zone` raw. Escape it
   the way the other Forever files do (a local `Esc` like `Spells/Measure.lua` 57: non-ASCII bytes
   and `|` made safe); assertion 13 gains a zone with a `|` and a non-ASCII byte in the fixture
   (set `GetRealZoneText`'s stub answer for this item) and checks the line is ASCII with no bare
   pipe.
3. **Rules: "Never read auras in combat".** `ScanAuras` runs whenever no pull is active; a module
   switched on, or loaded at login, while the player is in combat would read in combat. Skip the
   scan while `MD.API.UnitAffectingCombat("player")` is true (already bound, `Client/API.lua` 344;
   IsSecret-check the answer, treat anything but plain `false` as in combat). Assertion 10 gains:
   with `S.inCombat = true` and no pull started, a tick reads no aura (count the stub's
   `GetAuraDataByIndex` calls or check it did not raise into `MD` errors -- say which).

Accepted as is, no change wanted: raid detection through `MD.API.UnitExists("raid1")`; the stub's
`S.meter`; "the oldest unpinned one dropped" rather than TBC's cost-based choice (the task said so).

Acceptance is unchanged otherwise: recordcheck 14, every other suite at its count, apicheck 0,
`--selftest` 10 of 10. Append a **Report (re-issue)** section below this one with the failing run
(the new fixture lines against the old code), recordcheck in full, the stream printed compactly
again, every other tail, apicheck, luac, `git status --short`.

## Report (re-issue)

Fixed the three lines on top of the tree the first implementer left, changing nothing else.

### 1. CANCEL is now order-independent

`Modules/SpellTuner_Recorder/Recorder_Forever.lua`: `pending[castGUID]` is now `{ sid, startT,
endT }` rather than `{sid, t}`. `UNIT_SPELLCAST_STOP` / `_FAILED` / `_INTERRUPTED` (the shared
`OnCastEnd`) only set `p.endT` on a still-pending, not-yet-marked entry -- they no longer push a
CANCEL or touch `sentTarget` (a STOP arriving before SUCCEEDED must leave `sentTarget` alone, or
SUCCEEDED loses the cast's own target). `UNIT_SPELLCAST_SUCCEEDED` already cleared
`pending[castGUID]` unconditionally, which is what makes an early STOP harmless. A new
`FlushCancels(s, t)` walks `pending`, and for every entry with `endT` set (marked ended, never
cleared by a SUCCEEDED) pushes `CANCEL` at `t` with `amt = endT - startT`, `x = sid`, then clears
both `pending` and `sentTarget` for that castGUID. It runs once per tick (`MD:OnTick`, right after
the mana sample) and once more at `PLAYER_REGEN_ENABLED` before `active` is cleared (`Push` takes
`s` as an explicit parameter, so it works whether or not `active` is still set). A comment above
`OnCastEnd` names the unknown order and cites the probe report line the task's Facts section gives.

`tools/recordcheck.lua`: `Cast(castGUID, spellID, targetName, stopFirst)` now fires
`UNIT_SPELLCAST_STOP` for every successful cast too -- before `SUCCEEDED` when `stopFirst` is
true, after when false. Three of the six own casts use each order. `CancelCast` is unchanged
(START then STOP, no SUCCEEDED ever). Assertion 4 gained `cancel.amt >= 0`. Same 14 names, same
count.

### 2. `/st rec` escapes the zone

`Recorder_Forever.lua` gained a local `Esc` (byte-for-byte the same rule as
`Spells/Measure.lua`'s: backslash doubled, `|` doubled, everything outside `[ -~]` to `\ddd`),
duplicated for the same reason that file gives (no public `Esc` is exposed). The `/st rec` line
now prints `Esc(r.zone or "-")` instead of `r.zone or "-"`.

`tools/wowstub.lua`'s `GetRealZoneText` now answers `S.zoneText or "Blood Furnace"`. Swapping the
global function itself does not work for this test: `MD.API.Has` caches the resolved *function*
per dotted name forever, and the first pull in `recordcheck.lua` already resolves
`GetRealZoneText` before the zone-escaping fixture runs, so a later `GetRealZoneText = function()
... end` would never be seen through the cached binding. `S.zoneText` is read fresh on every call
through the same cached function, so it is not affected by the cache. `tools/recordcheck.lua`
adds a second kept pull (90s-115s, 5 own casts) with `S.zoneText = "Zone|Caf\195\169"` (a bare
pipe plus a UTF-8 non-ASCII byte) set only for the moment `PLAYER_REGEN_DISABLED` fires (the only
moment the recorder reads the zone) and cleared right after. Assertion 13 is otherwise unchanged
(it already stripped `||`/color codes before checking for a stray `|`, and already checked every
byte for `> 126`) and now exercises a real non-ASCII/pipe zone instead of always seeing "Blood
Furnace".

### 3. `ScanAuras` never runs in combat, pull or no pull

`Recorder_Forever.lua` gained `InCombat()`: `MD.API.UnitAffectingCombat("player")`
(`Client/API.lua:344`, already bound), `IsSecret`-checked, anything but a plain `false` treated as
in combat. The out-of-combat branch of the ticker now reads `if tickCount % 4 == 0 and not
InCombat() then ScanAuras() end`.

`tools/wowstub.lua`'s `C_UnitAuras.GetAuraDataByIndex` now increments `S.auraCalls` on every
call, before the in-combat raise check -- a suite can prove the scanner was skipped entirely
rather than relying on the pcall wrapper (`MD.API.Call`) swallowing the raise, which would make
"it did not raise into MD errors" true regardless of whether `ScanAuras` ran. Assertion 10 now
sets `S.inCombat = true` with no pull started, ticks four half-seconds (enough to guarantee
landing on the scanner's own `%4` boundary regardless of phase), and checks `S.auraCalls` did not
move.

### Tests first: the new fixture lines and assertion clauses against the OLD code

Restored the pre-review recorder file (kept a copy aside, no `git` command used -- a plain file
copy) and ran the already-updated `tools/recordcheck.lua` + `tools/wowstub.lua` against it:

```
|cff9966ffSpellTuner:|r Recorder: loaded
the recorder registers nothing until its module is on                                      ok - before=0 after=1
|cff9966ffSpellTuner:|r Recorder: loaded
a pull starts at combat and ends after it, and the damage meter is read once combat is over ok - rec=table: 0x... dur=40 meter.read=current
damage and heals are kept per tracked token, once each; other tokens are ignored           ok - dmg=3 heal=1
own casts carry their spell, cost and the target named when they were sent; an unfinished cast is a cancel FAIL - caststart=7 owncast=6 cancel=4 cast1.amt=nil castR2.amt=nil cancel.amt=0
the party keeps its indices across a roster change mid-pull                                ok - tgt=3
a party member's max health is recorded unknown, the player's as read                      ok - p1=375,false p2=-1,true p3=-1,true
mana is the clock's modelled pool every two seconds, marked modelled                       ok - manaModelled=true samples=20
a death is recorded once, from UnitIsDeadOrGhost                                           ok - deaths=1 died=1
a secret argument is counted and never stored                                              ok - unreadable=1 dmg=3
own HoTs on the party are read before the pull, never in combat                            FAIL - auras=1 auraCalls before=18 after=21
a short pull is dropped, a kept one enters a ring of eight                                 ok - before=1 after=1
the stream holds only numbers, strings, booleans and tables of them, nothing secret        ok
the list command prints one ASCII line per recording                                       FAIL - lines=2 list=2 ascii=false
the recorder answers the list, get, pin and address calls the replay window and Review use ok

11 ok, 3 failed
  FAIL own casts carry their spell, cost and the target named when they were sent; an unfinished cast is a cancel - caststart=7 owncast=6 cancel=4 cast1.amt=nil castR2.amt=nil cancel.amt=0
  FAIL own HoTs on the party are read before the pull, never in combat - auras=1 auraCalls before=18 after=21
  FAIL the list command prints one ASCII line per recording - lines=2 list=2 ascii=false
```

Exactly the three lines the review named failed (4 stray cancels from every STOP being treated as
one, the aura scan running while `S.inCombat = true`, the raw zone breaking assertion 13's ASCII
check), nothing else moved. Restored the fixed recorder file afterward (a straight copy back, byte
identical to what is committed to the working tree now -- confirmed with `diff`).

### recordcheck.lua, final run (full)

```
|cff9966ffSpellTuner:|r Recorder: loaded
the recorder registers nothing until its module is on                                      ok - before=0 after=1
|cff9966ffSpellTuner:|r Recorder: loaded
a pull starts at combat and ends after it, and the damage meter is read once combat is over ok - rec=table: 0x... dur=40 meter.read=current
damage and heals are kept per tracked token, once each; other tokens are ignored           ok - dmg=3 heal=1
own casts carry their spell, cost and the target named when they were sent; an unfinished cast is a cancel ok - caststart=7 owncast=6 cancel=1 cast1.amt=25 castR2.amt=40 cancel.amt=0
the party keeps its indices across a roster change mid-pull                                ok - tgt=3
a party member's max health is recorded unknown, the player's as read                      ok - p1=375,false p2=-1,true p3=-1,true
mana is the clock's modelled pool every two seconds, marked modelled                       ok - manaModelled=true samples=20
a death is recorded once, from UnitIsDeadOrGhost                                           ok - deaths=1 died=1
a secret argument is counted and never stored                                              ok - unreadable=1 dmg=3
own HoTs on the party are read before the pull, never in combat                            ok - auras=1 auraCalls before=18 after=18
a short pull is dropped, a kept one enters a ring of eight                                 ok - before=1 after=1
the stream holds only numbers, strings, booleans and tables of them, nothing secret        ok
the list command prints one ASCII line per recording                                       ok - lines=2 list=2 ascii=true
the recorder answers the list, get, pin and address calls the replay window and Review use ok

14 ok, 0 failed
```

(`lines=2 list=2` because assertion 13 now runs after the zone-escaping pull has added a second
kept recording; assertion 13 does not care about content, only that the printed line count
matches the list and every line is ASCII with no bare pipe.)

### The recorded fixture stream, printed compactly (unchanged fixture, current code)

```
== stream header ==
v=3 client=forever id=1757000000 zone=Blood Furnace t0=8 dur=40 pool=7009 manaModelled=true raid=false unreadable=1 truncated=false n=19
== roster ==
  1: name=Healroot guid=Player-1 class=DRUID role=HEALER level=64 maxHP=375 maxSecret=false
  2: name=Tank guid=Party-1-guid class=WARRIOR role=TANK level=64 maxHP=-1 maxSecret=true
  3: name=Mage guid=Party-2-guid class=MAGE role=DAMAGER level=64 maxHP=-1 maxSecret=true
== tracked == 1,2,3
== events (t kind tgt amt x) ==
    0.00   1   2    500      0
    0.00   1   3    300      0
    0.00  15   1    200      0
    0.00   6   2      0    774
    0.00   3   2     25    774
    0.00   6   3      0    774
    0.00   3   3     25    774
    0.00   6   2      0   5185
    0.00   3   2     25   5185
    0.00   6   1      0   5185
    0.00   3   1     25   5185
    0.00   6   2      0   1058
    0.00   3   2     40   1058
    0.00   6   3      0   5185
    0.00   3   3     25   5185
    0.00   6   2      0   5185
    0.50   7  -1      0   5185
   20.00   1   3    111      0
   30.00   9   2      0      0
== names ==
  5185 = Healing Touch Rank 1
  774 = Rejuvenation Rank 1
  1058 = Rejuvenation Rank 2
== initial ==
  mana=7009 form=caster
  known.HealingTouch=5185
  known.Rejuvenation=1058
  aura 1: token=party1 spellId=774 remaining=900 stacks=1
== deaths ==
  t=30 tgt=2
== restriction ==
  t=0 a=0 b=1
== mana samples (first 6) ==
  t=2 v=6900.66 base=69.24 cast=28.33
  t=4 v=6957.32 base=69.24 cast=28.33
  t=6 v=7009 base=69.24 cast=28.33
  t=8 v=7009 base=69.24 cast=28.33
  t=10 v=7009 base=69.24 cast=28.33
  t=12 v=7009 base=69.24 cast=28.33
== meter ==
  own=400 others=120 read=current
  bySource 1: name=Healroot amount=400 isLocal=true
  bySource 2: name=Someone amount=120 isLocal=false
  bySpell 774=1000
```

Only visible change from the first implementer's dump: the CANCEL row now lands at `t=0.50`
(the next tick after `cg7`'s STOP marks it ended) instead of `t=0.00` -- it is a genuine cancel,
pushed when the tick confirms no SUCCEEDED ever cleared it, not the moment STOP itself fired.

### Every other suite (unchanged counts)

```
simcheck      -> PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow     8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
probecheck    73 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   14 ok, 0 failed
kitcheck      7 ok, 0 failed
recordcheck   14 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc 15 ok, 0 failed
corecheck/forever 10 ok, 0 failed
corecheck/tbc 8 ok, 0 failed
svcheck/forever 6 ok, 0 failed
svcheck/tbc   1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc 1 ok, 0 failed
```

Every count matches the baseline given in the re-issue exactly (the TBC sixteen are inside the
`reccheck`..`measurecheck` and `corecheck/tbc`/`svcheck/tbc`/`consolecheck/tbc` lines above; this
task touched no TBC file).

### apicheck

```
apicheck: 8 Forever TOCs, 27 files, 41 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok   (refcheck.py --selftest)
```

Rule 8 (an event argument checked with `IsSecret` before comparison/arithmetic/index/`type() ==
"number"`) stayed at 0 findings; the new `FlushCancels`/`InCombat`/`Esc` code adds no new client
call site of its own (`InCombat` calls the already-bound `MD.API.UnitAffectingCombat`, `Esc` never
touches the client).

### luac -p

```
Modules/SpellTuner_Recorder/Recorder_Forever.lua  OK
Client/API_Forever.lua                            OK
tools/wowstub.lua                                 OK
tools/adaptercheck.lua                             OK
tools/recordcheck.lua                              OK
```

(Same `tools/.lua/lua-5.1.5/src/luac` the first implementer used; `luac` is not on `PATH`.)
`Client/API_Forever.lua` and `tools/adaptercheck.lua` are unchanged by this re-issue (no line in
the review named them) but are re-checked because the task names "every Lua file touched" and
they were touched by the original implementation this re-issue builds on.

### git status --short

```
 M Client/API_Forever.lua
 M Modules/SpellTuner_Recorder/SpellTuner_Recorder.toc
 M Modules/SpellTuner_Recorder/SpellTuner_Recorder_Mainline.toc
 M docs/tasks/HANDOVER.md
 M docs/tasks/T13-recorder-v3.md
 M tools/adaptercheck.lua
 M tools/wowstub.lua
?? Modules/SpellTuner_Recorder/Recorder_Forever.lua
?? tools/recordcheck.lua
```

`docs/tasks/HANDOVER.md` is the lead's and was not touched (it already showed modified before
this re-issue started). `docs/tasks/T13-recorder-v3.md` shows modified only because this Report
(re-issue) section was appended to it, as asked. No `git add`, `stash`, `checkout -- <path>`,
`reset` or commit was run.

### Accepted as is, not touched

Raid detection through `MD.API.UnitExists("raid1")`; the stub's `S.meter` shape; "the oldest
unpinned one dropped" ring-eviction policy -- none of these were named by the review, and none
were changed.

### Judgment calls / notes

- The review's item 2 ("assertion 13 gains a zone with a `|` and a non-ASCII byte in the fixture
  (set `GetRealZoneText`'s stub answer for this item)") reads as if swapping the global function
  per-test would work; it does not, because `MD.API.Has` caches the resolved function forever and
  the main fixture pull already resolved it earlier in the same suite run. Read "set
  `GetRealZoneText`'s stub answer" as license to change what the stub's existing, single
  `GetRealZoneText` function reads (`S.zoneText`) rather than swapping the global itself, which is
  the only way to make the fixture's override actually reach the recorder. Flagging this reading
  in case a different mechanism was intended.
- Rule 8 fixture-review interplay: `FlushCancels` reads `p.endT`/`p.startT`/`p.sid`, all filled in
  by earlier `IsSecret`-gated handlers (`START`'s `sid`, `OnCastEnd`'s `GetTime()`-derived
  `endT`), never a raw client value read again at flush time, so no new `IsSecret` call was
  needed there.

## Lead review 2 (2026-09-28)

Accepted. The three lines of review 1 are fixed and each is held by a clause that failed first
(pasted above). The lead reran every suite (recordcheck 14, kitcheck 7, everything else at its
baseline; apicheck 0 findings over 27 files, `--selftest` 10 of 10, refcheck ok) and `luac -p`.
The stub's `S.zoneText` rather than swapping the global is right (`MD.API.Has` caches). Left for the
game: whether STOP and SUCCEEDED can straddle a tick (a successful cast recorded as a cancel) -- the
next in-game round checks that a recorded pull's CANCEL count matches the casts actually cancelled.
