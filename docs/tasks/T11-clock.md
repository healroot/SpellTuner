# T11 — the mana clock on Forever: a modelled pool, and it says so

Status: **done -- lead-accepted 2026-09-28** (see the Review at the end). M2 (`docs/ROADMAP-FOREVER.md` §2), task line "T11 clock (TTO) on the
adapter". Needs T7 (`MD.Book`, for a cast's cost).

## Goal

A small movable widget -- the Forever counterpart of the TBC clock -- that projects time to OOM
in combat and time to full out of it, from a **modelled** mana pool: the plain maximum, minus the
cost of every own cast at the moment it succeeds, plus regen under the five-second rule at the
rate last read out of combat. It never pretends to the TBC clock's precision: every projection is
marked modelled (`~`), rounded to 5 seconds, and its hover says where the pool was last anchored,
what it did not price, and that the real pool is secret. Beside the text, a thin bar draws the
**real** mana, handed to the status bar by the adapter without anyone reading it, so the author can
see the model drift by eye. On by default; `/st clock` toggles, `/st clock lock` locks, and a
checkbox sits in Settings -> General. For any mana user.

## Facts

- `UnitPower("player", 0)` is **secret always** -- in and out of combat, solo (sixth report,
  `== readings now`; `FOREVER-PLAN.md` §1.2); `UnitPowerMax("player", 0)` is plain in and out of
  combat (275 at level 8, 304 at level 9, eighth report). `GetManaRegen()` is plain out of combat
  (8.0, 11.5, 11.75) and **secret in combat, both returns** (seventh report). So the clock runs on
  a modelled pool (`FOREVER-PLAN.md` §2.5): the regen rate is the last out-of-combat reading, and
  the pool is anchored at full whenever out-of-combat regen has had time to fill it.
- A secret value may be passed to `StatusBar:SetValue` (`FOREVER-PLAN.md` §1.2, from
  warcraft.wiki.gg's "Secret values"); arithmetic, comparison, `#`, indexing and table-key use raise.
  **UNVERIFIED on this client** -- T12 has the author look at the bar.
- Own casts: `UNIT_SPELLCAST_SUCCEEDED` registers (first report); whether its spell id is readable
  in combat is UNKNOWN (T7a counts it). The cost comes from `MD.Book` (`entry.cost.amount`), else
  from `MD.API.SpellPowerCost(id)`'s mana entry (T7's copy binding); a cost that is a percentage of
  base mana only, or unreadable, is **not priced** and is counted.
