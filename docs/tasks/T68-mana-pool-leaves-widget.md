# T68 -- The mana pool leaves the widget (plan P24)

Status: **built** 2026-09-30 on branch `plan/P24` (base `e0454fc`), wave 10 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. **The branch needs its TOC lines (below)**:
`UI/Clock_Forever.lua` now paints `MD.Pool`, which the new `Engine/ManaPool_Forever.lua` publishes, and
both clocks ask `MD.Visibility`, which the new `UI/Visibility.lua` publishes. Without the lines the
Forever core raises at login and 15 runs fail on the committed tree (`clockcheck`, `corecheck`,
`importcheck`, `measurecheck`, `modulecheck`, `practiceforever`, `probecheck/tbc`, `recordcheck`,
`recordingscheck`, `replayforever`, `reviewforever`, `spellsui`, `tipcheck`, `wincheck` -- checked).
The TOC lines were applied in the working tree only, to run the suites, and reverted before the
commit (the T56 / T63 / T65 / T66 pattern).

## The task (docs/PLAN-refactor-ux.md section 5, P24)

Review item (`docs/review/2026-09-30-project-review.md`): **A29** -- "two clocks share one spec
written as line-number citations; the mana model is owned by a widget". `UI/Clock_Forever.lua` owned
the model instance, the pricing, the events and the assume-full rule; `Recorder_Forever.lua` read
`MD.Clock.model.mana/.base/.casting`, so a v3 recording's mana track depended on a widget's private
field; `Book._lastRegenCasting` was the same pattern the other way; the 90/95 hysteresis existed
twice; `Engine/ManaModel.lua` and the clock cited `TTO.lua` / `Widget.lua` by line numbers that were
already wrong.

- `Engine/ManaPool_Forever.lua` (`MD.Pool`): the model instance, the cast/regen events, `CostFor`, the
  assume-full rule, `Sample()` (`mana, base, casting, max`), `Pool()`, `Project(now)`.
- `UI/Clock_Forever.lua` paints; `MD.Clock:Pool()` stays as an alias.
- `Recorder_Forever` samples `MD.Pool:Sample()` (no more `MD.Clock.model`).
- `Book:DefaultPool`'s cached regen reading moves to the pool.
- One pure `MD.Visibility.Want(pct, shown, inCombat, unlocked)` (`UI/Visibility.lua`, both TOCs)
  used by `Widget.UpdateVisibility` and the clock.
- The line-number citations in `ManaModel` become function names.
- Tests: `clockcheck` repointed (equal count) and +1 (a cast priced with no clock frame built);
  `recordcheck` (the mana track unchanged on the fixture); equal counts `regencheck`, `reccheck`,
  `spellsui`, `tipcheck`.
- TBC: `Widget.lua` calls a pure function with the same thresholds; no change.

Owned files (section 4, wave 10): `UI/Clock_Forever.lua`, new `Engine/ManaPool_Forever.lua`,
`Recorder/Recorder_Forever.lua`, `UI/Widget.lua`, new `UI/Visibility.lua`, `Spells/Book.lua`,
`tools/clockcheck.lua`, `tools/recordcheck.lua`. All committed, plus `Engine/ManaModel.lua` (comments
only) and one load-list line in `tools/ttocheck.lua` -- see Deviations 1 and 2.

## What was built

