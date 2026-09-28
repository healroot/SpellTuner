# T13 — the Forever recorder: stream v3 from UNIT_COMBAT, own casts and the damage meter

Status: **open**, after T13a (the static secret check) and T13c (module plumbing). M3
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

(implementer)