- The five-second rule: mana regen runs at the casting rate (`GetManaRegen`'s second return) for
  5 s after a mana spend and at the base rate (first return) after -- vanilla's rule, the TBC clock's
  (`Engine/RegenModel.lua`). Forever's in-combat Spirit talents raise the casting rate
  (`REFERENCES-FOREVER.md` §4); the client's own `GetManaRegen` carries them, which is why the rate
  is read, not computed.
- The TBC clock's text shape and its rules (`CLAUDE.md` file table, `Engine/TTO.lua`): `OOM 1:20 v
  rest 2:10`, `FULL 0:45`; ASCII only, never a bare `|`; never `v or 0` -- a missing value renders
  `--`. The TBC files are not reused (they call the client directly and read `UnitPower`).
- `type()` of a secret does not raise and may answer the underlying type -- a secret number can read
  `"number"` (`tools/wowstub.lua` header, from EllesmereUI; T9 Review). So "a plain number" means
  `not MD.API.IsSecret(v) and type(v) == "number"`, in that order, for every event argument.
- Drinks, potions, Innervate and mana from others are invisible to the model (auras are secret in
  combat, and out of combat the model has no mana reading to compare with) -- the drift the plan
  accepts (`FOREVER-PLAN.md` §2.5).

## Files

| file | change | role |
|---|---|---|
| `Client/API.lua` | `MD.API.DrawUnitPower(bar, unit, powerType)` | hands the real pool to a status bar unread |
| `Engine/ManaModel.lua` | new, pure (no client call, no `MD.API` call) | the pool and the projection |
| `UI/Clock_Forever.lua` | new | events, the ticker, the widget, the hover |
| `UI/Dashboard_Forever.lua` | Settings -> General gains "Show the mana clock" | settings |
| `Core_Forever.lua` | `clock = { shown = true, locked = false, point = nil }` in `MD.DEFAULTS`; `/st clock`, `/st clock lock` | defaults, commands |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `Engine\ManaModel.lua` after `Spells\Book.lua`; `UI\Clock_Forever.lua` after `UI\SpellTip_Forever.lua` | TOCs |
| `tools/wowstub.lua` | forever profile: `UNIT_SPELLCAST_SUCCEEDED` fired by `S.Cast(id)` helper for `"player"`; a StatusBar that records what `SetValue` / `SetMinMaxValues` received | stub |
| `tools/clockcheck.lua` | new suite (forever) | the clock |

### `MD.API.DrawUnitPower(bar, unit, powerType)` (shared)

Calls the client's `UnitPowerMax` and `UnitPower` (through `Has`, under one `pcall`) and passes the
raw results to `bar:SetMinMaxValues(0, max)` and `bar:SetValue(cur)` **without inspecting either**
(no `IsSecret`, no comparison, no arithmetic). Returns true when both calls and both setters ran,
else `false, "absent" | "error"`. This is the one sanctioned path for a secret to leave the adapter,
and it leaves only into a widget; comment it so.

### `MD.ManaModel` (pure)

`ManaModel.New()` -> a model with, at least: `max`, `mana`, `base`, `casting` (rates per second,
nil until set), `lastSpend` (time), `fight` (`{ start, spent, casts, fsrTime }` while in combat),
`anchor = { at, why }`, `unpriced` (count this fight), and methods:
- `SetMax(max)` (a plain number; the pool scales with it only when it grows, capped at max);
- `SetRegen(base, casting)` (plain numbers only);
- `Advance(t)`: integrate regen from the last `Advance` to `t` -- casting rate while
  `t < lastSpend + 5`, base after, split exactly at the boundary; clamp to `[0, max]`; accumulate
  `fight.fsrTime` in combat;
- `Spend(cost, t)`: `Advance(t)`, subtract, `lastSpend = t`, count the cast in the fight;
  `Unpriced(t)`: `Advance(t)`, count it, **no** spend and **no** five-second restart (the model does
  not know the cast cost mana);
- `Anchor(t, mana, why)`; `StartFight(t)`, `EndFight(t)`;
- `Project(t)` -> a state: `mode` `"warmup" | "oom" | "full" | "hold" | "ooc" | "fullnow"`, `tto`,
  `ttf`, `rest`, `spend` (fight spend per second), `regen` (duty-weighted: the fight's share of time
  inside the five-second rule times `casting`, the rest times `base`), `mana`, `max`, `unpriced`,
  `anchor`. In combat: warmup until 3 priced casts and 10 s; then `net = spend - regen`: `oom` when
  `net > 0` (`tto = mana / net`), `full` when `net < 0` (`ttf = (max - mana) / -net`), else
  `hold`. Out of combat: `fullnow` at `mana >= max`, else `ooc` with `ttf` = the time to full at
  zero spend (five-second-rule aware, as `Engine/TTO.lua`'s `RestTime`). `rest` = that same time
  to full, in combat too. A rate that is nil makes every time that depends on it nil.
- `ManaModel.Text(state)` -> `~OOM 1:20  rest 2:10`, `~FULL 0:45`, `~hold`, `~OOM --` (warmup or
  a nil time), `~full` (fullnow), `~refill 0:40` (ooc). Times rounded to the nearest 5 s, shown as
  `m:ss`; above 600 s `>10m`. ASCII, no pipe.

### The clock (`UI/Clock_Forever.lua`)

- At `MD_READY`: a model; `SetMax` from `MD.API.UnitPowerMax("player", 0)` when plain;
  `SetRegen` from `MD.API.ManaRegen()` when both returns are plain; `Anchor(now, max, "assumed full at login")`.
- `UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)`: only `unit == "player"`; a plain numeric id
  with a known mana amount -> `Spend`; anything else -> `Unpriced`.
- `PLAYER_REGEN_DISABLED` / `ENABLED` -> `StartFight` / `EndFight`.
- Every master tick (`MD:OnTick`): `SetMax` when plain; out of combat `SetRegen` when both returns
  are plain; `Advance(now)`; out of combat, when `max` and `base > 0` and `now - lastSpend >= max / base`
  and the pool is below max, `Anchor(now, max, "regen had time to fill it")`; then paint.
- The widget: a `BackdropTemplate` frame styled with `MD.UI`, one font string (the text), a thin
  StatusBar under it drawn by `MD.API.DrawUnitPower(bar, "player", 0)` each tick. Movable while
  unlocked, its point saved in `db.clock.point`. **Visibility has one owner**, a local
  `UpdateVisibility()`: hidden when `db.clock.shown` is false; else shown in combat, and out of
  combat while the modelled pool is below 95% of max, hidden once it reaches max.
- The hover (GameTooltip): `SpellTuner mana clock (modelled)`; `Mana 812 / 1200 (modelled - the
  real pool is secret on this client)`; `Anchored <m:ss> ago: <why>`; `Spend 12.3/s over N casts,
  regen 3.1/s` (in combat); `Regen rate read out of combat` ; `Unpriced casts: N` when N > 0; `The
  bar under the clock is the real pool, drawn by the game`.

## Rules

- **No client call and no client-table indexing outside `Client/`.** `Engine/ManaModel.lua` calls
  nothing at all (no `MD.API`, no `GetTime` -- times are arguments).
- Every number the clock does arithmetic on came plain from `MD.API` or from the model. A secret
  goes only into `DrawUnitPower`.
- Visibility has one owner. Any frame styled needs `BackdropTemplate`.
- ASCII only, no bare `|`; a nil time renders `--`, never 0.
- No new global; no library; the multi-return trap (`ManaRegen()` returns two values -- write the
  `if` out).
- Tests first: `tools/clockcheck.lua` before the code; say which assertions failed.
- Comments say why, not what.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `bash tools/run.sh tools/clockcheck.lua` ends `13 ok, 0 failed`. Names verbatim:
   1. "the pool starts full at login and says it was assumed"
   2. "a cast spends its cost from the book, when it succeeds"
   3. "regen runs at the casting rate for five seconds after a spend, then the base rate" (exact
      numbers across the boundary, derived in a comment)
   4. "in combat the regen rate is the last one read out of combat"
   5. "out of combat the pool is anchored at full once regen has had time to fill it"
   6. "the projection: warmup, then OOM when spending outruns regen, FULL when it does not"
   7. "every projection is marked modelled, in the text and the hover"
   8. "a cast with a secret id or an unpriced cost is counted, never guessed"
   9. "the bar is handed the real pool unread" (the stub bar received a secret value from
      `DrawUnitPower`; nothing raised; `DrawUnitPower` never called `issecretvalue` on it)
   10. "another unit's cast spends nothing"
   11. "the clock shows in combat and hides at full out of combat; off means off"
   12. "times are rounded to five seconds and capped at ten minutes"
   13. "every string the clock renders is ASCII with no bare pipe"
2. `adaptercheck` 18/14 plus one new assertion, both flavours, "DrawUnitPower hands the values over
   without reading them" -> 19/15. Every other suite at its count after T9 (say them).
3. `python3 tools/apicheck.py` 0 findings; `--selftest` 7 of 7; the two Forever TOCs differ on the
   marker only.
4. `luac -p` clean on every file touched.
5. Paste into the Report: failing run first; clockcheck in full; the widget's text and hover lines
   at three moments of a scripted fight (warmup, OOM, after combat); every other tail; apicheck;
   luac; `git status --short`.

## Out of scope

- `Engine/TTO.lua`, `Engine/RegenModel.lua`, `Engine/SpendTracker.lua`, `UI/Widget.lua` and every
  TBC file. The advisor, drinks, potions, Innervate (M3 or later).
- The dashboard (T10) -- it will read `MD.Clock`'s model for casts to OOM; expose the model as
  `MD.Clock.model` and a `MD.Clock:Pool()` returning `{ max, mana, regenCasting }` for it.
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

Implemented as specified. Tests first: `tools/clockcheck.lua` was written and run before any of
`Engine/ManaModel.lua`/`UI/Clock_Forever.lua` existed. Its failing run:

```
/home/.../tools/clockcheck.lua:53: attempt to index local 'ManaModel' (a nil value)
stack traceback:
	...clockcheck.lua:53: in main chunk
	[C]: ?
