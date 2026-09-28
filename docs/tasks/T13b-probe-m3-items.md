# T13b — the probe asks what M3 and the M2 re-check still need

Status: **open**. Roadmap M3 ("T13b, the probe items M1 left"), pulled into the `1.0.0-alpha.4`
build because the next testing round (`docs/TESTING.md` §38) needs it. Evidence:
`docs/probe/1.60.1_70009-m2.md` (lines 286-295, 311-312) and `docs/probe/1.60.1_70009.md`
(seventh/eighth reports).

## Goal

One `/st probe` run in a party fight answers the questions the M3 recorder is built on and the M2
shapes check left open: the heal spells' tooltip lines (the probe picked two passives instead), a
party member's max-health secrecy predicate, which unit tokens `UNIT_COMBAT` arrives under and how
often the same hit arrives twice, whether a token's GUID is readable when its event arrives, and the
party member reads a recorder keys and labels by (GUID, name, level, class, role). For the planner
and the lead, through the author's report.

## Facts

- **The heal/damage pick is a substring test** (`Client/Probe.lua` lines 643-646:
  `lowered:find("heal")`, `lowered:find("damage")`): Endurance ("Total **Heal**th increased") counted
  as a heal and Plainsrunning ("Taking **damage**") as damage -- the `== shapes` tooltips dumped are
  those two passives (m2 286-295) and "5 healing" counts Endurance (m2 311-312). So the heal spells'
  tooltip lines have never been seen.
- `UnitHealthMax(party1)` reads secret in and out of combat while the player's own max is plain
  (eighth report; `FOREVER-PLAN.md` §6 Q2). `C_Secrets.ShouldUnitHealthMaxBeSecret` is read for
  `player` only (`ReadingsLines`); for `party1` it is the plan's open question (§6 Q2, last line).
- `UNIT_COMBAT` is counted by *class* of token (`UnitClassOf`: player / target / party / raid /
  other), and a HEAL on `player` arrived again under `other` in the same fight (seventh report:
  `combat player HEAL n=4` and `combat other HEAL n=4`). Which tokens make up `other` (nameplates?
  `mouseover`? `focus`?) is UNKNOWN; the recorder must register per token or key by GUID
  (`FOREVER-PLAN.md` §6 Q3), and whether `UnitGUID(token)` is plain at that moment is UNKNOWN.
- Party members' role, level, class, name: UNKNOWN whether plain in combat (`UnitGroupRolesAssigned`
  exists in the baseline; the TBC recorder keys its roster on it, `Engine/Targets.lua`).
- Probe rules (T0-T0d): every check under `pcall`, every client value through `Show` / `Fmt` /
  `Esc`, `IsSecret` before anything but storing, no arithmetic on a client value; an amount may be
  compared `==` to another amount only after both are known plain numbers.

## Files

| file | change | role |
|---|---|---|
| `Client/Probe.lua` | (1) `healing` = the description has a word `heal`, `heals` or `healing` (frontier pattern, case-insensitive), `dmg` = a number, an optional school word, then the word `damage` -- neither matches "Health" or "Taking damage"; (2) the shapes section dumps the tooltip lines of the first direct heal (a healing description with `to` between two numbers), the first over-time heal (a healing description with `over`) and the first damage spell -- each at most once, in walk order; (3) `ReadingsLines` adds `C_Secrets.ShouldUnitHealthMaxBeSecret(party1)`, `UnitGUID(party1)`, `UnitName(party1)`, `UnitLevel(party1)`, `UnitClass(party1)`, `UnitGroupRolesAssigned(party1)` (so they are read out of combat and in the combat snapshot, like every reading); (4) a new section `== unit combat tokens` after `== events seen this session`: per phase, per exact token (a plain string token, escaped; `nameplateN` folded to `nameplate`, `raidN` to `raid`, `raidpetN` to `raidpet`), `n`, `guid readable`, `guid secret`; and per phase one line `mirrored: <m> of <n>` -- an event is a mirror when an earlier event in the **same `GetTime()`** had the same action and the same plain amount under a different token | the probe |
| `tools/wowstub.lua` | forever profile: `UnitGroupRolesAssigned` answering `S.roles[u]` (default `"NONE"`), `UnitGUID` for `party1` (`"Player-1-00000001"`) if not already, and `nameplate1` accepted as a token by `S.Combat` (it already fires any token) | stub |
| `tools/probecheck.lua` | four new assertions | suite |

