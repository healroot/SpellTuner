# T49 -- Forever recordings, Review pins and the coach address (plan P5)

Status: **built** 2026-09-30 on branch `plan/P5` (base `06f0969`), wave 2 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P5)

Review items (`docs/review/2026-09-30-project-review.md`): B14, B15, B16, B24.

- **(a) B14.** Review's Pin goes through `MD.FightRecorder:Pin` (capped; a refusal says why in one
  line) on both lines; `StoreOrDrop` honours only the first `MAX_PINNED` pins and always stores, as TBC
  does, with a debug line when it had to.
- **(b) B15.** The roster keeps `name` bare (what `SM.PartyMaxFromOthers` and
  `SM.DangerHitFromOthers` match other recordings on, old ones included) and gains `realm` from
  `UnitName`'s second return, through the adapter. `ResolveTargetIndex` matches a `Name-Realm` target
  against `name .. "-" .. realm` exactly, then a bare name when it is unique in the roster.
- **(c) B16.** The coach pattern accepts `[%d:]`; an argument it cannot read answers
  `coach: no recording <arg>` as validate does.
- **(d) B24.** The selected row's validation runs before the rows are painted.

Owned files (section 4, wave 2): `Recorder/Recorder_Forever.lua`, `Replay/Commands_Forever.lua`,
`UI/Dashboard_Review.lua`, `tools/recordcheck.lua`, `tools/reviewforever.lua`, `tools/reviewui.lua`,
`tools/coachforever.lua`, `tools/scenariocheck.lua`. Nothing else was touched.

## What was built

| file | change |
|---|---|
| `Modules/SpellTuner_Recorder/Recorder_Forever.lua` | **B15:** `R:Refresh` reads `local name, realm = MD.API.UnitName(token)` (a non-string or `""` realm is `nil`, and so is any realm when the name is not a plain string: a failed read answers `nil` and the adapter's status word, which is not a realm -- the review's fix); the live roster entry and `CopyRoster`'s stored copy carry `realm` beside the bare `name`. The session-only roster key (used only when a GUID is not plain) is the full name, so two same-name members of different realms stay two. `ResolveTargetIndex(target)`: first the full name exactly (`name .. "-" .. realm`, or the bare name for a same-realm member), then the bare name -- the target's own, or the part before its realm -- when exactly one roster entry carries it; two of one name with nothing to tell them apart are `-1`. **B14:** `MD.FightRecorder:Pin` returns `false, "at most 2 fights can be pinned - unpin one first."` on a refusal (and `false, "no recording N"` for a missing one); `StoreOrDrop` protects only the first `MAX_PINNED` pinned streams in list order (TBC's `Engine/FightRecorder.lua` rule), always has a victim (the oldest unprotected), and writes a `sim` debug line when that victim was pinned. |
| `Modules/SpellTuner_Replay/Commands_Forever.lua` | **B16:** `MD:RunCoach` matches `^([pP]?[%d:]*)%s*(%a*)$`; no match prints `coach: no recording <arg>.` and returns; an empty address is still recording 1. `2:7` reaches `MD:GetRecording`, which on Forever answers nil for a run address, so it prints `coach: no recording 2:7.` |
| `UI/Dashboard_Review.lua` | **B14:** a local `PinFight(rec, on)`: finds the record's index in `MD.FightRecorder:List()` and calls `FR:Pin(n, on)` when the recorder has one (Forever); where it has none (TBC's `Engine/FightRecorder.lua`, owned by P4 in this wave) the same cap is applied here at that file's `MAX_PINNED` (2). The Pin button prints `pin: <why>` on a refusal (the reason's pipes doubled). Practice pins and run pins unchanged. **B24:** `rec = Selected()` and its validation (`Validation(rec)` for a druid, the cache otherwise) move above the row loop, so the selected row's cell and hover are built from the result the buttons act on; the buttons' code below reads the same `rec` / `v`. |
| `tools/recordcheck.lua` | +5 (24 -> 29), below. |
| `tools/scenariocheck.lua` | +2 (12 -> 14), below. |
| `tools/reviewforever.lua` | +2 (11 -> 13), below; the sanity comment on the row count updated. |
| `tools/coachforever.lua` | +1 (19 -> 20), below. |
| `tools/reviewui.lua` | +2 (44 -> 46), below (one more than the plan named: see Deviations). |

