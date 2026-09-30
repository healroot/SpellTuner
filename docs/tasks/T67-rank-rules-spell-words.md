# T67 -- The rank rules and the spell words, once (plan P23)

Status: **built** 2026-09-30 on branch `plan/P23` (base `46c09d9`), wave 9 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. **The branch needs its five TOC lines (below) to
load**: without them `Spells/Book.lua` stops at `RR.CastsToOOM` / `RR.Pareto` (a nil `MD.RankRules`),
`UI/SpellTip_Forever.lua` and `UI/SpellsPane_Forever.lua` at `MD.Words`, and the TBC dashboard at
`MD.RankRules` in `RankMath:Compute` -- the same shape as T56 and T63, whose new files also waited for
the integrator's TOC lines.

## The task (docs/PLAN-refactor-ux.md section 5, P23)

Review items (`docs/review/2026-09-30-project-review.md`): **A13** -- "the rank rules exist three
times; the words four times": Pareto dominance and the suggested rank in `RankMath:Compute` (a literal
`0.4`) and `Book:Rows` (`SUGGESTED_FLOOR = 0.4`), casts to OOM twice, `SpellTip`'s `Dominator`
re-implementing `entry.dominatedBy`; the cost / cast / per-second / crit / casts words computed
separately in SpellTip and SpellsPane, `CRIT_MULT` in both UI files; `SpellTip.lastOutcome` a second
return smuggled through a field that the rank-row hover overwrites. And **A15's visible half** (R41):
`Book:ReadSpell` never carried the last readable value through a secret description, so a spell outside
the book went blank in combat.

- `Spells/RankRules.lua` (TBC TOC and Forever main TOCs, pure): `Pareto`, `Suggested`, `CastsToOOM`;
  `RankMath:Compute` and `Book:Rows` call it on `MD.Rules.SUGGESTED_FLOOR`.
- SpellTip reads `entry.dominatedBy` and loses `Dominator`.
- `Spells/Words.lua` (Forever): cost, cast, per second, value parts, casts, with a `style` where spec
  3.5 and 5.x want different wording; SpellTip and SpellsPane render from it.
- `SpellTip.Lines` returns `lines, outcome` (no `lastOutcome` field).
- `Book:ReadSpell` carries the last readable value through a secret description exactly as
  `BuildEntry` does; the two read paths are not merged here.
- Tests: equal strings in `tipcheck`, `spellsui`, `bookcheck`, `dashui`, `spelltip`; `tipcheck` +1,
  `bookcheck` +1.

Owned files (section 4, wave 9): `Engine/RankMath.lua`, `Spells/Book.lua`, `UI/SpellTip_Forever.lua`,
`UI/SpellsPane_Forever.lua`, new `Spells/RankRules.lua`, new `Spells/Words.lua`, `tools/tipcheck.lua`,
`tools/spellsui.lua`, `tools/bookcheck.lua`. Committed: all of them except `tools/spellsui.lua` (it
needed no change -- its 48 assertions hold every string byte for byte) and this task file. The TOC
lines were applied in the working tree only, to run the suites.

## What was built