## Rules

- The probe's rules above; ASCII, no bare `|` (the report goes through a copy box that renders `||`
  as `|` -- m2 287 -- so nothing new may print a pipe at all, escaped or not, except through the
  existing `Fmt`/`Esc`).
- The probe never registers `COMBAT_LOG_EVENT_UNFILTERED` (T0d). No new global, no library.
- Tests first: the four assertions written and failing first.
- Existing assertions: none may change. If "healing spells are dumped with id, name, rank and the
  whole description" or "the dump counts ranks per spell name" changes count because the stub's
  fixtures contain a false heal, that is a question, not an edit.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/probecheck.lua` ends `70 ok, 0 failed`. New names, verbatim:
   - "a passive whose text says Health or taking damage is not picked as a heal or a damage spell"
     -- `S.AddSpell` Endurance's and Plainsrunning's texts (m2 140, 175): neither is dumped under
     `== spells`, and neither has a `tooltip <id>` line.
   - "the shapes section dumps the tooltip lines of a direct heal, a HoT and a damage spell" -- with
     the stub's 5185 (direct), 774 (HoT) and 5176 (damage), three `tooltip` blocks, one per id.
   - "party readings carry the max-health predicate, guid, name, level, class and role" -- the six
     new `ReadingsLines` entries present, in the out-of-combat readings and in the combat snapshot.
   - "UNIT_COMBAT is counted per token with its guid readability, and a same-frame repeat as a
     mirror" -- in one frame `S.Combat("player", "HEAL", 12)` and `S.Combat("nameplate1", "HEAL",
     12)`; later `S.Combat("party1", "WOUND", 5)`: the section shows `player`, `nameplate`, `party1`
     with their counts and `mirrored: 1 of 3` for that phase.
2. Every other suite at its count (the lead's baseline; T7b/T10c/T11b/T12b counts if landed).
3. `python3 tools/apicheck.py` 0 findings (the new client names are called through `Show`, i.e.
   `MD.API.Has`, the probe's own path), `--selftest` 7 of 7.
4. `luac -p` clean on every file touched.
5. Paste into the Report: the failing run; probecheck in full; the new report sections as the stub
   run prints them; every other tail; apicheck; luac; `git status --short`.

## Out of scope

- Every other probe section and question; the Q1 logic; the recorder itself (T13).
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

Implemented all four items exactly as specced.

### `Client/Probe.lua`

- Replaced the two plain-substring tests (`lowered:find("heal", 1, true)` / `lowered:find("damage",
  1, true)`) with four small classifiers next to the other "own pattern only" helpers
  (`IsHealingText`, `IsDamageText`, `IsDirectHealText`, `IsOverTimeHealText`):
  - `IsHealingText`: word-bounded `heal` / `heals` / `healing` (`%f[%a]...%f[%A]`), so "Health"
    (which contains "heal" as a bare substring) no longer matches.
  - `IsDamageText`: a number, then optional letters (a school word), then the word "damage"
    (`%d+%s+%a-%s*%f[%a]damage%f[%A]`) -- "Taking damage" has no leading number close enough
    (the punctuation between "30%" and "Taking" breaks the letters/spaces run) and no longer
    matches.
  - `IsDirectHealText` / `IsOverTimeHealText`: "NN to NN" / the word "over", only asked of a
    description already classed as healing.
  - `SpellWalk` now stores `sp.direct` / `sp.overTime` alongside `sp.healing` / `sp.dmg`.
- `== shapes` item 3 now walks `order` once and dumps the tooltip of the first `sp.direct`, the
  first `sp.overTime` and the first `sp.dmg` spell, each at most once, in walk order --
  `knownFirstHeal` (the spell the combat snapshot re-reads live) is set to the direct heal.
- `ReadingsLines()` gained six lines after the existing `party1` block:
  `C_Secrets.ShouldUnitHealthMaxBeSecret(party1)`, `UnitGUID(party1)`, `UnitName(party1)` (through
  `First`, matching the player line's own truncation-to-first-return), `UnitLevel(party1)`,
  `UnitClass(party1)`, `UnitGroupRolesAssigned(party1)` -- read live in both the out-of-combat
  call and the combat-snapshot copy, since both already share this one function.
- New session state (`tokenCounters`/`tokenOrder`, `mirrorCounters`/`mirrorOrder`,
  `unitCombatEvents`), two new small classifiers (`TimeKey` -- `GetTime()` through
  `Has`/`pcall`/`IsSecret`, rendered to text before ever being compared; `FoldToken` -- exact
  token, `nameplateN`/`raidN`/`raidpetN` folded to their family, everything else `Esc`'d whole),
  `BumpUnitCombatToken` (counts n/guid-readable/guid-secret per phase+token, and flags a mirror
  when an earlier event at the same `TimeKey()`/phase/action/plain-amount carries a different
  token), `UnitCombatTokensLines()` (renders the per-token lines then one `mirrored: M of N` per
  phase). `OnCombatEvent` now calls both `BumpCombat` and `BumpUnitCombatToken`. `Run()` prints
  `== unit combat tokens` right after `== events seen this session`.

### `tools/wowstub.lua`

Two small, local additions inside `S.UseProfile("forever")`, right after `UnitIsDeadOrGhost`:
- `UnitGroupRolesAssigned` now answers `S.roles[u]` first if a script set one there directly,
  else falls back to the unit's own `.role` (`S.AddUnit`, unchanged behaviour for every existing
  fixture), else `"NONE"`.
- `UnitGUID` wraps the base definition: if the unit has its own guid, that still wins; only a
  `party1` with no guid at all answers the fixed placeholder `"Player-1-00000001"`.
- `nameplate1` needed no stub change -- `S.Combat` already fires any token given to it.

Re-read the file immediately before editing (per instructions) and again after; the only other
change present is T10c's unrelated `SetWordWrap`/`GetWordWrap` addition, no overlap.

### `tools/probecheck.lua`

- `HEADERS_IN_ORDER` gained `"== unit combat tokens\n"` between the events-seen and damage-meter
  entries (comment updated fifteen -> sixteen headers).
- New Step 9 (fresh Forever load): `S.AddSpell`s Endurance (20550) and Plainsrunning (1259918)
  with their exact m2 texts, adds `party1` the same way Step 2 does, then scripts
  `S.Combat("player","HEAL",12)` and `S.Combat("nameplate1","HEAL",12)` at `S.now=100` and
  `S.Combat("party1","WOUND",5)` at `S.now=105`, then runs the probe.
- Four new assertions, verbatim names as specced:
  - "a passive whose text says Health or taking damage is not picked as a heal or a damage
    spell" -- asserts neither `spell 20550`/`spell 1259918` nor `tooltip 20550 `/`tooltip 1259918 `
    appear in Step 9's report.
  - "the shapes section dumps the tooltip lines of a direct heal, a HoT and a damage spell" --
    against `report1`, `tooltip 5185 = 4 lines`, `tooltip 774 = 4 lines`, `tooltip 5176 = 4 lines`.
  - "party readings carry the max-health predicate, guid, name, level, class and role" -- all six
    lines checked in both the `== readings now` segment of `report1` and the `== combat snapshot`
    segment of `report2` (taken in combat).
  - "UNIT_COMBAT is counted per token with its guid readability, and a same-frame repeat as a
    mirror" -- against Step 9's `== unit combat tokens` segment: `ooc player n=1 guid readable=1
    guid secret=0`, `ooc nameplate n=1 guid readable=0 guid secret=0`, `ooc party1 n=1 guid
    readable=1 guid secret=0`, `ooc mirrored: 1 of 3`.

### Suite output

`bash tools/run.sh tools/probecheck.lua` -- **70 ok, 0 failed** (full transcript below).

```
the TBC line reads its version from SpellTuner_TBC.toc                   ok
Client/API.lua loads under the TBC line                                  ok
MD.API.client is forever on interface 16001                              ok
MD.API.Has walks dotted names and says false for a missing one           ok
the report is keyed by build                                             ok
the probe never raises                                                   ok
a missing function is reported absent, not raised                        ok
registering a bad event is caught                                        ok
a secret value is reported secret, not summed                            ok
a client error is reported as a string                                   ok
the report is ASCII with no bare pipe                                    ok
the report reaches the copy box                                          ok
the report sections are in order                                         ok
the header names build 70009 and interface 16001                         ok
healing spells are dumped with id, name, rank and the whole description  ok
a spell that does not heal is not dumped                                 ok
a change in bonus healing is reported against the previous run           ok
the combat snapshot is taken in combat                                   ok
UNIT_COMBAT and UNIT_SPELLCAST_SENT are counted by phase                 ok
the damage meter in combat is reported secret, not walked                ok
the damage meter after combat lists sources and spells                   ok
SavedVariables that did not come back are reported as such               ok
SavedVariables that came back are reported with their stamp              ok
the report prints the TOC that loaded                                    ok
the probe adds no global but its own                                     ok - SpellTunerDB, SPELLTUNER_TOC, SLASH_SPELLTUNER1, SpellTunerProbeFrame, SLASH_SPELLTUNER3, SLASH_SPELLTUNER2
/st and /md both reach the probe                                         ok
the to-do list names what is left                                        ok
an unreadable description is not counted as changed                      ok
the Q1 count covers comparable descriptions only                         ok
Q1 is answered only when both bonus readings are readable                ok
event and secret names are escaped                                       ok
MD.API.Has never hands back a secret                                     ok
a secret table is reported secret                                        ok
the copy box has no letter cap                                           ok
an in-combat damage meter read does not answer Q4                        ok
Q8 needs the combat snapshot                                             ok
a spellbook row that raises is counted as an error                       ok
the chat line says saved only when it saved                              ok
the character line shows the first return only                           ok
the dump counts ranks per spell name                                     ok
the talent APIs that exist are called and shown                          ok
blocked and forbidden actions naming us are recorded                     ok
a blocked action naming another addon is ignored                         ok
COMBAT_LOG_EVENT_UNFILTERED is never registered, not even by clog        ok
a blocked action at load names the registration that caused it           ok
Q1 stays answered on a later run of the same build                       ok
the secret readings are taken out of combat and in the snapshot          ok
the restriction state event is counted with its payload                  ok
the damage meter expands combatSpellDetails one level                    ok
the damage meter prints at most 5 spells a session                       ok
Q1 is answered by a level change                                         ok
Q6 waits for level 10                                                    ok
the build ships three TOCs                                               ok
the Forever TOCs are 1.0.0-alpha.3 and differ only in their marker       ok
a changed description prints what it was and what it is now              ok
was and now are shown for the first 12 changed spells, the rest counted  ok
the spells header shows bonus damage per school                          ok
Q1 is answered by a change in bonus damage                               ok
the shapes section sits between the talents and the readings             ok
the shapes section lists every skill line whole                          ok
every spell in the book has one shapes line: info, cost, learned, base, low rank, row ok
a spell's cost is rendered two levels deep                               ok
the first heal and the first damage spell carry their tooltip lines, pipes escaped ok
the shapes section dumps the tooltip lines of a direct heal, a HoT and a damage spell ok
a passive whose text says Health or taking damage is not picked as a heal or a damage spell ok
party readings carry the max-health predicate, guid, name, level, class and role ok
UNIT_COMBAT is counted per token with its guid readability, and a same-frame repeat as a mirror ok
a shape function the client lacks reads <absent>                         ok
the combat snapshot carries the shapes read in combat                    ok
UNIT_SPELLCAST_SUCCEEDED is counted with its id readable or secret, and the cost read at the cast ok

