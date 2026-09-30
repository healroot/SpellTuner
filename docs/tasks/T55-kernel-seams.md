# T55 -- Kernel seams (plan P11)

Status: **built** 2026-09-30 on branch `plan/P11` (base `fecaad4`), wave 4 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P11)

Review items (`docs/review/2026-09-30-project-review.md`): A4 (fault isolation), A9 (the
definitions), A3 (the defaults mechanism), A28 (the combat flag), A16 (`MD:Provide`).

All in `Core.lua`; the consumers move in P14, P16, P18, P20 and P23.

- `MD.Text = { Esc, EscASCII, EscKeepColours }` -- pipe-doubling and the probe's reversible escape
  named apart -- and `MD:PrintSafe(line)`.
- `MD.Util` (`Median` copying, `Clock`, `K`, `RECORD_GATE = { sec = 20, casts = 5 }`) and
  `MD.Rules.SUGGESTED_FLOOR`. GCD and the crit multiplier are not defined (plan section 6).
- `MD:RegisterDefaults(tbl)` (merges before login, back-fills `MD.db` after) and `MD:Setting(key)`.
- `MD.inCombat`, set by the two regen events and seeded at `MD_READY` through
  `MD.API.UnitAffectingCombat`.
- `MD:Provide(name, fn)` raising on a second provider; `MD:ModuleStateText(name)`.
- **A4:** `MD:On`'s and `MD:Fire`'s loops call each handler as `xpcall(handler, MD.ErrorSink, ...)`,
  `MD.ErrorSink` calling whatever `geterrorhandler()` answers at that moment. Arguments in the client's
  form (the stub's `xpcall` passes them since P1); a stub micro-benchmark decides per-handler against
  per-event isolation for the combat log; R21/R22 proven again under the new dispatch.

Owned files (section 4, wave 4): `Core.lua`, `tools/corecheck.lua`, `tools/consolecheck.lua`. Nothing
else was touched.

## What was built

| file | change |
|---|---|
| `Core.lua` | **A4:** one local `Dispatch(list, ...)` runs both loops (`OnEvent` and `MD:Fire`): `xpcall(list[i], ErrorSink, ...)` per handler. `MD.ErrorSink(msg)` asks `MD.API.GetErrorHandler()` at the moment of the error and **tail-calls** it (`return h(msg)`), so no frame of ours sits between the installed handler and the code that raised. With no handler at all (only an offline stub lacks `geterrorhandler`) the sink returns a private marker, the message rides in an upvalue read the instant `xpcall` returns (Lua 5.1's `xpcall` hands back only the sink's first return), and the loop raises it with `error(msg, 0)` after every handler ran -- so a suite still goes red on a raising handler. **A28:** `MD.inCombat = false` at load; `PLAYER_REGEN_DISABLED` / `_ENABLED` handlers registered here, first, so every other handler of those events already reads the new value; an `MD_READY` callback (the first registered) seeds it from `MD.API.UnitAffectingCombat("player")` -- an answer (`value, nil`) sets it (`true` or `1` is in combat), an unreadable one (`nil, "absent"/"error"/"secret"`) leaves it. **A9:** `MD.Text.Esc` (pipe-doubling), `MD.Text.EscASCII` (backslash doubled, pipe doubled, non-printable byte `\ddd`), `MD.Text.EscKeepColours` (EscASCII around kept `\|cXXXXXXXX` / `\|r`, exactly Commands_Forever's), each taking any value (`nil` -> `""`, a secret -> `<secret>`, else `tostring`); `MD:PrintSafe(line)` = `MD:Print(EscKeepColours(line))`; `MD.Util.Median(t, mode)` (copies; even count averages the middle two, `"low"` takes the lower -- PullBudget's choice), `MD.Util.Clock(sec, tenths)` (`m:ss` / `m:ss.t`, negative is 0), `MD.Util.K(n, from)` (`from` default 1000, the Waste view's 10000 passable; below it the rounded whole number), `MD.Util.RECORD_GATE`, `MD.Rules.SUGGESTED_FLOOR = 0.4`; `MD:ModuleStateText(name)` (UI/Dashboard_Forever.lua's and UI/Dump_Forever.lua's copy, word for word). **A3:** `MD:RegisterDefaults(tbl)` -- raises when a key already registered or already in `MD.DEFAULTS` would get a *different* value (one owner per default; nested tables compared key by key), else fills a private `registered` table, `MD.DEFAULTS` if it exists, and `MD.db` if login already ran, never overwriting; `InitDB` fills `MD.DEFAULTS` and then the db from `registered` too. `MD:Setting(key)`: the db value (a stored `false` is an answer), else the registered default, else `MD.DEFAULTS'`. **A16:** `MD:Provide(name, fn)` -- a dotted name walks existing tables (`"FightRecorder.Pin"`), a missing table on the way raises, anything already at the seam raises `a second provider for MD.<name>`. |
| `tools/corecheck.lua` | +9 under both flavours (below). |
| `tools/consolecheck.lua` | +3 under forever, in cases 14-15's session (below). |

Nothing reads any of the new names yet except the combat flag's own handlers; no consumer moved.

### The new assertions

`corecheck` (both flavours):

1. **a raising MD:On handler stops nothing and reaches the handler once (A4)** -- two `UNIT_COMBAT`
   handlers, the first raising (armed only for this firing); `geterrorhandler` swapped for a counter
   through `MD.API.Invalidate`. `S.Fire` does not raise, the second handler ran, the counter saw the
   message exactly once.
2. **a raising MD:Fire callback stops nothing and reaches the handler once (A4)** -- the same for two
   callbacks.
3. **with no error handler the loop re-raises after every handler ran (A4)** -- `geterrorhandler`
   removed: `MD:Fire` raises the handler's own message, and the second callback ran first.
4. **RegisterDefaults after login back-fills and never overwrites (A3)** -- a user value (`"user"`, and
   a stored `false`) kept against a registered default, a new key and a nested table filled; the same
   value registered again is fine; a different value (flat or nested) raises naming the key;
   `MD:Setting` answers the registered default once the db value is gone, and the stored `false`.
5. **MD.inCombat seeded from the adapter, flipped by the regen events (A28)** -- `UnitAffectingCombat`
   answering `true` -> `MD:Fire("MD_READY")` sets it; a raising `UnitAffectingCombat` leaves it;
   `PLAYER_REGEN_ENABLED` / `_DISABLED` flip it.
6. **Provide fills a seam once and refuses a second provider (A16)** -- plain and dotted names; the
   second provider raises naming the seam; a missing table on the path raises.
7. **MD.Text: Esc doubles pipes, EscASCII is the probe's escape (A9)** -- `a|b` -> `a||b` both ways;
   `Penek` + `\195\169`: kept by `Esc`, `\195\169` as text by `EscASCII`; a backslash doubled; `nil`
   and a number.
8. **PrintSafe keeps a well-formed colour code and escapes the rest (A9)** -- `|cff888888grey|r a|b
   <e-acute> |cffzz` prints as `|cff888888grey|r a||b \195\169 ||cffzz` after the prefix.
9. **MD.Util: Median copies, Clock and K format (A9)** -- median 2.5 / low 2 of `{5,1,3,2}` with the
   list untouched; `1:15`, `1:15.2`, `0:00`; `2.3k`, `2345` under a 10000 threshold, `1000`;
   `RECORD_GATE`; `SUGGESTED_FLOOR`.

`consolecheck` (forever; cases 19-21, the session of cases 14-15, the capture installed):

19. **a handler raising inside MD:On is named by its own line (A4, R22)** -- a `UNIT_COMBAT` handler
    raising `Interface/AddOns/SpellTuner/Dispatched.lua:3: ...` fired twice through `S3.Fire`: the
    captured entry's stack line is `consolecheck.lua:<the raising line>:`, carries no `Core.lua`, no
    `API.lua`, no `[C]`, and its count is 2.
20. **the previous handler gets a dispatched error exactly once (A4, R21)** -- over the two firings
    `S3.clientErrors` holds the message once, neither firing raised, and the handler after the raising
    one ran both times.
21. **a handler under xpcall receives the event's arguments (A4)** -- `n == 5`, `"player", "HEAL", "",
    120, 1`.

The tail call is what 19 holds down: with `return h(msg)` mutated to `local r = h(msg); return r`,
19 fails with the sink's own line
(`.../Core.lua:71: in function <.../Core.lua:68> count=2`), 19 ok / 1 failed. Restored.

## The cost measurement (A4 point 2)

`os.clock`, 1e6 dispatches of one handler, Lua 5.1.5 built by `tools/run.sh` (the script:
a bare loop, Lua's own `xpcall` with no arguments -- the C cost the client's `xpcall` has -- and the
stub's argument-passing shim):

```
bare loop, no args                       0.055 s  0.055 us/dispatch
bare loop, 3 args                        0.058 s  0.058 us/dispatch
Lua xpcall, no args (client's C cost)    0.141 s  0.141 us/dispatch
stub xpcall shim, 3 args                 0.369 s  0.369 us/dispatch
overhead of the protected call itself: 0.085 us/dispatch
overhead of the stub's shim with 3 args: 0.311 us/dispatch
```

0.085 us per dispatch is under the plan's 1 us bound, so **every** event -- the TBC combat log
included (`COMBAT_LOG_EVENT_UNFILTERED` -> one handler in `UI/Summary.lua`, no event arguments, so
exactly the "no args" row) -- is isolated per handler. The shim's closure and table are the stub's
only (the client's `xpcall` passes arguments in C); even so it stays under 1 us. No trampoline was
needed: both clients are expected to pass the arguments (plan section 9 check 5 confirms it in game;
if either does not, the plan's fallback is a fixed-arity trampoline in `Dispatch` alone).

## Tests first (on the parent's Core.lua, only the tests changed)

The parent's `Core.lua` (`git show fecaad4:Core.lua`) with this branch's two suites, all rc 1:

```
== corecheck/forever rc=1
a raising MD:On handler stops nothing and reaches the handler once (A4)  FAIL - fired=false second=false seen=0
a raising MD:Fire callback stops nothing and reaches the handler once (A4) FAIL - fired=false second=false seen=0
with no error handler the loop re-raises after every handler ran (A4)    FAIL - fired=false err=corecheck: raised in MD:Fire
RegisterDefaults after login back-fills and never overwrites (A3)        FAIL - raised: .../tools/corecheck.lua:280: attempt to call method 'RegisterDefaults' (a nil value)
MD.inCombat seeded from the adapter, flipped by the regen events (A28)   FAIL - seeded=false kept=false end=false start=false
Provide fills a seam once and refuses a second provider (A16)            FAIL - raised: .../tools/corecheck.lua:335: attempt to call method 'Provide' (a nil value)
MD.Text: Esc doubles pipes, EscASCII is the probe's escape (A9)          FAIL - raised: .../tools/corecheck.lua:353: attempt to index local 'T' (a nil value)
PrintSafe keeps a well-formed colour code and escapes the rest (A9)      FAIL - raised: .../tools/corecheck.lua:364: attempt to call method 'PrintSafe' (a nil value)
MD.Util: Median copies, Clock and K format (A9)                          FAIL - raised: .../tools/corecheck.lua:374: attempt to index local 'U' (a nil value)
13 ok, 9 failed
== corecheck/tbc rc=1
(the same nine lines)
13 ok, 9 failed
== consolecheck/forever rc=1
a handler raising inside MD:On is named by its own line (A4, R22)        FAIL - nil count=nil
the previous handler gets a dispatched error exactly once (A4, R21)      FAIL - forwarded=0 fired=false/false after=0
18 ok, 2 failed
```

(Case 3 on the parent: the loop raised, but at the first handler -- the second never ran. Case 21
passes on the parent, whose bare loop passes the arguments; it pins that the `xpcall` form keeps
them.) After the change: `corecheck` 22 / 22, `consolecheck` 20 / 1, all rc 0.

## Suites (exit codes checked; the loop in docs/TOOLS.md section 1)

| suite | before (fecaad4) | after |
|---|---|---|
| `corecheck` forever / tbc | 13 / 13 | **22 / 22** |
| `consolecheck` forever / tbc | 17 / 1 | **20 / 1** |
| every other suite | simcheck 13, reccheck 63, replaycheck 82, replayui 103, runcheck 81, reviewui 48, navui 35, dashui 64, regencheck 27, simwindow 8, solvercheck 84, restcheck 51, timeline 27, spelltip 48, costcheck 3, practice 81, practiceui 52, migrate 7, probecheck 87, forevercheck 16, modulecheck 14, kitcheck 7, recordcheck 29, scenariocheck 14, gatecheck 9, replayforever 15, reviewforever 13, coachforever 20, practiceforever 27, bindscheck 6, parsecheck 15, bookcheck 21, tipcheck 37, clockcheck 23, spellsui 48, measurecheck 30, releasecheck 16, importcheck 20, themecheck 23, tabscheck 24, wincheck 55, adaptercheck 23 / 16, svcheck 6 / 1 | all equal, all rc 0 |
| `simcheck` FAIL lines | 0 | 0 |
| `apicheck.py` / `--selftest` | 0 findings / 10 of 10 | same (47 distinct globals, was 46: `xpcall`, `error` and `math` are now touched by `Core.lua`, Lua's own) |
| `textcheck.py` / `--selftest` | 0 findings / 2 of 2 | same |
| `refcheck.py --selftest` | 2 of 2 | same |

`luac -p` passes on `Core.lua`, `tools/corecheck.lua`, `tools/consolecheck.lua`.

**Output, not only counts.** The parent tree (`git archive fecaad4`) and this branch were each run
through every suite above (except `releasecheck`) under every flavour it declares, and their full
outputs diffed, the tree's path normalised. 36 of the 48 outputs are byte-identical, among them the TBC list
of plan section 2 -- `dashui`, `navui`, `practiceui`, `replaycheck`, `simcheck`, `runcheck`,
`regencheck`, `spelltip`, `consolecheck` (tbc), `simwindow`, `restcheck`, `importcheck`. Apart from
`corecheck` and `consolecheck` (forever), the others differ only in lines that differ between two
runs of the parent itself: table and function addresses (`coachforever`, `kitcheck`,
`practiceforever`, `recordcheck`, `replayforever`, `solvercheck`), `N ms` (`reccheck`, `replayui`,
`reviewui`) and the coach's time-sliced search (`search N evaluations` and the order in which two
concurrent searches print `search done`, `replayui` / `reviewui` -- four runs of the parent's
`replayui` show both orders).

**No error went quiet.** Under the forever profile a raising handler now lands in the stub's default
error handler (`S.clientErrors`, via Core_Forever's capture) instead of stopping the suite. To prove
no suite now hides one, `tools/wowstub.lua`'s default handler was patched locally to write every
message to stderr and every suite was run under every flavour it declares: only `consolecheck`
(forever) wrote any -- its own deliberate errors. The patch was reverted (the stub is P10's file).

## TBC

`Core.lua` is shared. Only A4 changes behaviour, and only when a handler raises: the handlers after it
still run, and the error reaches the client's handler (or BugGrabber) once, as before. The client's
handler now runs under our `xpcall` rather than the client's own script call; the frame between is a
tail call, which Lua shows as one `(tail call)` line -- the same shape Core_Forever's forward (R21)
already has. `MD.inCombat` is set but read by nothing on either line until P14. No look, recorder
format or model rule changed.

## Integrator lines

**docs/DECISIONS.md** (one line, new section after T52's):

> ## A raising event handler no longer stops the others (2026-09-30, T55)
>
> `Core.lua` runs every `MD:On` handler and every `MD:Fire` callback as `xpcall(handler, MD.ErrorSink,
> ...)`; the sink tail-calls whatever `geterrorhandler()` answers then, so the error still reaches
> BugGrabber, Forever's capture or the client's own handler once, and the handlers after the raising
> one still run (review A4: one raise in an early `PLAYER_REGEN_ENABLED` handler used to stop the
> recorder closing its stream, the clock re-anchoring and the run recorder seeing the pull). Both lines;
> a change only when a handler raises. Measured cost 0.085 us per handler per event, so the combat log
> is isolated per handler too.

**CLAUDE.md**, `Core.lua` row, append before the closing ` |`:

` **T55 (P11):** every `MD:On` handler and `MD:Fire` callback under `xpcall` with `MD.ErrorSink` (a tail call into whatever `geterrorhandler()` answers; with none, the loop re-raises after every handler ran) -- one raise no longer stops the rest (A4); the seams, defined here and adopted by later tasks: `MD.Text` (`Esc` pipe-doubling, `EscASCII` the probe's reversible escape, `EscKeepColours`) and `MD:PrintSafe`, `MD.Util` (`Median` copying, `Clock`, `K`, `RECORD_GATE`), `MD.Rules.SUGGESTED_FLOOR` (A9); `MD:RegisterDefaults` (a different second default raises) and `MD:Setting` (A3); `MD.inCombat` (the regen events, seeded at `MD_READY` through the adapter, A28); `MD:Provide` (a second provider raises, A16); `MD:ModuleStateText``

**docs/TOOLS.md** section 1:

- `corecheck.lua` row, append: `Since **T55** (22 / 22): a raising handler stops neither `MD:On`'s nor
  `MD:Fire`'s loop and reaches the error handler once; with no error handler the loop re-raises after
  every handler ran (A4); `RegisterDefaults` after login back-fills without overwriting and refuses a
  different second default (A3); `MD.inCombat` seeded from the adapter and flipped by the regen events
  (A28); `Provide` refuses a second provider (A16); `MD.Text`, `PrintSafe`, `MD.Util` (A9)`.
- `consolecheck.lua` row, append: `Since **T55** (20 / 1): a handler raising inside `MD:On` under the
  capture is named by its own line (no `Core.lua`, `API.lua` or `[C]`), reaches the previous handler
  once over two firings, and received the event's arguments (A4, R21, R22)`.

**docs/TESTING.md**: item 5 of the plan's section 9 (**`xpcall` passes arguments (P11)**,
`/run print(xpcall(function(a, b) return a + b end, print, 2, 3))` on TBC and on Forever, expected
`true 5` on both), as written there. If either client prints anything else, A4 needs the plan's
fixed-arity trampoline before that client ships this change.

**tools/data/expected-counts.json** (when P13 creates it): `corecheck` 22 forever / 22 tbc,
`consolecheck` 20 forever / 1 tbc.

No TOC changes.

## Deviations

- **corecheck +9, not +7.** The plan's seven are all here (cases 1, 2, 4-8). Two more: case 3 (with no
  error handler at all the loop re-raises after every handler ran -- the rule that keeps a suite honest
  when the stub has no `geterrorhandler`, the TBC stub's case) and case 9 (`MD.Util` and
  `MD.Rules`, defined by this task and otherwise untested until their consumers move).
- **A no-handler fallback the plan does not name.** The plan's sink "calls whatever
  `geterrorhandler()` answers". When nothing answers (the TBC stub has no `geterrorhandler`; the client
  always has one) the error is re-raised after the loop instead of being dropped, so no TBC suite can
  turn green by swallowing a raise.
- **`MD:RegisterDefaults` refuses a conflicting second default.** The plan says "merges before login,
  back-fills after"; merging silently would keep A3's drift (two lists, two numbers) possible, so a
  key registered twice with a different value raises, the same rule as `MD:Provide`. The same value
  registered twice is accepted (P20 moves copies one at a time).
- **`MD.Util.Median(t, "low")` and `MD.Util.K(n, from)`.** The copies disagree (PullBudget takes the
  lower middle, RunRecorder averages; K's threshold is 1000 in five files and 10000 in the Waste view),
  so the shared helpers take the difference as an argument, letting P14 and P16 move each copy without
  changing what it prints.
- **For P10 / P13 (not this task's files):** under the forever profile the stub's default error handler
  records a message silently in `S.clientErrors`. Before this task a raising handler stopped the suite;
  now it is sunk there. No suite hides one today (measured above), but a suite could start to. A check
  that fails a run whose `S.clientErrors` is non-empty outside `consolecheck` (in `tools/check.sh`, P13,
  or the stub, P10) would close it.