| file | change |
|---|---|
| `Spells/RankRules.lua` | New, pure (no client call, no frame, no `MD.API`), `MD.RankRules`. Rows in, marks out; a field map `f = { eff, rate, value, eligible }` names what a caller's rows carry (`hpm` / `hps` / `heal` on the dashboard, `perMana` / `perSec` / `value` in the book) and which rows compete. **`RR.Beats(rj, ri, f)`** (at least as good on both, better on one, `rj` competing), **`RR.Pareto(rows, f)`** (marks `dominated = true`), **`RR.Suggested(rows, top, f)`** (the competing, non-dominated row with the best efficiency whose value is at least `MD.Rules.SUGGESTED_FLOOR` of `top`'s, the first of equals; else `top`), **`RR.DominatedBy(rows, suggested, f)`** (T38's rule, moved from `Book:Rows`: the id of the suggested rank when it beats the row, else of the beating row with the best efficiency) and **`RR.CastsToOOM(cost, interval, mana, regen)`** (the book's nil-guarded form: nil when an input is missing, `math.huge` when free or regen covers the chain, 0 when one cast is unaffordable). The floor is read at each call. |
| `Engine/RankMath.lua` | `Compute`'s Pareto and suggested loops replaced by `RR.Pareto` / `RR.Suggested` with **`RankMath.RULE_FIELDS`** (`hpm`, `hps`, `heal`; eligible = known and not virtual -- the rolling-stack Lifebloom rows stay out); `RankMath:CastsToOOM` is kept for its callers (`Engine/RegenMeasure.lua`, `Engine/SimSelfTest.lua`) and delegates to `RR.CastsToOOM`. |
| `Spells/Book.lua` | `SUGGESTED_FLOOR` and the local `CastsToOOM` gone; `Book:CastsFor` calls `RR.CastsToOOM`; `Book:Rows` ends with `RR.Pareto`, `RR.Suggested`, `RR.DominatedBy` on the book's field map (eligible = known with both `perMana` and `perSec`). `Book.GCD` exposed (Words reads it). **`Book:ReadSpell`** runs the same `ApplyStale` as `BuildEntry`, against **`Book._readSpells`** -- the previous entry `ReadSpell` answered for each id -- and stores each answer there: a text secret now keeps the last readable one, `stale = true`, and every number derived from it (value, per mana, per second); a spell never read before the fight has nothing to carry and stays blank (nothing guessed). |
| `Spells/Words.lua` | New, pure, Forever main TOCs after `Spells/Book.lua`, `MD.Words`. `W.CRIT_MULT` (the one Forever UI copy, UNVERIFIED as before), `W.GCD` (= `Book.GCD`), `W.Num`, `W.CritRange(part)`, `W.OtherPower(e)` (`10 Rage`), `W.PartOf(e, kind)`, **`W.Cost(e, style)`** (`cell` 3.5 `25` / `5%`; `card` 3.5 `25 mana` / `5% of base mana`; `export` 3.6 `25 Mana` / `unknown`), **`W.Cast(e, style)`** (`cell` `inst` / `chan` / `1.5s`; `phrase` `2.0 s cast` or nil; `card` `2.0 s`; `export` `Instant` / `2.0 sec cast` / `unknown`), **`W.PerMana(e, style)`** (`cell` the number; `tip` 5.1 `no mana (10 Rage)` / `free` / `5% of base mana` / `cost unknown`), **`W.PerSec(e, kind, style, c)`** (`tip` 5.1 `N over T s` or the number; `card` 3.5 the number and, in `c.muted`, what it is over), **`W.Casts(n, style)`** (`short` `inf` / N / `-`; `card` `never - regen keeps up` / `N casts from full`), **`W.Value(e, kind, style, c)`** -> `pairs, critGiven` (the block's detail lines 5.2-5.4, or the card's pairs 3.5), `W.CritNote()` and `W.SuggestedRule()` (the rule's sentence, its `40%` from `MD.Rules.SUGGESTED_FLOOR`). Colour codes come in as arguments; the words never pick a colour. |
| `UI/SpellTip_Forever.lua` | `CRIT_MULT`, `Num`, `PartOf`, the per-mana / per-second / value builders become Words calls in the `tip` style (the local names kept as one-line wrappers); `Dominator` reads `entry.dominatedBy` (an id looked up in the family) instead of re-running the rule. **`SpellTip:Lines` returns `lines, outcome`** (`block`, `no value`, `not in book`, `no id`); `SpellTip.lastOutcome` is gone and `OnSpell` takes the outcome from the call it made. |
| `UI/SpellsPane_Forever.lua` | `OtherPowerText`, `ManaCellText`, `CastCellText`, `ExportCostText`, `ExportCastText`, `CastWord`, `CostWord`, `CastsWord`, `PerSecWord`, `ToOOMWord`, `PartOf`, `Num`, `CRIT_MULT`, `GCD` and the card's value / cast pairs become Words calls in the `cell` / `card` / `export` / `phrase` styles; `SUGGESTED_RULE` is `Words.SuggestedRule()` (the same sentence). `GameTip` is unchanged (it ignores the new second return). |
| `tools/tipcheck.lua` | +1 (below); the T37 "free Other spell" assertion reads the outcome from `Lines`' second return instead of the removed field (same assertion, same count). |
| `tools/bookcheck.lua` | Forever +1 (below); **a new tbc run** (2, below), so `HARNESS_FLAVOUR = { "forever", "tbc" }`. |

### The new assertions

- **tipcheck 38, "T67: why after a rank-row hover still names the last macro hover"** -- a macro hover
  of an id nothing knows (424242: `first line: type 0 id 424242 -> not in book`), then a real rank-row
  hover in Spells -> Overview -> Whole book (Healing Touch R1: the game's tooltip with one block), then
  `/st tooltip why`: the same line as before the hover; `SpellTip.lastOutcome` is nil right after the
  hover; `Lines` answers `block`, `no id` and `not in book` as its second return.
- **bookcheck (forever) 22, "ReadSpell keeps a spell outside the book readable in combat, read before
  combat"** -- two flyout rows (never listed by the scan) whose descriptions the stub makes secret in
  combat: 90094 read out of combat (value 70), then twice in combat -- `descState` `secret`, `stale`,
  the same desc / parsed table / value / per mana -- and `SpellTip:Lines(90094)` carries `Text read
  before combat`; 90095, never read before the fight, stays blank (`secret`, no value, not stale); out
  of combat again, fresh and not stale.
- **bookcheck (tbc) 1, "tbc: Compute's dominated and suggested ranks are the old rule's on every
  family"** -- `RankMath:Compute()` on the TBC harness (4 families, 39 rows, 24 dominated) against the
  pre-T67 inline rule kept verbatim in the suite as the oracle (literal `0.4`), row by row and the
  `suggestedID`.
- **bookcheck (tbc) 2, "tbc: the floor is MD.Rules.SUGGESTED_FLOOR, a virtual or unknown row beats
  nothing"** -- constructed rows through `RankMath.RULE_FIELDS`: SubFamily's pair (R1 200 heal at 10 per
  mana, R2 the max at 500) suggests R1 at 200 and R2 at 199; a virtual and an unknown row that beat both
  count for nothing; a row tying R2 on per mana and slower is dominated (a tie on one number is not a
  draw); `MD.Rules.SUGGESTED_FLOOR == 0.4`; `RankMath:CastsToOOM` 12 / inf (free) / 0 / inf (regen).

Why a tbc run: the plan names `dashui` as the proof that TBC did not move, but no TBC suite reads
`Compute()`'s marks -- with the `RR.Pareto` call removed from `RankMath.lua`, `dashui`, `spelltip`,
`simcheck` and `practice` all stay green (mutation run below). A refactor on a shared rule with no
suite that can go red on TBC is what plan section 3 forbids, so the run was added to a file this task
owns.

## Tests first

**On the parent's shipped files** (`46c09d9` exported whole, the branch's `tools/tipcheck.lua` and
`tools/bookcheck.lua` copied over it):