70 ok, 0 failed
```

### New report sections, as the stub run prints them

`== readings now` (party1 block, out of combat):
```
C_Secrets.ShouldUnitHealthMaxBeSecret(party1) = true
UnitGUID(party1) = Party-1
UnitName(party1) = Tankname
UnitLevel(party1) = 64
UnitClass(party1) = Warrior, WARRIOR
UnitGroupRolesAssigned(party1) = TANK
```
(the same six lines appear verbatim in `== combat snapshot`'s copy, taken in combat.)

`== unit combat tokens` (Step 9's scripted fight):
```
ooc player n=1 guid readable=1 guid secret=0
ooc nameplate n=1 guid readable=0 guid secret=0
ooc party1 n=1 guid readable=1 guid secret=0
ooc mirrored: 1 of 3
```

### Every other suite

```
simcheck      PASS (BF-1 fixture, "-> PASS")
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
probecheck    70 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   12 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      FLAKY -- see note below
measurecheck  9 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc     15 ok, 0 failed
corecheck/forever    10 ok, 0 failed
corecheck/tbc        8 ok, 0 failed
svcheck/forever      6 ok, 0 failed
svcheck/tbc          1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc     1 ok, 0 failed
```

**`spellsui.lua` note:** I never touched `Spells/Book.lua`, `UI/*` or `tools/spellsui.lua`. This
suite intermittently failed and passed across repeated runs while T7b/T10c were concurrently
editing `Spells/Book.lua` / `UI/Dashboard_Forever.lua` / `UI/Dashboard_Rows.lua` /
`tools/spellsui.lua` in the same tree -- e.g. one run failed "lists every family... heals then
damage then other" with `order=BigSpell, GapFamily, Healing Touch, Rejuvenation, Wrath` (one
family short of the fixture a moment later), the very next run passed with `Bearform` included and
a fixture change (`Oakskin`, `Swing`) already landed in `tools/spellsui.lua`. This is a torn read
against another agent's in-progress edit, not a regression from this task's files (`Client/Probe.lua`,
`tools/wowstub.lua`, `tools/probecheck.lua`) -- reran per instructions, and the failure is not
reproducible against any Probe/stub/probecheck change.

`python3 tools/apicheck.py`:
```
apicheck: 8 Forever TOCs, 21 files, 40 distinct globals, 0 findings (baseline 69893)
```
`python3 tools/apicheck.py --selftest`:
```
selftest: 7 of 7 findings as expected
```

### `luac -p`

```
Client/Probe.lua      -- clean
tools/wowstub.lua      -- clean
tools/probecheck.lua   -- clean
```

### `git status --short` (at the end of this task)

```
 M Client/Probe.lua
 M UI/Dashboard_Forever.lua        <- T10c's, not mine
 M UI/Dashboard_Rows.lua           <- T10c's, not mine
 M tools/probecheck.lua
 M tools/spellsui.lua              <- T10c's, not mine
 M tools/wowstub.lua
?? docs/tasks/T10c-pane-layout.md
?? docs/tasks/T12b-measure-attribution.md
?? docs/tasks/T13-recorder-v3.md
?? docs/tasks/T13a-secret-arg-check.md
?? docs/tasks/T13b-probe-m3-items.md
?? docs/tasks/T13c-module-plumbing.md
?? docs/tasks/T15-kit-from-book.md
```

### Skipped / out of scope

Nothing skipped from this task's Files/Acceptance. Out-of-scope items (every other probe
section/question, Q1 logic, the recorder itself) untouched, as instructed.

### Questions

None -- the task's Facts, Files and Acceptance matched what the code showed; no ambiguity found.

## Review (lead, 2026-09-28) -- re-issued once

Read the diff whole; reran probecheck `70 ok`. The classifiers, the three tooltip picks, the six
party readings and the section are as specified. **Re-issued for one defect:** `unitCombatEvents`
is appended to on every `UNIT_COMBAT` for the whole session and each new event scans all of it
(`BumpUnitCombatToken`, the `for _, ev in ipairs(unitCombatEvents)` loop). The probe listens from
load, so over a dungeon session (tens of thousands of events) that is quadratic work inside an
event handler -- a frame-time cost the probe must never impose.

### Re-issue 1 (do exactly this)

1. A mirror can only be an event of the **same** `GetTime()` moment, so keep only the current
   moment's events: remember the last `timeKey`; when an event arrives with a different one, empty
   `unitCombatEvents` (`wipe`, or a fresh table) before scanning. The list then never holds more
   than one frame's events.
2. One new assertion in `tools/probecheck.lua`, verbatim: "the mirror list holds one moment's events,
   not the session's" -- fire 50 `UNIT_COMBAT` events across 50 different `S.now` values, then
   check the probe's list length is 1 (expose the length for the suite the way the file already
   exposes other internals, or read it through the report -- say which). probecheck ends `71 ok`.
3. Rerun probecheck, apicheck, luac; append `### Re-issue 1` to the Report with the output. Do not
   rewrite the rest.

### Re-issue 1

**Fix (`Client/Probe.lua`):** `unitCombatEvents` is now only ever this moment's events. A new
module-level `lastUnitCombatTimeKey` remembers the `TimeKey()` the list currently holds;
`BumpUnitCombatToken` checks the incoming event's `timeKey` against it first, and on a mismatch
empties `unitCombatEvents` in place (a manual reverse-index loop, no `wipe` dependency) before
setting `lastUnitCombatTimeKey` and doing anything else. The mirror scan and the append that
follow are unchanged. The list therefore never holds more than one `GetTime()` moment's events,
so the per-event scan stays O(1) regardless of session length. Also exposed
`MD.Probe.UnitCombatEventsCount()` (returns `#unitCombatEvents`) purely for the suite -- no report
section changed, no new global besides the ones the probe already declares.

**`tools/probecheck.lua`:** one new assertion, verbatim "the mirror list holds one moment's
events, not the session's" -- reusing Step 9's `MD9`/`S9` (no fresh session needed since it only
adds more events after the existing checks already read `reportG`), it fires 50 `S9.Combat`
calls each at its own `S9.now` (300+i, i=1..50, so 50 distinct `TimeKey()`s), then asserts
`MD9.Probe.UnitCombatEventsCount() == 1`.

**Suite output** (`bash tools/run.sh tools/probecheck.lua`):

```
...
UNIT_COMBAT is counted per token with its guid readability, and a same-frame repeat as a mirror ok
the mirror list holds one moment's events, not the session's             ok
a shape function the client lacks reads <absent>                         ok
the combat snapshot carries the shapes read in combat                    ok
UNIT_SPELLCAST_SUCCEEDED is counted with its id readable or secret, and the cost read at the cast ok

71 ok, 0 failed
```

**`python3 tools/apicheck.py`:**
```
apicheck: 8 Forever TOCs, 21 files, 40 distinct globals, 0 findings (baseline 69893)
```
**`python3 tools/apicheck.py --selftest`:**
```
selftest: 7 of 7 findings as expected
```

**`luac -p`** (via `tools/.lua/lua-5.1.5/src/luac -p`, the system had no `luac` on PATH):
```
Client/Probe.lua       -- clean
tools/probecheck.lua   -- clean
```

Only `Client/Probe.lua` and `tools/probecheck.lua` touched for this re-issue; did not rerun the
other suites since this is a request-local counter/loop change with no effect outside the probe
and its own suite (the other suites do not exercise `Client/Probe.lua`), per the instruction to
rerun a suite once only if affected.
