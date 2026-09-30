# T58 -- One combat flag and a TTO test (plan P14)

Status: **built** 2026-09-30 on branch `plan/P14` (base `a185bfb`), wave 5 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P14)

Review items (`docs/review/2026-09-30-project-review.md`): A28 (the consumers of the combat flag
P11 defined) and A9 (PullBudget's in-place sort).

- `TTO.Compute`, `Widget.UpdateVisibility`, `PullBudget:Lines`, the Advisor's two checks,
  `Core_TBC`'s gear reminder and `Clock_Forever` read `MD.inCombat` (T55, `Core.lua`).
- The TBC stub's `UnitAffectingCombat` / `InCombatLockdown` answer the fired regen events instead of
  `false`; `replayui` drops its adapter patch.
- PullBudget's median stops sorting the caller's table.
- New `tools/ttocheck.lua`: a scripted spend and regen stream through `Compute` and the display latch
  -- warmup -> oom, the confidence gate (digits vs bound), `hold`, the rest segment, the arrow.
- Tests: `ttocheck` new (it cannot fail first; a mutated confidence gate turns it red). Equal counts:
  `regencheck`, `reccheck`, `runcheck`, `clockcheck`, `replayui`.

Owned files (section 4, wave 5): `Engine/TTO.lua`, `UI/Widget.lua`, `Engine/PullBudget.lua`,
`UI/Advisor.lua`, `Core_TBC.lua`, `UI/Clock_Forever.lua`, `tools/wowstub.lua`, new
`tools/ttocheck.lua`, `tools/replayui.lua`. Nothing else was touched (this task file apart).

## What was built

| file | change |
|---|---|
| `Engine/TTO.lua` | `Compute`'s `inCombat` is `MD.inCombat == true` instead of `UnitAffectingCombat("player")`. Nothing else in the file moved; every later `s.inCombat` read (the cooldown projection, the horizon's sigma, the secondary segment, the debug cadence) follows it. |
| `UI/Widget.lua` | `MD:UpdateVisibility`'s in-combat branch is `MD.inCombat` instead of `InCombatLockdown() or UnitAffectingCombat("player")`. Still the single visibility owner; the 90 / 95 hysteresis is untouched. |
| `Engine/PullBudget.lua` | `Median` is `MD.Util.Median(t, "low")` (copies; an even count takes the lower middle, which is what `math.ceil(n / 2)` on the sorted list took, so every value is the same); `PB:Lines` returns `{}` on `MD.inCombat`. |
| `UI/Advisor.lua` | The mana-cooldown alert's gate and the drink reminder's "in combat: re-arm and stop" read `MD.inCombat`. |
| `Core_TBC.lua` | The gear reminder (`PLAYER_EQUIPMENT_CHANGED`) is held back on `MD.inCombat`. |
| `UI/Clock_Forever.lua` | Its own `local inCombat` is gone: the two regen handlers keep only the model's `StartFight` / `EndFight`, `UpdateVisibility`, the hover, the out-of-combat regen read and the assume-full rule read `MD.inCombat`, and `MD_READY` starts the fight when `MD.inCombat` is already true -- Core.lua's own `MD_READY` handler, registered first, seeded it through `MD.API.UnitAffectingCombat` (R36/R37 kept: an unreadable answer leaves it out of combat). |
| `tools/wowstub.lua` | TBC profile: `S.inCombat = false`, `UnitAffectingCombat` / `InCombatLockdown` answer `S.inCombat == true`, and `S.Fire` sets `S.inCombat` on `PLAYER_REGEN_DISABLED` / clears it on `PLAYER_REGEN_ENABLED` **before** the first handler runs (the client's order). A script may also set `S.inCombat` by hand (the client in combat with no event: a `/reload` mid-fight). The Forever profile is unchanged -- its suites set `S.inCombat` by hand around their events and some read secrets under it. Also `FrameMT:CreateAnimationGroup` (an object whose animations take every method as a no-op, `Play` / `Stop` counted in `g.plays` / `g.stops`, kept out of the frame registry): the fallback answered `nil` and `UI/Widget.lua` indexes what it returns, so the widget could not load under the stub. |
| `tools/replayui.lua` | The two `MD.API.UnitAffectingCombat` patches are gone: "refuses to open in combat" and T51's "combat at a pull boundary prints one line in 120 frames and pauses" enter combat with `S.Fire("PLAYER_REGEN_DISABLED")` and leave with `PLAYER_REGEN_ENABLED`. Count unchanged (103). |
| `tools/ttocheck.lua` | New, tbc, 45 assertions (below). |

### `tools/ttocheck.lua`

Loads the TBC harness, then `UI/Style.lua`, `UI/Tooltip.lua`, `UI/Widget.lua` and `UI/Advisor.lua`
(the harness keeps no UI file but `UI/Summary.lua`), handing the widget and the Advisor the
`MD_READY` they missed -- only their own handlers, captured as they register, so no other module's
`MD_READY` runs twice. `GetManaRegen` is scripted (10 / 5 per second, so net ~50/s: a clock of a
minute or two). The stream is real events: one Healing Touch rank 5 (219 mana after the harness's
talents) every 3.5 s through `UNIT_SPELLCAST_SUCCEEDED` priced by `Data/SpellData.lua` and
`UNIT_POWER_UPDATE`, the regen events, the master ticker; nothing in the model is replaced.

1. **The stub and the kernel** (4): out of combat before any event; `PLAYER_REGEN_DISABLED` makes
   `UnitAffectingCombat` and `InCombatLockdown` true and `MD.inCombat` true; `_ENABLED` clears all
   three.
2. **Full, out of combat** (2): `fullnow`, shown `FULL`, no rest segment; the locked widget hidden.
3. **A `/reload` mid-fight** (14): `MD.inCombat` set the way Core's seed sets it, the stub's
   poll left saying "out of combat", so only a reader of the flag passes -- the clock projects in
   combat at once (`warmup`, `OOM ...`), the widget shows at full mana, no pull-budget lines, no gear
   reminder, the Advisor calls Innervate (known, the deficit swallowing it) and that alert -- the
   only one -- pulses the widget, no drink reminder at 14% mana. Flag cleared: the clock leaves
   combat, the gear reminder prints once, the drink reminder fires after 5 s standing still, the
   pull-budget lines are back, and at full again: `FULL`, widget hidden.
4. **The pull budget's median** (2): spends 300, 600, 150, 1200 -> 300 (the lower middle), `n` 4,
   the history's own order untouched.
5. **Warmup -> oom** (9): `warmup` and `OOM ...` with the rest segment (no primary to compare
   against) at the pull; still `warmup` after two priced casts, `oom` on the tick after the third;
   digits with `~` while the estimate is not stable, without it once stable; the rest segment hidden
   within 25% of the clock and, beyond it, exactly the quantized time to full; while casting steadily
   `v` is seen and `^` never.
6. **The confidence gate** (4): `db.oomConfidence` set to half the current `rel` -> not confident,
   `OOM >bound =` on that very tick, and it stays; the gate restored -> the first confident tick still
   shows the bound, the second brings the digits back.
7. **Casting stops** (2): `^` within 15 s; out of the five-second rule `rest = deficit / RM.base`
   exactly.
8. **Hold** (2): regen set to spend + one sigma -> the state is `hold` at once but the display keeps
   `oom` for a tick (better news waits), then `OOM >bound =`.
9. **Full in combat** (1): regen three times spend -> `FULL <time>` with no rest segment beside it.
10. **Bad news at once** (1): regen back down -> `oom` on the very next tick.
11. **Leaving combat** (3): `ooc`, `FULL <time to full>`, no rest segment; the time to full is the
    deficit over the base rate; the widget, below 90%, still shown.
12. Every string shown in section 5: ASCII, no bare pipe (1).

## Tests first

**The parent as it is** (`git archive a185bfb`, this branch's `ttocheck.lua` copied in): rc 1 at load,
before the first assertion -- the parent's stub answers `CreateAnimationGroup` with `nil`:

```
.../UI/Widget.lua:65: attempt to index local 'pulse' (a nil value)
	.../UI/Widget.lua:65: in function 'CreateWidget'
	.../UI/Widget.lua:176: in function 'fn'
	.../tools/ttocheck.lua:60: in main chunk
```

**The parent's shipped files with this branch's stub and suite** (only `tools/wowstub.lua` and
`tools/ttocheck.lua` from this branch): rc 1, every reader that still polls fails the reload case --

```
reload mid-fight: the clock projects in combat at once (warmup)    FAIL - FULL
reload mid-fight: the widget shows at full mana                    FAIL
reload mid-fight: no pull-budget lines in combat                   FAIL
reload mid-fight: no gear reminder in combat                       FAIL
reload mid-fight: the Advisor calls Innervate                      FAIL - 0
reload mid-fight: no drink reminder in combat                      FAIL
39 ok, 6 failed
```

(`...and that alert, the only one, pulses the widget` was made to require the Innervate line too:
in its first form it passed on the parent, where the drink reminder's alert supplied the pulse.)

The branch's first commit (`2977e54`: the stub, the suite and `replayui` only) is exactly that
state: `ttocheck` 39 / 6 failed there; the second (`5d3dcb1`) moves the readers.

**Mutations on this branch** (each reverted):

- The confidence gate, `Engine/TTO.lua` `s.confident = s.rel <= ...` -> `>=` (the plan's named one):
  34 ok, **11 failed** -- `oom: digits with '~' ...` (`OOM >2:00 =  rest 1:10`), `once stable ...`,
  both rest-segment checks, the arrow, all four confidence-gate checks, `casting stops: '^'`, `hold
  is better news`.
- The digits' return latch, `disp.confTicks >= 2` -> `>= 1`: 44 ok, **1 failed** -- `gate restored:
  one confident tick still shows the bound` (`OOM 1:00 =  rest 5:30`).

After: `ttocheck` 45 ok, 0 failed, rc 0.

## Suites (exit codes checked; the loop in docs/TOOLS.md section 1, plus ttocheck)

| suite | before (a185bfb) | after |
|---|---|---|
| `ttocheck` (tbc) | -- | **45** |
| `regencheck`, `reccheck`, `runcheck`, `clockcheck`, `replayui` (the plan's equal counts) | 27, 63, 81, 23, 103 | 27, 63, 81, 23, 103 |
| every other suite | simcheck 13, replaycheck 82, reviewui 48, navui 35, dashui 64, simwindow 8, solvercheck 84, restcheck 51, timeline 27, spelltip 48, costcheck 3, verifycheck 13, practice 81, practiceui 52, migrate 7, probecheck 88, forevercheck 16, modulecheck 14, kitcheck 7, recordcheck 31, scenariocheck 14, gatecheck 9, replayforever 15, reviewforever 13, coachforever 20, practiceforever 28, bindscheck 6, parsecheck 15, bookcheck 21, tipcheck 37, spellsui 48, measurecheck 30, releasecheck 16, importcheck 21, themecheck 23, tabscheck 24, wincheck 55, adaptercheck 23 / 16, corecheck 22 / 22, svcheck 6 / 1, consolecheck 20 / 1 | all equal, all rc 0 |
| `simcheck` FAIL lines | 0 | 0 |
| `apicheck.py` / `--selftest` | 0 findings (47 globals) / 10 of 10 | same |
| `textcheck.py` / `--selftest` | 0 findings / 2 of 2 | same |
| `refcheck.py --selftest` | 2 of 2 | same |

`luac -p` passes on every changed file: `Engine/TTO.lua`, `UI/Widget.lua`, `Engine/PullBudget.lua`,
`UI/Advisor.lua`, `Core_TBC.lua`, `UI/Clock_Forever.lua`, `tools/wowstub.lua`, `tools/ttocheck.lua`,
`tools/replayui.lua`.

**Output, not only counts.** The parent tree and this branch were each run through the TBC suites of
plan section 2 (`dashui`, `navui`, `reviewui`, `replayui`, `practiceui`, `reccheck`, `replaycheck`,
`simcheck`, `runcheck`, `regencheck`, `spelltip`, `consolecheck` tbc, `simwindow`, `restcheck`,
`solvercheck`, `importcheck`) and `clockcheck`, and the outputs diffed. 14 of 17 are byte-identical --
`regencheck`, `reccheck` and `runcheck` among them, although the TTO now believes it is in combat
through their fights (nothing they print reads it). `reviewui` and `solvercheck` differ only in `N ms`,
the coach's time-sliced `search N evaluations` and table addresses (run-to-run noise on the parent
too). `replayui` differs in the same noise plus the log of the two combats it now enters with the real
event: `[combat] pull: ...`, `[combat] end: 0s, spent 0 - too short to record`, `[sim] stream
discarded: ...` -- both under every gate, so no recording, history row or index moves (its count and
every assertion are unchanged).

## TBC

The six TBC readers (the clock, the widget, the pull budget, the Advisor's two checks, the gear
reminder) polled `UnitAffectingCombat` (the widget also `InCombatLockdown`); on the client that poll
and the regen events move together, and after a `/reload` mid-fight the poll already answered "in
combat". So what a TBC player sees does not change: the in-combat projection after a `/reload`
mid-fight (plan section 9 check 16) now comes from the kernel's seed at `MD_READY` instead of a
per-tick poll. What changes is that there is one definition, and that the TBC clock's in-combat path
-- warmup, the confidence latch, hold, the rest segment, the arrow -- runs offline for the first time.
The DECISIONS line below says so. Forever's clock behaves as before (its own seed and flag were the
model for the kernel's).

## Integrator lines

**docs/DECISIONS.md** (one entry, after T55's):

> ## "In combat" is one flag on both lines (2026-09-30, T58)
>
> The TBC mana clock, its widget, the pull budget, the Advisor's two checks, the gear reminder and the
> Forever clock read `MD.inCombat` (Core.lua, T55: the regen events, seeded at `MD_READY` through the
> adapter) instead of each polling `UnitAffectingCombat` or keeping a copy (review A28). On TBC nothing
> visible changes -- the poll already followed the events and already said "in combat" after a
> `/reload` mid-fight; that case now comes from the seed. The offline stub's TBC profile answers the
> regen events, so the clock's in-combat path has a suite (`tools/ttocheck.lua`).

**CLAUDE.md**:

- `Engine/TTO.lua` row, append before the closing ` |`: ` **T58 (P14):** `inCombat` is the kernel's
  `MD.inCombat` (a `/reload` mid-fight projects in combat from the `MD_READY` seed); held offline by
  `tools/ttocheck.lua` (warmup -> oom, the confidence gate and its two-tick latch, hold, full, the rest
  segment's 25% rule, the arrow)`
- `UI/Clock_Forever.lua` row: in the Review sentence, `` `MD_READY` asks `UnitAffectingCombat` through
  the adapter `` becomes `` `MD_READY` starts the fight when the kernel's `MD.inCombat` (seeded through
  the adapter) is already true (T58) ``, and append ` **T58 (P14):** no combat flag of its own -- the
  kernel's `MD.inCombat``.
- `Engine/PullBudget.lua` row, append: ` **T58 (P14):** the median is `MD.Util.Median(t, "low")` (no
  in-place sort); no lines while `MD.inCombat``.
- `UI/Widget.lua` row, append: ` **T58 (P14):** in combat is `MD.inCombat``.
- `tools/` row, after the `tools/probecheck.lua` sentence: ` **`tools/ttocheck.lua`** (T58, tbc): the
  TBC clock through a scripted spend / regen stream -- the stub's TBC profile answers
  `UnitAffectingCombat` / `InCombatLockdown` from the regen events `S.Fire` delivers (or a hand-set
  `S.inCombat`), and `FrameMT:CreateAnimationGroup` exists, so `UI/Widget.lua` loads.`

**docs/TOOLS.md** section 1:

- New row after `regencheck.lua`: `| `ttocheck.lua` | **the TBC mana clock** (T58, tbc, 45): the stub's
  combat state follows the regen events; a `/reload` mid-fight (the kernel's flag set, the poll saying
  no) puts the clock, the widget, the pull budget, the Advisor and the gear reminder in combat; the
  pull budget's lower-middle median; warmup -> oom after three priced casts, `~` until stable, the rest
  segment's 25% rule and value, the arrow; the confidence gate (the bound at once, the digits after two
  confident ticks); hold, full, bad news at once; leaving combat |`
- `replayui.lua` row, append: ` Since **T58** (103): combat entered with `PLAYER_REGEN_DISABLED`, not an
  adapter patch`.
- The loop: `ttocheck` added to the first `for` list (after `regencheck`), or to `check.sh`'s list if
  P13 keeps one.

**docs/TESTING.md**: check 16 of plan section 9 as written there -- "`/reload` mid-fight on TBC: the
clock shows the in-combat projection at once (P14)."

**tools/data/expected-counts.json** (P13's, if it lands first or at the wave's end): `ttocheck` 45 (tbc).
`replayui` stays 103.

No TOC changes (`tools/ttocheck.lua` is not shipped).

## Deviations

- **The stub gained `CreateAnimationGroup`.** Not in the plan; without it `UI/Widget.lua` cannot load
  under the stub, and the widget is one of the readers this task moves. It is the stub's only other
  change and no existing suite calls it (nothing else in the tree creates an animation group).
- **ttocheck holds more than `Compute` and the latch.** It also holds every reader moved here (the
  reload case, section 3) and the pull budget's median, because the named suites (`regencheck`,
  `reccheck`, `runcheck`, `clockcheck`, `replayui`) exercise none of them on TBC: that is the
  assertion that fails on the parent's shipped files, where the plan expected none could.
- **The Forever stub's combat state still does not follow the events.** The plan names the TBC stub.
  Forever suites set `S.inCombat` by hand around their regen events (secrets depend on it); tying it
  to `S.Fire` there is a separate change with its own count checks.
- **The widget's `InCombatLockdown()` read went with the poll.** The flag covers both; on the client
  they agree outside the frame of a transition.
- **Pollers outside P14's files are unchanged**: `Engine/RegenMeasure.lua` (`/md regentest`'s
  refusal, a one-off read), `UI/ReplayWindow.lua` (open and practice refusals), `UI/Windows_Forever.lua`,
  `UI/SpellsPane_Forever.lua`, `UI/BindingsWindow.lua`, `Spells/Measure.lua`,
  `Modules/SpellTuner_Recorder/Recorder_Forever.lua`. And the event-only TBC flags the review's "same
  mid-fight-reload hole" points at -- `Engine/RegenModel.lua`'s `combat.active` (which gates the
  out-of-combat fill estimate and resets the duty cycle at the pull), `Engine/SpendTracker.lua`'s pull
  reset, `UI/Summary.lua` / `Engine/FightRecorder.lua`'s fight lifecycle -- still start out of combat
  after a `/reload` mid-fight; none of them is in wave 5's table. A later task that owns them can read
  `MD.inCombat` (or be handed a synthetic pull at `MD_READY`).
- **The plan's TBC "Yes"** ("a `/reload` mid-fight now starts TBC in combat") is true of the readers
  moved here only in the sense that they now get it from the seed: they already did through the poll
  (section TBC above). The DECISIONS line says that rather than claim a visible fix.