## Tests first (on the parent's code, only the tests changed)

`tools/recordcheck.lua` (rc 1):

```
B14: with all eight stored streams pinned the ninth pull is still stored (the first two pins kept) FAIL - before=8 after=8 ninth=false firstTwoKept=true
B15: a cross-realm member's Name-Realm target resolves to their roster index               FAIL - tgt=-1
B15: two same-name members on different realms are told apart by the full name             FAIL - RealmA=-1 RealmB=-1
B15: the stored roster name stays bare, the realm beside it                                FAIL - name=Healer realm=nil player realm=nil
24 ok, 4 failed
```

The fifth, added after the review (on 7b7fb85, the first submission, only the test changed; rc 1):

```
B15: a member whose name reads secret is stored with no realm (the status word is not one) FAIL - roster[2]=true name=nil realm=secret
28 ok, 1 failed
```

`tools/reviewforever.lua` (rc 1):

```
B24: the selected, never validated row paints its verdict on the first render                   FAIL - row1=not checked
B14: a third pin is refused with one line, and the first two stay pinned                        FAIL - pins=true,true,true line=nil
11 ok, 2 failed
```

`tools/coachforever.lua` (rc 1):

```
/st coach 2:7 with no such recording is refused, and no card (B16) FAIL - 2:7 -> |cff9966ffSpellTuner:|r coach: searching (this runs across frames; /md coach cancel stops it)... (34 lines, searched=true); '1 force now' -> |cff9966ffSpellTuner:|r coach: searching ... (34 lines, searched=true); plan=true
19 ok, 1 failed
```

`tools/reviewui.lua` (TBC, rc 1):

```
the selected row paints its verdict at once    FAIL - not checked
a third pin is refused with a line             FAIL - pins=true,true,true line=nil
44 ok, 2 failed
```

`tools/scenariocheck.lua`: `14 ok, 0 failed` on the parent too, **by design**. The two assertions pin
the choice (b) makes -- `name` stays bare and `realm` sits beside it -- so an old recording with a bare
`Tank` and a new one with `name = "Tank", realm = "X"` are one person to `SM.PartyMaxFromOthers`
(2500, `recorded`, 2 matched) and `SM.DangerHitFromOthers` (600, 2 matched). They go red the day
someone stores `Tank-X` in `name`.

After the fix: every one of the above passes (the outputs below).

```
B14: with all eight stored streams pinned the ninth pull is still stored (the first two pins kept) ok - before=8 after=8 ninth=true firstTwoKept=true
B24: the selected, never validated row paints its verdict on the first render                   ok - row1=ok
B14: a third pin is refused with one line, and the first two stay pinned                        ok - pins=true,true,false line=|cff9966ffSpellTuner:|r pin: at most 2 fights can be pinned - unpin one first.
the selected row paints its verdict at once    ok - mana mean: mean off by 4.6% of pool
a third pin is refused with a line             ok - pins=true,true,false line=|cff9966ffSpellTuner:|r pin: at most 2 fights can be pinned - unpin one first.
```

### What the new assertions do

