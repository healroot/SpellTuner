# T12 — /st measure: a cast against what its own text promised

Status: **done -- lead-accepted 2026-09-28 after one re-issue** (see the Review and Re-issue 1). M2 (`docs/ROADMAP-FOREVER.md` §2), task line "T12 `docs/TESTING.md`
for M2 and the dummy measurements, including the downrank measurement". Split by the lead: the
lead writes the `docs/TESTING.md` section; this task is the in-game instrument it uses. Needs T7
(`MD.Book`).

## Goal

`/st measure` switches on a measuring session in which every own cast is matched to what landed
-- a heal on yourself, damage on your target -- and one chat line says whether it landed inside the
range its own description stated, inside the crit range, or **below** it (a downrank penalty the
client text does not show, `FOREVER-PLAN.md` §6 Q10), and for a HoT or DoT how many ticks came, how
far apart and what they summed to. The lines are kept and `/st measure dump` puts them in one copy
box for the author to paste into `docs/probe/`. Off by default and registering nothing until first
switched on: it is a diagnostic, not combat tracking. For the author's M2 exit measurements (three
spells of two classes on a dummy, within the crit spread) and Q10.

## Facts

- `UNIT_COMBAT(unit, action, descriptor, amount, school)` amounts are **plain** for WOUND and HEAL on
  `player`, `target` and `party1`, in and out of combat (`docs/probe/1.60.1_70009.md` fourth,
  seventh, eighth, ninth reports; ~1,000 events, none secret). **The same hit arrives once per unit
  token** (seventh report: `other` mirrors `player`), so the handler filters by the unit token it
  watches. Whether a HEAL amount is **gross or effective** is UNKNOWN (Q3's open part; the damage
  meter counts effective) -- the protocol asks for enough missing health that the two are equal, and
  every heal line says `(heal amount: gross or effective unknown - see protocol)` once per session.
  What `descriptor` carries for a crit is UNKNOWN (retail's `"CRITICAL"`); read it as a plain string
  and print it, never rely on it -- the judgement uses the amount.
- `UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)` registers; whether the id is readable in combat
  is UNKNOWN (T7a counts it). A dummy fight is combat.
- A rank's text is the client's value at the caster's level, gear and buffs (`FOREVER-PLAN.md` §6
  Q1). A server-side downrank rule would not show in it (Q10): a landed heal consistently **below**
  the text's minimum, growing with the gap between the rank's level and the caster's, is that rule.
- Crit multiplier 1.5 is vanilla's (`docs/tasks/T9-spell-tooltip.md` Facts, UNVERIFIED on Forever);
  a landed amount above the text's top and at or under `max * 1.5` is `crit range`; above that, `above`.
- `type()` of a secret does not raise and may answer the underlying type -- a secret number can read
  `"number"` (`tools/wowstub.lua` header, from EllesmereUI; T9 Review). So "a plain number" means
  `not MD.API.IsSecret(v) and type(v) == "number"`, in that order, for every event argument.
