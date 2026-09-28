# T13d — a v3 stream becomes the engine's scenario

Status: **open**, after T15 (the Forever kit and spell index) and T13 (the v3 stream's shape). M3
(`docs/ROADMAP-FOREVER.md` M3, "`ScenarioFromRecording` v3"), split from T13 by the lead so each task
is one module. Carries two choices the planner ruled on 2026-09-28 (`FOREVER-PLAN.md`, "Planner
rulings for M3" above §2.4, items 1 and 2), each as **one replaceable function**.

## Goal

With the Replay module on, `SM.ScenarioFromRecording(rec, kit)` accepts a v3 stream (T13) and
returns a scenario of exactly the shape the engine already runs -- targets, recorded damage and
foreign heals, the script and the fixed casts, mana rates, pre-pull HoTs -- plus the **reconstructed
health** of every target at a 2 s grid for the health gate and the replay window. Every v2 stream
(TBC) goes through the old function untouched. The heals `UNIT_COMBAT` reported without a source are
split into the player's own (paired with their casts) and everyone else's; a party member's unknown
max health gets a stated stand-in. For T14 (gates), T16 (replay window), T17 (coach).

## Facts

- The v2 scenario shape (`Engine/SimModel.lua` `ScenarioFromRecording` 1056-1197): `{dur, pool,
  initial, energizeAssumed, targets[i] = {name, role, maxHP, danger, hp0, tracked}, ev, rates, fixed,
  incoming, threat, sampleT, hpSampleT, kit, floor, script}`. `SM:Run` walks `scenario.ev` with
  `#ev.t` (616-617) and applies `DMG` (damage), `FHEAL` (a foreign heal, landed by the engine), `DIED`,
  `CASTSTART` / `CANCEL` (trace only); own heals are **generated** by the engine from the script and
  never read (735-767). `init.auras` entries `{target, spellID, stacks, remaining}` start HoTs ticking
  (637-656). `fixed` entries `{t, id, cost, tgt, kind}` come from `MD:ClassifyCast` (TBC:
  `Data/DruidSpells.lua` 66).
- The v3 stream (T13): `ev` kinds `DMG = 1`, `HEAL = 15` (a heal of **unknown source**),
  `OWNCAST = 3`, `CASTSTART = 6`, `CANCEL = 7`, `DIED = 9`; `roster[i].maxHP = -1, maxSecret = true`
  for party members; `mana` from the clock's model; `initial.auras = { {token, spellId, remaining,
  stacks} }`; `initial.known` by the engine's family keys (T13); `meter`.
- `UNIT_COMBAT` HEAL carries **no source** (plan §2.3). The plan says the engine generates own heals
  and the foreign-share gate reads the damage meter, but not how the stream's sourceless heals are
  split into own (to drop) and foreign (to replay). **Planner ruling 2 -- `SM.AttributeHeals(rec, kit)`:** pair by time and target with the player's own
  casts (a direct heal in `[cast - 0.3, cast + 1.0]` on the cast's target; a HoT's ticks at
  `cast + 3k +/- 0.4` for `k = 1..ticks`, at most twice the kit's tick, ending at a recast of the
  same family on the same target; pre-pull HoTs' ticks counted back from their expiry); everything
  else is foreign. The damage meter's own total checks it (T14, gate 8 "heals attributed"; a pull
  that disagrees beyond the gate's threshold is not coached from).
- A party member's max health is secret (plan §6 Q2). **Planner ruling 1 --
  `SM.EstimateMaxHP(deficits, hits)`, a lower-bound stand-in:** the largest deficit the target lived through
  plus the biggest single hit it took (it survived the first, and one more such hit is the plan's own
  danger idea), marked `maxEstimated = true` on the target and on the scenario; the player's max is
  the plain one recorded. Every report that prints a percentage of a party member's health must say
  "estimated" (T14, T16); **the deficit is exact and is what the engine decides on**.
- Health, reconstructed (plan §2.3): per target a deficit, `+ DMG`, `- HEAL` (all heals, own and
  foreign -- they all landed), floored at 0, starting at 0 (full at the pull -- the plan's anchor),
  set to the max at a `DIED`; health = max - deficit, sampled on a 2 s grid from 0 to `dur`.
- Forever has no unreported regen (Dreamstate is TBC; plan §2.5): `initial.energize = 0`,
  `apiBase` / `apiCasting` = the first mana sample's `base` / `cast`.
- Kit families and the spell index: T15 (`MD.SpellData.spells[id].family`, `HOT_INDEX` names).

## Files

| file | change | role |
|---|---|---|
| `Modules/SpellTuner_Replay/Scenario_Forever.lua` (new) | `SM.AttributeHeals`, `SM.EstimateMaxHP`, `SM.ScenarioV3`; wraps `SM.ScenarioFromRecording` so `rec.v == 3` goes to `ScenarioV3` and anything else to the original; defines `MD:ClassifyCast(id)` **only if nil**: `(label, kind)` from the book -- a heal family `heal`, a damage family `damage`, a kindless book spell `utility`, else `unknown` | the scenario |
| `Modules/SpellTuner_Replay/*.toc` | `Scenario_Forever.lua` after `Engine\SimModel.lua`, before `Ready.lua` | TOCs |
| `tools/foreverfixture.lua` (new) | `return function(opts) ... end` building the hand-made v3 stream below (a fresh table each call; `opts` may override the meter, a death, the foreign heals) -- T14, T16 and T17 reuse it | fixture |
| `tools/scenariocheck.lua` (new, forever) | the suite below, on that stream | suite |

### `SM.ScenarioV3(rec, kit)` returns the v2 shape plus

- `ev`: a **new** array set (never the stream's own): `DMG`, `DIED`, `CASTSTART`, `CANCEL` copied;
  each `HEAL` either dropped (own) or copied as `FHEAL` (foreign); `OWNCAST` copied (the engine's
  script reads it through `script`, as v2).
- `targets[i]`: `maxHP` (plain or estimated), `maxEstimated`, `danger` (v2's rule on the recorded
  hits), `hp0 = maxHP`, `tracked` (in `rec.tracked` and hit or healed at least once).
- `initial`: `{mana, form = "caster", apiBase, apiCasting, energize = 0, auras = <mapped>,
  known = <engine family keys>}`; an aura whose spell is not in `MD.SpellData.spells` is dropped.
- `script` and `fixed` as v2 (fixed = casts not in `MD.SpellData.spells`, with `MD:ClassifyCast`'s kind).
- `rates` from `rec.mana`; `sampleT = rec.mana.t`; `hpSampleT` = the 2 s grid.
- `recordedHp = { t = grid, hp = { [i] = {...} } }` (the reconstruction), `attribution = { own,
  foreign, ownDirect, ownTick, prepull }` counts, `maxEstimated` (any target), `incoming = {}`,
  `threat = {}` (secret by policy, plan §5).

## Rules

- Pure: no client call, no `MD.API`, no `GetTime` in `Scenario_Forever.lua` except `MD:ClassifyCast`
  reading `MD.Book` (which is the adapter's). Never mutate `rec`.
- `Engine/SimModel.lua` untouched; a v2 stream's scenario byte-for-byte what it was (TBC suites).
- No new global; no library. Comments say why; the two escalated functions each carry a header
  comment "Planner ruling <1 or 2>, 2026-09-28 (FOREVER-PLAN.md, rulings for M3)" and the rule in one line.
- Tests first: scenariocheck written and failing first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/scenariocheck.lua` ends `9 ok, 0 failed`. Fixture: a hand-built v3 stream
   (use the field list in T13; say where you took it from), player (max 375) + party1 (tank), 30 s,
   the stub book's Healing Touch R1 and Rejuvenation R1, own casts with targets, foreign heals
   between them, a pre-pull Rejuvenation on party1 with 6 s left, one untracked-kit cast (Wrath).
   Names, verbatim:
   1. "a v3 stream becomes a scenario of the engine's shape, and a v2 one takes the old road"
   2. "a heal landing with an own direct cast on its target is own; the others are foreign"
   3. "a HoT's ticks by cadence are own; a heal between them is foreign"
   4. "a HoT recast on the same target ends the first one's ticks"
   5. "a pre-pull HoT from the out-of-combat read ticks from the start and its ticks are own"
   6. "health is a deficit from every landed amount, floored at full, sampled every two seconds"
   7. "a party member's max is the stated estimate and marked; the player's is the recorded one"
   8. "casts the healing kit does not price are fixed points with their kind from the book"
   9. "the engine replays the scenario to the reconstructed health when the kit matches the heals"
      -- the fixture's own heals equal the kit's amounts; `SM:Run(sc, nil, {critMode = "ev"})`'s
      `hpCurve` against `recordedHp` within 1% of max, mean, per tracked target.
2. Every other suite at its count (TBC sixteen unchanged; the Forever suites; kitcheck 7, recordcheck
   14).
3. `python3 tools/apicheck.py` 0 findings; `--selftest` as after T13a/T13c.
4. `luac -p` clean.
5. Paste into the Report: the failing run; scenariocheck in full; the fixture's attribution counts
   and reconstructed curves (a few rows); every other tail; apicheck; luac; `git status --short`.

## Out of scope

- The gates (T14), the replay window (T16), coaching (T17). The recorder (T13). `Engine/SimModel.lua`.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

(implementer)
