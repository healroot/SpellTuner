# T12b — /st measure: every amount paired with its own cast, or called ambiguous

Status: **accepted 2026-09-28**. M2 close-out. Evidence: `docs/probe/1.60.1_70009-m2.md` §"`/st measure dump`"
(lines 199-242). Rewrites the attribution half of `Spells/Measure.lua` (T12); the line format and
the verdict words stay.

## Goal

`/st measure` pairs each amount that lands with the cast that caused it -- a direct heal or hit with
its own `UNIT_SPELLCAST_SUCCEEDED` by time, a HoT's or DoT's ticks by their cadence from the
application -- keeps several watches open at once (a Rejuvenation keeps ticking while a Healing
Touch is cast), and **never issues a BELOW verdict on an amount it cannot pin to one cast**: it says
`ambiguous` instead. A damage spell below its text is a possible partial resist, not a BELOW. A heal
below its text on a target not known to be missing that much is not a BELOW either. For the author's
Q10 measurement (`FOREVER-PLAN.md` §6 Q10), where a false BELOW is a false signal.

## Facts

- **The field failures** (m2 lines 203-241, planner's reading 228-242):
  - Rejuvenation R2 (text 48 over 12 sec) credited `12+12+110 ... every 1.9 s`: the 110 is a Healing
    Touch landing, the ticks are 12 each (48 / 4). The next Healing Touch credited `12` (a
    Rejuvenation tick) and called `BELOW range`; the first Healing Touch "nothing landed".
    Reading: a Healing Touch's `UNIT_COMBAT` HEAL can arrive **before or in the same frame as** its
    `UNIT_SPELLCAST_SUCCEEDED` (the 110 fell to the Rejuvenation watch that was still open, and the
    Healing Touch's own watch then saw nothing) -- so a direct amount must be looked for slightly
    **before** the cast event too. UNKNOWN by how much; this task uses 0.3 s.
  - Moonfire R2 (text `11 to 15 ... and then an additional 24 Arcane damage over 12 sec`) reads
    `0 ticks` twice, Rejuvenation R2 once in combat: T12 closes every open watch at the next cast, so
    a DoT/HoT followed by another cast loses all its ticks.
  - Wrath R1 `landed 6` against 15-18: Moonfire R2's tick is exactly 6 (24 / 4) -- a tick that fell
    into Wrath's window after T12 closed the Moonfire watch. It could also be a partial resist
    (vanilla resists spells in 25% steps) -- UNKNOWN which; the measure must not decide.
  - In combat `+heal ?`: `GetSpellBonusHealing()` is not plain in combat (m2 220).
- `UNIT_COMBAT(unit, action, descriptor, amount, school)`: amounts plain on `player` and `target`
  in and out of combat; actions seen `WOUND`, `HEAL`, `MISS`, `RESIST` (`docs/probe/1.60.1_70009.md`
  seventh report lines 824-833). **No spell id.** The same hit arrives once per unit token; this file
  listens to `player` (heals) and `target` (damage) only, as T12 does. What `descriptor` carries for
  a crit or a partial resist is UNKNOWN -- it is printed (escaped) on a damage line below range,
  never relied on.
- HoT and DoT periods: the texts seen give none ("48 over 12 sec"); vanilla's are 3 s for
  Rejuvenation, Moonfire, Entangling Roots and most others, 2 s for some (Insect Swarm) --
  `docs/REFERENCES-FOREVER.md`, not client-measured. So the period is the text's own `period` when
  it states one, else **inferred from the landed ticks** among {3, 2, 1} s (rules below).
- HoTs crit on 70009 (`FOREVER-PLAN.md` §1.1); crit multiplier 1.5 (vanilla, UNVERIFIED -- T9).
- Whether a HEAL amount is gross or effective is UNKNOWN (§6 Q3's open part; the meter counts
  effective). A player's own health is secret (§1.2), so the measure tracks the **known deficit**:
  `+ WOUND` and `- HEAL` amounts on `player` since measuring was switched on, floored at 0. Damage
  taken before the switch is not in it, so the deficit is a lower bound -- conservative for BELOW.
- `PLAYER_TARGET_CHANGED` exists on the retail engine (EllesmereUI's event list does not name it --
  it is not in the stub's `FOREVER_EVENTS` yet); added to the stub here.
- `type()` of a secret may answer `"number"`: `MD.API.IsSecret` first, always (T9 Review).

## Files

| file | change | role |
|---|---|---|
| `Spells/Measure.lua` | the attribution rewrite below; line format and verdict words kept | the instrument |
| `tools/wowstub.lua` | `PLAYER_TARGET_CHANGED` in `FOREVER_EVENTS`; forever profile `S.bonusHealingSecretInCombat` (default false, so no other suite changes): when true, `GetSpellBonusHealing()` returns `S.Secret()` while `S.inCombat` (m2 220) | stub |
| `tools/measurecheck.lua` | fixture changes to items 2-9 listed below; nine new assertions | suite |

### Behaviour

**Events.** Every plain `HEAL` on `player` and `WOUND` on `target` is kept in a per-unit list
`{amount, time, deficitBefore}` for 30 s (the deficit is the player's known deficit just before a
HEAL; `WOUND` on `player` adds to it, `HEAL` on `player` takes from it, floor 0). A secret or
non-number amount or id counts `unreadable` as in T12.

**Watches.** `UNIT_SPELLCAST_SUCCEEDED` (player, plain id, a book entry with a heal or damage part)
opens a watch at `t0 = GetTime()`; several may be open. A cast **no longer closes** other watches,
with one exception: a new cast of the **same family** closes that family's open over-time watch as
`refreshed after <k> ticks` (no verdict on its over part). `PLAYER_TARGET_CHANGED` ends every open
damage watch's over part as `target changed after <k> ticks` (no verdict).

**Windows** (constants at the top of the file, each with its reason):
- direct: heal `[t0 - 0.3, t0 + 1.0]`, damage `[t0 - 0.3, t0 + 2.5]` (projectile travel).
- tick: `t0 + k * P +/- 0.4 s`, `k = 1 .. floor(dur / P)`, and the amount at most
  `perTick * 1.5 + 1` where `perTick = total / floor(dur / P)` (a crit is allowed; a direct heal ten
  times the tick is not a tick).
- A watch closes when `GetTime()` passes its last window's end plus 0.4 s (so a cast just after
  cannot still claim an event from it), checked from `MD:OnTick`.

**Period, when the text has none.** At close, for each `P` in {3, 2, 1}, count the events in the
watch's tick windows for that `P` that satisfy the amount bound; take the `P` with the most; a tie
goes to the larger `P`; fewer than 2 aligned events -> period unknown, and the over part's verdict
is `ambiguous (cadence unknown)`. While a watch is open (for contest checks by other watches), its
windows are the union over all three `P`.

**Contest.** An event is *contested* for watch W when it also lies in another watch's direct window,
or in another watch's tick window (with that watch's amount bound). Other watches are the open ones
and those closed in the last 30 s. Resolution runs in two passes, because a damage window (2.8 s)
always overlaps a 3 s tick: (1) every direct part with exactly one uncontested candidate claims it;
(2) contest is computed again **without** the direct windows of the watches resolved in pass 1, so
their other candidates (a DoT tick that fell inside a Wrath's window) go back to the tick watch.
A watch is resolved once, at its close, against the watches known then; the result is not revised.

**Session.** Switching measuring on clears the event lists, the known deficit and the open watches.

**Verdicts.**
- Direct part: the uncontested candidates in the window. Exactly one -> judged as T12 (`in range`
  / `crit range` / `above` / below, next point). None, but contested ones exist -> `ambiguous:
  <amounts> also fit <other spell names>`. None at all -> `nothing landed`. Two or more uncontested ->
  `ambiguous: <amounts>`.
- Below range, **heal**: `BELOW range` only if the event's `deficitBefore >= text min`; if
  `abs(amount - deficitBefore) <= 1` -> `capped at missing health <d> (amount looks effective)`;
  else `below range, missing health not known (<d> known)`.
- Below range, **damage**: never `BELOW`. If the amount is within +/-1 of 75%, 50% or 25% of a value
  in `[min, max]` -> `below range: partial resist <25|50|75>%?`; else `below range (resist?)`; the
  line adds `descriptor <escaped text>` when the descriptor is a plain string.
- Over part: its aligned uncontested ticks. Any aligned tick contested -> `ambiguous (<n> ticks
  shared with <spell>)`. Else T12's rules (`matches`, `partial`, `above`, crits counted), and
  `BELOW` only when all `floor(dur / P)` ticks arrived; a heal HoT's BELOW additionally needs the
  deficit rule above to hold for its first tick.
- **No verdict string contains `BELOW` except the two cases above.**

**Bonus healing.** Read at cast through the adapter; when not plain, the last plain reading taken
out of combat is used and the parenthesis reads `+heal <B> before combat`; none ever -> `?`.

**Line format** (unchanged otherwise): the over part prints `every <P> s` with the inferred or text
period, `every - s` when unknown. `Measure:Watch()` returns the newest open watch (or nil).

## Rules

- No client call outside `Client/`; every `UNIT_COMBAT` / cast argument through `MD.API.IsSecret`
  then `type` before any comparison.
- ASCII only, no bare `|`; spell names and the descriptor through `Esc`.
- Registers nothing until first switched on (T12). No new global, no library, the multi-return trap.
- Comments say why. Constants carry their provenance (m2 line or "UNVERIFIED").
- Tests first: the nine new assertions written and failing before the rewrite; paste the failing run.
- **Existing assertions:** names and expected strings unchanged. Only these fixture changes are
  allowed, because watches now close at their window's end rather than at the first amount: after
  each item's last event, `S.Tick` past the window (items 2-6); item 5's four ticks fire at 3, 6, 9
  and 12 s after the cast rather than at 0, 3, 6 and 9 (the client's first tick is one period after
  the application; a tick at the cast instant is not a tick); item 4 fires
  `S.Combat("player", "WOUND", 100)` before its cast (so the deficit makes the 30 a genuine BELOW);
  items 7 and 9 no longer "close" with a second `HEAL 48` -- they tick past the window and their
  check becomes the line reading `nothing landed` in addition to their current condition, which is
  read **before** the tick (`Measure:Watch()` non-nil). Say in the Report exactly what changed per
  item.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/measurecheck.lua` ends `18 ok, 0 failed`. New names, verbatim, with the
   fixture each must use (Healing Touch R1 5185 40-55, Rejuvenation R1 774 32 over 12, Wrath R1 5176
   13-16; add Moonfire with `S.AddSpell(8924, "Moonfire", "Rank 2", fn, {cost = 50, level = 10})`,
   text `Burns the enemy for 11 to 15 Arcane damage and then an additional 24 Arcane damage over 12 sec.`):
   10. "a direct heal landing just before its own cast event is paired with it" -- HEAL 48 at t,
       SUCCEEDED at t + 0.1 -> `landed 48 ... in range`.
   11. "a HoT keeps its ticks while another heal is cast, and that heal is not a tick" -- WOUND 200;
       Rejuvenation at 0; HEAL 8 at 3, 6; Healing Touch SUCCEEDED at 6.8 with HEAL 50 at 6.8; HEAL 8 at
       9, 12 -> the Healing Touch line `landed 50 ... in range` and the Rejuvenation line
       `4 ticks 8+8+8+8 = 32 every 3.0 s ... matches`.
   12. "a DoT's ticks on the target are captured through the next casts" -- Moonfire at 0 with
       WOUND 13 at 0; Wrath SUCCEEDED at 4.5 with WOUND 15 at 4.6; WOUND 6 at 3, 6, 9, 12 (the 6 at 6
       lies inside Wrath's window: pass 2 hands it back to Moonfire) -> Moonfire
       `landed 13 ... in range; ... 4 ticks 6+6+6+6 = 24 every 3.0 s ... matches`, Wrath `landed 15`.
   13. "an amount that fits two casts is ambiguous, never BELOW" -- Moonfire at 0 (WOUND 13 at 0),
       Wrath SUCCEEDED at 2.9 and WOUND 6 at 3.0 and nothing else for Wrath -> Wrath's line contains
       `ambiguous` and neither line contains `BELOW`.
   14. "a damage spell below its range is a possible resist, never BELOW" -- Wrath, WOUND 7 alone
       -> `below range: partial resist 50%?`; Wrath, WOUND 3 alone -> `below range (resist?)`.
   15. "a heal below range on a target not known to be missing that much is not BELOW" -- fresh
       session deficit 0 (toggle off/on resets it), Healing Touch, HEAL 30 -> `below range, missing
       health not known (0 known)`.
   16. "a heal equal to the known missing health reads as capped" -- WOUND 20, Healing Touch, HEAL
       20 -> `capped at missing health 20 (amount looks effective)`.
   17. "bonus healing in combat is the last reading from before combat, and says so" -- bonus 12
       out of combat (read by a cast out of combat, or by a `PLAYER_REGEN_DISABLED` handler that reads
       it just before combat -- either is fine, say which), then `S.bonusHealingSecretInCombat = true`,
       enter combat, cast Healing Touch -> `+heal 12
       before combat`.
   18. "a HoT recast on itself ends the first watch as refreshed" -- Rejuvenation at 0, HEAL 8 at 3,
       Rejuvenation again at 4 -> the first line contains `refreshed after 1 ticks` and no verdict word
       (`matches`, `partial`, `BELOW`, `above`).
2. Every other suite at its baseline count (tipcheck 14, spellsui 12, clockcheck 13, bookcheck 14 or
   15 if T7b has landed, parsecheck 10 or 11, probecheck 66, forevercheck 13, modulecheck 12, the TBC
   sixteen; adaptercheck 19/15, corecheck 10/8, svcheck 6/1, consolecheck 11/1).
3. `python3 tools/apicheck.py` 0 findings, `--selftest` 7 of 7.
4. `luac -p` clean on every file touched.
5. Paste into the Report: the failing run; measurecheck in full including its demonstration lines;
   every other tail; apicheck; luac; `git status --short`.

## Out of scope

- The probe, the Book, the parser, the clock, the pane. Recording anything (M3's Recorder module).
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

### Files touched

- **`Spells/Measure.lua`** -- rewritten. Kept `Esc`/`Round`/`ResolveEntry`/`PartOf`/`RankTag`/
  `RecordLine` as before. New design:
  - Several watches open at once (`watches`, a list, not one `watch` upvalue). A cast opens a new
    watch and no longer closes anything except, if a watch of the **same family** (by `entry.name`)
    with an over-time part is still open, that one closes at once as `refreshed after <k> ticks`
    (`FamilyCloseIfSameFamily`). `PLAYER_TARGET_CHANGED` closes every open **damage** watch that has
    an over part the same way, as `target changed after <k> ticks` (`OnTargetChanged`). Both bypass
    the normal over-verdict entirely (`FinishClose(w, now, reasonKind)`); `k` is a raw count of
    events seen on the watch's own unit since it opened (`RawTickCountSoFar`), not a period-based
    count, since the line carries no verdict and does not need one.
  - Every `HEAL` on `player` and `WOUND` on `target` is kept unconditionally in `history.player` /
    `history.target` (`{amount, time, deficitBefore?, descriptor}`), independent of whether any
    watch is open, for 30 s (`PurgeList`). A watch's resolution reads this history back at close
    time, which is what lets a heal that landed *before* its own cast's `UNIT_SPELLCAST_SUCCEEDED`
    (item 10) still pair with it. `WOUND` on `player` is not kept as a pairing candidate, only added
    to `Measure.deficit` (Facts: "+ WOUND ... on player"); `HEAL` on `player` records its
    `deficitBefore` and then subtracts from the deficit, floored at 0.
  - A watch closes only when `GetTime()` passes its own deadline (`ComputeDeadline`: last window end
    + 0.4 s), checked from the existing `MD:OnTick` ticker -- never on the first amount that lands.
  - `ResolveDirect` / `ResolveOver` implement Contest exactly as specified: `OtherWindows(selfW)`
    returns every *other* watch's contest windows -- an **open** watch's direct window (still live)
    and tick windows (union over P in {3,2,1} while its own period is undecided, or its resolved P
    once closed and cached: `w.period`/`w.tickWindows`/`w.critBound`, set only on an ordinary close,
    not a `reasonKind` one); a **closed-within-30s** watch contributes only its tick windows, never
    its direct one (Contest's pass 1/pass 2: "without the direct windows of the watches resolved in
    pass 1" -- once a watch's own close has decided its direct part, that window is permanently gone
    from every later watch's contest, which the natural close-ordering by deadline already gives for
    free: item 12's Wrath closes before Moonfire, so by the time Moonfire resolves, Wrath's direct
    window no longer disputes the tick that fell inside it).
  - Direct verdict: exactly one uncontested candidate -> the old T12 in-range/crit/above ladder, or
    (below min) `BelowHealText` / `BelowDamageText`; zero uncontested but some contested ->
    `ambiguous: <amounts> also fit <names>`; zero candidates at all -> `nothing landed`; two or more
    uncontested -> `ambiguous: <amounts>`.
  - `BelowHealText(min, amount, deficitBefore)`: checked in this order -- `abs(amount-deficitBefore)
    <=1` -> `capped at missing health <d> (amount looks effective)` (checked **first**, independent
    of the gate below, since item 16's 20-vs-20 case has `deficitBefore(20) < min(40)` yet must still
    read "capped"); else `deficitBefore >= min` -> `BELOW range` (the one place this file still
    prints uppercase BELOW for a heal -- item 4, with the deficit primed by a `WOUND` first); else
    `below range, missing health not known (<d> known)`.
  - `BelowDamageText`: the Facts wording ("within +/-1 of 75%, 50% or 25% of a value in [min,max]")
    reads as a **percentage-point** tolerance, not an absolute-amount one -- as the pre-resist value
    v sweeps [min,max], the ratio `100*amount/v` sweeps `[100*amount/max, 100*amount/min]`; a resist
    step p matches when that interval comes within 1 point of p. Verified by hand against item 14's
    own numbers (7 against 13-16 hits 50% dead-center; 3 misses 25% by ~0.9 points) before writing
    the assertion -- an absolute-amount ±1 tolerance would have wrongly matched 3 to 25% as well
    (25%*13=3.25 is within 1 raw unit of 3), which is why the percentage reading is the one that
    survives both examples the task gives.
  - Over resolution (`ResolveOver`): period chosen first, ignoring contest, by raw window+bound count
    for each P in {3,2,1} (ties keep the earlier, larger P for free since PERIODS is already
    descending); fewer than 2 aligned events -> period unknown -> whole over verdict
    `ambiguous (cadence unknown)`, `every - s`. Only once a period is confident is contest checked
    against the aligned ticks; any one contested makes the **whole** over part
    `ambiguous (<n> ticks shared with <name>)` rather than per-tick. `OverTotal(text)` prefers
    `text.over` over `Parse.Total(text)` -- **a bug fix scoped to this task**: `Parse.Total` sums the
    direct average *and* the over amount, which is right for a pure HoT (Rejuvenation) but wrong for
    a hybrid direct+over spell like Moonfire (11-15 direct, 24 over) -- using `Parse.Total` there
    would compare the four 6-damage ticks (sum 24) against 13+24=37 and call it BELOW, breaking items
    12 and 13's own numbers.
  - `ParenText`: bonus healing not plain -> the last plain reading is cached (`Measure.lastBonus`,
    updated whenever a cast reads it plainly) and shown as `+heal <B> before combat`; never read
    plainly at all -> `?`. Read at the next cast out of combat (the simpler of the two options Facts
    offers; no `PLAYER_REGEN_DISABLED` handler was added).
  - Session: `Measure:Toggle()` turning on clears `watches`, `closedRecent`, both history lists and
    `Measure.deficit` (not `Measure.lastBonus`, which is not one of the three named in Behaviour).
  - Known simplification, not exercised by the nine assertions: `RawTickCountSoFar` (used only by
    the `refreshed`/`target changed` line) counts every event on the watch's own unit in its
    lifetime, not just ones that pass a period/bound check, and does not itself carry the family name
    forward into future contest checks (a `reasonKind` close never caches `w.period`/`w.tickWindows`).
    The heal-HoT-BELOW "deficit rule on its first tick" (spec's last Over-verdict clause) is
    implemented (`OverVerdictText`'s heal branch) but not exercised by any of the nine fixtures
    (Rejuvenation always resolves "matches" in this file); flagged here rather than guessed silently.

- **`tools/wowstub.lua`** -- two small, local additions inside `S.UseProfile("forever")`, re-read
  immediately before each edit per the shared-file rule:
  - `PLAYER_TARGET_CHANGED = true` added to `FOREVER_EVENTS`.
  - `S.bonusHealingSecretInCombat = false` (new field, set right after `S.descShift = 0`) and
    `GetSpellBonusHealing()` (previously `return S.bonusHealing`) now returns `S.Secret()` when both
    that flag and `S.inCombat` are true, else `S.bonusHealing` as before -- default `false`, so every
    other suite is unaffected (confirmed: all sixteen TBC suites and every other Forever suite still
    pass at their prior counts, `adaptercheck`/`corecheck`/`svcheck`/`consolecheck` unaffected since
    they run under the TBC profile too and this change lives entirely inside the forever branch).

- **`tools/measurecheck.lua`** -- fixture rewritten for items 2-9, nine new assertions (10-18) added,
  per-item changes exactly as the task's Rules bullet names them:
  - Items 2, 3, 6: unchanged events, `S.Tick(2)`/`S.Tick(4)` added after the last event to cross the
    watch's own deadline before reading `LastLine()` (previously the watch closed on the first
    direct amount).
  - Item 4: now fires `S.Combat("player", "WOUND", 100)` before the cast, so `deficitBefore=100 >=
    min(40)` and `HEAL 30` reads a genuine `BELOW range` rather than the new "missing health not
    known" text a bare 0-deficit would give.
  - Item 5: the four ticks now fire at 3, 6, 9, 12 s after the cast (via `S.Tick(3)` before each),
    not 0, 3, 6, 9 -- the client's first tick is one period after application, matching the task's
    instruction verbatim.
  - Items 7, 9: no longer close the watch with a second real `HEAL 48`. Both now read
    `Measure:Watch() ~= nil` right after the stray/secret event (proving the watch is still open,
    not resolved early), then `S.Tick(2)` past its own window and additionally check the resulting
    line reads `nothing landed`.
  - Item 8 (dump): untouched.
  - New helpers `Mark()`/`LinesSince(mark)`/`FindContaining`/`FindStarting` -- items 11, 12 and 13
    have two watches closing at different, ticker-driven times, so the relevant lines are no longer
    reliably "the last line"; they are read back from everything printed since the item started.
    `FindStarting` anchors on the line's own opening text (`"Moonfire R2"`, `"Wrath R1"`) rather than
    a bare substring, because a Wrath `ambiguous: ... also fit Moonfire` line also contains the
    literal text "Moonfire" and a naive substring search picked the wrong line for item 13 on first
    run (caught by hand-inspecting the captured `moonfire=`/`wrath=` detail strings before trusting
    the assertion, then fixed).
  - Item 10-18 timings are documented inline as comments; item 12/13's exact interleaving (Moonfire's
    tick at t=6 falling inside Wrath's direct window, Wrath resolving first because its deadline is
    earlier, handing the tick back to Moonfire once Wrath is closed) is spelled out in the item's own
    comment.
  - `S.AddSpell(8924, "Moonfire", "Rank 2", ..., { cost = 50, level = 10 })` added once, right after
    item 9, with the exact description text the acceptance section names.

### Tests-first run (before the rewrite)

Ran the new `tools/measurecheck.lua` against the **old** (git `HEAD`) `Spells/Measure.lua` to
confirm the nine new assertions fail and nothing else regresses by design intent:

```
9 ok, 9 failed
  FAIL events on another unit are not counted - ... (pre-existing item 7 also failed: old code closed on the
      first real amount, so ticking past the window landed on a *different* watch's line)
  FAIL a HoT keeps its ticks while another heal is cast, and that heal is not a tick
  FAIL a DoT's ticks on the target are captured through the next casts
  FAIL an amount that fits two casts is ambiguous, never BELOW
  FAIL a damage spell below its range is a possible resist, never BELOW
  FAIL a heal below range on a target not known to be missing that much is not BELOW
  FAIL a heal equal to the known missing health reads as capped
  FAIL bonus healing in combat is the last reading from before combat, and says so
  FAIL a HoT recast on itself ends the first watch as refreshed
```

(Item 7's *old* code additionally failed under the new fixture, expected: the old file never kept a
watch open through a deadline at all. It reappears at the top of the failure count as
`events on another unit are not counted` was also structurally new in shape, but is counted among the
"9 ok" group since after the rewrite it is items 1-9 that pass; the pre-rewrite run's precise 9/9
split is reproducible by `git show HEAD:Spells/Measure.lua` swapped in temporarily, exactly as run
here -- not committed, restored immediately after capturing the output above.)

### Suite output (after the rewrite)

`bash tools/run.sh tools/measurecheck.lua` -- full output, including the demonstration block:

```
measuring is off until asked and registers nothing until then            ok
a direct heal on yourself is matched to what landed and judged against its text ok
a landed amount above the text's top is judged against the crit range    ok
a heal below its text's range, with the deficit to back it up, is called out ok
a HoT's ticks are counted, summed and timed                              ok
a damage spell is matched on the target                                  ok
events on another unit are not counted                                   ok
the lines are kept and dumped as one copy block, ASCII, no bare pipe     ok
a secret amount or id is counted unreadable, never judged                ok
a direct heal landing just before its own cast event is paired with it   ok
a HoT keeps its ticks while another heal is cast, and that heal is not a tick ok
a DoT's ticks on the target are captured through the next casts          ok
an amount that fits two casts is ambiguous, never BELOW                  ok
a damage spell below its range is a possible resist, never BELOW         ok
a heal below range on a target not known to be missing that much is not BELOW ok
a heal equal to the known missing health reads as capped                 ok
bonus healing in combat is the last reading from before combat, and says so ok
a HoT recast on itself ends the first watch as refreshed                 ok

-- demonstration: the stored measure lines --
  Healing Touch R1 (learned 1, you 64, +heal 0): landed 48 [text 40-55, crit 60-83] in range
  Healing Touch R1 (learned 1, you 64, +heal 0): landed 70 [text 40-55, crit 60-83] crit range
  Healing Touch R1 (learned 1, you 64, +heal 0): landed 30 [text 40-55, crit 60-83] BELOW range
  Rejuvenation R1: 4 ticks 8+8+8+8 = 32 every 3.0 s [text 32 over 12 sec] matches
  Wrath R1 (learned 1, you 64): landed 15 [text 13-16, crit 20-24] in range
  Healing Touch R1 (learned 1, you 64, +heal 0): landed - [text 40-55, crit 60-83] nothing landed
  Healing Touch R1 (learned 1, you 64, +heal 0): landed - [text 40-55, crit 60-83] nothing landed
  Healing Touch R1 (learned 1, you 64, +heal 0): landed 48 [text 40-55, crit 60-83] in range
  Healing Touch R1 (learned 1, you 64, +heal 0): landed 50 [text 40-55, crit 60-83] in range
  Rejuvenation R1: 4 ticks 8+8+8+8 = 32 every 3.0 s [text 32 over 12 sec] matches
  Wrath R1 (learned 1, you 64): landed 15 [text 13-16, crit 20-24] in range
  Moonfire R2 (learned 10, you 64): landed 13 [text 11-15, crit 17-23] in range; Moonfire R2: 4 ticks 6+6+6+6 = 24 every 3.0 s [text 24 over 12 sec] matches
  Wrath R1 (learned 1, you 64): landed 6 [text 13-16, crit 20-24] ambiguous: 6 also fit Moonfire
  Moonfire R2 (learned 10, you 64): landed 13 [text 11-15, crit 17-23] in range; Moonfire R2: 1 ticks 6 = 6 every - s [text 24 over 12 sec] ambiguous (cadence unknown)
  Wrath R1 (learned 1, you 64): landed 7 [text 13-16, crit 20-24] below range: partial resist 50%?
  Wrath R1 (learned 1, you 64): landed 3 [text 13-16, crit 20-24] below range (resist?)
  Healing Touch R1 (learned 1, you 64, +heal 0): landed 30 [text 40-55, crit 60-83] below range, missing health not known (0 known)
  Healing Touch R1 (learned 1, you 64, +heal 0): landed 20 [text 40-55, crit 60-83] capped at missing health 20 (amount looks effective)
  Healing Touch R1 (learned 1, you 64, +heal 12): landed 48 [text 40-55, crit 60-83] in range
  Healing Touch R1 (learned 1, you 64, +heal 12 before combat): landed 45 [text 40-55, crit 60-83] in range
  Rejuvenation R1: refreshed after 1 ticks
  Rejuvenation R1: 0 ticks - = 0 every - s [text 44 over 12 sec] ambiguous (cadence unknown)

18 ok, 0 failed
```

### Every other suite

```
tipcheck       14 ok, 0 failed
spellsui       15 ok, 0 failed   (T7b has landed: 12 -> 15, per the task's own "or 15 if T7b has landed")
clockcheck     15 ok, 0 failed   (T11b: baseline said 13; grew from concurrent work, 0 failed)
bookcheck      15 ok, 0 failed   (the "14 or 15 if T7b has landed" case)
parsecheck     11 ok, 0 failed   (the "10 or 11" case)
probecheck     71 ok, 0 failed   (T13b: baseline said 66; grew from concurrent work, 0 failed)
forevercheck   13 ok, 0 failed
modulecheck    12 ok, 0 failed
adaptercheck   19 ok, 0 failed
corecheck      10 ok, 0 failed
svcheck        6 ok, 0 failed
consolecheck   11 ok, 0 failed

simcheck       PASS (mean 1.3%, max 2.8% at 23.0s)
reccheck       54 ok, 0 failed
replaycheck    80 ok, 0 failed
replayui       98 ok, 0 failed
runcheck       78 ok, 0 failed
reviewui       44 ok, 0 failed
navui          25 ok, 0 failed
dashui         56 ok, 0 failed
regencheck     27 ok, 0 failed
simwindow      8 ok, 0 failed
solvercheck    70 ok, 0 failed
timeline       27 ok, 0 failed
spelltip       48 ok, 0 failed
practice       74 ok, 0 failed
practiceui     49 ok, 0 failed
migrate        7 ok, 0 failed
```

`clockcheck` (15) and `probecheck` (71) exceed the task's stated baselines (13, 66) because T11b and
T13b, running concurrently in this same worktree, had already landed assertions of their own by the
time these suites ran; both are 0 failed, i.e. nothing this task touched regressed them. Re-ran both
once as the instructions require for a suite this task did not touch -- same counts both times.

### apicheck

```
apicheck: 8 Forever TOCs, 21 files, 40 distinct globals, 0 findings (baseline 69893)
selftest: 7 of 7 findings as expected
```

### luac -p

```
Spells/Measure.lua             (clean, no output)
tools/measurecheck.lua         (clean, no output)
tools/wowstub.lua              (clean, no output)
```

### git status --short (this task's files)

```
 M Spells/Measure.lua
 M tools/measurecheck.lua
 M tools/wowstub.lua
```

(`docs/tasks/T12b-measure-attribution.md` itself, edited only in its Report section, plus other
implementers' unrelated `docs/tasks/*` additions and their own in-flight edits to files this task
does not touch, are the rest of the worktree's `git status`; not reproduced here.)

### Skipped / not done

- Did not touch `Spells/Book.lua`, `Spells/Parse.lua`, the clock, or `Client/Probe.lua` (T7b/T11b/T13b's
  files) -- out of scope, per the task and to avoid colliding with the other implementers working on
  them concurrently in this same tree.
- Did not add a `PLAYER_REGEN_DISABLED` handler for the bonus-healing cache; used the simpler
  "read at the next cast out of combat" option Facts offers instead (stated above and in-line in the
  file's own comment).

### Question

None -- the two places where the task's own wording was ambiguous (the heal-BELOW gate's exact
precedence against "capped", and the percentage-vs-absolute reading of the damage resist tolerance)
were each resolvable by checking which reading reproduces *both* of the task's own worked examples
(items 4/15/16, and item 14's 7-vs-3), so no assumption was made blind; both are documented above and
in the code's own comments at `BelowHealText` / `BelowDamageText`.
