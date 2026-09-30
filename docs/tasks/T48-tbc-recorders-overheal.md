# T48 (P4) -- TBC recorders and overheal: what ends a hard cast, the bloom, two runs back to back, raid Tranquility

Status: **built** 2026-09-30 on branch `plan/P4` (base 06f0969), awaiting review.

## The task (docs/PLAN-refactor-ux.md section 5, P4)

Review items (docs/review/2026-09-30-project-review.md): **B9, B10, B11 (the RunRecorder half), B12,
B13**. All on the TBC line.

- (a) B9: a pending cast is opened by an own `SPELL_CAST_START` and remembers the `castGUID` of the
  player's `UNIT_SPELLCAST_START` with the same spell id. It is closed as a success by its matching
  `SPELL_CAST_SUCCESS`; as a CANCEL by `UNIT_SPELLCAST_INTERRUPTED` carrying that `castGUID` (by
  spell id when the GUID was not readable); as a CANCEL of the old cast by any own
  `SPELL_CAST_START` while one is pending. Nothing else closes it -- not a HoT tick, an aura, an
  energize, and not `SPELL_CAST_FAILED` / `UNIT_SPELLCAST_FAILED` (a spam press). The unit events
  through `MD:On`.
- (b) B10: `UI/Summary.lua` uses the resolved id only when the raw id is not a row and the resolved
  row is Lifebloom (33778 -> 33763, kind `bloom`), for both `Overheal:Record` and
  `Calibration:Observe`. Every other id unchanged, Tranquility's 44208 / 44207 included.
- (c) B11: `||` in the run usage line.
- (d) B12: `RR:Start` resets `potionCount` and `pullStart`; `PullSkipped` clears `pullStart`.
- (e) B13: `Targets` records each raid member's subgroup from `GetRaidRosterInfo`; Tranquility's
  waste divides by the caster's party.

Owned files (section 4, wave 2): `Engine/FightRecorder.lua`, `UI/Summary.lua`,
`Engine/RunRecorder.lua`, `Engine/Overheal.lua`, `Engine/Targets.lua`, `tools/fakepull.lua`,
`tools/reccheck.lua`, `tools/runcheck.lua`. Nothing else was edited (this task file apart).

The author's standing answer (plan section 8, question 3): **old recordings are left as they are.**
A CANCEL written by the old rule (a cast under a rolling HoT, a spam-pressed cast) stays in every
stream recorded before this build, and the replay does **not** hide a CANCEL followed by the same
spell's success. Nothing here rewrites or filters stored data.

## What was built

