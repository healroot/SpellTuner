# SpellTuner for WoW: Forever — architecture and plan

Written 2026-09-27 by the planner (Fable) from research, not from memory. Every fact in §1 has a
source and a date; the beta changes per build, so §1 is a snapshot and §6 is the list of things
the probe must re-answer before anything is built on them.

## 0. The one-paragraph version

WoW: Forever is not a Classic client. It is the **retail 12.1.5 (Midnight) engine** with vanilla
content: interface `16001`, 269 `C_*` namespaces, Edit Mode, a built-in damage meter, and
Midnight's **secret values**. The Classic globals this addon was written against are gone, and —
the part that matters most — **`CombatLogGetCurrentEventInfo` does not exist**. The recorder,
the summaries, overheal measurement and calibration all read the combat log today. The engine,
the planner, the solver, the replay state machine, the practice session and the bindings work are
pure Lua and port unchanged. The tooltip and dashboard get *easier*, not harder, if the client's
spell descriptions turn out to be dynamic (retail-style, already scaled to your stats) — then the
whole coefficient model becomes optional and "any spell, any class" is a description parser over
the spellbook. Whether they are dynamic is the single most important unknown, and it is question
1 in §6.

## 1. What was established (2026-09-27, builds 1.60.1.69893 / 70009)

