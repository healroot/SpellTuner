# T14 — the eight gates on a Forever recording, re-founded on the damage meter

Status: **open**, after T13d. M3 (`docs/ROADMAP-FOREVER.md` M3, "T14 gates re-founded (calibration
and foreign share from `C_DamageMeter`; enemy-cast and threat inputs removed)").

## Goal

`SM:Validate(rec, kit)` answers a v3 stream with the same result shape the Review tab and the coach
already read -- `{ ok, gates = { {name, ok, text, value, limit, why} ... }, excluded, result, ... }`
-- with each gate re-founded on what Forever can know: health against the reconstruction, foreign
healing and the model's calibration against the damage meter's totals for the fight, mana against the
modelled pool and **said to be modelled**, spend coverage by the book. A recording still earns the
right to be coached from. For T16 (Review, replay window), T17 (coach) and the author's first
Forever pulls.

## Facts

- v2's gates (`Engine/SimModel.lua` 1204-1420): mana mean / max against the recorded pool samples;
  health curves per damaged target (excluded, not fatal, when off); no tracked death (practice
  exempt); foreign healing share (`rec.foreignShare`, TBC's combat log); model calibrated
  (`MD.Calibration:Drift` per spell >= 10% of spend, TBC only); spend coverage (kit + classified
  casts >= 90%). Thresholds in `SM.GATES` with provenance; each gate prints its own.
- Plan §2.3: "the health gate becomes stronger (more samples); the calibration gate needs a new
  source (own healing total from the damage meter vs the model's total per fight); the foreign-share
  gate reads the damage meter; the enemy-cast and threat inputs are dropped."
- The meter counts **effective** healing (eighth report: Healing Touch 88-112 counted 31). T13's
  `rec.meter = { own, others, bySource, bySpell, read = "current" | "none", why }`.
- The recorded mana is **the clock's model** (T13, `manaModelled = true`), so a mana gate compares the
  engine's mana model with the live mana model -- a consistency check (both from costs and regen),
  not a check against the real pool, which is secret. **Planner ruling 3** (`FOREVER-PLAN.md`,
  rulings for M3 above §2.4): keep the two mana gates, every report of them saying "modelled pool" --
  they measure consistency, not truth; thresholds as v2.
- **Planner ruling 2**: heals are attributed offline (T13d `SM.AttributeHeals`); "the damage meter's
  own healing total is the check, reported by gate 8 ('heals attributed'); a pull whose attributed
  own total disagrees with the meter beyond the gate's threshold is not coached from." So gate 8
  **can fail**. Whether a `UNIT_COMBAT` HEAL amount is gross or effective is still open (Q3; §38.2
  step 4 asks): if gross, the paired total exceeds the effective meter by the overheal on every
  honest pull. Lead's reading of the ruling, recorded here: the **short** side (paired own below the
  meter -- own heals the attribution called foreign, which the engine would then replay on top of
  its own) is always checked; the **long** side only once `SM.HEAL_AMOUNT == "effective"` (a
  constant in `Gates_Forever.lua`, `"unknown"` until the author's §38 answer, with that provenance
  comment), and the gate text says when it is one-sided.
- Health is reconstructed (T13d `sc.recordedHp`), party maxima estimated (`targets[i].maxEstimated`):
  the health gate's text says "estimated max" when any scored target's is.
- The engine's own healing by family: `SM:Run`'s result (`healByFamily`, `ohByFamily` -- check
  the field names in `Engine/SimModel.lua`'s result table and use them; if effective healing is not
  there, compute it as healed minus overhealed and say so).

## Files

| file | change | role |
|---|---|---|
| `Modules/SpellTuner_Replay/Gates_Forever.lua` (new) | `SM:ValidateV3(rec, kit)`; wraps `SM.Validate` so `rec.v == 3` goes to it and anything else to the original; adds to `SM.GATES` (only if absent) `meterOwn = { setting = "simGateMeter", default = 0.10, why = "lead's first threshold (2026-09-28); the meter counts effective healing; re-measured in M5" }` and `attributed = { setting = "simGateAttrib", default = 0.10, why = "planner ruling 2 (2026-09-28); lead's first threshold; re-measured on the author's first Forever pulls" }`; `SM.HEAL_AMOUNT = "unknown"` | the gates |
| `Modules/SpellTuner_Replay/*.toc` | `Gates_Forever.lua` after `Scenario_Forever.lua` | TOCs |
| `tools/gatecheck.lua` (new, forever) | the suite below, on `tools/foreverfixture.lua` | suite |

### The eight gates, v3 (same names as v2 where the meaning holds)

1-2. `mana mean`, `mana max`: v2's arithmetic on `rec.mana.v`; text adds `(modelled pool)`.
3. `health curves`: v2's rule on `sc.recordedHp` (`hp.t` = the 2 s grid) with `tg.maxHP`; text adds
   `, max estimated` when any scored target's max is.
4. `no tracked death`: as v2.
5. `foreign healing`: `others / (own + others)` from `rec.meter`, v2's limit and text; `read ==
   "none"` -> fails, `no damage meter reading after the fight (<why>)`.
6. `model calibrated`: the replay's effective own healing against `meter.own`:
   `abs(sim - meter) / meter <= simGateMeter`; text `replay heals <sim> effective, the meter counted
   <meter> (<d>% off, limit 10%)`; when `meter.bySpell` has spells worth >= 10% of `meter.own`, the
   worst one is named. No meter -> fails with the reason.
7. `spend coverage`: v2's rule, with the Forever `MD:ClassifyCast` (T13d).
8. `heals attributed`: new (ruling 2). `own <n> heals paired with your casts, foreign <m>; paired
   total <a> vs meter <b> (<d>% off, limit 10%)`, plus `; only a shortfall is checked until a heal
   amount is known to be effective` while `SM.HEAL_AMOUNT ~= "effective"`. Fails when `a < b * (1 -
   limit)`, or `a > b * (1 + limit)` with `SM.HEAL_AMOUNT == "effective"`; no meter -> fails with the
   reason. A failed gate 8 makes `ok` false like any other gate, so the coach refuses the pull
   (shift / `force` still coaches, as v2).

## Rules

- Pure except for what `SM:Run` already does; no client call. Never mutate `rec`.
- `Engine/SimModel.lua` untouched; v2 validation byte-for-byte (TBC suites).
- ASCII, no bare `|` in any gate text (the Review tab paints them). No new global; no library.
- Tests first: gatecheck written and failing first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/gatecheck.lua` ends `8 ok, 0 failed`. Names, verbatim:
   1. "a v3 recording is validated by the Forever gates, a v2 one by the old"
   2. "the mana gates pass on a clean fixture and say the pool is modelled"
   3. "the health gate scores the reconstruction and says when a max is estimated"
   4. "foreign healing is the damage meter's share, and no meter reading fails the gate"
   5. "the model is calibrated against the meter's own total, and a drift past the limit fails"
   6. "spend coverage counts the book's damage and utility casts as replayed"
   7. "the attribution gate fails when the paired own total falls short of the meter, and checks the long side only when amounts are effective"
   8. "every gate text is ASCII with no bare pipe"
2. Every other suite at its count.
3. `python3 tools/apicheck.py` 0 findings; `--selftest` as after T13a/T13c.
4. `luac -p` clean.
5. Paste into the Report: the failing run; gatecheck in full; the eight gate lines on the clean
   fixture and on a drifted one; every other tail; apicheck; luac; `git status --short`.

## Out of scope

- The Review tab and replay window (T16); coaching (T17); runs. The TBC gates.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

(implementer)
