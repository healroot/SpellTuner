# T11b — the Forever clock shows and words its modes as the TBC clock does

Status: **done -- lead-accepted 2026-09-28** (see Review). M2 close-out. Evidence: `docs/probe/1.60.1_70009-m2.md` lines 11-22 (the author:
"refill is shown even out of combat", "oom timer in combat (no number at first but then appeared)").

## Goal

The Forever mana clock appears, hides and words each state the way the TBC clock the author has
used for months does -- same thresholds, same hysteresis, same words -- with the `~` that says the
pool is modelled kept in front. Out of combat it shows `~FULL 0:45` (time to full) only once the
pool has dropped under 90% and hides again above 95%, instead of `~refill 0:05` at 94%. In combat
the first seconds read `~OOM ...  rest 0:20` -- the TBC warm-up wording that says "still gathering"
-- instead of a bare `~OOM --` that looks like a fault. For the author and every Forever user of the
clock.

## Facts

- **The author's two sightings** (m2 20-22): `~refill 0:05` drawn out of combat (screenshot 2);
  in combat no number for the first seconds, then `~OOM 0:45  rest 0:20` (screenshot 3).
- **What Forever does now** (`UI/Clock_Forever.lua` `UpdateVisibility`, `Engine/ManaModel.lua`
  `Project` / `Text`): shown in combat; out of combat shown while the modelled pool is under 95% of
  max, **no hysteresis** (so `~refill 0:05` at 94.x%); warm-up is `fight.casts < 3 or elapsed < 10`
  and renders `~OOM --` with **no** rest segment; out of combat below full renders `~refill <ttf>`;
  `hold` (no regen reading yet) renders `~hold`.