```

File by file:

- **`Client/API.lua`**: added `MD.API.DrawUnitPower(bar, unit, powerType)`. Fetches
  `UnitPowerMax`/`UnitPower` through `Has` (cached, classifies only the *function*, never the
  return) and calls both directly inside one `pcall`, handing the raw results straight to
  `bar:SetMinMaxValues(0, max)` / `bar:SetValue(cur)`. Deliberately bypasses `MD.API.Call`, which
  would run `IsSecret` over every return value -- the one thing this function must never do to the
  mana reading. Not recorded in `MD.API._bindings` (same as `AddonVersion`/`Print`): it is not a
  single dotted-path proxy, so it does not appear in `Capabilities()` and is not swept up by
  `adaptercheck`'s existing "every binding" / "no secret leaves" loops, which call every
  capability with a bare `"player"` argument and would break on a function whose first argument is
  a bar.

- **`Engine/ManaModel.lua`** (new, pure): `ManaModel.New()`, `SetMax`, `SetRegen`, `Advance`,
  `Spend`, `Unpriced`, `Anchor`, `StartFight`, `EndFight`, `Project`, `ManaModel.Text`. No client
  call, no `MD.API` call, no `GetTime` -- every timestamp is an argument, checked with `luac -p`
  and by inspection. `Project`'s one judgment call, not spelled out verbatim in the task: when a
  fight is past warmup but `regen` is still `nil` (no out-of-combat reading has ever landed), the
  mode is `"hold"` rather than a guessed direction -- consistent with "a rate that is nil makes
  every time that depends on it nil" and never exercised by the client's own defaults (which always
  hand back a regen pair before combat), noted here in case that reading is wrong.

- **`UI/Clock_Forever.lua`** (new): the model at `MD_READY`, `CostFor(id)` (reuses `MD.Book:Get()`
  and falls back to `MD.Book:ReadSpell(id)`, so the percent-only/free/absent cases come straight
  from T7's own `ResolveCost` rather than being re-derived here), the `UNIT_SPELLCAST_SUCCEEDED`
  handler (`not MD.API.IsSecret(v) and type(v) == "number"`, in that order, for both `unit` and
  `spellID` -- the T9 Review's lesson applied to this task's own two event arguments),
  `PLAYER_REGEN_DISABLED`/`ENABLED` -> `StartFight`/`EndFight`, the master-tick handler (`SetMax`;
  out-of-combat `SetRegen`; `Advance`; the out-of-combat "regen had time to fill it" `Anchor`
  check; paint), the widget (`BackdropTemplate`, `UI.StylizeFrame`, draggable while unlocked,
  point saved to `db.clock.point`), `UpdateVisibility` as the widget's one show/hide owner, and the
  hover built directly on `GameTooltip` (the tooltip frame's own methods are the widget toolkit,
  same reasoning `UI/SpellTip_Forever.lua` already uses). Exposes `MD.Clock.model` and
  `MD.Clock:Pool()` for T10, plus `MD.Clock.frame`/`MD.Clock.text`/`MD.Clock:Refresh()` for the
  settings checkbox, `/st clock` and this task's own suite.

- **`Core_Forever.lua`**: `clock = { shown = true, locked = false, point = nil }` added to
  `MD.DEFAULTS`; `/st clock` toggles `shown`, `/st clock lock` toggles `locked`, both refresh the
  widget at once if it exists yet.

- **`UI/Dashboard_Forever.lua`**: Settings -> General gained a second checkbox, "Show the mana
  clock", wired to `MD.db.clock.shown` and `MD.Clock:Refresh()`; `RefreshGeneralPane` updates it
  too. `pane.clockCheck` marks it for the test harness, the same convention `pane.tooltipCheck`
  already uses.

- **`SpellTuner.toc`, `SpellTuner_Mainline.toc`**: `Engine\ManaModel.lua` added right after
  `Spells\Book.lua`; `UI\Clock_Forever.lua` added right after `UI\SpellTip_Forever.lua`. The two
  TOCs still differ only on the marker line.

- **`tools/wowstub.lua`**: added `S.Cast(id, unit)` inside `S.UseProfile("forever")` -- fires
  `UNIT_SPELLCAST_SUCCEEDED(unit or "player", "cast-guid", id)`, so a suite can hand it a plain id
  or `S.Secret()` either way (Facts: whether the id is readable in combat is UNKNOWN). No separate
  "StatusBar" stub was needed: `CreateFrame`'s existing generic frame already records whatever
  `SetValue`/`SetMinMaxValues` receive (including a secret, since storing a value in a table field
  is not one of the operations the stub's secret stand-in raises on), which `tools/clockcheck.lua`
  item 9 relies on directly.

- **`tools/adaptercheck.lua`**: one new assertion, shared (both flavours), right after the
  Copy/Constant/copying-binding section: `"DrawUnitPower hands the values over without reading
  them"` -- a fresh `StatusBar`, `MD.API.DrawUnitPower(bar, "player", 0)` returns `true`, and the
  bar's `minV`/`maxV`/`value` were all set (never compared or inspected further, since on Forever
  `value` may be secret).