| file | change |
|---|---|
| `Engine/ManaPool_Forever.lua` (new, Forever) | `MD.Pool`. `Pool.model` (nil until `MD_READY`, a fresh `MD.ManaModel.New()` at each one). **`Pool.CostFor(id)`** -- the clock's lookup moved verbatim (the book's entry, else `Book:ReadSpell` under `pcall`; `costState == "free"` is 0; a percentage or unreadable cost is nil = unpriced). **`Pool:Sample()`** -> `mana, base, casting, max` (nothing before `MD_READY`). **`Pool:Pool()`** -> `{ max, mana, regenCasting }` (`{}` before `MD_READY`, as `MD.Clock:Pool()` answered). **`Pool:Project(now)`**. **`Pool:LastRegen()`** -> the base / casting rates last read plain. The handlers moved from the clock unchanged: `MD_READY` (max, regen, "assumed full at login", a fight started when the kernel's `MD.inCombat` says so -- R36/R37), `UNIT_SPELLCAST_SUCCEEDED` (IsSecret before every comparison, a free cast spends nothing, else unpriced), `PLAYER_REGEN_DISABLED` / `_ENABLED` (StartFight with B19's opener, EndFight), and the tick (max, out-of-combat regen, `Advance`, the assume-full rule "regen had time to fill it"). No widget, no frame. |
| `UI/Visibility.lua` (new, both TOCs) | `MD.Visibility.Want(pct, shown, inCombat, unlocked)`, pure: unlocked -> true; in combat -> true; `pct` not a number -> false; shown -> `pct <= HIDE_ABOVE` (0.95); else `pct < SHOW_BELOW` (0.90). The thresholds are fields (`Visibility.SHOW_BELOW`, `HIDE_ABOVE`). |
| `UI/Clock_Forever.lua` | Paints only: 299 -> 205 lines. The model, `CostFor`, the four event handlers and the tick's model work are gone; its `MD_READY` builds the widget, its tick paints (`MD.Pool:Project`), the hover reads `MD.Pool.model`. `UpdateVisibility` keeps the one Show/Hide owner and asks `MD.Visibility.Want(pct, shown, MD.inCombat, false)` (pct nil when there is no max yet). `MD.Clock:Pool()` returns `MD.Pool:Pool()`; **`MD.Clock.model`** is kept as a live alias of `MD.Pool.model` through `MD.Clock`'s metatable (read at every access, so a `/reload`'s new model is never stale). The line-number citation of `Widget.lua` is gone. |
| `UI/Widget.lua` (TBC) | `MD:UpdateVisibility` asks `MD.Visibility.Want(pct, shown, MD.inCombat, unlocked)` with `unlocked = not db.locked or preview`; `EnableMouse`, the `usesMana` refusal, `UnitPower` read only when locked and out of combat, and `pct = 1` when max is 0 are as before; the Show/Hide still happens only on a change. |
| `Spells/Book.lua` | `Book:DefaultPool`: a plain `ManaRegen()` casting rate is used as before; when it is secret (in combat) the fallback is **`MD.Pool:LastRegen()`**'s casting rate (the pool reads regen at login and every out-of-combat tick). `Book._lastRegenCasting` is gone. |
| `Modules/SpellTuner_Recorder/Recorder_Forever.lua` | The 2 s mana sample is `MD.Pool:Sample()` (mana, base, casting); the pull's starting mana is `(MD.Pool:Sample())`; its **copy of `CostFor` is gone** -- `CostFor(id)` calls `MD.Pool.CostFor(id)` (the pool is on the base Forever TOC, which the module always has). No `MD.Clock` left in the module. |
| `Engine/ManaModel.lua` | Comments only: `RestSegment` and `ManaModel.Text` cite TBC's `MD:GetDisplayString` (`Engine/TTO.lua`) by its branches and its "Secondary segment" block instead of line numbers (which had already drifted: the mode branches cited at 349-376 start at 352 today, the rest test cited at 397-403 is at 403). |
| `tools/clockcheck.lua` | Repointed: every `Clock.model` is `MD.Pool.model`; the frame, text, bar and hover checks still read `MD.Clock`. **+1**: a second copy of the core (API, kernel, parse, rank rules, book, model, pool -- no `UI/Clock_Forever.lua`, so no clock frame can be built) gets its own `MD_READY` and prices a Rejuvenation cast from its pool (7009 -> 6984), `Sample()` and `Pool()` agreeing, `MD.Clock` absent. |
| `tools/recordcheck.lua` | The R8 opener check reads the pool's mana (`E.MD.Pool:Sample()`). Check 7 (the mana track) is pinned to the fixture's track as the parent recorded it -- starting mana 7009, 20 samples, 6872.33 / 6928.99 first, 7009 by the fourth, base 69.24 / casting 28.33 -- with its label and detail unchanged, so the output does not move (count equal, 31). |
| `tools/ttocheck.lua` | Its hand-written load list adds `UI/Visibility.lua` before `UI/Widget.lua` (the suite loads the widget itself; count equal, 45). |

`grep -n "MD.Clock" Modules/ Engine/ Spells/` finds nothing; the remaining readers of `MD.Clock:Pool()`
(`UI/SpellsPane_Forever.lua`, `UI/SpellTip_Forever.lua`, owned by P25 this wave) and of `MD.Clock.model`
(`tools/spellsui.lua`, `tools/tipcheck.lua`) go through the aliases unchanged.

## Tests first

On the parent (`e0454fc`), the new `clockcheck` (repointed + the new assertion):

```
tools/run.sh --flavour forever tools/clockcheck.lua        (exit 1)
the pool starts full at login and says it was assumed                    FAIL - mana=nil max=nil why=nil
lua: tools/clockcheck.lua:170: attempt to index local 'model' (a nil value)
```

and the parent's own `clockcheck` with only the new assertion appended:

```
a cast is priced by the pool with no clock frame built (T68)             FAIL - loaded=false err=...wowstub.lua:1800: load Engine/ManaPool_Forever.lua: cannot open .../Engine/ManaPool_Forever.lua: No such file or directory pool=false clock=false before=nil after=nil why=nil
23 ok, 1 failed
```

On the branch (TOC lines applied): `clockcheck` 24 ok, 0 failed:

```
a cast is priced by the pool with no clock frame built (T68)             ok - loaded=true err=nil pool=true clock=false before=7009 after=6984 why=assumed full at login
```

**Mutations** (each applied alone, then restored):

- the pool's cast handler returning when there is no `MD.Clock` (pricing tied to the widget again):
  `clockcheck` 23 ok, 1 failed (`after=7009`).
- the recorder sampling the 4th return (max) as the mana: `recordcheck` 30 ok, 1 failed (check 7).
- `Visibility.HIDE_ABOVE = 0.97`: `clockcheck` 23 ok, 1 failed (the hysteresis check: `at96=true`).
  `ttocheck` stays green under it -- no suite drives the TBC widget's show/hide (it was not driven
  before either), hence the equivalence run below.

