# T90 -- engine correctness: cooldowns respected, kept per family

Status: **built** 2026-10-01 on branch `next/T90` (base `e2b13f4`), wave N1 batch A, awaiting the
integrator. `docs/SPEC-next.md` section 11 row T90; section 4.2 P0 (a-b); decision 10 (the
author: as recommended, 9.1). Integrator-owned files were **not** edited; their lines are below.

## The task

`R-classes` 3 [ran]: the solver ignored spell cooldowns. `Solver:Best` never asked `SM.Ready` and
the engine's `Succeed` cast whatever a plan returned, so with Swiftmend on cooldown until t = 20
`plan:Decide(S, 10, ...)` returned 18562 (`cdtest2.lua`). And cooldowns were kept per spell id
(`S.cd[spellID]`, `ReplayTrace`'s `cdUntil[spellID]`, a literal `15` in the replay window),
harmless while Swiftmend has one rank and wrong for Holy Shock R1-R4 or Riptide's ranks, which
share one cooldown (CRITIQUE point 1).

## What was built

- **`Engine/SimModel.lua`**
  - `SM.CooldownOf(S, spellID) -> family, seconds`: the key a cooldown is kept under and its
    length -- the kit entry's `cooldown`, else `SM.SPELL_CD[id]` (still `{ [18562] = 15 }`, now
    the fallback); seconds nil for a spell with none. `S` is anything carrying the kit: the
    engine's slot (`S.kit`, set by `SM:Run`) or a `ReplayTrace` state (its `scenario.kit`). The
    entry is looked up in `S.form`, then in every form; with no entry the family is
    `MD.SpellData.spells[id].family`, else the id. Allocates nothing.
  - `S.cd[family]`: `Succeed` starts the family's cooldown on **every** cast that succeeds -- a
    recorded one inside a running cooldown included (the script and the fixed casts are never
    refused: the recording is the truth -- a reset talent, a Light's Vigil'd Holy Shock).
  - `SM.Ready(S, spellID, t)` keeps its signature and reads `S.cd[family]`.
  - **A plan's cast on cooldown is refused** in the decision branch: nothing spent, no global
    cooldown, traced as the new **`SM.TK.REFUSED = 9`** (tgt = the target asked for, a = the
    spell, b = when the cooldown ends, the plan's reason carried), counted in `r.refused`, and
    the plan is asked again exactly as after a wait. `SM.TK`'s existing numbers are unchanged;
    `ReplayTrace`, the replay window and the import reports ignore a kind they do not know.
- **`Engine/SimSolver.lua`**: `Solver:Best` drops a candidate that is not `SM.Ready` at
  `t + delay` (now, or when the one-GCD-later cast would start -- the cooldown's end is on the
  healer's bar, so this is causal); rule 8 drops one not ready at `t`.
- **`Engine/Kit.lua`**: `Kit.FIELDS.cooldown = "number"`, optional on any entry type (declared
  first, as the file's rule asks). No builder emits it yet (T96 does, Swiftmend's 15).
- **`Engine/ReplayTrace.lua`**: `cdUntil[family]` from `SM.CooldownOf(self, spellID)`;
  `State:CooldownUntil(spellID)` and `State:Ready(spellID)` keep their signatures.
- **`UI/ReplayWindow.lua`** (the Swiftmend-ready dot, old line 812): the sweep's length is
  `SM.CooldownOf(st, SWIFTMEND)`'s seconds, not `SPELL_CD[SWIFTMEND] or 15`.
- **`tools/solvercheck.lua`** (+5, section 11 "T90"):
  1. a spell on cooldown is never picked by `Best` or rule 8 (cdtest2's Swiftmend through
     `Best` and `Decide`; a cheap direct heal on cooldown loses rule 8 to a dearer one);
  2. a plan's cast on cooldown is refused, traced (`TK.REFUSED` at 1.5 s, ready at 15), costs
     nothing, `r.refused` counts it;
  3. a two-rank family: R2 cast at 0 blocks R1 until 10 in the engine (`SM.Ready`, the cast) and
     in the replay's state machine, and R1's cast at 10 blocks R2 until 20;
  4. a recorded cast inside its cooldown is replayed as recorded (three scripted Swiftmends 2 s
     apart, two fixed casts), never refused (a guard: the parent never refused anything);
  5. causality unchanged with a cooldown in play: an 8 s cooldown heal cast no closer than 8 s,
     and a burst at 40 s changes nothing the solver does before it.

## Failing first (the parent `e2b13f4` with the new `tools/solvercheck.lua`)

```
85 ok, 4 failed
  FAIL T90: a spell on cooldown is never picked by Best or rule 8 - Best free=18562 cd=18562 Decide=18562; rule 8 free=26978(r8) cd=26978(r8)
  FAIL T90: a plan's cast on cooldown is refused, traced, and costs nothing - casts 4 (r 4), refused 0 (r nil), first at - ready -, spent 40
  FAIL T90: a two-rank family: R2 cast at t blocks R1 until t + cd - Ready(R1, 5)=true; casts 0.00:900002, 1.50:900001, 3.00:900001, ... replay R1 until(5)=nil ready(5)=true, R2 until(10.5)=nil
  FAIL T90: causality unchanged with a cooldown in play - 9 cooldown cast(s) of 11, closest 4.00 s apart; identical until the burst
```

After: `89 ok, 0 failed`.

## Suites, before and after

| suite | before | after |
|---|---|---|
| `solvercheck/tbc` | 84 | **89** (+5) |
| `restcheck/tbc` | 51 | 51 -- **output byte-identical**: no number moved, so nothing to re-base (its fights bind no cooldown spell; 3b's TBC recording compares the priced and the regen-blind solver, both of which get the fix) |
| `replaycheck/tbc` | 82 | 82, **byte-identical** |
| `replayui/tbc` | 107 | 107; every assertion line identical, the Swiftmend-ready dot's included. The only differing lines are the frame-sliced search's `[sim] search N evaluations` progress lines, which differ between two runs of the **parent** too (the stub's `debugprofilestop` is `os.clock`); `search done: 44 evaluation(s), best (...)` is identical |
| `reviewui/tbc`, `runcheck/tbc`, `simwindow/tbc` | | same: only the timing-sliced progress lines / "N frames" differ |
| every other suite | | identical (pointer addresses aside) |

`make check`: **72 run(s), all passed**, 67 counted against 67 expected, with one NOTE
(`solvercheck/tbc: 89 assertion(s), 84 expected`) until the counts line below is applied.
apicheck 0 findings (60 files, 48 distinct globals); textcheck 0 findings; `luac -p` clean on the
six files. No default registered (`defaultscheck` unchanged).

## The strategies report on the author's recordings (decision 10)

- **TBC, the eight anniversary recordings** (`tools/strategies.lua --file` on the author's
  `SpellTuner.lua`, copied 2026-10-01): **identical before and after**, every row:

  ```
  the recorded casts         deaths  4  floor  145.4s  used   42244   429 casts   <- the CONTROL
  Rules: balanced            deaths  3  floor   89.1s  used   42652   459 casts   yes
  Rules: HoTs only           deaths  4  floor  110.5s  used   40797   459 casts   yes
  Solver: no intuition       deaths  3  floor  122.3s  used   42328   430 casts   yes
  Solver: intuition from old logs deaths  3  floor  123.7s  used   42527   432 casts   yes
  Solver: intuition from many raids deaths  3  floor  138.9s  used   44137   421 casts   yes
  Solver: blurred foresight  deaths  3  floor  114.4s  used   41682   448 casts   NO - sees this fight
  Solver: frugal             deaths  3  floor  122.3s  used   41919   430 casts   yes
  Solver: reactive           deaths  3  floor  100.3s  used   42048   458 casts   yes
  ```

  `tools/import.lua coach N force` and `replay N` on all eight: the cards and replays are
  identical too (only the "search ran across N stub frames" timing line differs). On these
  fights no strategy ever asked for Swiftmend while it was on cooldown, so the fix moves none
  of the author's TBC numbers.
- **Forever, Healroot's eight pulls and four practice fights** (`tools/import.lua report N` /
  `pN`): identical before and after. The level 11 kit has no cooldown spell.

The fix is still live: on any fight where the solver would have recast Swiftmend inside its
15 s (cdtest2's case, solvercheck 1) the suggested column now waits or casts something else.

## Integrator lines

**`tools/data/expected-counts.json`:** `"solvercheck/tbc": 89,` (was 84).

**`docs/DECISIONS.md`**, a new entry:

> ## Cooldowns are respected and kept per family (2026-10-01, T90, decision 10)
>
> The solver no longer picks a spell on cooldown (`Solver:Best` asks `SM.Ready` now and for the
> one-GCD-later candidate; rule 8 asks it too), and the engine refuses a **plan's** cast on
> cooldown -- nothing spent, no global cooldown, traced as `SM.TK.REFUSED` and counted in
> `r.refused` -- while a **recorded** cast (the replay's script, a fixed cast) inside its
> cooldown is replayed as recorded, never refused: the recording is the truth (a reset talent,
> a Light's Vigil'd Holy Shock). A cooldown belongs to the **family** (`SM.CooldownOf(S, id)`:
> the kit entry's optional `cooldown`, else `SM.SPELL_CD`), so one rank's cast blocks every
> rank (Holy Shock R1-R4, Riptide). The author accepted it as a bug fix (decision 10). The
> strategies report on the author's eight TBC recordings is **identical before and after**
> (Rules: balanced 3 deaths / 89.1 s / 42652 used ... Solver: reactive 3 / 100.3 / 42048, the
> control 4 / 145.4 / 42244), and so are the eight coach cards and Healroot's twelve Forever
> reports: on those fights no plan asked for Swiftmend inside its cooldown.

**`CLAUDE.md`**, append to these rows:

- `Engine/SimModel.lua`: **T90 (decision 10):** `SM.CooldownOf(S, spellID)` -> family, seconds
  (the kit entry's `cooldown`, else `SM.SPELL_CD`, now the fallback; `S` is the slot -- `S.kit`
  set by `SM:Run` -- or a `ReplayTrace` state); cooldowns kept in `S.cd[family]`, so one rank
  blocks every rank; `SM.Ready` keeps its signature; a plan's cast on cooldown is refused (no
  mana, no GCD), traced as `SM.TK.REFUSED` (9: tgt, a = the spell, b = the ready time) and
  counted in `r.refused`; a recorded cast (script, fixed) is never refused.
- `Engine/SimSolver.lua`: **T90:** `Solver:Best` skips a candidate not `SM.Ready` at
  `t + delay`, rule 8 one not ready at `t` (cdtest2: Swiftmend on cooldown was picked).
- `Engine/Kit.lua`: **T90:** `Kit.FIELDS.cooldown` (number, optional, per family).
- `Engine/ReplayTrace.lua`: **T90:** `cdUntil[family]` through `SM.CooldownOf`;
  `State:CooldownUntil` / `Ready` keep their signatures.
- `UI/ReplayWindow.lua`: **T90:** the Swiftmend-ready dot sweeps `SM.CooldownOf`'s seconds,
  not a literal 15.

**`docs/TOOLS.md`**, the `solvercheck.lua` row, append:

> Since **T90** (89): a spell on cooldown is never picked by `Best` or rule 8, a plan's cast on
> cooldown is refused and traced (`TK.REFUSED`), a two-rank family's cooldown blocks the other
> rank (engine and replay state), a recorded cast inside its cooldown is replayed as recorded,
> and causality holds with a cooldown in play.

No TOC change, no new file in any TOC, no `tools/check.sh` change.