- **`tools/clockcheck.lua`** (new, forever only): 13 assertions, names verbatim (see run below).
  Items 3, 6, 7 (text half), 12 are unit tests against a bare `MD.ManaModel.New()` instance (no
  stub needed at all, since the file is pure); items 1, 2, 4, 5, 8, 9, 10, 11, 7 (hover half), 13
  drive the real `MD.Clock` through the harness's own login and `S.Fire`/`S.Cast`/`S.Tick`. Item 5
  ("out of combat ... once regen has had time to fill it") is worth spelling out: `GetManaRegen`'s
  stub defaults are base=69.24 > casting=28.33 (Facts' ordering -- the *casting* rate, active only
  in the five-second rule right after a spend, is the *slower* one; the *base* rate, active
  afterward, is faster), so a plain integral from empty genuinely finishes a few seconds *after*
  the conservative `max/base` bound the tick handler's gate uses -- the test drains the model to 0,
  seeds `lastSpend` in the past (no live FSR window), and checks that mana is still short of max at
  `max/base - 1` and pinned to `max` immediately once that bound is crossed, with `anchor.why`
  updated to say so.

Full `clockcheck` run:

```
regen runs at the casting rate for five seconds after a spend, then the base rate ok - at3=150 at8=280
the projection: warmup, then OOM when spending outruns regen, FULL when it does not ok - warm=warmup stillWarm=warmup oom=oom(tto=36523.666666667) full=full(ttf=0)
times are rounded to five seconds and capped at ten minutes              ok - a="~OOM 1:05  rest 2:00" b="~FULL 10:00" c="~FULL >10m"
the pool starts full at login and says it was assumed                    ok - mana=7009 max=7009 why=assumed full at login
a cast spends its cost from the book, when it succeeds                   ok - before=7009 after=6984
another unit's cast spends nothing                                       ok
a cast with a secret id or an unpriced cost is counted, never guessed    ok - mana 6984->6984 unpriced 0->2
in combat the regen rate is the last one read out of combat              ok - base 69.24->69.24 casting 28.33->28.33
out of combat the pool is anchored at full once regen has had time to fill it ok - before=6719.45(why=test seed) after=7009(why=regen had time to fill it) max=7009
the bar is handed the real pool unread                                   ok - drawOk=true minV=0 sawIt=false
the clock shows in combat and hides at full out of combat; off means off ok - shownInCombat=true hiddenAtFull=true shownWhenLow=true hiddenWhenOff=true stillOffInCombat=true
every projection is marked modelled, in the text and the hover           ok - textHalf=true hoverHalf=true
every string the clock renders is ASCII with no bare pipe                ok

-- demonstration: three moments of a scripted fight --
warmup: ~OOM --
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
after combat: ~refill 0:05
  SpellTuner mana clock (modelled)
  Mana 6784 / 7009 (modelled - the real pool is secret on this client)
  Anchored 0:23 ago: assumed full at login
  Regen rate read out of combat
  The bar under the clock is the real pool, drawn by the game

13 ok, 0 failed
```