- `recordcheck` B14: eight real pulls through the recorder, every stored stream then marked pinned (as
  the Review tab's old toggle or an old file could leave them), a ninth pull: still stored, and the
  first two pinned streams in list order survive.
- `recordcheck` B15 (x3): a party of `Healer-OtherRealm`, `Tank-RealmA`, `Tank-RealmB` (the stub's
  `realm` knob from T45); casts SENT at `Healer-OtherRealm`, `Tank-RealmB`, `Tank-RealmA` land on
  roster 2, 4 and 3; the stored roster entry is `name = "Healer"`, `realm = "OtherRealm"`, the
  player's realm nil.
- `recordcheck` B15 (review): a party member whose name reads secret (the stub's `S.Secret()` as
  `name`, with a realm set) is stored with `name` and `realm` both nil -- `MD.API.Call`'s `nil, "secret"`
  is not a realm.
- `scenariocheck` (x2): above.
- `reviewforever` B24: the first render after the recordings exist, before any Validate click, row 1
  (selected) reads `ok`. B14: Pin on rows 1 and 2 print nothing and pin; Pin on row 3 prints one ASCII
  line with no bare pipe, `pin: at most 2 ...`, and leaves it unpinned.
- `coachforever` B16: `/st coach 2:7` and `/st coach 1 force now` each print exactly one line,
  `coach: no recording <arg>.`, start no search and leave no plan.
- `reviewui` (TBC): the fakepull fight's row reads its first failing gate (`mana mean: ...`) on the
  first render; three copies of the fight, Pin on two, the third refused with the same line.

## Review fix (2026-09-30)

The reviewer found that `R:Refresh` stored the adapter's status word as a realm: when `MD.API.Call`
fails it answers `nil, "secret"` (or `"absent"` / `"error"`, `Client/API.lua`), so a member whose
name read secret was stored with `realm = "secret"`. The realm is now dropped whenever the name is not
a plain string (`if type(name) ~= "string" or type(realm) ~= "string" or realm == "" then realm = nil
end`), the guard the `UnitClass` read beside it already has. One `recordcheck` assertion holds it
(failing first, above). The full loop re-run afterwards, every suite rc 0, counts as below.

## Suites (exit codes checked; the loop in docs/TOOLS.md section 1)

| suite | before (06f0969) | after |
|---|---|---|
| `recordcheck` | 24 | **29** |
| `scenariocheck` | 12 | **14** |
| `reviewforever` | 11 | **13** |
| `coachforever` | 19 | **20** |
| `reviewui` | 44 | **46** |
| every other suite | simcheck 13, reccheck 54, replaycheck 82, replayui 98, runcheck 78, navui 35, dashui 63, regencheck 27, simwindow 8, solvercheck 84, restcheck 51, timeline 27, spelltip 48, costcheck 3, practice 81, practiceui 50, migrate 7, probecheck 87, forevercheck 16, modulecheck 14, kitcheck 7, gatecheck 9, replayforever 15, practiceforever 25, bindscheck 6, parsecheck 12, bookcheck 21, tipcheck 37, clockcheck 21, spellsui 47, measurecheck 30, releasecheck 16, importcheck 19, themecheck 23, tabscheck 24, wincheck 53, adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1, consolecheck 17 / 1 | all equal, all rc 0 |
| `apicheck.py` / `--selftest` | 0 findings / 10 of 10 | same |
| `textcheck.py` / `--selftest` | 0 findings / 2 of 2 | same |
| `refcheck.py --selftest` | ok | ok |

`luac -p` passes on every changed `.lua`.

## TBC

`UI/Dashboard_Review.lua` is shared, so two things move on TBC, both in the Review tab only:

- **A third pin is refused with a line** (`pin: at most 2 fights can be pinned - unpin one first.`)
  instead of being set on the record and then not protected by `Engine/FightRecorder.lua`, which
  honours only the first two. Nothing in the TBC recorder changed; the cap lives in the Review until
  the recorder has its own `Pin` (P18's `Engine/Recordings.lua`).
- **The selected row shows its verdict on the first paint** instead of on the next 2 s tick. Same
  validation, same cache, earlier.

No model, recorder or look change.

## Integrator lines

**docs/DECISIONS.md** (new section, after T47's "The client is the TOC's, the interface is a
fallback"):

> ## Pins are capped in the Review tab, and a cross-realm member keeps a bare name (2026-09-30, T49)
>
> Review's Pin on a single fight goes through the recorder's capped `Pin` (Forever's
> `Recorder_Forever.lua`; on TBC, whose `Engine/FightRecorder.lua` has no `Pin` yet, the same cap of
> two is applied by the Review until P18's `Engine/Recordings.lua` gives both lines one). A third pin
> is refused with one line, `pin: at most 2 fights can be pinned - unpin one first.`, on both lines;
> on TBC it used to be set and silently not honoured, on Forever it used to be set and, with every
> stream pinned, the next pull was lost. Forever's ring now protects only the first two pins (TBC's
> rule) and always stores. A party member from another realm is recorded with `name` bare and
> `realm` beside it (from `UnitName`'s second return): old recordings and new ones name the same
> person to `SM.PartyMaxFromOthers` and `SM.DangerHitFromOthers`; a cast SENT at `Name-Realm` is
> matched to the full name first, then to a bare name that is unique in the roster. The suffix form
> of the SENT target follows the retail convention and has not been seen on the beta.

**CLAUDE.md**, table rows:

- `Modules/<Name>/` row, after the Review sentence ending `... (R7-R11, R24, R25; `recordcheck` 24)`:
  add ` **T49 (P5):** a party member's `realm` is recorded beside the bare `name`, a SENT
  `Name-Realm` target resolved by the full name then a unique bare name (B15); `Pin` refuses a third
  with a reason, and the ring protects only the first two pins and always stores (B14); `/st coach`
  takes `2:7` and refuses an argument it cannot read (B16) (`recordcheck` 29)`.
- `UI/Dashboard_Review.lua` row, append: ` **T49 (P5):** Pin on a single fight goes through the
  recorder's capped `Pin` (the cap of two applied here on TBC, whose recorder has none), a third
  refused with one line; the selected row validated before the rows are painted (B14, B24)`.

**docs/TOOLS.md** section 1:

- `recordcheck.lua` row, append: `Since **T49** (29): every stored stream pinned and the ninth pull
  still stored, the first two pins kept (B14); a cross-realm `Name-Realm` target resolved, two
  same-name members of different realms told apart, the stored name bare with its realm, a member
  whose name reads secret stored with no realm (B15)`.
- `scenariocheck.lua` row, append: `Since **T49** (14): an old bare-name recording and a new one with
  a realm are one person to `SM.PartyMaxFromOthers` and `SM.DangerHitFromOthers` (B15)`.
- `reviewforever.lua` row, append: `Since **T49** (13): the selected row's verdict on the first
  render, a third pin refused with one line (B24, B14)`.
- `coachforever.lua` row, append: `Since **T49** (20): `/st coach 2:7` and `/st coach 1 force now`
  refused with `coach: no recording <arg>.`, no search, no card (B16)`.
- `reviewui.lua` row, append: `Since **T49** (46): the selected row's verdict on the first render,
  a third pin refused with a line (B24, B14 on TBC)`.

**docs/TESTING.md** section 44: items 10 (Pins, B14) and 14 (Coach address, B16) of the plan's
section 9, as written there; and, for TBC, "Pin three fights in `/md` -> Reports -> Review: the third
is refused with a line."

**tools/data/expected-counts.json** (when P13 creates it): `recordcheck` 29, `scenariocheck` 14,
`reviewforever` 13, `coachforever` 20, `reviewui` 46.

No TOC changes.

## Deviations

- **`reviewui` +2, not +1.** The plan names one TBC assertion (the verdict on first render). The
  third-pin refusal is a TBC behaviour change too, and its TBC path is code of its own (the cap in the
  Review, because TBC's recorder has no `Pin` and `Engine/FightRecorder.lua` belongs to P4 this wave),
  so it is asserted on TBC as well.
- **TBC's cap lives in `UI/Dashboard_Review.lua`.** The plan says Review's Pin goes through
  `MD.FightRecorder:Pin` on both lines; TBC's recorder has none and is not this task's file. The
  Review calls the recorder's `Pin` wherever it exists and otherwise applies the same cap (2, the TBC
  file's `MAX_PINNED`) itself. P18 (`Engine/Recordings.lua`, `Pin` capped, both lines) is where the
  duplicate goes.
- **The two `scenariocheck` assertions pass on the parent**, as stated above: they guard the
  decision to keep `name` bare, which the parent already did for everyone.
- `ResolveTargetIndex` also treats two roster entries of one bare name with no realm to tell them apart
  as nobody (`-1`) rather than the first; and the session-only roster key (used only when a GUID is not
  plain) is the full name. Neither is stored.
- `MD.FightRecorder:Pin` on Forever also returns a reason for a missing recording
  (`no recording N`); the Review never asks for one.