- **What TBC does** (`UI/Widget.lua` `MD:UpdateVisibility` lines 144-173; `Engine/TTO.lua`
  `GetDisplayString` 342-406): in combat shown; out of combat shown when `pct < 0.90`, and once shown
  kept until `pct > 0.95` (hysteresis); `ooc` renders `FULL <ttf>`, `fullnow` `FULL`, `warmup`
  `OOM ...`, `oom` `OOM <t>`, `full` `FULL <ttf>`, a missing value `OOM --` ("never fabricate a
  number"); the second segment (in combat, for `oom` / `hold` / `warmup`) is `rest <t>`, shown when
  the primary is missing or bounded, or when `abs(rest - v) / max(v, 1) >= 0.25`; the two are joined
  by two spaces.
- **The warm-up is intended, not a bug:** Forever's gate (3 casts and 10 s) is T11's (accepted);
  the model has no spend rate to project before it. What was wrong is only that it read like a
  missing number. TBC's words for the same state are `OOM ...`.
- **Differences kept, each with its reason:**
  - TBC shows the widget always while **unlocked**; Forever's `db.clock.locked` is a drag lock only
    and ships `false` (`Core_Forever.lua` defaults), so adopting that rule would show the clock
    permanently for every new user. Not adopted.
  - TBC's arrow, colour ramps, stability `~`, confidence bound and cooldown segment need a spend
    spread (`sigma`) and mana cooldown tables the Forever model does not have (T11). Not adopted;
    every Forever string keeps its leading `~` (the pool is modelled, T11).
  - `hold` on Forever means "no out-of-combat regen reading yet" (no bound exists) -> `~OOM --`,
    TBC's words for a missing value.
- Times: Forever rounds to 5 s and caps at `>10m` (T11, accepted); kept.

## Files

| file | change | role |
|---|---|---|
| `Engine/ManaModel.lua` | `ManaModel.Text(state)`: `fullnow` -> `~FULL`; `ooc` -> `~FULL <ttf>`; `full` -> `~FULL <ttf>`; `warmup` -> `~OOM ...` plus the rest segment; `oom` -> `~OOM <t>` plus the rest segment by TBC's 25% rule; `hold` -> `~OOM --` plus the rest segment; a nil `tto` in `oom` -> `~OOM --` plus rest. The rest segment is `  rest <t>` (two spaces), only in combat modes, only when `state.rest` is a number | the words |
| `UI/Clock_Forever.lua` | `UpdateVisibility`: out of combat shown when `mana < 0.90 * max`, and while shown kept until `mana > 0.95 * max`; a module-local `shown` flag is the hysteresis state; in combat and "off means off" unchanged | the one owner of show/hide |
| `tools/clockcheck.lua` | expected strings updated where the words changed (listed below); two new assertions | suite |

## Rules

- Rendered strings ASCII, no bare `|`, every one starting with `~`. A nil time is `--`, never 0.
- `Engine/ManaModel.lua` stays pure (no client call, no `GetTime`, no `MD.API`).
- Visibility has one owner (`UpdateVisibility`); nothing else calls `Show`/`Hide` on the widget.
- No new global, no library. Comments say why (cite TBC's file and line for each copied rule).
- Tests first: the two new assertions written and failing before the change.
- **Existing assertions:** names unchanged. The only allowed edits: the expected string in "times
  are rounded to five seconds and capped at ten minutes" stays `~OOM 1:05  rest 2:00`, `~FULL 10:00`,
  `~FULL >10m` (unchanged -- confirm it still passes); in "the clock shows in combat and hides at
  full out of combat; off means off" the `shownWhenLow` step sets the pool to 50% (already under 90%,
  unchanged). Any other existing assertion that fails is a question, not an edit.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/clockcheck.lua` ends `15 ok, 0 failed`. New names, verbatim:
   - "each state is worded as the TBC clock words it, marked modelled" -- `Text` of `{mode="fullnow"}`
     is `~FULL`; `{mode="ooc", ttf=45}` is `~FULL 0:45`; `{mode="warmup", rest=20}` is
     `~OOM ...  rest 0:20`; `{mode="warmup"}` is `~OOM ...`; `{mode="hold", rest=20}` is
     `~OOM --  rest 0:20`; `{mode="oom", tto=80, rest=90}` is `~OOM 1:20` (rest within 25%: hidden);
     `{mode="oom", tto=80, rest=130}` is `~OOM 1:20  rest 2:10`.
   - "out of combat the clock appears under 90% and stays until 95%" -- out of combat, pool 94% of
     max from hidden: hidden; 89%: shown; 93%: still shown; 96%: hidden.
2. Every other suite at its baseline count (see T7b's list; spellsui 12, tipcheck 14 -- the pane
   reads `MD.Clock:Pool()`, which does not change).
3. `python3 tools/apicheck.py` 0 findings, `--selftest` 7 of 7.
4. `luac -p` clean on every file touched.
5. Paste into the Report: the failing run; clockcheck in full, including its demonstration lines;
   every other tail; apicheck; luac; `git status --short`.

## Out of scope

- The model's arithmetic, the warm-up gate's numbers, anchoring, pricing (T11, accepted).
- TBC's `UI/Widget.lua` and `Engine/TTO.lua` -- read, never edited (the TBC line must not change).
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

Implemented as specified.

### Files

- **`Engine/ManaModel.lua`** — `ManaModel.Text(state)` reworded to match TBC's
  `Engine/TTO.lua` `GetDisplayString` (lines 349-406, cited in the new comments):
  `fullnow` -> `~FULL`; `ooc`/`full` -> `~FULL <ttf>`; `warmup` -> `~OOM ...`;
  `hold` -> `~OOM --`; `oom` -> `~OOM <t>`, or `~OOM --` when `tto` is nil. Added
  a local `RestSegment(v, rest)` that reproduces TBC line 400's gate verbatim:
  shown when the primary (`v`) is missing, or when
  `abs(rest - v) / max(v, 1) >= 0.25`, joined by two spaces, appended to
  `warmup`/`hold`/`oom` only (never `full`/`fullnow`/`ooc`, matching TBC's "never
  next to a FULL clock", line 378). No client call, no `GetTime`, still pure.
- **`UI/Clock_Forever.lua`** — `UpdateVisibility` gained a module-local `shown`
  flag and now reproduces TBC's `UI/Widget.lua` `MD:UpdateVisibility` hysteresis
  (lines 144-173): out of combat, shows once the pool drops under 90% of max and
  stays shown until it is back over 95%, instead of the old flat "< 95%"
  threshold that redrew at 94.x% (the author's `~refill 0:05` sighting). Still
  the single owner of `Show`/`Hide`; in-combat and "off means off" paths
  unchanged.
- **`tools/clockcheck.lua`** — two new assertions, written first and run to
  confirm they failed against the pre-change code (below), then left in place
  unedited once the implementation passed:
  - "each state is worded as the TBC clock words it, marked modelled"
  - "out of combat the clock appears under 90% and stays until 95%"
  No existing assertion's name or expected value was touched; "times are
  rounded to five seconds and capped at ten minutes" and the `shownWhenLow`
  step of "the clock shows in combat and hides at full out of combat; off means
  off" were confirmed to still pass unedited.

### Tests first: the failing run (before the change)

```
each state is worded as the TBC clock words it, marked modelled          FAIL - a="~full" b="~refill 0:45" c="~OOM --" d="~OOM --" e="~hold" f="~OOM 1:20  rest 1:30" g="~OOM 1:20  rest 2:10"
out of combat the clock appears under 90% and stays until 95%            FAIL - startHidden=true at94=true at89=true at93=true at96=false
13 ok, 2 failed
  FAIL each state is worded as the TBC clock words it, marked modelled - a="~full" b="~refill 0:45" c="~OOM --" d="~OOM --" e="~hold" f="~OOM 1:20  rest 1:30" g="~OOM 1:20  rest 2:10"
  FAIL out of combat the clock appears under 90% and stays until 95% - startHidden=true at94=true at89=true at93=true at96=false
```
(reproduced by temporarily reverting `Engine/ManaModel.lua` and
`UI/Clock_Forever.lua` with `git apply -R` on the diff, running the suite, then
`git apply` to restore -- no working-tree state was left reverted.)

### `bash tools/run.sh tools/clockcheck.lua` (after the change): `15 ok, 0 failed`

```
regen runs at the casting rate for five seconds after a spend, then the base rate ok - at3=150 at8=280
the projection: warmup, then OOM when spending outruns regen, FULL when it does not ok - warm=warmup stillWarm=warmup oom=oom(tto=36523.666666667) full=full(ttf=0)
times are rounded to five seconds and capped at ten minutes              ok - a="~OOM 1:05  rest 2:00" b="~FULL 10:00" c="~FULL >10m"
each state is worded as the TBC clock words it, marked modelled          ok - a="~FULL" b="~FULL 0:45" c="~OOM ...  rest 0:20" d="~OOM ..." e="~OOM --  rest 0:20" f="~OOM 1:20" g="~OOM 1:20  rest 2:10"
the pool starts full at login and says it was assumed                    ok - mana=7009 max=7009 why=assumed full at login
a cast spends its cost from the book, when it succeeds                   ok - before=7009 after=6984
another unit's cast spends nothing                                       ok
a cast with a secret id or an unpriced cost is counted, never guessed    ok - mana 6984->6984 unpriced 0->2
in combat the regen rate is the last one read out of combat              ok - base 69.24->69.24 casting 28.33->28.33
out of combat the pool is anchored at full once regen has had time to fill it ok - before=6719.45(why=test seed) after=7009(why=regen had time to fill it) max=7009
the bar is handed the real pool unread                                   ok - drawOk=true minV=0 sawIt=false
the clock shows in combat and hides at full out of combat; off means off ok - shownInCombat=true hiddenAtFull=true shownWhenLow=true hiddenWhenOff=true stillOffInCombat=true
out of combat the clock appears under 90% and stays until 95%            ok - startHidden=true at94=false at89=true at93=true at96=false
every projection is marked modelled, in the text and the hover           ok - textHalf=true hoverHalf=true
every string the clock renders is ASCII with no bare pipe                ok

-- demonstration: three moments of a scripted fight --
warmup: ~OOM ...  rest 0:00
  SpellTuner mana clock (modelled)
  Mana 7003 / 7009 (modelled - the real pool is secret on this client)
  Anchored 0:02 ago: assumed full at login
  Spend 40.0/s over 1 casts, regen 28.3/s
  The bar under the clock is the real pool, drawn by the game
oom: ~OOM 9:40  rest 0:05
  SpellTuner mana clock (modelled)
  Mana 6770 / 7009 (modelled - the real pool is secret on this client)
  Anchored 0:22 ago: assumed full at login
  Spend 40.0/s over 41 casts, regen 28.3/s
  The bar under the clock is the real pool, drawn by the game
after combat: ~FULL 0:05
  SpellTuner mana clock (modelled)
  Mana 6784 / 7009 (modelled - the real pool is secret on this client)
  Anchored 0:23 ago: assumed full at login
  Regen rate read out of combat
  The bar under the clock is the real pool, drawn by the game

15 ok, 0 failed
```

### Every other suite, tail (all at the lead's 2026-09-28 baseline; none touched)

```
tipcheck        14 ok, 0 failed
spellsui        12 ok, 0 failed
measurecheck     9 ok, 0 failed
probecheck      66 ok, 0 failed
forevercheck    13 ok, 0 failed
modulecheck     12 ok, 0 failed
adaptercheck    19 ok, 0 failed
corecheck       10 ok, 0 failed
svcheck          6 ok, 0 failed
consolecheck    11 ok, 0 failed
```

TBC sixteen (ran for completeness; none touched by this task):

```
simcheck    -> 9 self-tests ok + fixture replay PASS (spend exact 6169 vs 6169)
reccheck    54 ok, 0 failed
replaycheck 80 ok, 0 failed
replayui    98 ok, 0 failed
runcheck    78 ok, 0 failed
reviewui    44 ok, 0 failed
navui       25 ok, 0 failed
dashui      56 ok, 0 failed
regencheck  27 ok, 0 failed
simwindow    8 ok, 0 failed
solvercheck 70 ok, 0 failed
timeline    27 ok, 0 failed
spelltip    48 ok, 0 failed
practice    74 ok, 0 failed
practiceui  49 ok, 0 failed
```

### `python3 tools/apicheck.py`

```
apicheck: 8 Forever TOCs, 21 files, 40 distinct globals, 0 findings (baseline 69893)
```

### `python3 tools/apicheck.py --selftest`

```
FAIL Bad.lua:1 GetSpellInfo not in baseline 69893
FAIL Bad.lua:2 os not in the client's Lua
FAIL Bad.lua:3 UnitHealth client call outside Client/
FAIL Bad.lua:4 NewGlobalName new global
FAIL Bad.lua:5 COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT_UNFILTERED named
FAIL Bad.lua:6 C_Spell.NoSuchMember C_ member not in baseline 69893
FAIL Fixture_Mainline.toc:6 Gone.lua missing file
selftest: 7 of 7 findings as expected
```

### `luac -p` (`tools/.lua/lua-5.1.5/src/luac -p`)

```
$ luac -p Engine/ManaModel.lua UI/Clock_Forever.lua tools/clockcheck.lua
LUAC_OK (no output -- clean)
```

### `git status --short` (end of task)

```
 M Engine/ManaModel.lua
 M UI/Clock_Forever.lua
 M tools/bookcheck.lua
 M tools/clockcheck.lua
 M tools/data/parse-fixture.lua
 M tools/parsecheck.lua
?? docs/tasks/T10c-pane-layout.md
?? docs/tasks/T11b-clock-modes.md
?? docs/tasks/T12b-measure-attribution.md
?? docs/tasks/T13b-probe-m3-items.md
?? docs/tasks/T7b-shapes-gate.md
```
`tools/bookcheck.lua`, `tools/parsecheck.lua` and `tools/data/parse-fixture.lua`
are being edited concurrently by another implementer (T7b) and were not
touched by this task.

### Skipped / out of scope

Nothing in this task's Files list was skipped. Did not touch `Engine/TTO.lua`
or `UI/Widget.lua` (TBC, read-only reference per Out of scope), `Spells/Book.lua`,
`Spells/Parse.lua`, `Spells/Measure.lua`, `Client/Probe.lua`, or
`tools/wowstub.lua` (other implementers' tasks).

### Question

None. Facts held, acceptance met exactly as written.

## Review (lead, 2026-09-28)

Read the diff whole. `ManaModel.Text` words every mode as `Engine/TTO.lua` does with the `~` kept;
the rest segment follows TBC's 25% rule and appears only in the three in-combat modes; the model
stays pure. `UpdateVisibility` is still the single owner, with the 90/95 hysteresis in one local
flag. Reran clockcheck `15 ok`, spellsui 12, tipcheck 14, dashui 56, apicheck 0, luac clean.
Accepted as is.