Every other suite, at today's counts (all unaffected suites reran to confirm no regression):
`bookcheck` 14 (T9's own `ReadSpell` addition, unchanged by this task), `adaptercheck` 19/15
(18/14 plus the one new shared `DrawUnitPower` assertion), `parsecheck` 10, `probecheck` 66,
`forevercheck` 13, `modulecheck` 12, `tipcheck` 12, `corecheck` 10/8, `svcheck` 6/1, `consolecheck`
11/1, `simcheck` PASS, `reccheck` 54, `replaycheck` 80, `replayui` 98, `regencheck` 27, `spelltip`
48, `navui` 25 -- all exactly as before.

`adaptercheck` tails:
```
(forever) ... no secret ever leaves the adapter                              ok
19 ok, 0 failed
(tbc)     ... the add-on bindings are the classic globals on TBC              ok
15 ok, 0 failed
```

`python3 tools/apicheck.py`: `apicheck: 8 Forever TOCs, 19 files, 40 distinct globals, 0 findings
(baseline 69893)`. `--selftest`: `selftest: 7 of 7 findings as expected`. `SpellTuner.toc` /
`SpellTuner_Mainline.toc` diff to exactly the marker line (`Client\TOC_Plain.lua` vs
`Client\TOC_Mainline.lua`).

`luac -p` clean on every touched file: `Client/API.lua`, `Core_Forever.lua`,
`Engine/ManaModel.lua`, `UI/Clock_Forever.lua`, `UI/Dashboard_Forever.lua`, `tools/adaptercheck.lua`,
`tools/wowstub.lua`, `tools/clockcheck.lua`.

`git status --short`:
```
 M Client/API.lua
 M Core_Forever.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M UI/Dashboard_Forever.lua
 M tools/adaptercheck.lua
 M tools/wowstub.lua
?? Engine/ManaModel.lua
?? UI/Clock_Forever.lua
?? tools/clockcheck.lua
```
(`docs/tasks/T10-spells-pane.md`, `docs/tasks/T12-measure.md` and this file predate/accompany this
session's assignment and were not otherwise touched; no commits made.)

### Questions / things worth the lead's eye

- The `Project` "hold when past warmup but `regen` is still nil" rule above is my own
  interpretation of "never guessed" applied to a case the task's Facts/Rules do not name outright
  (only "a rate that is nil makes every time that depends on it nil" is stated) -- flagging it
  rather than guessing quietly.
- The hover's "Anchored `<m:ss>` ago" line is *not* run through the 5-second-rounding/10-minute-cap
  rule that `ManaModel.Text` applies to projections -- it is an elapsed time, not a projected one,
  and the task's rounding rule reads as being about the projection text specifically. Said here in
  case that reading is too narrow.
- `MD.Clock.frame`/`MD.Clock.text` are exposed beyond what the task's Files table lists (only
  `MD.Clock.model` and `MD.Clock:Pool()` are named for T10) -- needed for `tools/clockcheck.lua` to
  drive the widget's visibility and read its rendered text/hover without reaching into
  `UI/Clock_Forever.lua`'s locals. Not otherwise used by any other file.

### Out of scope, untouched

`Engine/TTO.lua`, `Engine/RegenModel.lua`, `Engine/SpendTracker.lua`, `UI/Widget.lua`, every TBC
file, the dashboard (T10), the advisor/drinks/potions/Innervate. `CLAUDE.md` and every `docs/`
file except this Report. No commits made.

## Review (lead, 2026-09-28)

Accepted. Reran: clockcheck `13 ok` (its pre-code failure is in the Report), adaptercheck 19/15,
bookcheck 14, tipcheck 12, parsecheck 10, probecheck 66, modulecheck 12, every TBC suite at its
count, apicheck 0 (19 files), TOCs marker-only. `Engine/ManaModel.lua` calls nothing; the clock
checks `IsSecret` before comparing the unit and before using the id; `DrawUnitPower` hands the two
raw values to the bar under one `pcall` and reads neither.

**One line changed by the lead:** a cast whose cost read as free (`costState == "free"`, cost 0)
went through `Spend(0, now)`, which restarted the five-second rule and counted as a priced cast
toward the warmup gate. A free cast spends no mana, so it restarts nothing: the handler now calls
`Spend` only when `cost > 0`.

Both judgement calls stand: past warmup with no regen reading yet the mode is `hold` (no direction
can be judged, and `~hold` says nothing false); the hover's "Anchored m:ss ago" is an elapsed time,
not a projection, and is shown to the second.