| file | change |
|---|---|
| `Engine/FightRecorder.lua` | **B9.** The "any other own event cancels the pending cast" block at the top of `FR:Event` is gone. `CancelPending(s, t)` pushes `K.CANCEL` (amt = seconds the cast ran, x = the spell) and clears `FR.pending`. The own `SPELL_CAST_SUCCESS` branch closes the pending cast when `p1` is its spell (another success, an off-GCD instant, leaves it open). The own `SPELL_CAST_START` branch first cancels any pending cast (the same spell included), then pushes `CASTSTART` and opens `FR.pending = { spell, t }`, adopting the `castGUID` of a `UNIT_SPELLCAST_START` that came first (`FR.unitStart`, same spell, within `UNIT_START_TTL` = 0.5 s). New `FR:UnitCast(event, unit, castGUID, spellID)`, registered through `MD:On` for `UNIT_SPELLCAST_START` (attaches the GUID to a pending cast of that spell that has none, else stashes it for the combat log's start) and `UNIT_SPELLCAST_INTERRUPTED` (cancels the pending cast when the GUIDs match, or, when either GUID is missing, when the spell ids match). `UNIT_SPELLCAST_FAILED` is not registered; no failure reason text is read. `FR:Start` clears `FR.unitStart`. |
| `UI/Summary.lua` | **B10.** The heal handler computes `attrID` and `kind`: periodic -> `tick`; a row whose family is Lifebloom -> `bloom` (as before); a raw id that is not a row but resolves (`SD:Resolve`) to a Lifebloom row -> `attrID` = the resolved id, `bloom`. `Overheal:Record` and `Calibration:Observe` receive `attrID`. The HoT tick credit, the fight totals and the debug line still use the raw id. |
| `Engine/RunRecorder.lua` | **B12:** `RR:Start` sets `RR.potionCount = {}` and `RR.pullStart = nil`; `RR:PullSkipped` clears `RR.pullStart`. **B11:** `usage: /md run start [name] || stop || status`. |
| `Engine/Targets.lua` | **B13:** `RaidSubgroup(i)` (`GetRaidRosterInfo`'s third return under `pcall`, a number or nil); in a raid every member's entry carries `subgroup`, the player's own (`UnitIsUnit(unit, "player")`) set on the player's entry. New `Targets:PartySize()`: non-pet entries in the player's subgroup; everyone when the player's subgroup is unknown (a party, or a raid the client did not describe), as before; at least 1. |
| `Engine/Overheal.lua` | **B13:** `Attribute`'s channel branch divides by `MD.Targets:PartySize()` instead of every non-pet in the roster; the header comment says "the caster's party". |
| `tools/fakepull.lua` | A second pull, `ids.castPull()`, played **only when a harness calls it** (reccheck does; replaycheck, replayui, reviewui, solvercheck and restcheck keep the stream they always had). On the tank under a rolling Lifebloom: HT1 with a Lifebloom tick between its start and its success; HT2 with a spam press mid-cast (the combat log's `SPELL_CAST_FAILED` "Another action is in progress", `UNIT_SPELLCAST_FAILED` and a `UNIT_SPELLCAST_INTERRUPTED` both carrying a new `castGUID`); HT3 interrupted (`UNIT_SPELLCAST_INTERRUPTED` with its own `castGUID`); HT4 replaced by HT5's start (unit event after the combat log's this time); a fully overhealed bloom (33778) and a Tranquility heal (44208), both `SPELL_HEAL`. Returns the moments on the stream's clock and what was pending after the spam and after HT2's success. |
| `tools/reccheck.lua` | +9 (54 -> 63): the cast pull stored; no CANCEL for the ticked cast; no CANCEL for the spam-pressed cast and its success closing it (pending after the spam = Healing Touch, after the success nil); one CANCEL for the interrupted cast, at the interrupt, 1.0 s long; one CANCEL for the replaced cast, at the new start, 1.0 s long; the bloom stored as `k:33763:bloom` and no `k:33778:direct`; `Calibration:Observe(33763, "bloom", ...)` called and the `33763:bloom` bucket written; 44208 still in `s:44208` / `k:44208:direct` with calibration kind `direct` as before; a 25-member raid with the caster (raid13) in subgroup 3: a fully overhealed 44208 wastes cost / (4 x 5) = 82.50, not / (4 x 25) = 16.50. |
| `tools/runcheck.lua` | +3 (78 -> 81), a block after the v0.13.7 one (so every earlier assertion reads the run it always read): run A stops while a pull is in progress, a Super Mana Potion leaves the bags (a local `GetItemCount`), run B starts and the pull ends inside it -- no `K.POTION` in run B; its first pull's `runT0` on B's own clock (0.0 s, not A's 30.0 s); `/md run bogus` prints the usage line with no bare pipe. |

## Tests first

The tests were committed first (cb38f84) and run against the parent's engine files:

```
reccheck
B9: a HoT tick mid-cast is no CANCEL FAIL - 2.0s (1.0s of 26978), 6.0s (1.0s of 26978)
B9: a spam press is no CANCEL      FAIL - 2.0s (1.0s of 26978), 6.0s (1.0s of 26978); pending after the spam nil, after the success nil
B9: an interrupt is one CANCEL     FAIL - 2.0s (1.0s of 26978), 6.0s (1.0s of 26978)
B9: a new start cancels the pending one FAIL - 2.0s (1.0s of 26978), 6.0s (1.0s of 26978)
B10: the bloom is stored as k:33763:bloom FAIL - k:33763:bloom false, k:33778:direct true
B10: calibration gets a 33763 bloom FAIL - call nil, bucket none
B13: raid Tranquility waste / caster's party of 5 FAIL - 16.50, expected 82.50 (a raid of 25 gives 16.50)
56 ok, 7 failed                                         (exit 1)

runcheck
B12: run B does not inherit run A's potions FAIL - 1 POTION event(s) in run B
B12: run B's first pull is on B's own clock FAIL - runT0 30.0s (run A's pull began at 30.0s of A)
B11: the usage line has no bare pipe FAIL - |cff9966ffSpellTuner:|r usage: /md run start [name] | stop | status
78 ok, 3 failed                                         (exit 1)
```

Read against the old rule: the tick at 2.0 s cut HT1 and the spam's `SPELL_CAST_FAILED` at 6.0 s
cut HT2 (both false CANCELs); the interrupt produced nothing (the unit event was not listened to),
and HT4's replacement produced nothing (a start never cancelled). The two guards pass on the parent,
as they should: "the cast pull was recorded" and "Tranquility's 44208 unchanged".

After the fix (0eec181): reccheck 63 ok, runcheck 81 ok, both exit 0. The CANCELs are exactly
`10.0s (1.0s of 26978)` (the interrupt) and `12.0s (1.0s of 26978)` (the replacement).

## Suites (exit codes checked; the loop of docs/TOOLS.md section 1)

Every suite exited 0 before and after. Counts before -> after:

| suite | before | after |
|---|---|---|
| reccheck | 54 | **63** |
| runcheck | 78 | **81** |
| simcheck | 13, 0 FAIL lines | 13, 0 FAIL lines |
| replaycheck 82, replayui 98, reviewui 44, navui 35, dashui 63, regencheck 27, simwindow 8, solvercheck 84, restcheck 51, timeline 27, spelltip 48, costcheck 3, practice 81, practiceui 50, migrate 7, probecheck 87, forevercheck 16, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 15, reviewforever 11, coachforever 19, practiceforever 25, bindscheck 6, parsecheck 12, bookcheck 21, tipcheck 37, clockcheck 21, spellsui 47, measurecheck 30, releasecheck 16, importcheck 19, themecheck 23, tabscheck 24, wincheck 53 | same | same |
| adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1, consolecheck 17 / 1 (forever / tbc) | same | same |

`python3 tools/apicheck.py`: 0 findings (48 files); `--selftest` 10 of 10. `python3
tools/textcheck.py`: 0 findings; `--selftest` 2 of 2. `refcheck.py --selftest`: ok. `luac -p` on
every changed file: ok.

**Proves no other change** (`replaycheck`, `simcheck`, `regencheck`, `reviewui`, and every other
suite that plays `tools/fakepull.lua`): each suite's whole output was captured before the first edit
and compared after, with table addresses, millisecond timings and the frame-sliced search's
evaluation and frame counts masked (they vary from run to run on the same commit). Every suite's
output is identical except reccheck's and runcheck's, which only gain the new lines and the final
count. (One apparent replayui difference, two `search done` lines in the other order, went away
on a second run of the same code: two frame-sliced searches interleaving.)

## Integrator lines

**docs/DECISIONS.md** -- a new section after "The client is the TOC's, the interface is a fallback
(2026-09-30, T47)":

```
## What a CANCEL means, and the bloom's bucket (2026-09-30, T48)

The whole-project review (`docs/review/2026-09-30-project-review.md` B9, B10, B13) found three TBC
recorder and overheal bugs; T48 (`docs/tasks/T48-tbc-recorders-overheal.md`) fixes them.

1. **A CANCEL is a hard cast that ended without its success** (B9): an interrupt carrying its
   `castGUID` (`UNIT_SPELLCAST_INTERRUPTED`; by spell id when no GUID was readable), or another own
   cast start while it was pending. Its own success closes it; nothing else does -- not a HoT tick,
   an aura, an energize, and not the failure a spam press of the same button produces
   (`SPELL_CAST_FAILED` / `UNIT_SPELLCAST_FAILED`), whose reason text is localised and not read.
   **Recordings made before this build keep their spurious CANCELs**: the pending cast was dropped
   when they were written, so they cannot be repaired, and the replay does not hide a CANCEL followed
   by the same spell's success (the author's answer, plan section 8, question 3).
2. **The bloom is a Lifebloom bloom** (B10). 33778 is attributed to 33763 with kind `bloom` in the
   overheal buckets and in calibration, so the Effective Lifebloom row can use a measured bloom
   fraction, `/md calibrate` gets a bloom line, and a fully overhealed bloom wastes no mana (the ticks
   carry the cost). Old `k:33778:direct` / `s:33778` entries decay out on their own (150-event
   half-life); `s:33763` now includes the bloom (`f:Lifebloom` always did). Only the Lifebloom alias is
   resolved: Tranquility's 44208 / 44207 stay under their own ids (resolving them is a model change
   left to the author).
3. **Tranquility's waste is divided by the caster's party** (B13): in a raid, the members of the
   player's own subgroup (`GetRaidRosterInfo`); in a party, everyone, as before.
```

**docs/TOOLS.md** -- append to the rows in section 1:

- `reccheck.lua`: ` Since **T48** (63): a second scripted pull (`fakepull`'s `castPull`, reccheck only) -- no CANCEL for a Healing Touch with a HoT tick mid-cast or a spam press of the same button, one CANCEL for an interrupt carrying the cast's GUID and one for a start replacing a pending cast; the bloom as `k:33763:bloom` and a `33763:bloom` calibration bucket, 44208 unchanged; a 25-man raid's Tranquility waste over the caster's subgroup of 5`
- `runcheck.lua`: ` Since **T48** (81): two runs back to back -- no POTION in the second from the first's count, a pull that began in the first placed on the second's clock; the usage line with no bare pipe`

**CLAUDE.md** -- append to the rows:

- `Engine/FightRecorder.lua`: ` **T48 (P4, 2026-09-30):** a pending hard cast ends only on its success, an interrupt carrying its castGUID (`UNIT_SPELLCAST_INTERRUPTED` via `MD:On`, `FR:UnitCast`; by spell id without a GUID) or another own start -- never a HoT tick, an aura or a spam press's failure; older recordings keep their spurious CANCELs (B9)`
- `UI/Summary.lua`: ` **T48 (P4):** a bloom arriving as 33778 is recorded and calibrated as 33763 `bloom`; every other id unchanged (B10)`
- `Engine/RunRecorder.lua`: ` **T48 (P4):** `RR:Start` resets the potion counts and the pull start, `PullSkipped` clears the pull start (B12)`
- `Engine/Overheal.lua`: ` **T48 (P4):** Tranquility's waste per event over `Targets:PartySize()`, the caster's party (B13)`
- `Engine/Targets.lua`: ` **T48 (P4):** each raid member's `subgroup` (`GetRaidRosterInfo`), `Targets:PartySize()` (B13)`

**docs/TESTING.md** section 44 -- under **TBC.**, after item 3 (the plan's section 9 items, verbatim):

```
4. **Casts under a rolling HoT (B9).** Keep Lifebloom rolling on the tank and hard-cast Healing Touch
   three times in one pull, **pressing the Healing Touch button again two or three times during one of
   the casts**; then move to cancel one cast. `/md replay 1`: three full cast bars, one cut. Also paste
   `/run local f=CreateFrame("Frame") f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED") f:SetScript("OnEvent",function(_,e,...) print(e,...) end)`
   and then move during a cast: the line shows `player`, a cast GUID and the spell id.
6. **Bloom (B10).** After a dungeon with Lifebloom, `/md calibrate` lists a bloom line; the Waste view
   has a Lifebloom bloom row.
8. **Two runs (B12).** Stop a run, drink a potion, start a run: `/md run status` shows no potion.
```

**TOCs:** none (no new file). **tools/data/expected-counts.json:** it does not exist at this base;
when P13 creates it: reccheck 63, runcheck 81.

## Deviations

- **The new events are a second pull, not the existing one.** The plan says `fakepull.lua` gains
  them "inside one pull"; they are all inside one pull, but a second one (`ids.castPull()`) that only
  reccheck plays. Five other suites (replaycheck, replayui, reviewui, solvercheck, restcheck) play
  the first pull and assert on its stream, and this task owns none of them; putting the events into
  the first pull would have changed their inputs. Their outputs are identical before and after.
- **reccheck gains 9, not 8.** The ninth, "the cast pull was recorded", is a guard so the eight
  plan-named assertions cannot pass on a stream that was never stored.
- **The spam press also fires a `UNIT_SPELLCAST_INTERRUPTED` with the new GUID**, beside the plan's
  two failure events. Which unit events a spam press raises on the TBC client is not verified; the
  fixture covers the worse case, and the GUID check is what keeps it from cancelling the real cast.
  (If the client ever sent an INTERRUPTED with no GUID for a spam press of the same spell, the
  spell-id fallback would cancel it -- the rule the plan specifies; section 9 check 4 shows the
  shape.)
- **A `UNIT_SPELLCAST_START` that arrives before the combat log's `SPELL_CAST_START`** is held for
  0.5 s and adopted by the start of the same spell; the fixture covers both orders (HT1-HT3 unit
  event first, HT4-HT5 after).
- **`PullSkipped` clearing `pullStart` has no assertion of its own** (the plan's runcheck +3 does
  not name one); the back-to-back case exercises the `RR:Start` reset, which is the same field.
- A pending cast still open when the fight ends is not recorded, as before (the plan does not
  change it).
- Seen while testing, not changed: a pull already in progress when a run starts joins the run with
  its whole length, so a run shorter than that pull reports a combat share above 100% (run B's line
  in runcheck says `combat 143%`). Pre-existing and outside B9-B13.
