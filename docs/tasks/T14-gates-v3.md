# T14 — the eight gates on a Forever recording, re-founded on the damage meter

Status: **accepted** 2026-09-28 (lead review at the end), after T13d. M3 (`docs/ROADMAP-FOREVER.md` M3, "T14 gates re-founded (calibration
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

### Files

- `Modules/SpellTuner_Replay/Gates_Forever.lua` (new): `SM:ValidateV3(rec, kit)` -- the eight
  gates, in order `mana mean`, `mana max`, `health curves`, `no tracked death`, `foreign healing`,
  `model calibrated`, `spend coverage`, `heals attributed`. `Threshold` and `MeanMax` are
  duplicated from `Engine/SimModel.lua` (both are `local` there and that file is untouched by this
  task) but read/write the same `SM.GATES` table, so every threshold's setting/default/why still
  lives in one place; this file only adds `meterOwn` and `attributed` to it (guarded by
  `if not SM.GATES.x`). `SM.HEAL_AMOUNT = "unknown"`, with the Q3 provenance comment. `SM.Validate`
  is wrapped: `local V2Validate = SM.Validate; function SM.Validate(self, rec, kit) ...` dispatches
  `rec.v == 3` to `SM.ValidateV3`, everything else to the original (byte for byte; `Engine/
  SimModel.lua` was not touched).
  - Gate 3 (`health curves`) scores `sc.recordedHp` against `r.hpCurve`, same mean/max rule as v2,
    and appends `, max estimated` to the text when any *scored* target's `maxEstimated` is true.
  - Gate 5 (`foreign healing`) reads `rec.meter.others / (own + others)`; `meter == nil` or
    `meter.read == "none"` fails with `"no damage meter reading after the fight (<why>)"`.
  - Gate 6 (`model calibrated`) compares `r.healed - r.healByFamily.foreign` (the replay's own
    effective healing; `r.healByFamily` already holds effective, not gross, amounts -- see
    `Land()` in `Engine/SimModel.lua`, `eff` is what's added to it -- so no "healed minus
    overhealed" fallback was needed, Facts' own hedge) against `meter.own`. When `meter.bySpell`
    has an entry worth >= 10% of `meter.own`, the largest such entry is named ("<name> is <n>% of
    it") -- the meter's `bySpell` is per spell id (rank-granular), the engine's own breakdown is
    per family only, so there is no rank-level model number to *compare* it against; naming the
    dominant contributor is the reading I used. Flagged below as a question.
  - Gate 7 (`spend coverage`) is v2's gate 8 arithmetic verbatim, renamed, reading `sc.script` and
    `kit` with `MD:ClassifyCast` for anything the kit does not price.
  - Gate 8 (`heals attributed`) calls `SM.AttributeHeals(rec, kit)` directly (pure, already
    exposed), sums the `HEAL` (v3 kind 15, duplicated as a local `V3_HEAL` for the same reason
    `Scenario_Forever.lua` gives for its own duplicate) events its `own` map marks true, and checks
    the shortfall (`paired < meter.own * (1 - limit)`) unconditionally and the long side
    (`paired > meter.own * (1 + limit)`) only when `SM.HEAL_AMOUNT == "effective"`, appending
    `"; only a shortfall is checked until a heal amount is known to be effective"` while it isn't.
- `Modules/SpellTuner_Replay/SpellTuner_Replay.toc` and `..._Mainline.toc`: `Gates_Forever.lua`
  added right after `Scenario_Forever.lua`.
- `tools/gatecheck.lua` (new): the 8-assertion suite below, on `tools/foreverfixture.lua` (no
  changes to the fixture file). A pooled-state bug surfaced while writing assertion 2 (see "the
  failing run" below) and was fixed in the test, not the engine.

### Question flagged (not blocking, noted per the task's own escape hatch)

Facts says of gate 6: "when `meter.bySpell` has spells worth >= 10% of `meter.own`, the worst one
is named." `meter.bySpell` is keyed by spell id (rank-granular, e.g. Rejuvenation rank 1 vs rank 2
are different ids) while the engine's own per-spell healing (`r.healByFamily`) is keyed by family
only (ranks merged) -- there is no rank-level model number on the engine side to size a
"worst-by-drift" against. I read "worst" as "the dominant contributor among the >=10% spells" (by
share of `meter.own`) rather than a per-spell drift, and said so in the code comment. If the lead
meant something else (e.g. a per-rank kit lookup added on top), that is a small follow-up, not a
rewrite of the gate.

### Suites

`bash tools/run.sh tools/gatecheck.lua`, full output:

```
|cff9966ffSpellTuner:|r Recorder: loaded
|cff9966ffSpellTuner:|r Replay: loaded
a v3 recording is validated by the Forever gates, a v2 one by the old                           ok - v3 gates=8 v2 has attribution=nil
the mana gates pass on a clean fixture and say the pool is modelled                             ok - mean=true (mean off by 0.0% of pool (limit 2%) (modelled pool)) max=true (worst sample off by 0.0% of pool (limit 5%) (modelled pool))
the health gate scores the reconstruction and says when a max is estimated                      ok - ok=true text=1 damaged target(s) reproduced, 1 excluded, max estimated
foreign healing is the damage meter's share, and no meter reading fails the gate                ok - pass=true share=false(0.33333333333333) none=false(no damage meter reading after the fight (damage meter closed))
the model is calibrated against the meter's own total, and a drift past the limit fails         ok - baseSimOwn=96.0 pass=true(replay heals 96 effective, the meter counted 96 (0% off, limit 10%)) drift=false(replay heals 96 effective, the meter counted 288 (67% off, limit 10%))
spend coverage counts the book's damage and utility casts as replayed                           ok - ok=true value=1 text=100% of the mana is accounted for (82% healing, 18% replayed as cast)
the attribution gate fails when the paired own total falls short of the meter, and checks the long side only when amounts are effective ok - short=false(own 10 heals paired with your casts, foreign 3; paired total 144 vs meter 500 (71% off, limit 10%); only a shortfall is checked until a heal amount is known to be effective) longUnknown=true(own 10 heals paired with your casts, foreign 3; paired total 144 vs meter 50 (187% off, limit 10%); only a shortfall is checked until a heal amount is known to be effective) longEffective=false(own 10 heals paired with your casts, foreign 3; paired total 144 vs meter 50 (187% off, limit 10%))
every gate text is ASCII with no bare pipe                                                      ok

8 ok, 0 failed
```

The failing run, during development (assertion 2, before the fix): `SM:Run` reuses a pooled state
table (`Engine/SimModel.lua`'s own doc comment: "per-run state from a reused pool slot"), so
`baseRun.manaCurve` captured once at the top of the suite was silently overwritten by assertion
1's own `SM:Validate` calls (each of which calls `SM:Run` again) before assertion 2 read it:

```
a v3 recording is validated by the Forever gates, a v2 one by the old                           ok - v3 gates=8 v2 has attribution=nil
the mana gates pass on a clean fixture and say the pool is modelled                             FAIL - mean=nil (nil) max=nil (nil)
...
7 ok, 1 failed
  FAIL the mana gates pass on a clean fixture and say the pool is modelled - mean=nil (nil) max=nil (nil)
```

Fixed by deep-copying `manaCurve` immediately after the baseline `SM:Run` call, before any other
`SM:Validate`/`SM:Run` call could reuse the slot (`local baseManaCurve = DeepCopy(baseRun.
manaCurve)`, used instead of `baseRun.manaCurve` in assertion 2).

Sanity check that assertion 7 actually exercises the "checks the long side only when effective"
behaviour (temporarily forced `SM.HEAL_AMOUNT = "effective"` for the whole run, then restored):

```
the attribution gate fails when the paired own total falls short of the meter, and checks the long side only when amounts are effective FAIL - short=false(...) longUnknown=false(...) longEffective=false(...)
7 ok, 1 failed
```

confirming `longUnknown` really does flip from pass to fail when the constant changes -- the test
is not just restating the code.

The eight gate lines on a clean fixture (mana copied from the engine's own model; `meter.own` set
to the replay's own effective heal total) and on the same fixture with `meter.own` tripled
(drifted):

```
-- clean fixture: mana copied from the engine's own model, meter.own = the replay's own effective heal total --
ok:	true
mana mean          true  mean off by 0.0% of pool (limit 2%) (modelled pool)
mana max           true  worst sample off by 0.0% of pool (limit 5%) (modelled pool)
health curves      true  1 damaged target(s) reproduced, 1 excluded, max estimated
no tracked death   true  nobody died
foreign healing    true  0% of healing on your group was somebody else's (limit 25%)
model calibrated   true  replay heals 96 effective, the meter counted 96 (0% off, limit 10%)
spend coverage     true  100% of the mana is accounted for (82% healing, 18% replayed as cast)
heals attributed   true  own 10 heals paired with your casts, foreign 3; paired total 144 vs meter 96 (49% off, limit 10%); only a shortfall is checked until a heal amount is known to be effective

-- drifted fixture: same mana, meter.own tripled (model calibrated + heals attributed drift) --
ok:	false
mana mean          true  mean off by 0.0% of pool (limit 2%) (modelled pool)
mana max           true  worst sample off by 0.0% of pool (limit 5%) (modelled pool)
health curves      true  1 damaged target(s) reproduced, 1 excluded, max estimated
no tracked death   true  nobody died
foreign healing    true  0% of healing on your group was somebody else's (limit 25%)
model calibrated   false replay heals 96 effective, the meter counted 288 (67% off, limit 10%)
spend coverage     true  100% of the mana is accounted for (82% healing, 18% replayed as cast)
heals attributed   false own 10 heals paired with your casts, foreign 3; paired total 144 vs meter 288 (50% off, limit 10%); only a shortfall is checked until a heal amount is known to be effective
```

(Note: `heals attributed` "passes" in the clean case despite a 49% gap between `paired total`
(144, the sum of `HEAL` events the attribution matched to a cast) and `meter.own` (96, set equal to
the *effective* engine total) only because `SM.HEAL_AMOUNT ~= "effective"` -- the gate only checks
the shortfall direction, and 144 > 96 is the long side. This is the ruling working as specified,
not a bug: paired totals are necessarily gross-ish (raw recorded `amt`, pre-overheal-split) while
the engine's own total is post-overheal-floor, so until `SM.HEAL_AMOUNT` is known to be effective
the two are expected to disagree on this side.)

Every other suite, at its baseline count:

```
simcheck         PASS (measured mean 1.3% max 2.8% at 23.0s (+23.1 mana/s energize))
reccheck         54 ok, 0 failed
replaycheck      80 ok, 0 failed
replayui         98 ok, 0 failed
runcheck         78 ok, 0 failed
reviewui         44 ok, 0 failed
navui            25 ok, 0 failed
dashui           56 ok, 0 failed
regencheck       27 ok, 0 failed
simwindow        8 ok, 0 failed
solvercheck      70 ok, 0 failed
timeline         27 ok, 0 failed
spelltip         48 ok, 0 failed
practice         74 ok, 0 failed
practiceui       49 ok, 0 failed
migrate          7 ok, 0 failed
probecheck       73 ok, 0 failed
forevercheck     13 ok, 0 failed
modulecheck      14 ok, 0 failed
kitcheck         7 ok, 0 failed
recordcheck      14 ok, 0 failed
scenariocheck    9 ok, 0 failed
gatecheck        8 ok, 0 failed   (new)
parsecheck       11 ok, 0 failed
bookcheck        15 ok, 0 failed
tipcheck         14 ok, 0 failed
clockcheck       15 ok, 0 failed
spellsui         15 ok, 0 failed
measurecheck     18 ok, 0 failed
adaptercheck/forever  19 ok, 0 failed
adaptercheck/tbc      15 ok, 0 failed
corecheck/forever     10 ok, 0 failed
corecheck/tbc          8 ok, 0 failed
svcheck/forever        6 ok, 0 failed
svcheck/tbc            1 ok, 0 failed
consolecheck/forever  11 ok, 0 failed
consolecheck/tbc       1 ok, 0 failed
```

`python3 tools/apicheck.py`:
```
apicheck: 8 Forever TOCs, 29 files, 41 distinct globals, 0 findings (baseline 69893)
```
(29 files, up from the baseline's 28, because `Gates_Forever.lua` is now counted; still 0
findings -- the file only calls `SM`/`MD` functions, never a `C_*` global or a Blizzard global
directly.)

`python3 tools/apicheck.py --selftest`: `selftest: 10 of 10 findings as expected` (unchanged).
`python3 tools/refcheck.py --selftest`: `selftest: ok` (unchanged).

`luac -p` (no system `luac`; used the repo's own built Lua 5.1.5's `luac` per `tools/run.sh`):
```
tools/.lua/lua-5.1.5/src/luac -p Modules/SpellTuner_Replay/Gates_Forever.lua tools/gatecheck.lua
LUAC_OK
```
(clean on both files; the rest of the tree was not touched.)

`git status --short`:
```
 M Modules/SpellTuner_Replay/SpellTuner_Replay.toc
 M Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc
 M docs/tasks/HANDOVER.md
?? Modules/SpellTuner_Replay/Gates_Forever.lua
?? tools/gatecheck.lua
```
`docs/tasks/HANDOVER.md` was already modified before this task started (the lead's, per the
handoff instructions) and was not touched here; `git diff docs/tasks/HANDOVER.md` was not run by
this implementer and the file's content was never opened.

### Skipped / out of scope

- `docs/TOOLS.md` §1's suite-loop listing was not updated to add `gatecheck` (docs files besides
  this Report are out of scope per the task).
- T16 (Review tab, replay window), T17 (coach) and runs: untouched, as scoped.
- No `git add`/`stash`/`checkout -- <path>`/`reset`/commit was run.

## Lead review (2026-09-28)

Accepted. The lead reran every suite (gatecheck 8, scenariocheck 9, recordcheck 14, kitcheck 7,
everything else at its baseline; apicheck 0 over 29 files, `--selftest` 10 of 10, refcheck ok) and
`luac -p`. `r.healed` is effective healing in the engine (`Engine/SimModel.lua` 374), so gate 6
compares like with like. Gate 6 naming the meter's largest spell rather than the worst-drifting one
is accepted as reported: the engine has no per-rank number to compare. Gate texts can carry player
names as the client gave them (non-ASCII on EU realms); the paint layer escapes them -- the rule was
added to T16a and T16b rather than to this file.