Sources: [forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) (its captured API
baseline `data/forever_api.json`: 6,045 globals, 269 namespaces; its bug reports and watch list),
[Secret values](https://warcraft.wiki.gg/wiki/Secret_values) on warcraft.wiki.gg, the
[realmlist](https://realmlist.org/resources/guides/wow-forever-beta-addons-what-works/) and
[wow4ever](https://wow4ever.quest/en/addons) addon censuses, the
[Blizzard beta announcement](https://news.blizzard.com/en-us/article/24304160/the-world-of-warcraft-forever-beta-now-live),
and the source of **EllesmereUI**, a working Forever addon installed in the author's beta folder
(`_classic_beta_/Interface/AddOns`), read as a live reference the way ElvUI was.

### 1.1 The client

| fact | source |
|---|---|
| Retail engine: `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`; `## Interface: 16001`; game type "camelot" | kit README; EllesmereUI_ClientGate.lua |
| Vanilla ruleset, level 60 cap; beta cap 20 rising to 30; beta 2026-09-17 → 10-21; launch 2026-11-04 | Blizzard, Wikipedia |
| Spell ranks exist (the Cooldown Manager "doesn't handle spell ranks yet") | classicwowforever.com |
| Classic globals gone: `GetSpellInfo`, `UnitAura`, `UnitBuff`, `GetTalentInfo`, `GetItemInfo` | kit README, baseline |
| Trap: `select(4, GetBuildInfo()) >= 100000` is FALSE on Forever (16001), so retail/classic switches pick the Classic path | kit README |
| `ReloadUI()` is protected; registering an unknown event throws | kit README |

### 1.2 What is gone or secret

| | status |
|---|---|
| `CombatLogGetCurrentEventInfo` | **absent** from the baseline; `C_CombatLog.IsCombatLogRestricted` exists |
| Enemy health, damage numbers, threat | secret ("combat-decision automation cannot exist here") |
| Own auras in combat | secret: `C_Secrets.ShouldAurasBeSecret()` true → reading throws ("Auras cannot be accessed when secret while tainted") |
| A secret value | arithmetic, comparison, `#`, table key, call → **immediate Lua error**; store / pass / concat / `StatusBar:SetValue` allowed; `issecretvalue(v)` tests |
| The damage meter session | secret **in** combat; readable after (`C_DamageMeter.GetCombatSessionFromType`: per-source `totalAmount`, `amountPerSecond`, `isLocalPlayer` NeverSecret; per-spell breakdown and overheal **not documented**) |

### 1.3 What survives (present in the baseline)

`GetManaRegen`, `GetSpellBonusHealing`, `GetSpellBonusDamage`, `GetSpellCritChance`, `UnitStat`,
`UnitPower`, `UnitPowerMax`, `UnitHealth`, `UnitHealthMax`, `UnitThreatSituation`,
`UnitCastingInfo`, `GetShapeshiftFormID`, `GetInventoryItemID`, `GetMacroInfo`, `GetBinding`,
`GetActionInfo`, `IsSpellKnown`, `issecretvalue`.

Moved: `C_Spell.GetSpellInfo / GetSpellPowerCost / GetSpellDescription / GetSpellSubtext /
GetSpellLevelLearned / GetSpellName / GetSpellTexture / GetSpellCooldown`; `C_SpellBook.*`
(`GetNumSpellBookSkillLines`, `GetSpellBookSkillLineInfo`, `GetSpellBookItemInfo`,
`IsSpellKnown`); `C_UnitAuras.*`; tooltips through
`TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, fn)` and `C_TooltipInfo.*`
(structured lines — no font-string scanning). Talents: **both** `C_SpecializationInfo.GetTalentInfo`
and `C_Traits` / `C_ClassTalents` exist; which one Forever's trees answer is unknown.

Events a working Forever addon lives on (EllesmereUI, counted): `UNIT_SPELLCAST_*` on
`"player"`, `UNIT_HEALTH`, `UNIT_MAXHEALTH`, `UNIT_POWER_UPDATE`, `UNIT_AURA`, `GROUP_ROSTER_UPDATE`,
`PLAYER_REGEN_*`, `SPELLS_CHANGED`, `PLAYER_TALENT_UPDATE`, `TRAIT_CONFIG_UPDATED`,
`DAMAGE_METER_COMBAT_SESSION_UPDATED`, `ADDON_RESTRICTION_STATE_CHANGED`. The kit's own fight
recorder uses `UNIT_COMBAT` (unit, action, descriptor, amount, damageType) and reports its
amounts readable, counting the secret ones separately.

### 1.4 Beta bugs to design around

- **SavedVariables are not always read back at launch** (unfixed in 69893; EllesmereUI ships a
  login notice about it on 70009). The kit's workaround runs the saved file as addon code.
- **Error reporting stops after 100 errors per session.** A debug console that floods is a
  debug console that blinds you.
- Secure snippets were broken until 70009 (fixed).

### 1.5 The author's beta

`/mnt/e/Blizzard/World of Warcraft/_classic_beta_`, build 70009, character **Healroot**
("Classic Beta PvP"), EllesmereUI installed. Beta level cap 20–30, so healing at the cap cannot be
tested before launch; everything about level 60 numbers waits.

## 2. What each target feature becomes

### 2.1 Spell tooltips — any spell, and in the spellbook

Rebuilt on `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, fn)`, which is
why today's `OnTooltipSetSpell` hook does nothing in the spellbook. The spell id comes from
`tooltip:GetPrimaryTooltipData()` / `data.id`; the description from
`C_Spell.GetSpellDescription(id)` or the tooltip's own lines.

**If descriptions are dynamic** (retail behaviour: "Heals for 812" already scaled to your +healing),
the game has done the coefficient work and our value is *derived* numbers: per mana, per second,
per tick, the crit range, a HoT/DoT total, and **this rank against your highest** (ranks exist;
the Cooldown Manager ignores them; nobody else answers "is Rank 5 worth its mana"). No spell
table, no coefficient model, class-agnostic by construction.

**If descriptions are static** (TBC behaviour), `Engine/DamageMath.lua`'s pattern applies — read
the base from the text, add the coefficient model — and "any class" means a coefficient model per
class, which is a much larger and much less trustworthy project. Then the first release is druid
heals only, as now.

### 2.2 The spell dashboard — any spell in the spellbook, any class

Enumerate `C_SpellBook` skill lines → items; group by base name (`C_Spell.GetBaseSpell`,
`C_Spell.GetSpellSubtext` for "Rank N"); per rank: value (from the description parser), cost
(`C_Spell.GetSpellPowerCost`), cast (`C_Spell.GetSpellInfo`), crit per school, value per mana,
per second, casts to OOM (`GetManaRegen`, `UnitPower`). The Pareto / suggested-rank logic ports
as-is. **No combat tracking at all**: the overheal-adjusted "Effective" mode depends on measured
overheal, which lived in the combat log — it moves to the Recorder module and appears only when
that module is on.

### 2.3 Heal replay — the recorder has to be re-founded

There is no combat log to record. What a healer addon can still observe, per §1.3:

| stream | source | attribution |
|---|---|---|
| health of every party member | `UNIT_HEALTH` / `UNIT_MAXHEALTH` per unit (event-driven, not 5s snapshots — a *better* curve than today) | exact |
| damage and heals landing on party members | `UNIT_COMBAT(unit, action, descriptor, amount)` — amounts reported readable by the kit's recorder | amount and target only; **no source** |
| own casts | `UNIT_SPELLCAST_START / SUCCEEDED / STOP / FAILED` on `"player"`, target via `UNIT_SPELLCAST_SENT` | exact |
| own mana | `UNIT_POWER_UPDATE("player")`, `GetManaRegen` | exact |
| deaths | `UNIT_HEALTH` at 0 / `UNIT_FLAGS` | exact |
| own healing total, others' healing total | `C_DamageMeter` session **after** combat (HealingDone per source) | per player, per fight — the foreign-share gate's ground truth |
| HoTs on party | `C_UnitAuras` — probably secret in combat; readable out of combat | pre-pull state from the last out-of-combat snapshot |
| enemy casts, threat | secret by policy | **gone**: the v0.12 foresight inputs do not survive |

So the v3 stream is: health curves at event resolution, landed heals and damage as amounts on
targets, own casts with targets, own mana, deaths — and the engine's own model generates the
own-heal events exactly as it does now (it never read the recorded own-heal amounts to simulate;
it only compared). The health gate becomes stronger (more samples); the calibration gate needs a
new source (own healing total from the damage meter vs the model's total per fight); the
foreign-share gate reads the damage meter; the enemy-cast and threat inputs are dropped. The
engine, `ReplayTrace`, the planner, the solver and the replay window port without change — they
consume a scenario, not a log.

### 2.4 The simulator (practice)

Pure Lua plus bindings. `GetBinding`, `GetActionInfo`, `GetMacroInfo` survive; Cell and Clique
import survive (Cell's Forever release, if any, may store click-castings differently — re-check).
Ports last because it depends on the replay window.

### 2.5 The clock (TTO) and the advisor

Class-generic and cheap: spend from `UNIT_SPELLCAST_SUCCEEDED`, regen from `GetManaRegen`,
five-second rule as today. Drink detection read own auras — secret in combat, readable out of
combat, which is when you drink. Innervate is a druid talent in vanilla (level 40) — `C_UnitAuras`
out of combat, or the cast event. Dreamstate does not exist in vanilla; the "unreported regen"
machinery becomes a measurement only.

## 3. Architecture

### 3.1 Modules, as LoadOnDemand addons

The standard WoW way to make a module the user can switch off with zero footprint is a separate
addon folder with `## LoadOnDemand: 1` and `## Dependencies: SpellTuner`, loaded with
`C_AddOns.LoadAddOn` when its switch is on. The in-game AddOn list disables it too. This is how
Details, WeakAuras and DBM ship their heavy parts.

| addon | on by default | contents | footprint |
|---|---|---|---|
| `SpellTuner` | yes | core, client adapter, capability probe, debug console, module registry + settings, **Tooltips**, **Dashboard**, **Clock** | no combat tracking beyond own casts and mana |
| `SpellTuner_Recorder` | off | the v3 fight/run recorder, fight summaries, overheal and calibration from the damage meter | event handlers on party units during combat |
| `SpellTuner_Replay` | off, needs Recorder | SimModel, RankMath/SpellKit-from-spellbook, planner, solver, ReplayTrace, replay window, coach, Review tab | the engine |
| `SpellTuner_Practice` | off, needs Replay | practice session, panel, bindings window, imports | — |

Modules talk through `MD:RegisterCallback` / `MD:Fire` and declared dependencies only. A module
that is off contributes no frames, no events, no tables.

### 3.2 The client adapter — one file touches the client

`Client/API.lua` is the **only** file that calls `C_*` or a Blizzard global. Everything else
calls `MD.API.SpellInfo(id)`, `MD.API.UnitHealth(unit)`, … Each wrapper: checks presence once
(so a missing function is a capability, not a crash), `pcall`s, and **converts a secret into
`nil` plus a reason** (`issecretvalue`), so no arithmetic on a secret ever happens outside this
file. This is also where the retail/classic build-check trap is neutralised: the adapter reads
`WOW_PROJECT_ID` and the interface number once and exposes `MD.API.client = "forever"`.

### 3.3 The capability probe — the tool for a moving beta

`Client/Probe.lua` (core, `/md probe`): for every function the adapter needs, present or not; for
every `C_Secrets.Should*` predicate, its value in and out of combat; for every event we register,
whether registering throws; the dynamic-vs-static description test (§6 Q1); which talent API
answers; whether `UNIT_COMBAT` amounts are secret on the player in a real fight; whether
SavedVariables came back. The report goes to the copy box **and** to SavedVariables keyed by
build number, and the probe **diffs against the last build's report** — "since 70009: X gone, Y
now secret". That diff is what keeps the addon up with the beta, and its output is what the
lead attaches to every task.

### 3.4 Debug console, beta edition

Error capture through `seterrorhandler`-style hooking with **dedupe and counting**, because the
client stops reporting after 100 — the console must never contribute to the flood and must show
"this error, 340 times" rather than 340 lines. Categories as today. A `/md dump` that writes the
capability report, the last errors and the module states into one copyable block for a bug
report.

### 3.5 The offline harness gets a Forever profile

`tools/wowstub.lua` grows a second profile: `C_*` namespaces, **no** `CombatLogGetCurrentEventInfo`,
`UNIT_COMBAT`, `C_DamageMeter` sessions, `TooltipDataProcessor`, and a **secret-value type** — a
table with metatables that raise on `__add`, `__lt`, `__len`, `__index` and answers
`issecretvalue`. Every suite that touches the adapter runs with secrets switched on, so "did
arithmetic on a secret" fails offline the way it fails in the client. `tools/apicheck.py` scans
our code for client calls and diffs them against the current build's baseline (the kit's
`forever_api.json` now; our own probe's capture later) — a used function that the build no longer
has fails the check before anyone logs in.

### 3.6 Repository

Recommendation: **stay in this repository.** Tag `master` as `tbc-final` (v0.15.4) and keep a
`tbc` branch for anything the TBC realm still needs; develop Forever on `master`. The engine,
tools, docs and history carry over intact, and the port is a series of ordinary versions
(`v1.0.0-forever` when the recorder works end to end). A new repository would lose the harness
and the decision record for no gain. **This is the author's call** (§7).

## 4. Phases

Each phase is one or more tasks written by the lead (Opus) from this plan, implemented by the
implementer (Sonnet), reviewed by the lead against the suites and the probe report. Nothing in a
later phase starts on an assumption the probe has not confirmed.

| phase | deliverable | gates on |
|---|---|---|
| **0 — Probe** | `SpellTuner` skeleton that loads on 16001, `Client/Probe.lua`, `/md probe`, the report from Healroot on the current build | nothing; **this is first** |
| **1 — Core** | client adapter, capability table, module registry with settings, debug console (dedupe), SavedVariables guard, harness Forever profile with secrets, `apicheck` | probe report |
| **2 — Tooltips + Dashboard** | tooltip on `TooltipDataProcessor` working in the spellbook; description parser; spellbook enumeration; rank comparison; any class | Q1 (dynamic descriptions) — decides whether a coefficient model is needed |
| **3 — Recorder v3 + Replay** | the health/`UNIT_COMBAT`/casts/mana stream, gates re-founded on the damage meter, engine + replay window ported, `SpellKit` fed from the spellbook | Q2–Q5 |
| **4 — Practice** | session, panel, bindings, imports ported | phase 3 |
| **5 — Level 60** | heal values, regen and talents at the cap; the solver re-measured | launch (2026-11-04) |

## 5. What is deliberately not carried over

- **Enemy cast bars and threat as plan inputs** (v0.12): secret by policy. The foresight
  experiments (`Intuition`, `Foresight`) were already shipped off; they stay off.
- **Per-target overheal from the combat log**: only totals per player per fight survive
  (damage meter). Overheal by spell is gone unless the session exposes it (§6 Q4).
- **The TBC spell table and Dreamstate.** Vanilla has neither TBC ranks nor Dreamstate.
- **`OnTooltipSetSpell` and font-string scanning.**

## 6. The questions the probe must answer, in order of how much rides on them

1. **Are spell descriptions dynamic?** `C_Spell.GetSpellDescription(Rejuvenation)` with and
   without a +healing item equipped: same text → static (coefficient model needed) / different →
   dynamic (parser only). Decides phase 2's whole shape.
2. **Is party health readable in combat?** `UnitHealth("party1")` and the `UNIT_HEALTH` payload
   during a pull — `issecretvalue`. Decides whether a recorder exists at all.
3. **Are `UNIT_COMBAT` amounts on party units readable in combat**, and does the event fire for
   heals (`action == "HEAL"`) as well as damage, with the target unit? Decides the damage stream.
4. **What does `C_DamageMeter`'s session carry after a fight?** Per-source HealingDone; is there
   any per-spell or overheal breakdown? Decides the calibration and overheal features.
5. **Are party auras (`C_UnitAuras.GetAuraDataByIndex("party1", …)`) secret in combat?** And out
   of combat? Decides how pre-pull HoTs are captured.
6. **Which talent API answers on Forever's trees** — `C_SpecializationInfo.GetTalentInfo` or
   `C_Traits`? Decides the talent scan.
7. **Do SavedVariables come back on build 70009?** Decides whether recordings can be kept in the
   beta at all, or need the kit's seed workaround.
8. **Is `GetShapeshiftFormID` / own-cast target (`UNIT_SPELLCAST_SENT`) readable in combat?**
   Decides form tracking and cast attribution.

## 7. Decisions that are the author's

- Repository: in place with a `tbc-final` tag (recommended), or a new repository.
- Whether TBC keeps receiving fixes on a `tbc` branch, or is frozen.
- Whether to run the two-party debate + judge on the two contested designs before phase 3: the
  recorder without a combat log (§2.3), and the module boundaries (§3.1).
- Name and version line: `SpellTuner` continues, version resets to `1.0.0` at the first Forever
  release, or keeps counting from 0.15.