**Mana track** (the plan's `recordcheck` item): the fixture pull's `initial.mana` and all 20 samples
(`t`, `v`, `base`, `cast`) dumped on the parent and on the branch -- identical (`cmp`), and now pinned
by check 7.

**Visibility equivalence** (a scratch script, not committed): the parent's widget decision and clock
decision against the branch's, through `MD.Visibility.Want`, over every combination of locked /
preview / usesMana / in combat / shown, max 0 / 1000 / 7009 and mana in 0.1% steps, plus the clock's
"no max" case: **96096 input combinations, 0 disagreements**.

## Suites (`make check` = `tools/check.sh`, exit codes and footers checked)

Before: `e0454fc`, 67 runs, all passed (62 counted). After: this branch with the TOC lines applied in
the working tree, 67 runs, all passed (62 counted). Every count equal except `clockcheck`:

| suite | before | after |
|---|---|---|
| `clockcheck/forever` | 23 | **24** |
| `recordcheck/forever` / `spellsui/forever` / `tipcheck/forever` / `bookcheck/forever` / `bookcheck/tbc` | 31 / 48 / 38 / 22 / 2 | same |
| `regencheck/tbc` / `reccheck/tbc` / `ttocheck/tbc` / `slashcheck/tbc` | 27 / 63 / 45 / 8 | same |
| every other suite in `tools/data/expected-counts.json` | as expected | same |
| `apicheck` | 0 findings, 8 Forever TOCs, **54** files, 47 globals | 0 findings, 8 Forever TOCs, **56** files, 47 globals |
| `textcheck` | 0 findings, 9 TOCs, **90** files | 0 findings, 9 TOCs, **92** files |
| `releasecheck` (13) | tbc package 61 files, forever 28 | tbc **62**, forever **30** |
| selftests, harness skip, reproduce / strategies smoke | pass | pass |

**Outputs.** Every suite's saved output (`tools/.lua/check/*.out`) before and after, compared with
table addresses, milliseconds and search evaluation counts normalised: identical except
`clockcheck`'s new line and footer, the file counts above, and `simwindow`'s "search completes on a
synthetic fight ok - 6 frames" (5 after), which is frame-sliced on `debugprofilestop()` and varies
between runs of the same tree (three runs on this branch: 6, 6, 5). `recordcheck`, `spellsui`,
`tipcheck`, `bookcheck`, `regencheck`, `reccheck`, `ttocheck`, `measurecheck`, `modulecheck`,
`corecheck` byte-identical after that normalisation.

`luac -p` on every changed file: clean.

## TBC

No behaviour change. `UI/Widget.lua` asks the same thresholds through a pure function (the
equivalence run above: 0 disagreements), with the same `EnableMouse`, the same `UnitPower` reads and
the same change-only Show/Hide; the only new TBC file is `UI/Visibility.lua`, which draws nothing and
registers nothing. `Engine/ManaModel.lua` and `Spells/Book.lua` are Forever-only. No DECISIONS entry
(nothing TBC shows or records moved).

## Integrator lines

**`SpellTuner_Mainline.toc`** and **`SpellTuner.toc`** (identical) -- two new lines right before
`UI\Clock_Forever.lua`:

```
UI\SpellTip_Forever.lua
Engine\ManaPool_Forever.lua
UI\Visibility.lua
UI\Clock_Forever.lua
UI\DebugConsole.lua
```

(`Engine\ManaPool_Forever.lua` sits where the clock's own handlers sat, just before it, not beside
`Engine\ManaModel.lua`: its `MD_READY`, cast, regen and tick handlers then run in the same order
relative to every other file's as the clock's did -- after the Spellbook pane's and the tooltip's,
before the debug console's and the recorder module's -- so nothing that reads the pool in the same
event sees it one step earlier or later than it saw the clock's model. It reads `MD.ManaModel` and
`MD.Book` at run time only.)

**`SpellTuner_TBC.toc`** -- one new line right before `UI\Widget.lua`:

```
UI\SpellTooltip.lua
UI\Visibility.lua
UI\Widget.lua
```

No module TOC changes (the recorder reads `MD.Pool`, which the base TOC loads before any module).

**tools/data/expected-counts.json**: `"clockcheck/forever": 24`. Every other count unchanged.

**CLAUDE.md**, the files table:

- New row after `Engine/ManaModel.lua`'s: `| `Engine/ManaPool_Forever.lua` | **The modelled pool's owner** (T68, P24, review A29; Forever): `MD.Pool` -- the one `Engine/ManaModel.lua` instance (`MD.Pool.model`, made at `MD_READY`), the cast / combat / regen events that move it, `MD.Pool.CostFor(id)` (the book's cost; free = 0; a percentage or unreadable cost unpriced), the assume-full rule, and the readers `Sample()` (`mana, base, casting, max`), `Pool()`, `Project(now)`, `LastRegen()`. The clock paints it, the recorder samples it, `Book:DefaultPool` falls back on its last regen reading. Listed just before `UI/Clock_Forever.lua` so its handlers keep the clock's old place |`
- New row after `UI/Widget.lua`'s: `| `UI/Visibility.lua` | **When a mana clock is on screen** (T68, P24, review A29; both TOCs): `MD.Visibility.Want(pct, shown, inCombat, unlocked)`, pure -- unlocked or in combat shown; out of combat under 90% (`SHOW_BELOW`) to appear, over 95% (`HIDE_ABOVE`) to hide; no reading hidden. Asked by `MD:UpdateVisibility` (TBC) and the Forever clock; each keeps its own Show/Hide |`
- `UI/Clock_Forever.lua` row, append: ` **T68 (P24, review A29):** paints only -- the model, the pricing, the events and the assume-full rule are `Engine/ManaPool_Forever.lua`'s; its visibility asks `MD.Visibility.Want`; `MD.Clock:Pool()` and `MD.Clock.model` are aliases of the pool's`
- `Engine/ManaModel.lua` row, append: ` **T68:** its citations of TBC's `MD:GetDisplayString` name the branch, not a line number; the instance is `MD.Pool`'s`
- `UI/Widget.lua` row, append: ` **T68 (P24):** the 90/95 rule is `MD.Visibility.Want` (`UI/Visibility.lua`), shared with the Forever clock`
- `Spells/Book.lua` row, append: ` **T68 (P24):** `Book:DefaultPool` falls back on `MD.Pool:LastRegen()` when `ManaRegen()` is secret (no `Book._lastRegenCasting`)`
- `Modules/<Name>/` row, after the T13 recorder sentence, append: ` **T68 (P24):** the recorder samples `MD.Pool:Sample()` and prices through `MD.Pool.CostFor` (its copy of the clock's `CostFor` is gone)`
- Conventions: `- **Widget visibility has a single owner** (`MD:UpdateVisibility` in `UI/Widget.lua`) with 90%/95% hysteresis.` -> `- **Widget visibility has a single owner** (`MD:UpdateVisibility` in `UI/Widget.lua`; the Forever clock's own `UpdateVisibility`) with the 90%/95% hysteresis of `MD.Visibility.Want` (`UI/Visibility.lua`).`

**docs/TOOLS.md** section 1:

- `clockcheck.lua` row, append: ` Since **T68** (24): the model is `MD.Pool`'s (the suite drives `MD.Pool.model`), and a second copy of the core without the clock file prices a cast from its pool -- no clock frame needed`
- `recordcheck.lua` row, append: ` Since **T68** (31): the mana track is the pool's (`MD.Pool:Sample()`), pinned to the fixture's values`
- `ttocheck.lua` row: no text change needed (its load list gained `UI/Visibility.lua`).

**docs/DECISIONS.md**: none (a refactor; no TBC-visible change).

## Deviations

1. **`Engine/ManaModel.lua` is edited, comments only.** Section 5's P24 asks for its line-number
   citations to become function names, but section 4's wave-10 table does not list the file. No other
   wave-10 task owns it (P25's list has no engine file), so there is no collision; no code line moved.
2. **`tools/ttocheck.lua` gains one load-list entry** (`UI/Visibility.lua`), also outside the table.
   The suite loads `UI/Widget.lua` by hand, and the widget now asks `MD.Visibility`; without the line
   `ttocheck/tbc` raises at its `MD_READY`. No other wave-10 task owns it; its count and output are
   unchanged.
3. **`MD.Pool:LastRegen()`** is published beside the four readers the plan names -- it is how
   "`Book:DefaultPool`'s cached regen reading moves to the pool". The fallback is now the pool's last
   out-of-combat reading (taken at login and every 0.5 s tick out of combat) instead of the last one
   `DefaultPool` happened to see itself: in combat both are the last plain reading before the pull,
   the pool's never older.
4. **`MD.Clock.model` is kept as a live alias** (a metatable read of `MD.Pool.model`), not only
   `MD.Clock:Pool()`: `tools/spellsui.lua` and `tools/tipcheck.lua` (not owned in wave 10) drive
   `MD.Clock.model` directly. Switching them to `MD.Pool.model` is a one-line follow-up for whoever
   owns them next; then the alias can go.
5. **The recorder's copy of `CostFor` is gone** (`MD.Pool.CostFor`); the plan names only the sample.
   A29 puts `CostFor` in the pool, and the copy's own comment said it was duplicated only because the
   clock was a UI file. Same code, same results (`recordcheck` output identical).
6. **`recordcheck` check 7 is strengthened, not added**: the fixture's mana track is pinned inside the
   existing assertion with its label and detail unchanged, so the count stays 31 and the output does
   not move; the dump-and-compare above is the evidence it was the parent's track.
7. **The `clockcheck` +1 loads a second copy of the core** (eight files) into a fresh table: the
   harness builds the clock at login, so "no clock frame built" in the same process means a copy
   without `UI/Clock_Forever.lua`. It runs last in the suite (its cast also reaches the first copy).
8. **`Want`'s `pct = nil` reads as "hidden"** (the clock's "no max yet"); the widget keeps passing 1
   for a zero max, as it did, so neither caller's answer changes.
9. **The TOC position** of `Engine\ManaPool_Forever.lua` is just before `UI\Clock_Forever.lua`
   rather than next to `Engine\ManaModel.lua` (reason under Integrator lines).