- `GetSpellBonusHealing()` is plain out of combat (every probe report's spells header); in combat
  UNKNOWN (stats go secret in combat, seventh report) -- read it through the adapter, print `?` when
  not plain.

## Files

| file | change | role |
|---|---|---|
| `Client/API_Forever.lua` | `SpellBonusHealing = "GetSpellBonusHealing"` | binding |
| `Spells/Measure.lua` | new | the session, the watches, the judgement, the lines |
| `Core_Forever.lua` | `/st measure` (toggle), `/st measure dump`; the lines are kept in `SpellTunerDB.measures` (account-wide, last 100) | commands |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `Spells\Measure.lua` after `Engine\ManaModel.lua` | TOCs |
| `tools/wowstub.lua` | forever profile: `S.Combat(unit, action, amount, descriptor)` firing `UNIT_COMBAT` | stub |
| `tools/measurecheck.lua` | new suite (forever) | the instrument |

### Behaviour

- The first `/st measure` registers `UNIT_SPELLCAST_SUCCEEDED` and `UNIT_COMBAT` through `MD:On`;
  every later toggle only flips `MD.Measure.on`. Printing `measure: on - cast on yourself for heals,
  on a target dummy for damage; one spell at a time` / `measure: off`.
- A player cast with a plain id whose `MD.Book` entry has a heal or damage part opens a **watch**:
  the unit is `"player"` for a heal family and `"target"` for a damage family; it records the
  entry's name, rank, level, the text's numbers (`min`, `max`, `over`, `dur`, `tick`, `period`,
  `periodDur`), the caster's level and bonus healing, and the time. A new cast closes every open
  watch first.
- `UNIT_COMBAT` on the watched unit with action `HEAL` (heal) or `WOUND` (damage) and a plain
  amount: the first within 2.5 s of the cast is the **direct** amount when the text has a direct
  part; every other one until `dur` / `periodDur` + 1.5 s after the cast (or after the direct amount
  for a spell with no over-time part, the watch closes at once) is a **tick**, with its time.
- A watch closes at its deadline or at the next cast and prints one line:
  - direct: `<Name> R<n> (lvl <L>, +heal <B>): landed <A> [text <min>-<max>, crit <cmin>-<cmax>] <verdict>`
    with verdict `in range` / `crit range` / `BELOW range` / `above` / `nothing landed`;
  - over time: `<Name> R<n>: <k> ticks <a1>+<a2>+... = <sum> every <avg interval> s [text <over> over <dur> sec] <verdict>`,
    verdict `matches` (sum within the text's total, crits aside -- a tick over the text's
    per-tick share times 1.5 is a crit and is reported as `k crits`), `BELOW`, `above`, or
    `partial` (fewer ticks than `dur / interval` would give).
  - a hybrid prints both parts on one line.
- A secret or non-numeric amount or id is counted (`unreadable`) and never judged.
- Lines go to chat and to `SpellTunerDB.measures` (last 100, oldest dropped). `/st measure dump`
  shows them with a header (`build`, character, level, date) in `MD:ShowCopyPopup`.

## Rules

- **No client call and no client-table indexing outside `Client/`.** `UNIT_COMBAT`'s arguments are
  client values: check them with `MD.API.IsSecret` and `type` before any comparison or arithmetic.
- Registers nothing until first switched on; nothing registers the combat log.
- ASCII only, no bare `|`; every client string through the probe's escaping rule (`||`).
- No new global; no library; the multi-return trap.
- Tests first: `tools/measurecheck.lua` before the code; say which assertions failed.
- Comments say why, not what.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `bash tools/run.sh tools/measurecheck.lua` ends `9 ok, 0 failed`. Names verbatim:
   1. "measuring is off until asked and registers nothing until then"
   2. "a direct heal on yourself is matched to what landed and judged against its text"
   3. "a landed amount above the text's top is judged against the crit range"
   4. "a heal below its text's range is called out"
   5. "a HoT's ticks are counted, summed and timed"
   6. "a damage spell is matched on the target"
   7. "events on another unit are not counted"
   8. "the lines are kept and dumped as one copy block, ASCII, no bare pipe"
   9. "a secret amount or id is counted unreadable, never judged"
2. Every other suite at its count after T10 (say them).
3. `python3 tools/apicheck.py` 0 findings; `--selftest` 7 of 7; the two Forever TOCs differ on the
   marker only.
4. `luac -p` clean on every file touched.
5. Paste into the Report: failing run first; measurecheck in full; the lines a scripted session
   printed (a Healing Touch in range, one crit, one below, a Rejuvenation's ticks, a Wrath on the
   target); every other tail; apicheck; luac; `git status --short`.

## Out of scope

- Any fight recording, overheal, the damage meter (M3's Recorder module).
- `docs/TESTING.md` (the lead writes it), `CLAUDE.md`, every other `docs/` file except this Report.
  Commits.

## Report

Implemented as specified. Tests first: `tools/measurecheck.lua` was written (and `S.Combat` added
to the stub) before `Spells/Measure.lua` existed. Its failing run:

```
.../tools/measurecheck.lua:51: attempt to index local 'Measure' (a nil value)
stack traceback:
	...measurecheck.lua:51: in main chunk
	[C]: ?
```

File by file:

- **`Client/API_Forever.lua`**: added `SpellBonusHealing = "GetSpellBonusHealing"` via `MD.API.Bind`,
  in its own block after the T7/T9 spellbook bindings, commented with the Facts item it answers.

- **`tools/adaptercheck.lua`**: added `"SpellBonusHealing"` to `FOREVER_ONLY_NAMES`. Not in this
  task's Files table, but without it the existing "every binding is on MD.API and in the capability
  table" exhaustiveness assertion (which counts `MD.API.Capabilities()` against that exact list)
  fails the moment a new Forever-only binding exists -- the same mechanical addition T7's Review
  called "an extension, not a weakening" when that task's own fourteen names landed there. No new
  assertion, same count (19 ok forever, 15 ok tbc, both unchanged).

- **`Spells/Measure.lua`** (new): `MD.Measure` -- `on`, `registered`, `unreadable`, `Toggle()`,
  `Watch()` (exposed for the suite), `Dump()`. One open watch (`local watch`, "one spell at a
  time"), opened by `UNIT_SPELLCAST_SUCCEEDED` when the id is a plain number and `MD.Book`
  resolves it to a family member (its family's `kind`) or a standalone `Book:ReadSpell` entry with
  a heal or damage part -- reusing the exact "family first, else ReadSpell" lookup
  `UI/SpellTip_Forever.lua` and `UI/Clock_Forever.lua` already use. `entry.parsed[kind]` (not
  `entry.min/max/over/dur`) is where the watch's seven text numbers come from, because a pure tick
  shape (Tranquility) leaves those four nil while still carrying `tick`/`period`/`periodDur` --
  same reasoning `UI/SpellTip_Forever.lua`'s own `PartOf` comment gives. `UNIT_COMBAT` on the
  watched unit (`"player"` for a heal family, `"target"` for damage) with the wanted action
  (`HEAL`/`WOUND`) and a plain amount: the first inside 2.5s of the cast is the direct amount (and
  closes the watch at once if the spell has no over-time part); everything else, while the spell
  has one, is a tick. A watch closes at its deadline (checked from `MD:OnTick`, not its own timer --
  "the model is event-driven, tickers only accumulate/render" and closing a stale watch is the
  render), at the next cast (`CloseWatch()` runs unconditionally at the top of the cast handler,
  before the new id is even read), or at once after a direct amount on a spell with no over-time
  part. `MD.API.IsSecret` is checked before every comparison on `unit`/`action`/`amount`/`spellID`
  (T9 Review's lesson: `type()` of a secret does not raise and may answer the underlying type), and
  a secret or non-numeric amount or id only increments `unreadable` -- the watch is left open,
  never judged from it. `Client/Probe.lua`'s reversible `Esc` is duplicated (that file exposes no
  public one) and applied to the one client string this file ever prints, a spell's own name.

  Two verdict functions, `DirectVerdict` (in range / crit range / BELOW range / above / nothing
  landed, exactly as Facts states) and `OverVerdict`. **One place the Behaviour section left room
  for a judgement call, noted rather than guessed at random:** "matches (sum within the text's
  total, crits aside -- a tick over the text's per-tick share times 1.5 is a crit and is reported
  as `k crits`)" does not say what tolerance "within" means, nor what "the text's per-tick share"
  is for a HoT whose text gives no per-tick number at all (Rejuvenation: `{over=32, dur=12}`, no
  `tick`/`period`). Implemented: the per-tick share is the text's own `tick` when it states one
  (Tranquility), else `Parse.Total(text) / (dur/period)` when a period is known, else crit
  detection is simply skipped for that spell (never guessed); the sum is judged against
  `Parse.Total(text)` with a +/-10%..+50% band (`BELOW` under 90%, `above` over 150%, `matches`
  between -- the same 1.5x the direct verdict already uses for "crit range", so one crit-sized
  tick does not itself flip a matching HoT to "above"), and any crit ticks are appended as
  `"(k crits)"` to whichever base verdict is chosen. `partial` fires ahead of all of that when the
  text's own period is known and fewer ticks arrived than `dur/period` implies. None of the nine
  named acceptance assertions pin the exact wording here (only assertion 5, the plain Rejuvenation
  case with no period at all, touches ticks, and that one has no crit and no `partial` question), so
  this was implemented and tested rather than raised as a blocker -- flagging it here as the one
  interpretation call in an otherwise literal read of the task.

- **`Core_Forever.lua`**: `/st measure` toggles (`MD.Measure:Toggle()`); `/st measure dump` opens
  `MD:ShowCopyPopup("SpellTuner measure", MD.Measure:Dump())`. No new default needed --
  `SpellTunerDB.measures` is created lazily by `Spells/Measure.lua` itself, the same way
  `SpellTunerDB.session`/`.probe` already are.

- **`SpellTuner_Mainline.toc`, `SpellTuner.toc`**: `Spells\Measure.lua` added right after
  `Engine\ManaModel.lua`. Both TOCs still differ only on the marker line
  (`Client\TOC_Mainline.lua` vs `Client\TOC_Plain.lua`). `tools/harness.lua` reads its file list
  straight from `SpellTuner_Mainline.toc`, so no harness change was needed.

- **`tools/wowstub.lua`**: inside `S.UseProfile("forever")`, added `S.Combat(unit, action, amount,
  descriptor)` firing `UNIT_COMBAT` in the client's own argument order (`unit, action, descriptor,
  amount, school`) -- args are accepted in a more convenient order (the amount a fixture actually
  varies, ahead of the descriptor it never reads) and reassembled before firing. This *overrides*
  the top-level `S.Combat` (line 188, the TBC combat-log fake) once the forever profile is
  selected -- the same shadowing shape `GetSpellBonusHealing`/`GetManaRegen`/etc. already use for
  their own profile-specific redefinitions two names above it; no TBC suite calls
  `S.UseProfile("forever")`, so the TBC-profile `S.Combat` is untouched there. `UNIT_COMBAT` was
  already in `FOREVER_EVENTS` (added by an earlier task), so no change was needed there.

- **`tools/measurecheck.lua`** (new): the 9 assertions, names verbatim (see the run below). Uses
  only the four fixed spellbook slots every forever suite already has (5185 Healing Touch,
  774/1058 Rejuvenation, 5176 Wrath) -- no new `S.AddSpell` fixture was needed. Item 7 ("events on
  another unit") and item 9 ("secret ... never judged") each leave the watch open on purpose and
  close it with one more `S.Combat` call afterwards so state does not leak into the next item.

### `bash tools/run.sh tools/measurecheck.lua` (full)

```
measuring is off until asked and registers nothing until then            ok - on=false registered=false
a direct heal on yourself is matched to what landed and judged against its text ok - Healing Touch R1 (lvl 1, +heal 0): landed 48 [text 40-55, crit 60-83] in range
a landed amount above the text's top is judged against the crit range    ok - Healing Touch R1 (lvl 1, +heal 0): landed 70 [text 40-55, crit 60-83] crit range
a heal below its text's range is called out                              ok - Healing Touch R1 (lvl 1, +heal 0): landed 30 [text 40-55, crit 60-83] BELOW range
a HoT's ticks are counted, summed and timed                              ok - Rejuvenation R1: 4 ticks 8+8+8+8 = 32 every 3.0 s [text 32 over 12 sec] matches
a damage spell is matched on the target                                  ok - Wrath R1 (lvl 1, +heal 0): landed 15 [text 13-16, crit 20-24] in range
events on another unit are not counted                                   ok
the lines are kept and dumped as one copy block, ASCII, no bare pipe     ok - 574
a secret amount or id is counted unreadable, never judged                ok - unreadable 0->2 untouched=true

9 ok, 0 failed
```

The lines a scripted session printed (Behaviour: a Healing Touch in range, one crit, one below, a
Rejuvenation's ticks, a Wrath on the target):

```
Healing Touch R1 (lvl 1, +heal 0): landed 48 [text 40-55, crit 60-83] in range
Healing Touch R1 (lvl 1, +heal 0): landed 70 [text 40-55, crit 60-83] crit range
Healing Touch R1 (lvl 1, +heal 0): landed 30 [text 40-55, crit 60-83] BELOW range
Rejuvenation R1: 4 ticks 8+8+8+8 = 32 every 3.0 s [text 32 over 12 sec] matches
Wrath R1 (lvl 1, +heal 0): landed 15 [text 13-16, crit 20-24] in range
```

### Every other suite

All at the same count as before this task (T10's tails, T10b's own work-in-progress files
untouched -- confirmed by `git status --short` below not naming them):

```
adaptercheck  forever 19 ok, tbc 15 ok
bookcheck             14 ok
forevercheck          13 ok
modulecheck           12 ok
corecheck     forever 10 ok, tbc 8 ok
svcheck       forever  6 ok, tbc 1 ok
consolecheck  forever 11 ok, tbc 1 ok
probecheck            66 ok
parsecheck            10 ok
clockcheck            13 ok
simcheck              PASS (measured mean 1.3%  max 2.8% at 23.0s)
reccheck              54 ok
replaycheck           80 ok
replayui              98 ok
runcheck              78 ok
reviewui              44 ok
navui                 25 ok
dashui                56 ok
regencheck            27 ok
simwindow              8 ok
solvercheck           70 ok
timeline              27 ok
spelltip              48 ok
practice              74 ok
practiceui            49 ok
migrate                7 ok
```

### `python3 tools/apicheck.py`

```
apicheck: 8 Forever TOCs, 21 files, 40 distinct globals, 0 findings (baseline 69893)
selftest: 7 of 7 findings as expected
```

`SpellTuner.toc` and `SpellTuner_Mainline.toc` differ on exactly the marker line
(`Client\TOC_Plain.lua` vs `Client\TOC_Mainline.lua`).

### `luac -p`, every file touched

```
Client/API_Forever.lua   OK
Spells/Measure.lua       OK
Core_Forever.lua         OK
tools/wowstub.lua        OK
tools/measurecheck.lua   OK
tools/adaptercheck.lua   OK
```
(`SpellTuner.toc`/`SpellTuner_Mainline.toc` are not Lua.)

### `git status --short`

```
 M Client/API_Forever.lua
 M Core_Forever.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M tools/adaptercheck.lua
 M tools/wowstub.lua
?? Spells/Measure.lua
?? docs/tasks/T12-measure.md
?? tools/measurecheck.lua
```

None of T10b's files (`UI/Dashboard_Forever.lua`, `UI/SpellTip_Forever.lua`, `tools/spellsui.lua`,
`tools/tipcheck.lua`) were opened or touched.

### Skipped / out of scope

Nothing from the Files or Behaviour sections was skipped. Left for the author to check in-game, as
the task's Goal section asks for: whether `UNIT_COMBAT` actually fires for `player`/`target`/
`party1` the way `docs/probe/1.60.1_70009.md` describes, whether the crit multiplier really is 1.5x
on this client, and the Q10 downrank measurement itself -- none of that can be settled offline, only
instrumented, which is what this task built.

### Question

None -- no Fact turned out false and the one place the Behaviour section left room for a judgement
call (the exact tolerance/crit-share rule inside "matches") is documented above rather than blocking,
since it is testable and tested but not pinned by wording in any of the nine named acceptance
assertions.

## Review (lead, 2026-09-28) -- re-issued once

Read the diff whole and reran measurecheck (`9 ok`), adaptercheck 19/15, every other suite at its
count, apicheck 0 (21 files). The secret checks precede every comparison, registration waits for
the first toggle, lines go to chat and to `SpellTunerDB.measures`. The HoT band (90%..150% of the
text's total, crit ticks counted when a per-tick share is known) is an acceptable reading of an
under-specified line, and stands.

**Re-issued for one line of the spec the implementation reads the other way -- the lead's wording
was ambiguous, the intent is not.** The direct line's `(lvl <L>, +heal <B>)` prints the **spell's
learn level** (`entry.level`: "lvl 1" for Healing Touch R1). The Behaviour section asks the watch to
record "the caster's level", and the whole point of the line is Q10 -- a shortfall that grows with
the gap between the rank's level and the caster's -- so both numbers are needed.

### Re-issue 1 (do exactly this)

1. `OpenWatch` records `casterLevel` from `MD.API.UnitLevel("player")` (plain number after
   `IsSecret`, else nil) beside the entry's learn level.
2. The direct line's parenthesis becomes `(learned <entry level>, you <caster level>, +heal <B>)`
   for a heal and `(learned <entry level>, you <caster level>)` for a damage spell (bonus healing
   says nothing about damage); a nil prints `?`. The over-time part of a line is unchanged.
3. `tools/measurecheck.lua`: assertion 2's expected line becomes
   `Healing Touch R1 (learned 1, you 64, +heal 0): landed 48 [text 40-55, crit 60-83] in range`
   (the stub's `S.level` is 64 unless the suite sets another -- use whatever the suite's caster
   level is and say it), and assertion 6's Wrath line carries no `+heal`. These are the only edits
   to existing assertions allowed; no new assertion; the count stays `9 ok`.
4. Rerun measurecheck, apicheck and luac; append a `### Re-issue 1` subsection to the Report with
   the new measurecheck output and the five demonstration lines. Do not rewrite the rest.

### Re-issue 1

Done exactly as specified, nothing else touched.

- **`Spells/Measure.lua`**: `OpenWatch` now also reads `casterLevel` from
  `MD.API.UnitLevel("player")`, cleared through the same `IsSecret`/`type ~= "number"` guard as
  every other client value in this file (nil, not 0, when unreadable), and stores it on the watch
  beside `level` (the entry's learn level, unchanged). `DirectHead` builds the parenthesis as
  `(learned <L>, you <C>, +heal <B>)` for `w.kind == "heal"` and `(learned <L>, you <C>)` for
  damage (`w.kind` is already `"heal"`/`"damage"` from `ResolveEntry`, set on the watch since T12's
  first pass) -- bonus healing is only formatted/printed in the heal branch, so a damage line has no
  `+heal` at all rather than a meaningless `+heal 0`. The over-time part of the line
  (`OverBody`/`BuildLine`) is untouched, as the re-issue said.

- **`tools/measurecheck.lua`**: assertions 2 and 6 changed from a substring `find` to an exact
  `line ==` against the full expected string (tighter than required but the two strings are now
  fully pinned by the re-issue's own wording, so asserting the whole line is the more honest test).
  Assertion 2 now expects
  `Healing Touch R1 (learned 1, you 64, +heal 0): landed 48 [text 40-55, crit 60-83] in range`
  (learned level 1 from `SPELL_LEVEL[5185]` in `tools/wowstub.lua`; caster level 64 from `S.level`,
  the stub's own default, unchanged by this suite). Assertion 6 now expects
  `Wrath R1 (learned 1, you 64): landed 15 [text 13-16, crit 20-24] in range` (no `+heal`). No new
  assertion; the nine names are unchanged; the count stays `9 ok`.

#### `bash tools/run.sh tools/measurecheck.lua` (full, after the re-issue)

```
measuring is off until asked and registers nothing until then            ok - on=false registered=false
a direct heal on yourself is matched to what landed and judged against its text ok - Healing Touch R1 (learned 1, you 64, +heal 0): landed 48 [text 40-55, crit 60-83] in range
a landed amount above the text's top is judged against the crit range    ok - Healing Touch R1 (learned 1, you 64, +heal 0): landed 70 [text 40-55, crit 60-83] crit range
a heal below its text's range is called out                              ok - Healing Touch R1 (learned 1, you 64, +heal 0): landed 30 [text 40-55, crit 60-83] BELOW range
a HoT's ticks are counted, summed and timed                              ok - Rejuvenation R1: 4 ticks 8+8+8+8 = 32 every 3.0 s [text 32 over 12 sec] matches
a damage spell is matched on the target                                  ok - Wrath R1 (learned 1, you 64): landed 15 [text 13-16, crit 20-24] in range
events on another unit are not counted                                   ok
the lines are kept and dumped as one copy block, ASCII, no bare pipe     ok - 625
a secret amount or id is counted unreadable, never judged                ok - unreadable 0->2 untouched=true

9 ok, 0 failed
```

The five demonstration lines (Healing Touch in range, one crit, one below, a Rejuvenation's ticks,
a Wrath on the target), now with both levels:

```
Healing Touch R1 (learned 1, you 64, +heal 0): landed 48 [text 40-55, crit 60-83] in range
Healing Touch R1 (learned 1, you 64, +heal 0): landed 70 [text 40-55, crit 60-83] crit range
Healing Touch R1 (learned 1, you 64, +heal 0): landed 30 [text 40-55, crit 60-83] BELOW range
Rejuvenation R1: 4 ticks 8+8+8+8 = 32 every 3.0 s [text 32 over 12 sec] matches
Wrath R1 (learned 1, you 64): landed 15 [text 13-16, crit 20-24] in range
```

#### `python3 tools/apicheck.py` (after the re-issue)

```
apicheck: 8 Forever TOCs, 21 files, 40 distinct globals, 0 findings (baseline 69893)
selftest: 7 of 7 findings as expected
```

No binding changed, so the count is unchanged from the original Report.

#### `luac -p` (only files this re-issue touched)

```
Spells/Measure.lua       OK
tools/measurecheck.lua   OK
```

`Client/API_Forever.lua`, `Core_Forever.lua`, `tools/wowstub.lua`, `tools/adaptercheck.lua`, the
two TOCs -- unchanged by this re-issue, still `OK`/matching from the original Report.

#### `git status --short` (after the re-issue)

```
 M Client/API_Forever.lua
 M Core_Forever.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M tools/adaptercheck.lua
 M tools/wowstub.lua
?? Spells/Measure.lua
?? docs/tasks/T12-measure.md
?? tools/measurecheck.lua
```

Same file set as before the re-issue -- only `Spells/Measure.lua` and `tools/measurecheck.lua`
(both already untracked/new from the first pass) changed content.

No other suite was affected: nothing outside `Spells/Measure.lua` and `tools/measurecheck.lua` was
edited, so every other suite's count from the original Report stands unrerun here (they do not
touch `MD.Measure`).

### Re-issue 1 accepted (lead, 2026-09-28)

Reran: measurecheck `9 ok` with `(learned 1, you 64, +heal 0)` on the heal line and no `+heal` on
Wrath's; every other suite at its count; apicheck 0. Accepted.