```
tipcheck: exit 1
T37: a free Other spell gets no block                                    FAIL - lines=nil outcome=nil shown=0
T67: why after a rank-row hover still names the last macro hover         FAIL - hovered=true blocks=1 same=true lastOutcome=block outcomes=nil/nil/nil why=... first line: type 0 id 424242 -> not in book; slot: no owner
36 ok, 2 failed
bookcheck (forever): exit 1
ReadSpell keeps a spell outside the book readable in combat, read before combat FAIL - before=ok/70 first=secret/nil/nil second=nil/nil said=false never=secret/nil after=ok/nil
21 ok, 1 failed
```

(The T37 line fails on the parent because the adjusted assertion reads `Lines`' second return, which
the parent does not have. On the parent the `why` line itself does not change after a hover -- the
field only leaks into `OnSpell`'s answer when a caller reads it between two calls -- so the new
assertion pins the contract: the field is gone and the outcome is a return.)

The tbc run on the parent: its first assertion is a refactor-equivalence check and passes there too
(the parent's `Compute` IS the oracle); its second fails, because the parent has neither
`Spells/RankRules.lua` nor `RankMath.RULE_FIELDS`:

```
bookcheck (tbc):
tbc: Compute's dominated and suggested ranks are the old rule's on every family ok - ran=true families=4 rows=39 dominated=24 bad=none
tbc: the floor is MD.Rules.SUGGESTED_FLOOR, a virtual or unknown row beats nothing FAIL - fields=false dominated=nil/nil/nil at200=nil at199=nil casts=12
1 ok, 1 failed
```

After: tipcheck `38 ok, 0 failed`; bookcheck forever `22 ok, 0 failed`, tbc `2 ok, 0 failed`.

**Mutations on the finished branch** (one replacement each, reverted by the same replacement back):

| mutation | result |
|---|---|
| `RankMath.lua`: the `RR.Pareto(rows, RULE_FIELDS)` call removed | bookcheck tbc 1 ok, 1 failed (1); **dashui 64, spelltip 48, simcheck 13, practice 84 all green** |
| `RankMath.lua`: eligible without `not r.virtual` | bookcheck tbc 0 / 2; dashui, spelltip, simcheck, practice green |
| `Core.lua`: `SUGGESTED_FLOOR = 0.5` | bookcheck tbc 0 / 2, bookcheck forever 21 / 1, tipcheck 37 / 1, spellsui 44 / 4; dashui green |
| `RankRules.lua`: `Beats` strict on both numbers | bookcheck tbc 1 / 1 (2); every Forever suite green before the tie row was added |
| `Words.lua`: `CRIT_MULT = 2` | tipcheck 35 / 3, spellsui 47 / 1 |
| `Words.lua`: the card's `never - regen keeps up` reworded | spellsui 47 / 1 |
| `Book.lua`: `ReadSpell` does not store its answer | bookcheck forever 21 / 1 |

**Equivalence, off the suites** (a throwaway script in the scratchpad, not committed): the pre-T67
inline rules of `Book:Rows` (Pareto, suggested, `dominatedBy`) and `RankMath:Compute` (Pareto,
suggested) against `RankRules` on 20 000 random row sets each -- missing numbers, unknown and virtual
rows, ties -- 0 disagreements.

## Suites (`make check` = `tools/check.sh`, exit codes and footers checked)

Run with the five TOC lines applied in the working tree. The parent's column is a run of `46c09d9`
exported whole.

| suite | before (`46c09d9`) | after |
|---|---|---|
| `tipcheck` (forever) | 37 | **38** |
| `bookcheck` (forever / tbc) | 21 / -- | **22 / 2** |
| `spellsui` | 48 | 48, output byte for byte equal |
| `dashui` (tbc) | 64 | 64, byte for byte |
| `spelltip` (tbc) | 48 | 48, byte for byte |
| every other suite | adaptercheck 23 / 16, bindscheck 6, clockcheck 23, coachforever 21, consolecheck 20 / 1, corecheck 24 / 24, costcheck 3, defaultscheck 48 / 52, forevercheck 16, gatecheck 9, importcheck 21, kitcheck 11 / 3, measurecheck 30, migrate 7, modulecheck 19, navui 35, parsecheck 15, practice 84, practiceforever 28, practiceui 52, probecheck 88, reccheck 63, recordcheck 31, recordingscheck 32 / 32, regencheck 27, releasecheck 21, replaycheck 82, replayforever 15, replayui 103, restcheck 51, reviewforever 13, reviewui 49, runcheck 81, scenariocheck 14, simcheck 13, simwindow 8, slashcheck 8, solvercheck 84, svcheck 6 / 1, tabscheck 24, themecheck 23, timeline 27, ttocheck 45, verifycheck 14, wincheck 55, lib/t 12 | all equal, all passing |
| harness-skip, reproduce-smoke, strategies-smoke | ok | ok |
| `apicheck.py` / `--selftest` | 0 findings, 51 files / 13 | 0 findings, **53** files / 13 |
| `textcheck.py` / `--selftest` | 0 findings, 87 files / 2 | 0 findings, **89** files / 2 |
| `refcheck.py --selftest` | 2 | 2 |

`tools/check.sh`: 67 runs, all passed, rc 0; its notes are `bookcheck/forever: 22 assertion(s), 21
expected`, `tipcheck/forever: 38 assertion(s), 37 expected` and `bookcheck/tbc: 2 assertion(s), not in
the expected counts`. Every suite's saved output was compared with the parent's, table addresses and
millisecond timings normalised: equal except the new lines above, `apicheck` / `textcheck` (the file
counts), `releasecheck` (the TBC package has 61 files, was 60; the Forever one 28, was 26; and the
parent's scratch path), and the frame counts of the frame-sliced search (`simwindow` "6 frames" / "5
frames", `coachforever` "frames=3" / "2", `reccheck` "3 frames" / "4") -- the search is sliced on
`debugprofilestop()`, and T63 saw the same lines differ between two runs of one tree. `luac -p` passes
on every changed file.

## TBC

No behaviour change. `RankMath:Compute` marks the same rows dominated and suggests the same rank (the
tbc run's oracle, and the 20 000-set equivalence run); the floor is the same 0.4, now read from
`MD.Rules.SUGGESTED_FLOOR`. `RankMath:CastsToOOM` answers the same for every numeric input; with a
`nil` input it now answers `nil` where it used to raise on the arithmetic (no caller passes one:
`Engine/RegenMeasure.lua` and `Engine/SimSelfTest.lua` hand it numbers, `Compute`'s context always has
mana and casting regen). `dashui` and `spelltip` are byte for byte equal. No DECISIONS entry is needed.

## Forever

- A spell outside the book (a chat link, another addon's bar) keeps its block in combat, marked `Text
  read before combat`, once it was read out of combat (R41's gap); before, it had no block at all in
  combat.
- `/st tooltip why` can no longer be told a stale outcome by a Spells-pane hover (the field is gone).
- Every string on the tooltip block, the RANKS table, the rank card and the export is unchanged
  (`tipcheck`, `spellsui` equal).

## Integrator lines

**`SpellTuner_TBC.toc`** -- a new line `Spells\RankRules.lua` **immediately before**
`Engine\RankMath.lua` (after `Engine\Kit.lua`).

**`SpellTuner_Mainline.toc`** and **`SpellTuner.toc`** (both, identical) -- a new line
`Spells\RankRules.lua` **immediately after** `Spells\Parse.lua` (before `Spells\Book.lua`), and a new
line `Spells\Words.lua` **immediately after** `Spells\Book.lua` (before `Spells\Tabs.lua`).

No module TOC: `Engine/RankMath.lua` is not loaded on Forever, and the modules read the book through
the main addon.

**tools/data/expected-counts.json**: `"bookcheck/forever": 22`, a new `"bookcheck/tbc": 2`,
`"tipcheck/forever": 38`.

**CLAUDE.md** (the repo-structure table):

- New row after `Spells/Book.lua`'s: `| `Spells/RankRules.lua` | **The rank rules, once** (T67, P23,
  review A13): `MD.RankRules` -- `Beats`, `Pareto` (marks `dominated`), `Suggested` (the best per mana
  among the non-dominated ranks worth at least `MD.Rules.SUGGESTED_FLOOR` of the highest known, else the
  highest known), `DominatedBy` (the id that beats a dominated rank: the suggested one when it does,
  else the best per mana) and `CastsToOOM` (nil for a missing input, inf when free or regen keeps up, 0
  when one cast is unaffordable). Pure; a field map says what the caller's rows carry (`hpm` / `hps` /
  `heal` on TBC's dashboard, `perMana` / `perSec` / `value` in the book). `Engine/RankMath.lua`'s
  `Compute` and `Spells/Book.lua`'s `Rows` both call it; TBC TOC before `Engine/RankMath.lua`, the
  Forever main TOCs before `Spells/Book.lua` |`
- New row after that: `| `Spells/Words.lua` | **The spell words, once** (T67, P23, review A13; Forever):
  `MD.Words` -- how a rank's cost, cast, per mana, per second, casts to OOM and value parts are said,
  with a `style` where docs/SPEC-forever-ui.md wants different words for one fact (`cell` / `card` /
  `export` / `phrase` for the Spells pane 3.5 / 3.6, `tip` for the tooltip block 5.x: `10 Rage` in a
  cell, `no mana (10 Rage)` in the block; `inf` in a cell, `never - regen keeps up` on the card); the one
  UI copy of the crit multiplier (1.5, unverified) and the GCD (`Book.GCD`); the suggested rule's
  sentence from `MD.Rules.SUGGESTED_FLOOR`. Pure, colours passed in. After `Spells/Book.lua` |`
- `Engine/RankMath.lua` row, append before the closing ` |`: ` **T67 (P23):** the Pareto filter, the
  suggested rank and `CastsToOOM` are `Spells/RankRules.lua`'s (`RankMath.RULE_FIELDS`: `hpm`, `hps`,
  `heal`, known and not virtual); `RankMath:CastsToOOM` stays as a delegate`
- `Spells/Book.lua` row, append before the closing ` |`: ` **T67 (P23, review A13, A15's R41 gap):**
  `Rows` calls `Spells/RankRules.lua` (`Pareto`, `Suggested`, `DominatedBy`, `CastsToOOM`);
  `Book:ReadSpell` carries the last readable text through a secret description as `BuildEntry` does,
  from its own previous answers (`Book._readSpells`), so a spell outside the book keeps its numbers in
  combat, marked stale; `Book.GCD``
- `UI/SpellTip_Forever.lua` row, append before the closing ` |`: ` **T67 (P23):** its words are
  `Spells/Words.lua`'s `tip` style; a dominated rank's "Dominated by" reads `entry.dominatedBy`;
  `SpellTip:Lines` returns `lines, outcome` -- `SpellTip.lastOutcome` is gone, so a Spells-pane hover
  cannot change what `/st tooltip why` is told`
- `UI/SpellsPane_Forever.lua` row, append before the closing ` |`: ` **T67 (P23):** every cost / cast /
  per-second / casts / value word is `Spells/Words.lua`'s (`cell`, `card`, `export`, `phrase`)`

**docs/TOOLS.md** section 1:

- the `bookcheck.lua` row: `(T7, forever)` becomes `(T7; forever, and tbc since T67)`, and append before
  the closing ` |`: ` Since **T67** (P23; forever 22, tbc 2): `ReadSpell` keeps a spell outside the book
  readable in combat (the last text read, stale, and the block's "Text read before combat"; a spell
  never read before stays blank); on tbc, `RankMath:Compute`'s dominated and suggested ranks equal the
  pre-T67 inline rule (kept in the suite as the oracle) on every family, and on constructed rows the
  floor is `MD.Rules.SUGGESTED_FLOOR`, a virtual or unknown row beats nothing and a tie on one number
  with a loss on the other is dominated`
- the `tipcheck.lua` row, append before the closing ` |`: ` Since **T67** (P23; 38): `SpellTip:Lines`
  returns `lines, outcome`, and `/st tooltip why` after a Spells-pane rank-row hover still names the
  last macro hover`

**docs/TESTING.md** section 44 (the refactor plan's checks), under **Forever**: "**A spell outside the
book in combat (P23).** Link a heal you know in chat, hover the link out of combat (the SpellTuner block
shows), then again in combat: the block is still there, with `Text read before combat` last. The Spells
pane's rank table, the rank card and the spell tooltip read as before. `/st tooltip why` after hovering
a rank row in the Spells pane still describes your last macro hover." Under **TBC**: "**The dashboard's
ranks (P23).** `/md` -> Spells: the same ranks are marked dominated and the same one suggested as
before (a regression check: the rules moved to `Spells/RankRules.lua`)."

**docs/DECISIONS.md**: none required (TBC unchanged). Optionally, one line under the Forever port's
notes: "A spell read outside the book keeps its last readable text through a secret description, as a
book spell does, and says it was read before combat (T67, review R41's gap)."

**docs/HISTORY.md**: the integrator's wave entry.

## Deviations

- **bookcheck gained a tbc run (2 assertions).** The plan names `dashui` as TBC's proof; no TBC suite
  reads `Compute()`'s marks (the mutation table), so the refactor of a shared rule could not go red on
  TBC. The run holds it against the pre-T67 rule kept verbatim as an oracle, plus constructed rows for
  the floor, the virtual rows and a tie. To reach the dashboard's field map it reads
  **`RankMath.RULE_FIELDS`**, which RankMath now exposes.
- **`RR.DominatedBy` is in RankRules**, beyond the plan's three (`Pareto`, `Suggested`, `CastsToOOM`):
  T38's `dominatedBy` loop in `Book:Rows` was the second copy of SpellTip's `Dominator`, and moving it
  beside `Beats` keeps one definition of "beats". RankMath does not call it (its rows never had
  `dominatedBy`).
- **`RR.CastsToOOM` is the book's nil-guarded form**, so `RankMath:CastsToOOM` with a nil input answers
  nil instead of raising (no caller passes one; see TBC).
- **Words carries three helpers the plan does not list**: `W.PartOf`, `W.CritNote` (the block's "x1.5,
  not measured") and `W.SuggestedRule` (the pane's rule sentence, its 40% now from the floor), all
  strings the two UI files said separately. `Spells/Measure.lua` and
  `Modules/SpellTuner_Replay/Scenario_Forever.lua` keep their own `CRIT_MULT` (the review's "two UI
  files" are SpellTip and SpellsPane; neither of the others is owned in this wave).
- **`tools/spellsui.lua` is unchanged**: owned, but its 48 assertions already hold every string this
  task moved, byte for byte.
- **tipcheck's T37 "free Other spell" assertion now reads the outcome as `Lines`' second return** --
  the field it read is gone; same assertion, same count.
- **The rank-row hover assertion pins the contract, not a visible lie**: on the parent `/st tooltip why`
  itself does not change after a hover (the field reaches `OnSpell`'s answer only when read between two
  calls), so the failing-first evidence is the field being set by the hover and the missing second
  return.
- **`Book._readSpells` keeps one entry per id `ReadSpell` ever answered** for the session (chat links
  and bars: a handful of ids); it is not in the book's generation signature, which covers the scan's
  entries only.
- **The branch does not load without its TOC lines** (as T56 and T63): the TOCs are integrator-owned.
  The suites above were run with the five lines applied in the working tree and not committed.
