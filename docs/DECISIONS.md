# ManaDemon — design decisions and rationale

This documents the full design process: two AI agents ("Party A: Theorycrafter" — math
correctness first; "Party B: UX Pragmatist" — glanceable, decision-driving UI first)
brainstormed independently, exchanged rebuttals, and critiqued the implementation plan;
a judge synthesized; the author (NeRgY, Resto Druid, TBC Anniversary) made the final calls.
Date: 2026-09-01.

## v1 scope (final)

1. **Static spell data table** (`Data/SpellData.lua`) — ships first: the 2.5.x client does
   not reliably expose per-rank mana costs, so a frozen hand-built table is the foundation
   *and* the schedule risk. Verified once in-game via `/md verify`.
2. **TTO engine** — spend rate from casts (EWMA), regen rate analytic, FSR state machine.
3. **One-line combat UI** — floating widget + ElvUI datatext, both rendering
   `MD:GetDisplayString()`. 5SR underline on the widget.
4. **Rank dashboard** (`/md`) — druid-only, Pareto-filtered.
5. **Advisor extras** — Innervate/potion advisor, gear-change rank toast, drink reminder
   (all four extras chosen by the author; the drink reminder was disputed — A called it a
   nag, B proposed it — author sided with B).
6. **End-of-combat summary** + last-5-fights in-memory history.

**Cut from v1** (explicit decisions, not omissions):
- **History-based fine-tuning of the OOM prediction** — both parties converged on cutting
  it: the decision it drives ("pot now or in 20s?") is coarse; weeks of modeling to move a
  number the player rounds anyway. Survives only as: (a) pull-time seeding of the spend
  EWMA from the last ~5 fights' median rate, (b) a "last fight" reference line. No
  SavedVariables persistence of history, no curve fitting.
- **Non-druid rank dashboard** — per-class coefficients/spell lists are real work; the TTO
  engine is class-generic for free (see FSR decision below), so TTO+advisor work for any
  healer and the dashboard says so.
- **Confidence band in the UI** — A wanted p25/p75 shown; B argued a band isn't actionable.
  Merged: the single displayed number is the *pessimistic* edge (p75 of the spend
  distribution) and instability is carried by one `~` prefix + grey, driven by a
  suppression rule (≥6 casts in window AND IQR ≤ 40% of median).
- **Config UI** — slash commands + three checkboxes in the dashboard footer.
- Raid comms/sync, graphs/animations/themes, "efficiency scores", per-rank
  overheal-calibrated recommender (v2 candidate — needs a corpus of the author's logs).

## Model decisions (who won which argument)

| Decision | Outcome | Why |
|---|---|---|
| TTO before dashboard | **B** (A conceded) | TTO needs only cost+cast-time; the dashboard's dependency chain (coefficients, talents, Lifebloom split) is deeper, not shallower. |
| EWMA over 10s sliding window | **A** | Spirit regen ticks every 2s; a 10s window catches 3–5 ticks (±40% swing) and extrapolates chain-cast bursts into eternity. EWMA is also less code. |
| Regen analytic, never regressed from raw mana | **A** (B conceded) | Regressing raw mana entangles spend and regen; Innervate/potions poison the sample. |
| Use `GetManaRegen()` returns **directly** (base = out of FSR, casting = in FSR) | **A's self-correction** | Decomposing into spirit/mp5 components and re-weighting double-counts Intensity (casting already includes it). The spirit/mp5 decomposition exists for display only. Refreshed every tick because the value can go stale mid-combat on Classic clients. |
| FSR trigger = any player mana *decrease* on `UNIT_POWER_UPDATE` | **A (plan critique)** | Spell-table-independent: catches wands, off-spec casts, any class — this is what makes TTO class-generic. `UNIT_SPELLCAST_SUCCEEDED` alone misses spenders and the deduction anchor is unverified (hence `/md fsrtest`). Known false-positive: enemy mana burns (accepted). |
| Sustainable sentinel instead of TTO=∞ | **A (plan critique)** | `mana / max(0, spend−regen)` divides by zero when regen wins. |
| Spend-cost fallback = `GetSpellPowerCost` (pcall), then **log**, never UnitPower-delta sampling | **B (plan critique)** | Delta sampling races spirit ticks and Innervate; a missing cost is exactly what `/md verify` should report, not paper over. |
| Drop dominated-rank rows behind "show all"; never highlight raw best-HPM | **A** (B conceded) | Raw HPM monotonically favors rank 1 — an HPM-only dashboard always answers "HT R1". Pareto filter on (HPM, HPS); "suggested" = highest-HPM non-dominated rank healing ≥40% of max rank (labeled assumption). |
| Mana-cost modifier pipeline (Moonglow −3%/r on HT/Regrowth/Rejuv, Tranquil Spirit −2%/r on HT/Tranquility, Tree of Life −20% on HoTs, floor at the end) | **A (plan critique)** | Without it every HT HPM figure is off by up to ~18% for a typical resto build. |
| Talents scanned by **name** across all tabs, re-scanned on respec events | **A (plan critique)** | Positional `(tab, index)` silently returns the wrong talent when builds shift. |
| Widget: single visibility owner, 90/95% hysteresis, frames created at login, position persisted, `/md unlock`+`reset`, first-run 60s forced preview | **B (plan critique)** | Prevents flicker at the threshold, mid-pull frame creation, unrecoverable off-screen drags, and the "fresh install shows nothing" trap. |
| Model event-driven; tickers only accumulate/render | **A (plan critique)** | The draft ran the 0.25s recompute "only while the widget is shown", which would stall the estimator while hidden. |
| ElvUI datatext built-in (not a separate addon), `## OptionalDeps: ElvUI`, clamp ElvUI's first `elapsed=20000` OnUpdate call, take theme color from `ApplySettings` | **B** (A conceded v1 placement) | Verified against vendored ElvUI TBC build: `DT:RegisterDatatext` exists, comparable datatexts are 19–72 lines. |
| One attention event per fight (pulse at TTO<30s), no sound | **B** | Alert fatigue kills combat UIs. |
| 5SR underline stays in v1 | **Author** (B tried to defer its own idea) | Author explicitly selected it. |
| Drink reminder in v1 | **Author** (against A's cut vote) | |

## Formulas encoded in `Engine/RankMath.lua`

- Direct coefficient: `clamp(baseCastTime, 1.5, 3.5) / 3.5`
- HoT coefficient: `duration / 15`
- Hybrid (Regrowth, c = cast/3.5, h = dur/15): direct `c²/(c+h)` ≈ 0.1657, HoT `h²/(c+h)` ≈ 0.9941
- Sub-level-20 malus: `1 − (20 − spellLevel) × 0.0375` (3.75%/level, **not** 5%)
- Downrank penalty: `min(1, (spellLevel + 11) / casterLevel)`
- Penalties apply to the **bonus-healing contribution only**, not base heal
- Healing crits are **1.5×**; HoTs never crit; Improved Regrowth is +10% crit *chance*/rank (Regrowth only)
- Talent multipliers applied after coefficients: Gift of Nature +2%/r (all), Improved
  Rejuvenation +5%/r, Empowered Rejuvenation +4%/r on the bonus portion of HoTs,
  Empowered Touch +10%/r on the bonus portion of HT, Naturalist −0.1s/r HT cast
- Lifebloom: HoT coefficient 0.5187 total, bloom 0.3422 (empirical 2.4-era values)

## Open verification items (run `/md verify` in-game)

- All `-- VERIFY` rows in `SpellData.lua` (high-rank costs/heals are the least certain).
- `GetManaRegen()` unit (assumed mana **per second**; ElvUI's TBC datatext ×5 agrees) and
  its combat staleness behavior.
- FSR anchor: cast start vs. mana deduction vs. cast completion → `/md fsrtest`.
- ~~Whether talent-modified costs floor or round~~ — **round** (Swiftmend 216.8 → 217, 2026-09-03). Tree of Life also discounts Tranquility.
- ~~Lifebloom coefficients and whether Empowered Rejuvenation touches the bloom~~ — **confirmed 2026-09-03** (heal log): 0.5187 / 0.3422 exact, Emp Rejuv applies to the bloom
  (assumed **not** — applied to tick portion only, conservative).
- `GetSpellPowerCost` presence on the anniversary client (harness reports either way).
- Downrank penalty exact form vs. tooltip reality at level < 70.

## v2+ backlog (from the debates)

- ~~Overheal-calibrated effective HPM~~ — **shipped v0.5.3** (`Engine/Overheal.lua`).
- ~~Per-boss "last time you sustained X mps" reference~~ — **shipped v0.5.3** as a
  zone-scoped pull seed (`MD.cdb.fights`); per-boss would need encounter IDs.
- ~~TTO-with-cooldowns second line~~ — **shipped v0.5.2** as the `inn 2:10` segment.
- Non-druid rank dashboards (priest first).
- Rank→keybind/macro helper; localization.

## Feedback round 3 (2026-09-02): OOM + FULL display, estimator stability

The author reported the readout "changes a lot and it is hard to catch what it really
means" and asked for OOM time and time-to-full "at the same place". Same two-party
debate (A Theorycrafter, B UX Pragmatist) with a rebuttal round; judged by Fable.
Both parties converged on most of the math; the table records who won the rest.

| Decision | Won by | Why |
|---|---|---|
| One signed clock, label carries the sign (`OOM 1:20` / `FULL 0:45`), not two permanent slots | **both** | One of the two is structurally dead (`--`) in every state; a permanent dead slot is the confusion being fixed. |
| Secondary `rest 2:10` segment = time to full if you stop casting now, combat only, hidden when within 25% of the primary or next to a FULL clock; `/md rest` toggle | **A** (B conceded, then A conceded back — judge kept it) | Every input is exact (mana, `GetManaRegen`, FSR clock) so it is ~zero-variance; it is the cost of the decision the primary provokes (drop out / Innervate / pot) and it is live during warm-up. It is also the literal "both at the same place" the author asked for. |
| Separator is two spaces, never `\|` | **B** | A bare pipe opens a WoW colour escape and eats the rest of the line. |
| Drop `max(EWMA, p75-of-six-buckets)`; pessimistic = `rate + 1.0 * sigma`, `sigma = lambda * sqrt(sum w^2 c^2)` | **A** (B conceded) | `max()` of two estimators is upward-biased by an unstatable amount and kinks when the argmax switches; the 6-bucket order statistic re-sorts every 5s. Sigma is continuous, calibrated (`sigma/rate = 1/sqrt(n)` for equal casts), one extra accumulator in the same loop, and it feeds display precision and the stability flag for free. Caveat: real casting is autocorrelated, so sigma understates; `K=1.0`, `CV<=0.35` are first guesses. |
| Regen for projection = FSR-duty-weighted `duty*casting + (1-duty)*base`, duty = EWMA of in-FSR (half-life 20s), reset to 1 at pull | **both** | Instantaneous `RM:Current()` flips the denominator by the whole spirit share every time a casting gap crosses 5s — the single biggest source of jumps. Both `GetManaRegen` returns are still consumed raw; nothing is decomposed. `RM:Current()` keeps driving the 5SR underline. |
| Display precision derived from uncertainty: step = smallest of {1,5,10,15,30,60} >= 0.5*sigma_TTO (floor 1s/5s, cap 60s); step coarsens at once, refines only after holding 5s | **A** + B's ratchet | Showing `1:23` when sigma is 20s is a lie of precision. Zero bias: only rendering resolution changes. The ratchet stops the granularity itself from flickering. |
| Latch, not a smoothing filter, on the shown value: change after 2 consecutive ticks, except worsening by >2 steps or crossing 60s/20s downward (instant) | **A** (B conceded its asymmetric follower) | `TTO = mana/net` is convex in `net`, so time-averaging the horizon is biased optimistic (Jensen). The latch has no bias in either direction. Raw `GetManaState()` stays unsmoothed for the advisor/summary. |
| `hold` mode when `\|net\| <= sigma`: print the one-sided bound `OOM >4:00 =` (`mana/(net+sigma)`), `OOM >10m` when unbounded; mode changes toward "better" also need 2 ticks | **A** (B conceded its 1.10/0.98 label hysteresis) | A true statement instead of a point estimate that is statistically zero; the hysteresis falls out of the statistics instead of being bolted on. Replaces the old "sustainable" sentinel. |
| Arrow derived from the SHOWN value over ~10s, adjusted for the 1s/s countdown (`=` steady drain, `v` losing ground faster, `^` recovering); no arrow in FULL or out of combat | **A** (B: "the best idea in A's proposal") | Arrow and number can no longer contradict each other; the old raw-net ring could. |
| Out of combat: fill = max(observed mana-gain EWMA (half-life 5s, >=2 gains), FSR-aware `GetManaRegen`) | **B** (A conceded) | Drink/food are periodic energize effects `GetManaRegen` does not report; without this the FULL clock would read ~10x too long in the widget's most common OOC state. `/md verify` now prints the drink-buff state next to `GetManaRegen` to confirm the premise. |
| Half-life stays 15s (user-settable 5–60) | **A** | Noise falls as `1/sqrt(H)`; 4x half-life buys 2x less noise and an 86s window straddles fight phases. Sigma now expresses the uncertainty honestly instead of hiding it. (Each party conceded the other's number; judge kept the default.) |
| Widget text left-anchored, 190px, render 0.25s (underline stays 0.1s), `>10m` cap | **B** | Centred text slides when the digit count changes; beyond 10 minutes the raw number is both enormous and relatively unstable and drives no different action. |
| Rejected: counterfactual "at fight-average spend" second clock; confidence band; second line | **B** | A readout the player must be taught fails the one-second glance test. |

Supersedes the v1 rows "pessimistic edge = p75" and "sustainable sentinel".

## Talent audit (2026-09-03)

Reviewed every talent that touches heal size, mana cost or regen against `Engine/RankMath.lua`,
`Data/SpellData.lua` and `Engine/RegenModel.lua`.

| Talent | Where | Status |
|---|---|---|
| Gift of Nature +2%/r | RankMath, all families incl. Lifebloom bloom | OK |
| Improved Rejuvenation +5%/r | RankMath (whole Rejuv heal) | OK, but see stacking below |
| Empowered Rejuvenation +4%/r on HoT bonus | Rejuv, Regrowth HoT, Lifebloom ticks (+x2/x3 rows) | OK; bloom deliberately excluded pending verification |
| Empowered Touch | RankMath, HT bonus × (1 + 0.1r) | **Wrong shape**: the talent ADDS 0.1r to the coefficient. Identical for HT R5+ (coef 1.0), low for R1–R4 |
| Improved Regrowth +10% crit/r | RankMath (Regrowth direct only) | OK |
| Naturalist −0.1s/r HT | RankMath cast time; coefficient still from base cast | OK |
| Nature's Grace (−0.5s next cast after a crit) | — | **Not modelled**; ≈ −0.5·crit s per chain-cast HT/Regrowth (a few % HPS) |
| Moonglow −3%/r (HT, Regrowth, Rejuv) | SpellData:GetCost | OK, but see stacking |
| Tranquil Spirit −2%/r (HT, Tranquility) | SpellData:GetCost | OK, but see stacking |
| Tree of Life −20% cost on form HoTs; castable set | SpellData:GetCost, families.tol | OK |
| Intensity, Living Spirit, Dreamstate, Lunar Guidance, Natural Perfection, Tree aura | via `GetManaRegen` / `UnitStat` / `GetSpellBonusHealing` / `GetSpellCritChance` | Implicit, no double count — **except Dreamstate, which the author reports is NOT in the reported mp5** |
| Omen of Clarity | — | Melee-proc only in TBC; irrelevant to a healer's spend |

**Percent-modifier stacking.** The code multiplies same-type percent mods; the TBC client
sums them first (spellmod pct accumulation). GoN 5 + Imp Rejuv 3 = +25%, not +26.5%;
HT cost with Moonglow 3 + Tranquil Spirit 5 = −19%, not −18.1%; Rejuv/Regrowth in Tree
with Moonglow 3 = −29%, not −27.2% (≈7 mana per Rejuv). The cost half shows up directly as
COST mismatches in `/md verify`; that output decides it (open item, not changed yet).

**Dreamstate.** Measured 2026-09-03 (`/md regentest`, two specs, same character): the raw
`GetManaRegen()` EXCLUDES it — ticks ran ~34 mp5 above the API with the talent and matched
the API without. `RegenModel` now adds `{4,7,10}% × Int / 5` per second to both rates
(`RM.unreported`); the raw values are kept in `RM.apiBase/apiCasting` and the test compares
against those, so the verdict remains valid. Not extended to other classes' int-based regen
talents (Shaman Unrelenting Storm) until measured.

**Costs, superseding "the 2.5.x client does not reliably expose per-rank costs" (v1 scope) and
"mana-cost modifier pipeline" (model decisions):** `GetSpellPowerCost` works on this client
(44 costs checked), so `SD:GetCost()` is live-first and the static table is the fallback +
verify reference. Static Rejuvenation R6–R12, Tranquility R1–R4 and Swiftmend costs were
wrong and are now the live values; Innervate is a percentage of base mana and has no static
cost. With live costs the cost-side stacking question is moot; the heal-side one (GoN +
Improved Rejuvenation, ≈1%) stays open.

**Spirit share decomposition (display only):** the level-70 constant read 2× low at level 64,
so `RM:Components()` now derives it from the API's own two numbers and the in-5SR talent
fraction: `S = (base − casting) / (1 − f)`, `G = base − S`. Cross-checked: G = 21 mp5 in both
specs of the test character.

**Display latch:** the shown value now latches on a candidate within one step of the previous
candidate (jitter-tolerant); and the OOC observed-fill estimate is an EWMA over gain events
(gain / interval), not a per-tick EWMA of a 2s-periodic signal. Fixes `FULL 2:05` stuck at a
true 94s.

**Tree of Life form (2026-09-03, v0.4.2).** Cost: live via `GetSpellPowerCost`, refreshed on
`FORM_CHANGED`. Heal: the form's aura is +25% of Spirit as healing *received* by party members
(the tree included), invisible to `GetSpellBonusHealing()`; `RankMath` adds it to the +healing
input while in form (`db.treeAura`, default on) because it takes the same coefficient and
downrank path as caster +healing (MaNGOS-era `SpellHealingBonus`: taken advertised benefit ×
coeff). Only true for party targets, which is why it is a setting and labelled on the
dashboard. **Confirmed 2026-09-03** (heal log): Rejuv ticks +21 and Lifebloom ticks +7 / bloom +32
in form = 70 Spirit × coefficient × Emp Rejuv × talent multipliers, i.e. exactly "+healing on the
target". The aura is target-side and dynamic: a HoT already running gains it the moment the
tree shifts. **Relics:** the same log showed Rejuvenation ~3% above the model with Lifebloom
exact — the signature of a flat +50 on Rejuvenation (Idol of Rejuvenation); `SD.relics` +
`SD:Relic()` read the relic slot and add flat / per-tick / aura bonuses (best-effort table,
VERIFY per idol). With the idol, GoN × Improved Rejuvenation fits multiplicative (1.265) better
than additive (1.25); kept multiplicative.

## Settings window and debug console (2026-09-03)

| Decision | Why |
|---|---|
| Mimic Cell's options UI (flat 0.115-grey panels, 1px black borders, class-colour accent, tab buttons on the frame's top edge, titled panes, 13/14px fonts) with a from-scratch kit in `UI/Style.lua` | Author's explicit ask ("I like their settings in general"). No dependency on Cell or its libraries; no pixel-perfect layer — plain sizes are enough for one fixed-width window. |
| Settings live in their own frame (`/md options`), the dashboard keeps only a "Settings" button | Cell separates the options frame from the unit frames; the rank table and the options have different widths and lifetimes. |
| Debug console = Cell's DebugConsole concept: `MD:Debug()` is a no-op unless enabled, memory-only ring (1000 lines), category filters, Copy popup with select-all edit box | Author's ask ("debug logs concept"). Memory-only keeps SavedVariables clean; the Copy popup is the only way to get text out of the client. |
| Explicit categories on each `MD:Debug` call (regen / mana / spend / tto / combat / chat / other) instead of Cell's pattern-matching on the text | Cheaper and never misfiles a line. |
| `MD:Print` mirrors into the `chat` category | `/md verify` and the regen test output become copyable without a second code path. |
| Timestamp = wall clock + seconds since load with 2 decimals | Sub-second spacing is the point for mana ticks and 5SR edges; wall clock ties it to the author's notes. |
| `/md regentest` measures instead of assuming (observed gain vs time-weighted API, diff vs `{4,7,10}% × Int / 5`) | The only honest way to answer whether the API includes Dreamstate on this client. |


## v0.5 (2026-09-05): design calls made without a debate round

Design in `docs/DESIGN-v0.5.md`; the author approved it and said to implement. The five
calls its §11 flagged as arguable were decided as follows — all reversible, and each one
notes what would change my mind.

**1. `inn 2:10` takes the one-liner's secondary segment (under 90s), rather than living
only in the tooltip.** The widget's value is that it never changes shape, so this spends
its single secondary slot. Justification: under 90s the cooldown is the only decision
left, and `rest` ("stop casting entirely") is the option you are least likely to take.
Gated on the cooldown being ready AND worth ≥10% of the pool, so it stays quiet otherwise.
`db.showCooldown` turns it off. **Would change my mind:** the author finding it noisy in
one real fight (`docs/TESTING.md` §9 asks directly).

**2. Overheal keyed by family, refined per rank at 40 events.** Per-rank-only would be an
empty column for months; family-average is precisely the wrong shape for "does downranking
overheal less", since one factor on every rank of a family cannot reorder them. Both are
true, so both are shown: the tooltip labels the scope, and a rank with no data of its own
shows the raw number with a grey `?` rather than a borrowed one dressed up as measured.

**3. The Pareto filter and the suggested rank stay on RAW values.** With a family-scope
fraction the ranking cannot move anyway; the only thing that *would* move is the
"heals ≥40% of max rank" gate. Letting a noisy measurement silently change the recommended
rank — and therefore fire a "rebind?" toast — is not a trade worth making yet. Revisit when
per-rank scopes routinely fill.

**4. Effective mode is a toggle, not an eleventh column.** The table is already ten columns
at 760px. A column would let you see raw and effective at once, which is the real
comparison — that comparison now lives in the row tooltip instead, which shows both.

**5. Nature's Grace feeds HPS, HP5 *and* To OOM, not HPS alone.** They are all
chain-cast metrics from the same cast interval; feeding one and not the others would make
the row internally inconsistent. The visible consequence is that To OOM goes slightly
*down* (a faster cast earns less regen per cast), which is correct and is stated in the
tooltip.

**6. The Nature's Grace term is the exact mixture, not the plan's shorthand.**
`docs/PLAN.md` wrote `cast − 0.5 × crit` floored at 1.5s. That clips the wrong branch:
with `T0 = 2.0` and `p = 0.65` the floored form gives `max(1.675, 1.5) = 1.675` while the
truth is `0.35 × 2.0 + 0.65 × 1.5 = 1.675` — equal here, but at `T0 = 1.8, p = 0.5` the
floored form gives 1.55 and the mixture gives 1.65, because half the casts cannot go below
the GCD. Implemented as `(1 − p)·T0 + p·max(T0 − 0.5, 1.5)`. Throughput over a chain is
`heal / E[T]` exactly, so averaging the cast time (not `heal/T` per cast) is the right
statistic for a sustained column.

**7. Innervate's value is MARGINAL, not gross.** `(boosted − RM:Effective()) × 20 − cost`,
where `boosted = 5·S + G + U`. The clock already projects `RM:Effective()`; adding the
gross figure to the pool would double count it. Suppressed entirely while the buff is up,
because `GetManaRegen` reports the boosted rate then and the clock is already right.
**Assumed** (§9 in TESTING): that the 400% multiplies the Spirit share only, and not flat
gear/buff mp5 or Dreamstate — neither is spirit-based.

**8. Static cost percentages now SUM.** The code already documented that the client sums
same-type modifiers (Moonglow + Tree of Life = −29%, not ×0.91 × ×0.8) and called the
multiplicative fallback a known ~2% error. The Simulate strip's form/Moonglow overrides
depend on that path, so it was fixed rather than inherited.

**9. The combat log's `amount` convention is detected, not assumed.** WoW documents
`SPELL_HEAL`'s `amount` both ways across versions (gross, of which `overhealing` was
wasted / net, with `overhealing` on top), and the fight summary had quietly assumed net. A
full overheal discriminates: gross reports `amount == overheal`, net reports `amount == 0`.
The first unambiguous sample latches `db.healAmountGross`, and `OH:Split()` then feeds both
the dashboard and the summary. Net stays the default until proven, so nothing moves on its
own.

### Still assumed, with the log line that settles each

| Assumption | Where | Settled by |
|---|---|---|
| Nature's Grace is 0.5s, floored at the GCD | `Engine/RankMath.lua` `ctx.ExpectedCast` | `cast` debug category, TESTING §8 |
| Innervate's 400% is spirit-share only | `Engine/ManaCooldowns.lua` `InnervateValue` | `regen` line on buff gain/fade, TESTING §9 |
| Overheal half-life 150 events, 40-event gate | `Engine/Overheal.lua` | one raid; counts visible in `/md profile` |
| `K_SIGMA` / `CV_STABLE` | `Engine/TTO.lua` | TESTING §5 — **unchanged by v0.5** |


## v0.6 (2026-09-05): calls made from the dungeon-BF-1 log

Full design in `docs/DESIGN-v0.6.md`. The log was a **level 61 dungeon on a level 64
druid** — a sample of how the author heals, not a specification. Every constant taken from
it is a setting with recorded provenance, to be re-derived from heroic and raid data.

**1. HP5 redefined to "sustained while chain-casting".** The author's intent was healing
per 5s on regenerated mana *while still casting* — permanently inside the five-second
rule. The old formula let you drop out of the FSR between casts and collect full regen, a
more optimistic and different question. Now `T = max(cost/castingRegen, castTime)`. This
simplifies to `HP5 = 5 x castingRegen x HPM` in the normal case, so the column rank-orders
exactly like HPM — that is stated in the tooltip rather than left to imply independence.
The old figure survives as a tooltip line ("if you let the 5SR lapse between casts"), being
the honest ceiling.

**2. `v = v or 0` is deleted from the clock.** It turned "no value yet" into "zero
seconds", which lands in the red critical band. Seen 9+ times in one run at 72-97% mana,
because the mode latch holds `disp.mode == "oom"` for two ticks after the state moves to
`hold`, and `hold` sets `bound`, not `tto`. Now: keep the last shown value, or render
`OOM --`.

**3. Digits are gated on the projection's own error, not retuned.** `sigma/net` separated
the one hard pull (median 0.43) from everything else (median 1.01) cleanly. Above
`db.oomConfidence` (default 0.7) the clock shows the one-sided bound it already has for
`hold` instead of a point estimate. `K_SIGMA` and `CV_STABLE` are deliberately NOT touched:
the mode logic was right, only the decision to print digits was wrong. **Would change my
mind:** heroic/raid logs where 0.7 hides a projection that was in fact actionable.

**4. Calibration reads the model; the model never reads calibration.** Multiplying
`RankMath`'s output by an observed drift ratio would make the dashboard agree with reality
while `Data/SpellData.lua` stayed wrong, silently absorbing every real finding — a missing
relic, a wrong coefficient, an unmodelled talent. Drift is a report to a human, who fixes
the data. This is exactly how the Idol of Rejuvenation was found by hand, automated.

**5. Calibration compares EVENTS, with crits separated, and does not decay.** A predicted
`(1 + 0.5 x crit)` expected value cannot be compared against an individual event, so
non-crit events are compared against the non-crit prediction and the crit *rate* becomes an
independent second check. No decay because the statistic is a ratio and therefore
gear-invariant: when +healing rises, observed and predicted rise together, so anything that
accumulates is a model error. Reset on talent change only.

**6. Role is READ, not inferred — correcting an earlier error in this session.** I first
concluded TBC exposed no role API, having checked `Cell/Utils.lua` and `LibGroupInfo.lua`
and stopped. Wrong: `RaidFrames/UnitButton_Vanilla.lua`, the file `Cell_TBC.toc` actually
loads, calls `UnitGroupRolesAssigned(unit)` unguarded, and `roleIcon` ships enabled by
default in `Layout_Defaults_TBC_Vanilla.lua`. Source order is
`UnitGroupRolesAssigned` -> `GetPartyAssignment` -> class-implied -> unknown, and
**`roleSource` travels with every report** so a guessed role is never presented like a read
one. Talent-based inference was rejected outright: it cannot separate a feral tank from a
feral cat.

**7. Overheal gains an event-kind dimension (tick / direct / bloom).** Needed twice over:
calibration compares per event kind, and Lifebloom's economics turn on the bloom
overhealing 49.8% against the ticks' 38.2%. Shared plumbing.

**8. Per-target overheal is session-only.** `u:<guid>` buckets are pruned on roster change
so SavedVariables cannot grow with every stranger healed in a pug. Family, spell, kind,
role and class buckets persist.

**9. The pull is the unit of decision in 5-man content.** All four potion alerts in the log
were ignored; the likely reason is that the alert answered "is this potion efficient?" when
the question was "can I pull again?". Hence `Engine/PullBudget.lua`.

**10. HP5 removed rather than redefined.** Redefining it to the author's intent (sustained
while chain-casting, i.e. inside the 5SR) reduces to `5 x castingRegen x HPM`, which orders
every rank exactly like HPM. On review the author agreed it carried no insight of its own.
Gone in v0.6.0: column, closure, tooltip lines, `effHp5`. Recorded so nobody reintroduces it
as a "new" metric.

**11. The confidence gate's numbers, corrected.** Inside `oom` mode (the only place it acts)
the hard pull sat at median 0.41 and the quiet pulls at median 0.73; a 0.7 gate keeps all six
hard-pull samples and drops 55% of quiet digits — not the 80% first claimed, which had mixed
in `hold` samples that are above 1 by construction. Still the right default; still to be
re-derived on raid logs.

**12. Two deviations from `docs/DESIGN-v0.6.md` made while implementing.** (a) The drift
threshold is a constant (3%, `Engine/Calibration.lua ALERT_REL`) with an on/off checkbox,
not a user-facing threshold setting — the Idol case pins 3% and a slider would invite
turning a real finding into noise. (b) Hybrid (Regrowth) wasted-mana attribution splits the
cost half to the direct hit and half across the seven ticks; the design table only covered
single-kind spells. Both are stated in the code.

**13. The Waste tab works for any class.** Only the rank tabs are druid-only; overheal by
target, role and class needs no spell table.

**14. Relics: checked, corrected, and made self-verifying (v0.6.7).** The author asked
why calibration should "find" an idol the slot check already reads. It should not — a
*known* idol is applied exactly by `SD:Relic()`; calibration's job is the value the table
holds when that value was never measured. So `verify` became data instead of a comment, and
the drift alert now names the equipped relic and solves for it
(`implied = table + (observed − predicted) × ticks / talentMult`), turning "3.2% high" into
the exact table edit. Looking the IDs up rather than trusting memory found **two wrong
entries**: Idol of Health (22399) is a −0.15s Healing Touch cast relic, not +100 healing;
Idol of the Emerald Queen (27886) is +88 to Lifebloom's *total* periodic healing
(~12.6/tick), not +47/tick. My remembered ID for Idol of Budding Life (33076) was a PvP
idol; it is 33508. Added the TBC set: Budding Life (−36 Rejuv mana), Crescent Goddess
(30051, −65 Regrowth mana) as cost-only relics the live cost already covers, and Harold's
Broach at +87 (one source says 86 — calibration will settle it). Everything but the measured
Idol of Rejuvenation is flagged `verify`.

**15. Regrowth's +healing split is amount-weighted, not coefficient-weighted (v0.6.8).**
The first regression log (`.logs/regression/spam-test`, 13 Regrowth R9 casts on self at +531
healing, Gift of Nature 1, no Improved Regrowth) is the first thing calibration ever caught.
One HoT tick landed at **209**; the coefficient-weighted split (`c²/(c+h)`, `h²/(c+h)` =
0.166 / 0.994) predicted **232**, the amount-weighted split (direct `c × avg/(avg+hot)`,
HoT `h × hot/(avg+hot)` = **0.286 / 0.701** — the numbers theorycraft has always quoted for
Regrowth) predicts **209.3**. The eleven non-crit direct hits averaged 1282 against 1172 /
1237. Switched. **Rests on one tick and eleven directs**; the next run's `/md calibrate`
confirms or refutes it. The residual +3.7% on the direct portion is NOT the equipped idol
(Communal Idol of Life is +15 Rejuvenation) and is most likely the table's base range for
R9 — calibration will say.

**16. Calibration must never see the Simulate strip.** The same log reported "model
1487.7" for that Regrowth; the implied simulated +healing is **exactly 2400** — the author
had run TESTING §7 and left the strip populated. `RankMath:Context({ live = true })` now
exists and `EventPrediction` uses it. Any other consumer that compares against reality must
do the same.

**17. `GetSpellCooldown` reports the GCD.** For 1.5s after any cast, every spell's cooldown
reads as the global cooldown, so `ManaCooldowns` logged "cooldown used: Innervate" on every
Regrowth and would have flickered the `inn` segment and the advisor's readiness. A duration
≤ 1.6s is now treated as ready. Also: the player is `HEALER (self)` when nobody has assigned
a role — solo, the author's own heals were filed under UNKNOWN.

### Priority, set by the author

C1 self-calibration -> A waste report -> D1 logging -> B1 pull budget -> D2 Cell
(investigate only). **F6 logging ships before F4 waste** because the waste report's role
dimension rests on `UnitGroupRolesAssigned` returning real values in the author's groups,
and the roster log line is what proves it.


## v0.7 (2026-09-05): combat simulation and fight review — debate outcome

Design: `docs/DESIGN-v0.7.md`. Debated by two Opus parties (a theorycrafter and a healer
pragmatist) with rebuttals and a Fable judge; papers in `docs/debates/v0.7-sim/`, verdicts
in `JUDGE.md` there. Implementation spec: **`docs/SPEC-v0.7.md`** — it wins over the design
wherever they differ. The calls, as ruled:

1. **Expected value everywhere in replay and search**; triage sized on the non-crit heal;
   Monte Carlo (K=30, three plans) only in synthetic Setup. On a frozen timeline crit is the
   only noise (~2% of healing) and never moves P(death).
2. **Five-rule fixed-order family stands** with exact domains (`swiftmend ≤{.30,.40}`,
   `direct ≤{.35,.45,.55}`, `roll ×{0,1,3}`, `hot ≤{.60,.80,.90}`, `filler wait|LB x1`);
   the engine models every logged action for replay, the planner emits only the rules. The
   physical lower bound is a debug assertion, never a card number.
3. **Overheal endogenous** (HP cap); sim-vs-measured printed as a named residual per family;
   promotion to a gate at ≤10% |Δ| once ≥5 recordings pass everything else.
4. **Other healers**: environment in replay, assignment in synthetic; one gate
   `foreignShare ≤ 0.25` → Coach, else validate-only. No bracket.
5. **Event-driven**, 10–20 ms per plan (the design's 1 ms was 10× optimistic), zero
   allocation in `Run`, early abort.
6. **Review is a dashboard tab**; the window arrives with synthetic Setup.
7. **"Wait" first-class**, `minActivity = 0`; card reports `waitFraction` and the longest gap.
8. **Six validation gates** as settings with provenance (mana mean 2% / max 5% of pool; HP
   mean 5% / max 15% of maxHP; no death; foreign ≤25%; drift <3% on spells ≥10% of spend;
   ≥90% of spend modelled); mana/death/foreign/coverage disable Coach, one target's HP
   failure only excludes it; `apiBase/apiCasting` recorded per mana sample.
9. **Two recording tiers**: 8 full streams (≥20 s, ≥5 casts, 4,000 events; 3 most recent +
   ≤2 pinned protected, evict lowest spend) and 200 summaries (≥15 s, ≥4 casts). Flat
   parallel arrays. Cast target from `SPELL_CAST_SUCCESS`'s `destGUID`. Raids: subgroup +
   main tanks (author default).
10. **Labels in two classes**: plan-free (`overheal early utility shift prehot`) on every
    summary, feeding habits; plan-relative (`fine rank spell stack late idle unclassified`)
    from Coach only. Sum identity printed. HP-at-cast on every label.
11. **Lexicographic score** (deaths → floor-seconds → mana → held-on-other-streams → binds →
    sim overheal); coordinate descent only, 4 seeds, ≤300 evaluations, ≤8 ms/frame, Cancel;
    mana headline + a "you had X headroom, nothing needed to change" verdict line; downtime
    line only at n ≥ 4.
12. **Causality invariant** (`Plan:Decide` never sees the event list; one derived input:
    trailing-5 s damage), **cast commitment**, death → validate-only, overkill correction,
    initial aura/form/buff snapshot at the pull.
13. **Presets from recordings per target** (never pooled by role first); big hit = ≥15% of
    maxHP within 1 s; "use as preset" = the fight's own joint timeline.
14. **Binds fixed by default** (`db.simAllowRebinds` off); rank advice only via the existing
    new-rank toast or a passive Review line — compliance evidence: 73–100% max-rank casts
    against a standing downrank suggestion, 0 of 4 potion alerts acted on.
15. **GCD** `max(castEnd, lastCastStart + 1.5)`; 0.5 s reaction post-idle only, zero when
    chaining (log: p10/p25 inter-cast gap 1.50/1.52 s).
16. **Delivery**: v0.7.0 HP-at-cast + habit line → v0.7.1 engine mana half + BF-1 fixture →
    recorder → HP replay + gates → classifier/card/loop closure → search → Review tab →
    SimWindow. The first win is one summary line built from one recorded field.

**Additional rulings:** cast commitment; initial state at pull; form as stream events with a
kit per form; utility mana as recorded lumps (the `utilityMp5` drip deleted); loop closure
("since your last card: overheal 39% → 31%") ships with the card; provenance tooltips on
every row and card; cancelled casts as busy intervals; baselines *you / max rank / HoTs only /
best* on every card.

**Corrections to the design the debate produced:** simulation cost 10–20 ms not 1 ms; the
cast→first-heal heuristic replaced by CLEU `destGUID` (Details! reads it); `amount` on damage is
post-absorb and the killing blow carries `overkill`; the 2 s-window 3×-mean pulse detector
fires on ordinary melee; a blanket reaction delay contradicts the log; the `early` label was
wrong for 68% of casts (Lifebloom refresh is the play).

**Rejected, not to be re-proposed:** see `docs/SPEC-v0.7.md` §13.

### v0.7.1 corrections made by running the engine (2026-09-06)

Three calls in `docs/SPEC-v0.7.md` §3 changed once the engine could actually be executed
(`tools/run.sh tools/simcheck.lua` — a WoW API stub plus a real Lua 5.1, so the engine runs
outside the game). Each is a correction from evidence, not a preference.

1. **Mana leaves, and the 5SR restarts, when a cast SUCCEEDS — not when it starts.** Spec
   §3.6 said "at cast start". `.logs/dungeon-BF-1.txt` is unambiguous: `[mana] -460`,
   `[spend] Regrowth cost 460` and `5SR start` all carry the timestamp of
   `UNIT_SPELLCAST_SUCCEEDED`, i.e. the end of the cast bar. The engine follows the client.
   A plan is therefore charged when its cast lands, and cast commitment (the plan is not
   asked again until then) is what keeps that from being a free option.

2. **Regen is integrated continuously, not in 2 s ticks.** The client ticks; the engine has
   no way to know the tick phase of a fight it is replaying, and guessing costs more than it
   saves. Over a 40 s pull the difference is at most one tick of phase (~1% of a 7k pool).

3. **A recorded sample that sits exactly on an event's timestamp is read AFTER every event at
   that instant.** This was a real bug, not a definition: the first cut sampled after the
   *first* event at a timestamp, so a cast that shared its timestamp with a form change was
   sampled before it had been paid for. It put the fixture's max error at 13.7%; fixing it
   gave 2.8%.

**The BF-1 fixture carries ~23 mana/s of energize `GetManaRegen` never reports.** Measured
from the log's own mana lines: over 40.26 s continuously inside the five-second rule the
player gained 2072 mana; the reported casting rate accounts for 1140. The remaining 931
(116 mp5) arrives as two clean periodic streams — **exactly 17 every 2.00 s** and **13-15 on
a 3.00 s cycle** — plus updates where the two merged. **This is the same shape of finding as
Dreamstate in v0.5 and it gets the same treatment: it is not added to `RM:Unreported()` on a
guess.** `docs/TESTING.md` §16 is the in-game test that settles it.

### The two streams are different kinds of thing (2026-09-06)

Taking the *whole* 28-minute log apart, rather than the one pull, separated them, and the
distinction is a design constraint rather than trivia:

| | cadence | in / out of combat | per-pull yield | what it is |
|---|---|---|---|---|
| **A** — 17 | exactly 2.00 s, **497 times, never a different value** | 380 / 117, the same split as the time | constant | a property of the **character**: the mp5 bucket (gear, an idol, or Blessing of Wisdom — all `MOD_POWER_REGEN`, all landing on the server's 2 s tick) |
| **B** — 13-15 | **3.00 s**: 55% of its 378 events have a partner exactly 3.00 s later, against a 9% baseline at 3.5 / 4 / 5 s; one to four phases overlap | **373 of 378 in combat**, though combat is 57% of the log | **0.0 to 17.6 mana/s**, and exactly **zero in two of the thirty pulls** | a property of the **group and the pull**: a party-wide periodic energize |

The author recalls a **shadow priest** in that party, and 5% of a shadow DoT ticking every
3 s is exactly B's signature (Vampiric Touch). The log records no classes, so this is
corroboration rather than proof — and Vampiric Touch is a level-70 spell, which is the one
thing that does not fit. Either way the ruling does not depend on naming the spell:

- **A may eventually enter the model**, as Dreamstate did, and only by the same route: an
  in-game `/md regentest` that shows the constant on its 2 s beat next to the spirit tick,
  cross-checked against the character sheet's mp5. It is a number about *you*.
- **B must never enter the model.** It is not yours, it is not present in every group, and it
  is *zero* in two of the thirty pulls in the one log we have. A healer's clock that assumes
  a shadow priest is wrong on the pull where it matters. The only correct treatment is the
  one the recorder already gives it: measure it per fight, replay what was measured.

This is also why `Data/SimFixture_BF1.lua` no longer presents 23.1 mana/s as one number with
one cause, and why the fixture's roster classes are now marked unverified — the log records
names only, and the classes in it had been carried over from a mockup table in
`docs/DESIGN-v0.6.md`.

`/md regentest` gained a **tick histogram** (size x count, median spacing) for exactly this:
a size is *what* a source gives, a cadence is *which* source it is. Reading it off a chat
line beats hand-decomposing a 400 KB log.

**Addendum (2026-09-06, evening): stream A measured on the character alone.** The import tool
ran the engine on three real *solo* recordings (Hellfire Peninsula, 21 / 58 / 87 s, no party).
Recorded mana runs ahead of the two-rate model by **+5.4 / +6.2 / +6.8 mana/s (27–34 mp5)**,
steadily, and the 2 s samples show why: gains of **+49** where the casting tick is 35
(17.58/s × 2) — a constant ~14 per 2 s beside the spirit tick. Nobody else was there. That is
the item-mp5 bucket on this character today (BF-1's 17 per 2 s was other gear and possibly a
blessing on top). It is why the 87 s recording fails the mana gate (+410 by the end, 6.5% of
the pool) and would pass with it modelled. **Ruling unchanged: it does not enter
`RM:Unreported()` as a constant.** The value is gear, so the model must *measure* it — the
regentest histogram's 2 s beat, stored per character with its date and re-taken on a gear
change — or *read* it (equipped-item tooltip scan for "mana per 5 sec"). Which, is the
author's call; both are honest, the constant is not.

> **Correction (2026-09-06, night): stream A on this character was Dreamstate.** The first
> in-game `/md regentest` after v0.9.0 settled it. Observed 55.77/s against a raw API 48.76/s
> is a gap of 7.01/s, and Dreamstate 3 on 326 intellect is 6.52/s — the whole of it, with
> +0.49/s (2 mp5) left over, which is inside what a 30 s window can resolve. The recordings
> looked like they were missing 27–34 mp5 of *item* mp5 because the replay scenario carried
> only `apiBase`, the raw client rate, and **nothing ever added Dreamstate to a replay**. The
> talent is 33 mp5 on this character. Re-validating the 87 s recording with Dreamstate alone
> and no measured mp5 at all takes its mana gate from 3.3% to **1.0%**, inside the 2% limit.
> The in-combat ticks in the same log agree from the other side: +48/+49 per 2 s inside the
> five-second rule is 24.3/s, against API casting 17.58 + Dreamstate 6.52 = 24.10/s.
>
> So v0.9.0's actual fix — recording `RM:Unreported()` as each pull's `initial.energize` —
> was right, and its *measured* half was measuring nothing. What it stored instead was the
> size of the whole regen tick (see the v0.9 addendum below), because on a druid with
> Dreamstate there is only one tick and the histogram called it an unreported beat. Stream A
> is not a separate stream on this character. BF-1's 17-per-2 s next to a 138 spirit tick, on
> a build with no Dreamstate, remains a genuine second stream and the fixture keeps it.

Consequently `/md simreplay fixture` reports three numbers rather than one pass/fail: `spend`
(must be exact), `modelled` (the fit `GetManaRegen` alone can produce — mean 6.3%, max 12.1%
on BF-1) and `measured` (with the fixture's recorded energize — mean 1.3%, max 2.8%, which
passes spec §3.9's mean ≤ 2% / max ≤ 5%). The gate is on `measured`, because §3.9 is a test of
the engine's *mechanics*, and a rate the fixture already measured should not be re-litigated
inside it.

**One drive-by fix:** `lbHot` / `lbBloom` in `Engine/RankMath.lua`'s `RowFor` were globals.
Behaviour was correct by luck (only the Lifebloom branch reads them, and it always writes
them first), but they were `_G` writes on a path the dashboard runs every 2 s.

## v0.8 (2026-09-06): replay visualisation — three calls, no debate

The author asked for a replay that *plays*: two sets of unit frames, what happened next to
what the math suggested, "stupid simple" first — HP bar and where each cast went — and
indicators added per iteration (HoTs, debuffs, defensive cooldowns, role, class). Cell's
layout preview was the reference. It is a renderer over v0.7's decided machinery, so it got
a spec (`docs/SPEC-v0.8.md`) rather than a debate round. The three calls:

1. **One window, two columns, one clock.** The author had floated two windows; lockstep is
   the point, and two windows drift and double the chrome.
2. **Both columns are engine output.** Author's own reasoning: generating both from the
   engine "will lead to better comparison compatibility" — yes, and precisely because the
   damage is then identical by construction and every visible difference is a healer
   decision. The recorder's real 5 s HP snapshots stay on screen as **ticks on the left
   bars**: the health gate's number turned into a picture, so trust in the right column is
   earned from the left one the way the gates earn it.
3. **Play without a plan is allowed.** The left column is class-agnostic and works the day it
   ships; only the right column is Druid-only.

Carried over unchanged: the causality invariant, the search never traces, nothing from this
work enters the model. Rejected up front (spec §7): raw snapshots as the left column, Cell's
real unit buttons, interpolation between grid points, playing live, Monte Carlo playback,
running the search from Play, defensive cooldowns changing damage in the engine.

**Two items the author asked to keep room for** (spec §7 "reserved"), and the distinction
that makes each safe: **coach inside the replay** — *explanation*, not search; the trace
records the rule that fired (`why`) from v0.8.0 so a later "here is where and why the plan
differed" has data. **Defensives and debuffs as a decision input** — a rogue under Evasion
is not urgent — which is a present-state input to `Plan:Decide`, legal under the causality
invariant, and *not* the engine altering damage (the damage Evasion prevented was recorded
as prevented). The recording of auras in v0.8.3 is its prerequisite; the rule waits for a
recording that shows the case.

## v0.9 (2026-09-06): runs, the measured character, the drink — spec, no debate

The author, after the first real replays and the import tool: "each separate combat is ok for
bossing, but in a 5-man it makes more sense to record the whole run — a checkpoint (could be
manual) to start and stop, stored separately, ideally in a file, selectable for replay." Then:
"keep it manual for now, but keep the possibility to add auto-start later." `docs/SPEC-v0.9.md`
carries the plan. The calls:

1. **Runs are manual**; auto-start is reserved behind a setting that ships off and a
   `Start("auto")` that already exists.
2. **The SavedVariables is the file.** An addon can write nothing else; runs live under their
   own key, two kept, pinnable, and `tools/import.lua` reads them.
3. **Every pull of a run is kept**, gate or no gate — the gate is for coaching *from* a pull.
4. **The measured mp5 enters the model as a measurement** (option 1 of the v0.7.1 addendum: the
   regentest histogram's 2 s beat, stored per character with its date, re-taken on a gear
   change). Never as a constant, never per named source. Tooltip reading stays reserved.
5. **The run's score puts time before mana**: `(deaths, floor, addedTime, drinks, mana, ...)`.
   Mana in a dungeon is only worth the time it saves; a drink that did not fit its gap made
   the run longer, which is the thing the healer was trying not to do. The drink rate is the
   run's own, measured; there is no preset.
6. **The profile is persisted** so the offline engine sees the character, not the BF-1 build.

### Addendum (2026-09-06, from implementing v0.9.0–v0.9.4)

7. **An older recording gets the current measurement, and the report says so.** A fight recorded
   before `/md regentest` ever ran carries no `initial.energize`, and replaying it without one is
   what put the author's 87 s Hellfire fight 3.3% off its own mana curve. `ScenarioFromRecording`
   applies the character's current measurement to such a recording and flags the scenario
   `energizeAssumed`; every validation report prints which of the two it used. Recordings made
   from v0.9.0 on carry their own, so this only ever applies to the ones that predate it. The
   assumption being made — that the gear was the same then — is stated rather than hidden, which
   is the same rule the gates follow.
8. **An Innervate inside a gap is counted, not modelled.** The spec said "a recorded Innervate or
   potion in the gap is applied as recorded". A potion can be: its value is a table constant
   (`Engine/ManaCooldowns.lua`), applied at the max roll. An Innervate cannot: it is 400% of the
   **spirit share** of regen, and a recording carries the total rate, not the split — so putting
   a number on it would be a guess, and nothing enters the model on a guess. The chain counts
   them and the card names them as unmodelled. Both sides of every comparison see the same
   recorded gaps, so the comparison stays fair either way. If the split turns out to matter, the
   fix is to record it (the recorder already samples both API rates), not to estimate it.
9. **Coach on a run coaches the run.** On the Review tab, while a run is shown, the Coach button
   becomes *Coach run* — one plan and one drink policy for the dungeon — and a second *Coach
   pull* button keeps the single-fight card for the selected pull. The run question and the pull
   question have different answers and both are worth asking.
10. **The next pull follows on its own** (the spec's open question, answered yes;
    `db.replayNextPull`). Pull-by-pull is the way through a dungeon, and stopping to click at
    every boundary makes it a chore. There is still no run-level play-through at 1×.
11. **What is stored is the leftover, never a tick** (v0.9.5, after the first in-game run of the
    v0.9.0 test stored 279 mp5 on a character regenerating 279 and the clock read 556). The
    stored value is `observed - GetManaRegen - Dreamstate - any 3 s party stream`, and nothing
    else can be correct: a term the API does not report is by definition what is *left over*
    after everything it does report. Three consequences, all of them in the code:
    - the histogram compares a tick against the rate the **model** expects (API + Dreamstate),
      not the raw API rate — Dreamstate rides inside the same server tick, so comparing against
      the raw rate reads the one true tick as an unexplained beat;
    - rates are measured **between the first and last tick of a stream**, not across the window,
      because a window edge is worth up to a whole tick (111 mana over 30 s is 3.7/s — bigger
      than the leftover being measured); interleaved phases of one source drop as many ticks as
      they have phases;
    - a leftover under **5 mp5** is not stored and *clears* any previous measurement. "The model
      already accounts for everything" is a result. `Engine/RegenModel.lua` additionally refuses
      any stored value larger than what the client reports, and says so once, so a database
      written before this fix cannot keep lying.

## v0.10 (2026-09-07): the casts that are not heals — spec, no debate

The author, looking at three solo recordings the engine refused to coach from: "I'm not sure 90%
mana spent on heals is right. The fight may not be heavy on incoming damage and I can assist the
damage dealers. I may also cast a lot of CC (Cyclone), which reduces incoming damage by a lot.
We should not add CC and damage abilities to coach suggestions — too situational. But we could
check when casting damage abilities breaks the 5s rule and leaves too little mana for healing
later; and treat CC casts as necessary at that moment, so they are in the record and in the
coach variant at the same place." `docs/SPEC-v0.10.md` carries the plan. The calls:

1. **The 90% spend-coverage gate was measuring the wrong thing.** The mana curve reproduces
   without it — the recorder stores each cast's real cost, and recording 2 sits at 1.0% on the
   mana gate with a third of its spend unpriced. What the gate stood in for is the *plan* side:
   `RunPlan` drops the recorded script, so the simulated healer never casts the Moonfires and
   starts with their mana in hand against an unchanged damage timeline. 2043 mana of free money
   in recording 2. A threshold cannot fix that; fixed points can.
2. **Every non-healing cast is a fixed point** — same moment, same cost, same global cooldown,
   same five-second-rule restart, in both columns. The plan decides around them.
3. **Damage casts too, not only CC.** A plan allowed to skip a Wrath pockets the mana while the
   fight still ends at the same second, because the recording's length already contains the
   effect of that damage. Same as the root: the damage you took is the damage you took *because*
   you rooted it.
4. **CC and damage stay out of the plan's rules.** The trigger for a Cyclone is not party health
   and trailing damage. What the coach may say about a damage cast is its price — mana plus the
   spirit regen lost to the five-second rule it restarted — measured as the difference between
   two runs, and always with the counterfactual stated: the fight would not have been the same
   fight without them.
5. **Spell identity is seeded from the TBC database and checked against the recordings.** Four of
   the five unknown ids in the author's logs reproduce their recorded cost exactly, three of them
   only after Moonglow's -9% — a stronger check than the lookup itself. Every row stays
   `-- VERIFY` until a recording proves it, and the addon learns the rest from `GetSpellInfo`
   into `cdb.spellbook` rather than from a website.

## Forever review R6 (2026-09-29): the danger line a plan decides on is causal

The independent Forever review (`docs/review/2026-09-29-forever-review.md` R6) found that the
solver's danger line was the whole fight's biggest hit, set once at the start of `SM:Run`, so a
coached solver plan could be advised by a hit that had not landed yet. The finding was held for
the author because it changes the coach on both lines. **The author chose "Fix both lines"**
(relayed by the planner, 2026-09-29); implemented by T20 (`docs/tasks/T20-causal-danger-line.md`).

1. **Deciding reads only the causal line.** At time t a target's line is the biggest hit it has
   taken so far in this fight, times `db.simDangerHits`, capped at 1 (`SM.DangerLine`).
   `Solver:AtRisk`, rule 8 and its reason record read it; nothing a plan's `Decide` reaches reads
   `S.danger` any more.
2. **Scoring keeps the whole-fight line.** `floorSeconds` in `SM:Run` and the card's "danger line"
   still use the biggest hit of the whole fight (`tg.danger`): scoring may look at everything,
   deciding may not.
3. **Before a target's first hit**, the line is a prior from other recordings of the same target
   where the scenario carries one (the leave-one-out rule T17b uses for max health, never the fight
   being coached; T20b), else `db.simFloor`.
4. **Synthetic scenarios keep the flat floor** for both deciding and scoring (lead's call, confirmed
   by the planner): a constant sees no future. Practice, the Simulate window's presets and every
   hand-built test scenario decide exactly as before; the causal line applies only where the
   scenario carries a measured line (a recorded fight).
5. **The rules coach does not change** (confirmed by the planner): the threshold plans
   (`SP.NewPlan`, `SP.Search`, TBC's `/md coach`) never read the danger line. Only the solver
   strategies change, on TBC and Forever alike. The TBC TOC stays at 0.15.4 until the author
   decides a TBC release.


## One version, two installations (2026-09-29)

The author, 2026-09-29 (relayed by the planner): "lets have single addon version and just separate
installations". On the number: **0.16.0 for both lines now, 1.0.0 at the Forever launch
(2026-11-04)**. This supersedes the `1.0.0-alpha.N` / `1.0.0-beta.N` scheme of
`docs/ROADMAP-FOREVER.md` §1.2 (and the TBC line's separate `0.15.x`).

1. **One version for the whole tree.** Every TOC -- `SpellTuner_TBC.toc`, `SpellTuner_Mainline.toc`,
   `SpellTuner.toc` and the six module TOCs -- carries the same `## Version:`. A TBC release and a
   Forever release cut from the same commit are the same version.
2. **The number.** `0.16.0` now; Forever beta builds from now on are `0.16.x` (what was going to be
   `1.0.0-alpha.9`, `-beta.1`, ... is `0.16.1`, `0.16.2`, ...); **`1.0.0` at the Forever launch**. The
   TBC line never shows "alpha" or "beta".
3. **Two installations, one tree.** `release.sh` builds a TBC package (`SpellTuner/` with only
   `SpellTuner_TBC.toc` and its files) and a Forever package (`SpellTuner/` with the two Forever
   TOCs and their files, plus the three module folders beside it), zipped by flavour and version.
   An install puts exactly one flavour into one client and never the other flavour's files.
   (T22, T23.)


## The coach values regen (2026-09-29)

The author played a practice fight at level 10 on the WoW: Forever beta (Party, 47.9 s), opened it
as a replay, and compared his column with the coach's "Solver: frugal": his spent 425, regen 137,
lowest 43%, the coach's spent 385, regen 45, lowest 51%, both at 0:43.9. The author: **"I've found
the coach issue, it does not tolerate non casting window to regen. It will be less relevant on
higher level, but as a concept it is critical. And to measure it, I would like to have practice
recordings so we can improve the code from such reports."** The concept is critical for both
lines, so the TBC coach changes where this is the point, and every changed output is named in the
commits (`b062413`, `9a694f1`, `cfd4314`).

**Why the coach never rested.** Nothing in the solver or the score knew the five-second rule
existed. The solver priced a cast at its mana cost; the rule state and the two regen rates were
locals of `SM:Run` that `Decide` never saw. Every score ranked gross mana SPENT, so a pause that
let the rule lapse could never score better. On Forever the rule is nearly all of the regen
(`GetManaRegen` 8.5 to 11.5 a second outside it, 0.001 inside): a Healing Touch R2 cast out of the
rule forfeits 57.5 mana, more than its own 55.

1. **The solver prices the regen a cast forfeits** (`SV.Forfeit`). The price is the difference
   between two mana curves over the cast's window [t, land + 5], without the cast and with it:
   `cost + max(0, min(R x added, room - G1))`. R is base - casting; `added` is the seconds of the
   window the rule would not have covered anyway; `room` is what the pool can still hold when the
   cast lands without it; G1 is what both branches regain inside the rule. The forfeit is 0 at a
   full pool and whenever base == casting, so a class or moment with nothing to forfeit decides
   exactly as before (`tools/restcheck.lua` 3a/3b: cast for cast). Everything it reads is the
   healer's own and present tense: the 5SR underline, `GetManaRegen`, `UnitPowerMax`, published by
   the engine by cursor and after the classifier's lockstep hook (4a-4f). **Rule 8, the danger
   line, stays on nominal cost.**
2. **The one-GCD-later candidate carries the price of casting now.** Waiting is a question about
   timing and stays one. Priced at its own later forfeit, a cast inside a running rule always beat
   the same cast one GCD later, so a chain never broke: on the author's Sethekk Halls recording
   the solver rolled Lifebloom R1 for twenty seconds on a target the unpriced one left alone.
3. **The danger rule's pick was broken, and is fixed.** `better = low > (pickLow or -1)`, with the
   projection not clamped at 0, meant a target projected through the floor by more than one point
   under every cast got no pick at all, and the value rule decided instead. That is the deepest
   danger there is, and it is exactly what regen pricing relies on rule 8 to own. The first
   candidate is now always taken. This fix alone changes the TBC solver more than the price does:
   over the author's eight anniversary recordings its six strategies go from 29 deaths and 145 s
   one hit from death to 27 and 126 s, spending more mana.
4. **No separate rest guard.** Critic 1 proposed pricing regen only while nobody is projected
   under a larger hit multiple (`db.simRestHits`). I measured it before finding item 3. At 1, 2,
   3 or 4 hits it gave identical results on TBC and on the author's fight, because a linear 18 s
   projection either crosses every line or none. At one hit it is rule 8's own test, and
   everything it changed was a decision rule 8 had dropped (item 3). With rule 8 fixed, it differs
   only when no non-instant cast is affordable. It would have been a setting with nothing to
   measure it on, so it is not added.
5. **The score ranks mana USED** (what the fight took out of the pool: start - end, plus the
   regen a rule still running at the end has yet to cost), in the same third slot that gross spend
   held. `(deaths, floorSeconds, manaUsed + manaOwed, -heldOn, #binds, overheal)`. It is the
   quantity spend was standing in for; as a later tie-break it would change nothing. Deaths and
   seconds in danger still lead and nothing is blended. The same change reaches the objectives, the
   card, the alternates, both coach commands, the Sim window and the run score. `SP.ChainScore`
   ranks the run's own used (first pull's mana less what is left after the last, gaps, drinks and
   potions included). `SM.ChainRun` carries each pull's rule tail into the gap at the casting
   rate, so the forfeit is charged once and no per-pull debt is added. The search's early abort
   stops a run only when it can no longer end having used less than the incumbent, bounding
   everything that could still come back (the pool's room, the fastest rate any sample reaches,
   energize and every recorded potion). Gross spend would have killed exactly the plans that rest.
   Stated bias, held by a test (7d): `ManaOwed` prices health left missing at the best heal per
   mana with no forfeit, so ending hurt scores slightly better than paying for the heal out of the
   rule.
6. **Frugal's floor 30 -> 20**, measured, with provenance in `SP.STRATEGY_SET`. A priced value is
   smaller by cost / (cost + forfeit), and at 30 a level 10 Healing Touch R2 out of the rule (at
   most ~15 per mana) could never clear it. On 180 synthetic level 10 party fights 20 cost no
   deaths (0 against 1) and ended with 85 mana against 34. On the author's fight it used 301
   against 364, with the same lowest health (48%) and less owed (244 against 302). On the eight
   TBC recordings its row in `tools/strategies.lua` was compared at 20 and at 30, totals only, not
   its decisions cast for cast. On the anniversary snapshot the recordings were first measured on,
   20 and 30 give the same deaths, the same seconds one hit from death and the same 346 casts, but
   not the same mana: 31189 used at 20 against 31234 at 30. On the author's current eight-recording
   file the two rows are identical (442 casts, 33609 used). (Corrected 2026-09-30 from "read the
   same, mana included", which the review's re-run measured as too strong for the snapshot.)
   The other floors keep their numbers.
7. **The replay window leads with "used"**, the pool at the pull less the pool now, which is the
   number the coach ranks on. The author read "spent 385" against his "spent 425" as the coach
   being cheaper while it had 24 mana left to his 76.
8. **Practice fights are reports.** A practice record carries the kit it was simulated with, the
   client, level, version and build. `PR.Pin` keeps up to four past the ring of eight, from Review's
   Pin. `tools/import.lua report pN` (on both clients; it was `tools/practicereport.lua`'s until the
   2026-09-30 merge with the recordings pipeline) puts the replay beside every strategy: spent,
   regen, used, end, owed, deaths, seconds in danger, lowest. The
   author's fight is `tools/data/practice/1790701698.lua`; its kit was reconstructed from its own
   events, because it predates the stored kit, and it passes every gate. `/reload` before sending:
   SavedVariables reach the disk only then.

**What changed on TBC, per strategy** (items 1-6 together; the review's re-run, 2026-09-29):
- on the anniversary snapshot the recordings were first measured on: "Solver: no intuition"
  4 -> 5 deaths, and "Solver: intuition from many raids" 15.3 -> 22.1 s one hit from death;
- on the author's current eight-recording file: the solver strategies together 23 deaths and
  270 s one hit from death -> 19 and 208 s; the two rules strategies unchanged.

**Critics' objections rejected, and why.**
- *Normalise the floor to `minFrac x BestHPM x horizon`* (critic 1, O4/D5): right in principle.
  But at level 70 the solver's values sit far above every floor (on eight TBC recordings 20 and 30 give
  the same deaths, seconds and casts in `tools/strategies.lua`, and mana used within
  0.2%; see 6), so there is nothing yet to fit a fraction to. It stays open until a
  high-level fight where the floor binds.
- *A rest guard with its own hit multiple* (critic 1, D4): see 4.
- *Price the later candidate at its own delay* (one reading of "the same price"): see 2.
- *Measure the solver's gap only up to `fullAt`* (proposal): the author asked for top-ups
  (v0.13.5), and it is not the regen concept (both critics).
- *A `restOut` rule parameter* (proposal): not needed for the concept. The price is the
  solver's, and the rules search now ranks used mana. It would also double the domain in a
  300-evaluation budget (critic 2).
- *An in-game Export copy box for practice*: the report tool reads the SavedVariables file
  directly, so there is nothing to paste. Pin is what stops the fight being lost.
- *Report lowest mana and OOM time on the card* (critic 1, D7): not done here. The replay's
  mana bar shows it, and no card line was asked for.

**Still open.** The two TBC rows that got worse on the anniversary snapshot ("no intuition" one
more death, "many raids" 6.8 s more one hit from death), named rather than tuned away. The first
write-up named instead one extra death for "Solver: reactive" in a 180 s Blackrock fight where both
versions sit near 250 mana for 90 s, and read that divergence as chaotic rather than mana banked
while someone was in danger; the review's re-run is the one above. The frugal floor is a constant
from one synthetic setup and one real fight.

## One kit record and one report tool (2026-09-30)

`work/regen` (practice fights as reports) and `work/recordings` (the beta's SavedVariables read by
`tools/import.lua`) each stored the kit a fight was played with, differently: the first a copy of
every form's entries on practice fights, the second `RM.KitSnapshot` on practice fights and Forever
pulls -- the entries plus a copy of the whole `MD.SpellData` index (spells, families, known, all,
max rank, skipped, order) on every record, and the same again as the character's `cdb.kit`.

1. **One record, `SM.KitSnapshot`** (Engine/SimModel.lua, both clients): each form's entries with
   their number, string and boolean fields, the crit, the time and the level. It is a kit as it
   stands (`SM.ScenarioFromRecording(rec, rec.kit)` replays with it), so TBC needs nothing more,
   and it holds nothing a replay does not read. The index is not stored: on Forever
   `RM.KitRestore` rebuilds the part the engine reads (family, rank, cost, cast; every rank in a kit
   is a known one) from the entries, offline only. `RM.KitSnapshot` is kept as the Forever name for
   it. Practice fights (both clients), Forever pulls and `cdb.kit` all carry it.
2. **`cdb.kit` stays**: a few dozen numbers, and the only kit a Forever pull recorded before pulls
   carried their own can be replayed with (the tool says `last` when it uses it).
3. **One tool, `tools/import.lua`.** It already read both clients' files, addressed practice fights
   as `pN` and, on Forever, read a kit back off an old practice fight's own heals (the same
   reconstruction `practicereport.lua` did; on TBC the character's profile rebuilds the kit).
   Its `report N|pN` is practicereport's report, shared by both halves (`tools/reportlines.lua`),
   and `--fixture` reads a `{ rec, kit }` file. `tools/practicereport.lua`
   is removed rather than kept as a wrapper: a wrapper would be a second place to document and keep
   in step, for nothing the entry point does not do. What it did that `import.lua` does differently:
   its `export` wrote a `{ rec, kit }` fixture; `import.lua`'s Forever `export pN` writes the fight
   and its kit as a SavedVariables file of its own (`--file` reads it), and the existing fixture
   stays readable with `--fixture`.

## Coach fixes (2026-09-30)

The whole-project review (`docs/review/2026-09-30-project-review.md` B5-B8, A18) found four engine
bugs that change what the coach suggests on both lines; T46 (`docs/tasks/T46-coach-engine-fixes.md`)
fixes them. The author accepted that coach cards change (plan section 8, question 2).

1. **A Swiftmend ends the HoT it eats, in the trace** (B5). The replay, the Swiftmend-ready dot and
   the practice window stop drawing an eaten Regrowth or Rejuvenation to its nominal expiry.
2. **The search's key is every plan parameter** (B6). One `SP.PARAMS` list derives the defaults,
   `Plan:Params()`, the key and the domains; `noDirect` is in the key, so the HoTs-only seed is
   evaluated (it collided with the default seed and was never run) in `SP.Search` and
   `SP.SearchRun`. `noDirect` is fixed per seed, not stepped by the descent. The third seed, a copy
   of the first, is now the low-threshold corner (Swiftmend 30%, direct 35%, no roll, HoT 60%) that
   the run search already used; the random seed is re-drawn when it lands on a fixed one.
3. **A preempted plan is asked again when it is free** (B7). A fixed cast (damage, control, a
   shift) that cancels a plan's long cast frees the healer at its own global cooldown; the plan is
   asked then, instead of at the cancelled cast's landing time, so the suggested column no longer
   idles, and is no longer charged for idling, after a Moonfire. The cancelled cast's landing
   event, still queued, lands nothing: only the live cast lands, at its own time.
4. **Swiftmend is priced on the HoT it will eat** (B8). `SM.SWIFTMEND_ORDER` (Regrowth, then
   Rejuvenation: TBC's rule) is read by the engine and the solver; the solver priced Rejuvenation
   first and wrote `swiftmendAmount` onto the shared kit entry (copied into practice recordings'
   kits by `SM.KitSnapshot`). It writes nothing now.
5. **The `others` store reaches the v3 builder** (A18, the dropped argument): the Replay module's
   wrappers of `SM.ScenarioFromRecording` and `SM.Validate` forward every argument.

The lexicographic score and the causality invariant are unchanged. On the three fixtures tried the
winner is the same and only the evaluation count grows (the author's practice fight: 26 -> 56).

## The client is the TOC's, the interface is a fallback (2026-09-30, T47)

`MD.API.client` comes from the TOC the client loaded: its first file, `Client/TOC_<X>.lua`, sets
`SPELLTUNER_TOC = "<X>"`, and `TBC` is `tbc`, `Mainline` and `Plain` are `forever`
(`MD.API.MARKERS`). The interface band (`MD.API.BANDS`: tbc 20000-29999, forever 16000-19999)
decides only when that marker is absent. Why: WoW: Forever runs the retail engine, and its launch
interface is not promised to stay in 16xxx; the band alone would turn the addon into an "unknown
client" (and Practice's `OnForever()` false, undoing T24) the day it moves, and `release.sh` would
refuse to build. `release.sh` classifies a TOC by the marker file it lists (a TOC under `Modules/`
is forever), warns when the interface is outside its flavour's band and refuses only a TOC with
neither. One table, `tools/data/flavours.txt`, is what `release.sh`, `tools/apicheck.py` and
`tools/releasecheck.lua` read; `tools/forevercheck.lua` asserts `Client/API.lua`'s two tables
equal it. On TBC nothing changes: its interface is inside the band and its marker says `tbc`.
The same task made the ten TBC chat strings with an em or en dash and the window's U+00D7 close
glyph ASCII (`tools/textcheck.py`, B3, U31) -- text only.

## What a CANCEL means, and the bloom's bucket (2026-09-30, T48)

The whole-project review (`docs/review/2026-09-30-project-review.md` B9, B10, B13) found three TBC
recorder and overheal bugs; T48 (`docs/tasks/T48-tbc-recorders-overheal.md`) fixes them.

1. **A CANCEL is a hard cast that ended without its success** (B9): an interrupt carrying its
   `castGUID` (`UNIT_SPELLCAST_INTERRUPTED`; by spell id when no GUID was readable), or another own
   cast start while it was pending. Its own success closes it; nothing else does -- not a HoT tick,
   an aura, an energize, and not the failure a spam press of the same button produces
   (`SPELL_CAST_FAILED` / `UNIT_SPELLCAST_FAILED`), whose reason text is localised and not read.
   **Recordings made before this build keep their spurious CANCELs**: the pending cast was dropped
   when they were written, so they cannot be repaired, and the replay does not hide a CANCEL followed
   by the same spell's success (the author's answer, plan section 8, question 3).
2. **The bloom is a Lifebloom bloom** (B10). 33778 is attributed to 33763 with kind `bloom` in the
   overheal buckets and in calibration, so the Effective Lifebloom row can use a measured bloom
   fraction, `/md calibrate` gets a bloom line, and a fully overhealed bloom wastes no mana (the ticks
   carry the cost). Old `k:33778:direct` / `s:33778` entries decay out on their own (150-event
   half-life); `s:33763` now includes the bloom (`f:Lifebloom` always did). Only the Lifebloom alias is
   resolved: Tranquility's 44208 / 44207 stay under their own ids (resolving them is a model change
   left to the author).
3. **Tranquility's waste is divided by the caster's party** (B13): in a raid, the members of the
   player's own subgroup (`GetRaidRosterInfo`); in a party, everyone, as before.

## Pins are capped in the Review tab, and a cross-realm member keeps a bare name (2026-09-30, T49)

Review's Pin on a single fight goes through the recorder's capped `Pin` (Forever's
`Recorder_Forever.lua`; on TBC, whose `Engine/FightRecorder.lua` has no `Pin` yet, the same cap of
two is applied by the Review until P18's `Engine/Recordings.lua` gives both lines one). A third pin
is refused with one line, `pin: at most 2 fights can be pinned - unpin one first.`, on both lines;
on TBC it used to be set and silently not honoured, on Forever it used to be set and, with every
stream pinned, the next pull was lost. Forever's ring now protects only the first two pins (TBC's
rule) and always stores. A party member from another realm is recorded with `name` bare and
`realm` beside it (from `UnitName`'s second return): old recordings and new ones name the same
person to `SM.PartyMaxFromOthers` and `SM.DangerHitFromOthers`; a cast SENT at `Name-Realm` is
matched to the full name first, then to a bare name that is unique in the roster. The suffix form
of the SENT target follows the retail convention and has not been seen on the beta.

## usesMana is whether the player has a mana pool; Tree form's buff scan is a fallback for a missing API only (2026-09-30, T52)

**usesMana is whether the player has a mana pool.** `MD.player.usesMana` was the power type at login
(`UnitPowerType("player") == 0`). A druid who logged in or reloaded in Cat or Bear form (power type 3
or 1) therefore had the clock, the Advisor, the datatext, the self-assigned HEALER role and the mana
cooldowns switched off for the session, and nothing re-evaluated it. It is now answered from data:
`MD.API.UnitPowerMax("player", 0)` read plain and above 0 (a druid in any form has a mana pool; a
warrior or rogue has a maximum of 0). There is no class list: which classes use mana on Forever's
retail engine is not guessed. Only when that read is absent, secret or raised does the current power
type decide, as before. Both lines (`Core.lua` is shared).

**Tree form: the buff scan is a fallback for a missing API only.** `GetShapeshiftFormID` answering
`nil` is an answer (caster form). The buff scan by name used to run on that `nil` too and found
another resto druid's Tree of Life party aura (34123, the same name). The rank math, the kit, the
recorder, the cast labels and the profile then thought the player was in Tree form, and
`FORM_CHANGED` fired whenever the other druid shifted or left range. The scan now runs only when the
function is absent or raised. TBC only (`Core_TBC.lua`).

## A raising event handler no longer stops the others (2026-09-30, T55)

`Core.lua` runs every `MD:On` handler and every `MD:Fire` callback as `xpcall(handler, MD.ErrorSink,
...)`; the sink tail-calls whatever `geterrorhandler()` answers then, so the error still reaches
BugGrabber, Forever's capture or the client's own handler once, and the handlers after the raising
one still run (review A4: one raise in an early `PLAYER_REGEN_ENABLED` handler used to stop the
recorder closing its stream, the clock re-anchoring and the run recorder seeing the pull). Both lines;
a change only when a handler raises. Measured cost 0.085 us per handler per event, so the combat log
is isolated per handler too.

## "In combat" is one flag on both lines (2026-09-30, T58)

The TBC mana clock, its widget, the pull budget, the Advisor's two checks, the gear reminder and the
Forever clock read `MD.inCombat` (Core.lua, T55: the regen events, seeded at `MD_READY` through the
adapter) instead of each polling `UnitAffectingCombat` or keeping a copy (review A28). On TBC nothing
visible changes -- the poll already followed the events and already said "in combat" after a
`/reload` mid-fight; that case now comes from the seed. The offline stub's TBC profile answers the
regen events, so the clock's in-combat path has a suite (`tools/ttocheck.lua`).

## Practice is a policy the flavour installs; its recording carries FightRecorder's fields (2026-09-30, T59)

`Engine/Practice.lua` no longer asks which client it runs on. `MD.Practice.policy` --
`defaultBinds`, `kitIsLive`, `client` -- is TBC's by default (the author's Cell click-casting, the
static kit, `"tbc"`), and `Modules/SpellTuner_Replay/Kit_Forever.lua` provides Forever's
(`MD.PracticePolicy`: no bindings, the live spellbook kit, `"forever"`); the panel and the bindings
sheet read it, and apicheck rule 10 refuses `MD.API.client` outside `Client/` and
`UI/Dump_Forever.lua` (review A6a). A practice recording now writes `threatOn = {}` (practice has no
threat) and names every spell id its own events carry, the bloom's 33778 included (review A30).
Nothing a TBC player sees changes; recordings already stored are left as they are.

## An address that does not parse is refused (2026-09-30, T62)

Every recording is addressed by one grammar, `Engine/Recordings.lua` on both lines: nothing (or blanks) is the newest single fight, `N` a single fight, `pN` a practice fight, `a:b` pull b of run a (TBC; Forever records no runs and answers nil). An address neither shape reads -- `foo`, `2x`, `p`, `:7`, `0x2` -- is now refused and the command prints its "no recording" line; it used to mean recording 1 (`0x2` recording 2), which is how `/st coach` printed a card for the wrong fight (B16). This changes TBC: `/md replay foo` no longer opens the newest fight. Each recorder still decides which recording it drops; the pin cap is the router's -- two single fights on both lines (TBC now has a `Pin` of its own with the Review tab's line, `at most 2 fights can be pinned - unpin one first.`), four practice fights. Both recorders keep a pull by `MD.Util.RECORD_GATE` (20 s, 5 casts), unchanged.

## A Forever kit rank with no readable cast is dataMissing (2026-09-30, T63)

A Forever kit rank whose cast time the book cannot read is `dataMissing` (Practice refuses it) rather than carrying a `nil` cast into the engine (T63). TBC is unchanged: its kit already validates against `Engine/Kit.lua`'s shape (Innervate declared as `Kit.UNPRICED`).

## The review commands are one implementation (2026-09-30, T65)

**The review commands are one implementation (T65, P21, review A1).** `/md coach`, `/md coachrun`, the validation report and Forever's `/st validate` are `Engine/ReviewCommands.lua` on both lines. Every line they print goes through `MD:PrintSafe`, so on TBC a zone, name, run name or spell with a pipe, a backslash or a non-ASCII byte now prints escaped, as it already did on Forever; and `/md coach` refuses an argument it cannot read (`1 force now`) instead of coaching recording 1 (B16, the router's rule, now on the coach's own parse too). What still differs by line is a policy the flavour installs: the copy box for a long card (TBC), the report's verb (`simreplay` / `validate`) and the slash in hints.

## A stream's version picks its road (2026-09-30, T66)

**A recording is replayed and validated by the road registered for its version (T66, P22, review A18).** `Engine/SimModel.lua` keeps one registry per question (`SM.scenarioBuilders`, `SM.validators`, `SM.healthReconstructors`); v1, v2 and a recording without a version take the v2 road, the Replay module registers v3. A version nobody registered is refused with a named error instead of being read as a v2 stream, because the same numbers mean other things in another version (a v3 heal is kind 15, which the engine's own kinds do not have). The v3 constants live once, in the Recorder module's `Stream_Forever.lua`, and the Replay module refuses to load if a v3 heal would collide with an engine kind. No TBC recording changes road; nothing TBC prints moved.

## A spell outside the book keeps its last readable text (2026-09-30, T67)

A spell read outside the book keeps its last readable text through a secret description, as a book spell does, and says it was read before combat (T67, review R41's gap). TBC is unchanged: the rank rules moved to `Spells/RankRules.lua` and mark the same ranks.

## TBC's disagreeing colour literals are named tokens (2026-09-30, T69)

T69 (P25): TBC's three disagreeing literals kept as named tokens -- dominated 8a8a8a (muted is 888888), note ffcc00 (text2's TBC stand-in), tipGold ffd100 (accent is ffcc00). Unifying them moves TBC and is P34's question to the author (plan section 8).

## The author's answers to the refactor plan (2026-09-30)

`docs/PLAN-refactor-ux.md` section 8.1 records them one by one. In short: the new UI comes to TBC too
(decision 10, wave C after wave 17, mockup M6 first) and SpellTuner replaces ManaDemon on both
clients; a failed fight is coached from the Review row menu's "Coach anyway"; a module placeholder's
"Turn on" loads the module; `dominated` becomes `beaten`; a window size per group stays; Forever
gets the minimap button TBC has; replay keys only under the pointer and never in combat; and the four
defaults the running waves used (coach cards change, old CANCELs stay, a third pin refused, an
unreadable address refused) are confirmed.

## The Forever clock opens the window out of combat only (2026-09-30, T70)

Forever clock (T70): a left-click opens the window only out of combat; in combat the click does nothing, because the window hides in combat (decision 4).

## Review on Forever: forcing is the row menu's Coach anyway (2026-09-30, T71)

Review on Forever: forcing is the row menu's Coach anyway (T71, PLAN-refactor-ux 8.1 item 5). Under the theme the Coach* star and the shift-click on Coach, Coach pull and Play are gone. A plain Coach on a fight that does not replay shows why in the result area and searches nothing. The window's Validate and Coach answer in the result area with one chat line; the slash commands still print in full. TBC keeps the star and shift-click until wave C turns the theme on there.

## Replay keys under the pointer (2026-09-30, T72, P28)

The replay window takes the keyboard on both lines: Space plays and pauses, Left / Right move 5 s,
and every other key goes on to the game (`SetPropagateKeyboardInput`, practice's pattern). Space
and the arrows are jump and turn, and TBC does not hide the replay in combat, so the window holds
the keyboard only after the pointer *enters* it out of combat, and lets go when the pointer leaves,
when the window hides and on `PLAYER_REGEN_DISABLED`; after a fight it comes back only when the
pointer enters again. A failed `SetPropagateKeyboardInput` (only `pcall`'d) can therefore swallow
keys at most while the player points at the window out of combat. Practice keeps its own keyboard
rules. The author's answer, `docs/PLAN-refactor-ux.md` 8.1 item 12; the play button's tooltip had
promised Space since v0.8 without it working (review U27).

## No dead ends (2026-10-01, T73, P29)

A placeholder's **Turn on** switches its module on, with what it needs, and loads it at once (the
author's answer 6 to `docs/PLAN-refactor-ux.md` section 8). This retires the T16b rule "a placeholder
never loads a module". Settings -> Modules stays the way to switch one off, and a module switched off
but still loaded gets a Reload UI button there. On TBC the Options slider for `db.simFloor` now reads
"Danger line for built fights (%)". Since v0.10.3 a recorded fight measures its own line, and since
T20 a plan decides on the biggest hit so far, so the flat line is what a fight built in Simulate is
scored on (and a recorded target's fallback). The old label and tooltip called it the scoring line.
This is a text fix; the value and its use are unchanged.

## One selection language (2026-10-01, T74, P30)

On Forever a button group's active member is the `selected` fill plus a 2-px accent bar (left on the
nav's groups, bottom elsewhere) and hover is the `hover` fill laid over any member, the active one
included (spec 4.3, mockup `.nb.on` / `.vt.on` / `.btn.act`). TBC keeps the active button in its
hover colour (decision 10 is wave C's).

### Spells and Settings have one size (T75, P31, 2026-10-01)

On Forever the Spells and Settings groups are 860 x 560 with that as their minimum: nothing in them
reflows (the rank table and card are a fixed 540; Settings' two columns fit), so the resize grip is
hidden there (mockup M1) and a size saved for them by an earlier session is ignored. Reports and
Simulate keep the grip and their saved sizes (decision 6, a size per group, stands). Under the theme
the grip is three 1-px lines; TBC keeps Blizzard's grip art (it has no resizable window).

**Lists flip at the screen's edge on both lines (T77, P33, review U12, 2026-10-01).** A dropdown's
list that would leave the bottom of the screen opens upward, and a tree dropdown's second list that
would leave the right edge opens to the left -- on TBC too, since a list off the screen is a bug on
either line (mockup M4). Nothing else of P33 reaches TBC: the chevron textures are under
`UI.THEMED`, and the rail is not on the TBC TOC until C5.

**`beaten`, one label grey and a white selection bar on Forever (T78, P34, review U1 / U7 / U9,
2026-10-01; the author's answer 8.1 item 7, mockup M5).** The rank a rank beats on both per mana and
per sec is tagged `beaten`, never `dominated`, and its tag names the rank that beats it; the table,
the card and the tooltip say `Per sec` and count `Casts` (`N from full`); `label` and `text2` are
one grey (#B3B3B3), `muted` is for explanations, `disabled` for inert controls and the numbers of a
rank you do not have; the selected rank is a white bar so the fill means "suggested" alone. TBC
keeps its words and its three greys until wave C gives it the theme (decision 10).
