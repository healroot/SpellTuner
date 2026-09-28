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
the spellbook. **They are dynamic** — answered on the beta on 2026-09-27 (§6 Q1). The unknown that
replaced it the same day: the character's own health and mana read as secret values out of
combat (§6 Q2), which decides what a recorder and the clock can read.

## 1. What was established (2026-09-27, builds 1.60.1.69893 / 70009)

Sources: [forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) (its captured API
baseline `data/forever_api.json`: 6,045 globals, 269 namespaces; its bug reports and watch list),
[Secret values](https://warcraft.wiki.gg/wiki/Secret_values) on warcraft.wiki.gg, the
[realmlist](https://realmlist.org/resources/guides/wow-forever-beta-addons-what-works/) and
[wow4ever](https://wow4ever.quest/en/addons) addon censuses, the
[Blizzard beta announcement](https://news.blizzard.com/en-us/article/24304160/the-world-of-warcraft-forever-beta-now-live),
and the source of **EllesmereUI**, a working Forever addon installed in the author's beta folder
(`_classic_beta_/Interface/AddOns`), read as a live reference the way ElvUI was. For **spells and
talents** the author named two reference sites, **talentsforever.com** and **Wowhead's Forever
database**; what each exposes, how current it is, and what the two (and Blizzard's own notes)
say Forever changes about healing is in **`docs/REFERENCES-FOREVER.md`** (2026-09-27, every
claim refetched by a skeptic). They are for checking and planning; no value from them goes into
code.

### 1.1 The client

| fact | source |
|---|---|
| Retail engine: `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`; `## Interface: 16001`; game type "camelot" | kit README; EllesmereUI_ClientGate.lua |
| Vanilla ruleset, level 60 cap; beta cap 20 rising to 30; beta 2026-09-17 → 10-21; launch 2026-11-04 | Blizzard, Wikipedia |
| Spell ranks exist and are **tuned per rank** ("Lightning Bolt: damage on ranks 3 and 4 increased to make these spells always upgrades"); the Cooldown Manager does not support ranks yet | Kaivax, beta development notes 2026-09-24 (`REFERENCES-FOREVER.md` §4) |
| Downranking is live: purchased ranks do **not** auto-update on bars for mana users, and the spellbook **hides lower ranks** unless "show all ranks" is on | Wowhead news 383050, 2026-09-22 |
| **HoTs crit**: Rejuvenation, Tranquility, Wild Growth (and Renew, Riptide) "can land critical hits" since build 70009 | Kaivax, 2026-09-24 |
| Bonus healing also grants **one third** as much bonus damage; hit and crit are merged across spell / melee / ranged | Blizzard Deep Dive recap, 2026-09-13 |
| Client data: **every rank carries the full vanilla coefficient** (cast/3.5, duration/15) with **no Classic sub-20 cut** (Healing Touch R1 0.429, Classic 0.123). A **server-side** downrank rule would not show in client data — unknown (§6 Q10) | talentsforever `co`, Wowhead `SP mod`, foreverchanges.pro |
| Client data: **base values and costs moved at every rank** (rank-1 heals up, level-60 HoT ticks ~12-14% down, direct heals within ~3%); a Classic Era table cannot be reused. Old ranks keep Classic ids, new ranks have 7-digit ids; **TBC ids are absent** | both sites, build 70009 |
| **No Lifebloom, Tree of Life, Earth Shield or Circle of Healing** on Forever. Druid heals: Healing Touch 11, Regrowth 9, Rejuvenation 11, Tranquility 4, Swiftmend (talent-granted, eats the full remaining HoT), Wild Growth 3 ranks (40/50/60) | talentsforever spellbooks, Wowhead env 16 |
| Costs print as `N Mana` **or** `N% of base mana`; rank 1 of a talent-granted spell is in the book with no trainer; some ranks are tome / quest (Rejuvenation R11) | both sites |
| In-combat Spirit regen talents at 17/33/50% (Classic 5/10/15%); Paladin Reverence; "all classes that do damage and healing via mana will have talents or abilities that give them mana back based on your spirit" | talentsforever talents; Kris Zierhut, BlizzCon transcript p.5 |
| **From the first probe report (build 70009, Healroot level 8, out of combat, solo, PvP realm):** the client loads `SpellTuner_Mainline.toc`; 57 of the 65 listed functions present, the 8 absent are the Classic globals and `CombatLogGetCurrentEventInfo`; all 20 events register (the combat log one included, under pcall); `C_ClassTalents.GetActiveConfigID` + `C_Traits.GetConfigInfo` answer, `C_SpecializationInfo.GetTalentInfo({tier, column})` is nil below level 10; `C_DamageMeter` **out of combat lists per-source totals and per-spell rows** (spellID, totalAmount, amountPerSecond, overkillAmount, a `combatSpellDetails` table); `GetManaRegen` plain; own auras plain; Healing Touch R1 reads "40 to 55" at level 8 where both reference sites print "40 to 54" for level 60 | `docs/probe/1.60.1_70009.md` |
| **Same report, the two open alarms:** own health and mana read **secret out of combat** (Q2, widened); the ADDON_ACTION_FORBIDDEN dialog appeared at load, culprit unproven, `COMBAT_LOG_EVENT_UNFILTERED` registration the suspect (EllesmereUI never registers it) — T0c records the forbidden event's function name and moves that registration to `/st probe clog` | `docs/probe/1.60.1_70009.md`; T0c |
| Classic globals gone: `GetSpellInfo`, `UnitAura`, `UnitBuff`, `GetTalentInfo`, `GetItemInfo` | kit README, baseline |
| Trap: `select(4, GetBuildInfo()) >= 100000` is FALSE on Forever (16001), so retail/classic switches pick the Classic path | kit README |
| `ReloadUI()` is protected; registering an unknown event throws | kit README |

### 1.2 What is gone or secret

| | status |
|---|---|
| `CombatLogGetCurrentEventInfo` | **absent** from the baseline; `C_CombatLog.IsCombatLogRestricted` exists |
| `COMBAT_LOG_EVENT_UNFILTERED` | **registering it is forbidden** (2026-09-28, build 70009): the `RegisterEvent` call returns normally, then the client fires `ADDON_ACTION_FORBIDDEN` (function `UNKNOWN()`) and shows the "blocked from an action only available to the Blizzard UI" dialog. Proven by `/st probe clog` (`docs/probe/1.60.1_70009.md`, sixth report). **No Forever file registers it, not even under pcall** |
| Current health and mana, own and party | **secret out of combat too** (2026-09-28): `C_Secrets.HasSecretRestrictions()` is true solo out of combat; `UnitHealth`, `UnitPower`, `UnitHealthPercent`, `UnitHealthMissing`, `UnitPowerPercent`, `UnitGetIncomingHeals` all read secret. **`UnitHealthMax` and `UnitPowerMax` read plain** (234 / 275), as do `UnitIsDeadOrGhost`, `GetManaRegen` and **`UNIT_COMBAT` amounts** (WOUND and HEAL, on player, target and other units, out of combat) |
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

**Answered: dynamic** (§6 Q1, 2026-09-27: a +5 spell power elixir changed every damage
description and no heal). The two hints that pointed there — talentsforever's "the beta client's
text at level 60 with no gear", Wowhead's leaked `[(172 + (Healing * 0.42899999)) * (1 * 1)]` —
were right. The first paragraph above is the plan; the static paragraph stays only as the record
of what was ruled out. Either way the parser must read
`N Mana` and `N% of base mana`, and the druid set has **no Lifebloom**: `Engine/RankMath.lua`'s
Lifebloom rules (stacks, bloom, rolling) are TBC-only and stay out of the Forever kit.

### 2.2 The spell dashboard — any spell in the spellbook, any class

Enumerate `C_SpellBook` skill lines → items; group by base name (`C_Spell.GetBaseSpell`,
`C_Spell.GetSpellSubtext` for "Rank N"); per rank: value (from the description parser), cost
(`C_Spell.GetSpellPowerCost`), cast (`C_Spell.GetSpellInfo`), crit per school, value per mana,
per second, casts to OOM (`GetManaRegen`, and the modelled mana of §2.5 -- `UnitPower` is secret, §1.2; casts from
full use the plain `UnitPowerMax`). The Pareto / suggested-rank logic ports
as-is. **Known ranks come from the spellbook enumeration, never from a trainer list**: rank 1 of a
talent-granted spell (Swiftmend, Wild Growth, Penance, Holy Shock, Riptide) sits in the book with
no trainer, and some ranks are tome or quest rewards; the enumeration must ask for **all** ranks,
since the default spellbook view hides the lower ones. **No combat tracking at all**: the overheal-adjusted "Effective" mode depends on measured
overheal, which lived in the combat log — it moves to the Recorder module and appears only when
that module is on.

### 2.3 Heal replay — the recorder has to be re-founded

There is no combat log to record. What a healer addon can still observe, per §1.3:

| stream | source | attribution |
|---|---|---|
| health of every party member | ~~`UNIT_HEALTH` per unit~~ -- current health is secret even out of combat (§1.2, 2026-09-28), and **a party member's max is secret too** (§6 Q2). **Reconstructed** as a deficit from `UNIT_COMBAT` amounts (WOUND down, HEAL up); as a fraction only for the player, against the plain `UnitHealthMax`, anchored at full out of combat, clamped to [0, max]; deaths from `UnitIsDeadOrGhost` re-anchor at 0 | reconstructed; exact only if every event arrives -- Q3 in combat decides |
| damage and heals landing on party members | `UNIT_COMBAT(unit, action, descriptor, amount)` — amounts reported readable by the kit's recorder | amount and target only; **no source** |
| own casts | `UNIT_SPELLCAST_START / SUCCEEDED / STOP / FAILED` on `"player"`, target via `UNIT_SPELLCAST_SENT` | exact |
| own mana | ~~`UnitPower`~~ secret (§1.2). **Modelled**: `UnitPowerMax` (plain) as the ceiling, minus own cast costs (`C_Spell.GetSpellPowerCost` at `UNIT_SPELLCAST_SUCCEEDED`), plus `GetManaRegen` under the five-second rule -- the engine's own mana model, run live | modelled, drifts; re-anchored at full when regen has had time to fill it out of combat |
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
five-second rule as today. **Since 2026-09-28 the pool itself is secret** (§1.2): the clock cannot
read where it starts from. It runs on a *modelled* pool -- `UnitPowerMax` (plain) minus each own
cast's cost plus regen, **the regen rate taken from the last out-of-combat `GetManaRegen()`, which
reads secret in combat** (2026-09-28, seventh report) -- which is the engine's mana model run live, anchored at full whenever
out-of-combat regen has had time to fill it. The error is the model's (a missed cost, a drink or
potion not seen, a mana gain from someone else) and grows through a fight; the display must say
"modelled" and never pretend to the TBC clock's precision. A secret value can still be *drawn*
(`StatusBar:SetValue` accepts one), so the widget can show the real bar beside the modelled clock
-- which also lets the author see the drift by eye. Drink detection read own auras — secret in combat, readable out of
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

**Where they live (decided 2026-09-28, M1/T2):** in this repository under `Modules/<Name>/`;
`release.sh` builds each into its own top-level folder beside `SpellTuner/`, because the client
never loads a nested addon folder. Open: one zip currently carries both release lines and a TBC
install also receives the three siblings (listed there as out of date, never loaded) -- per-flavour
packaging is a release task for M5.

### 3.2 The client adapter — one file touches the client

`Client/API.lua` is the **only** file that calls `C_*` or a Blizzard global. Everything else
calls `MD.API.SpellInfo(id)`, `MD.API.UnitHealth(unit)`, … Each wrapper: checks presence once
(so a missing function is a capability, not a crash), `pcall`s, and **converts a secret into
`nil` plus a reason** (`issecretvalue`), so no arithmetic on a secret ever happens outside this
file. This is also where the retail/classic build-check trap is neutralised: the adapter reads
`WOW_PROJECT_ID` and the interface number once and exposes `MD.API.client = "forever"`.

**What "the client" means for this rule (confirmed 2026-09-28, M1/T1b-T6):** game **data reads and
actions** go through `MD.API` (`MD.API.Call` / `Bind`, per-flavour bindings in `API_Forever.lua` /
`API_TBC.lua`; a secret comes back as `nil, "secret"`). The **widget toolkit** (`CreateFrame`,
`UIParent`, fonts, `SlashCmdList`, ...) and WoW's **Lua extensions** (`wipe`, `date`, `GetTime`,
...) may be used anywhere -- the shared `UI/Style.lua` could not exist otherwise.
`tools/apicheck.py` enforces exactly this split, and **no Forever file registers
`COMBAT_LOG_EVENT_UNFILTERED`** (§1.2); the adapter refuses it.

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

Decided 2026-09-27: **this repository, renamed SpellTuner**, one code line with a TOC per client
(`SpellTuner.toc` for Forever, `SpellTuner_TBC.toc` for TBC), the modules as sibling
LoadOnDemand addon folders, branches for release lines only. The full tree, the branch and tag
scheme, the harness changes and the milestones are in `docs/ROADMAP-FOREVER.md`.

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
- **The TBC spell table, Dreamstate and Lifebloom.** Forever has none of them: TBC ids do not
  exist, Dreamstate is a TBC talent, and Lifebloom (with Tree of Life) is not in the Forever druid
  book at all (`REFERENCES-FOREVER.md` §4). The Lifebloom logic in `Engine/RankMath.lua` and
  `Engine/SimModel.lua` stays for the TBC flavour and is never reached by a Forever kit.
- **`OnTooltipSetSpell` and font-string scanning.**

## 6. The questions the probe must answer, in order of how much rides on them

(Questions 1-9 are what `/st probe` asks the client; question 10 is a measurement the author
takes with the probe's help, added after the reference scout.)

1. **Are spell descriptions dynamic?** **Answered 2026-09-27, build 70009: DYNAMIC.** Between
   two probe runs the author drank an elixir worth +5 spell power and nothing else changed (level 8,
   bonus healing 0 both times); the descriptions of every damage spell in the book (Wrath R1 and
   R2, Moonfire, Entangling Roots) changed and the three heals did not
   (`docs/probe/1.60.1_70009.md`, second report). So the client computes the text from the
   caster's stats — the elixir moved spell damage, not bonus healing, which is why the heals
   stood still. The heal texts will be confirmed the same way the first time bonus healing moves
   (T0c prints the old and new text of every changed spell and the bonus damage per school beside
   the bonus healing). Phase 2 takes the dynamic branch of §2.1: a parser over
   `C_Spell.GetSpellDescription`, no coefficient table. A coefficient is still *measurable* from
   the client alone — the text at two known bonus values gives the slope — which is how a
   "per +healing" line can be shown without typing a number in. **Heals confirmed dynamic
   2026-09-28** (eighth report): at level 8 -> 9 with no gear change Healing Touch R2 went "88 to
   112" -> "89 to 114" (R1 and Rejuvenation R1 did not move), so a rank's base grows with level;
   and the damage texts fell when bonus damage went 5 -> 0 (Wrath R1 17-20 -> 15-18).
2. **Is party health readable in combat?** `UnitHealth("party1")` and the `UNIT_HEALTH` payload
   during a pull — `issecretvalue`. Decides whether a recorder exists at all. **Widened
   2026-09-27 after the first report:** `UnitHealth("player")`, `UnitHealthMax`, `UnitPower("player")`
   and even `UnitHealth("target")` with no target read **secret OUT of combat**, solo, at level 8
   on the PvP beta realm, while `GetManaRegen`, the damage meter and auras read plain and
   `ShouldUnitStatsBeSecret` / `ShouldAurasBeSecret` / `ShouldCooldownsBeSecret` were false. So
   the question is now "is health or power readable by addon code at all, and under what state" —
   `C_Secrets.HasSecretRestrictions()`, `ShouldUnitHealthMaxBeSecret`, `ShouldUnitPowerBeSecret`,
   `GetPowerTypeSecrecy`, and the secret-safe percent functions EllesmereUI lives on
   (`UnitHealthPercent`, `UnitPowerPercent`, `UnitHealthMissing`). T0c measures all of them in
   and out of combat. If current health and mana are secret always, the recorder's health curve
   comes from `UNIT_COMBAT` amounts (Q3) and the clock's mana from cast costs and regen, never
   from the pool. **Answered 2026-09-28 out of combat** (`docs/probe/1.60.1_70009.md`, sixth report):
   `HasSecretRestrictions()` is **true** solo out of combat, and every *current* health and power
   reading is secret -- `UnitHealth` (with and without its second argument), both
   `UnitHealthPercent` forms, `UnitHealthMissing`, `UnitPowerPercent`, `UnitGetIncomingHeals`;
   `ShouldUnitPowerBeSecret(player) = true`, `GetPowerTypeSecrecy(0) = 2`. The **maxima are plain**
   (`ShouldUnitHealthMaxBeSecret` / `ShouldUnitPowerMaxBeSecret` false, 234 / 275), and so is
   `UnitIsDeadOrGhost`. So the "if" above holds: health is reconstructed from `UNIT_COMBAT`, mana
   modelled (§2.3, §2.5). Still open: whether it is the same in a party and in combat on a PvE
   realm -- the author's beta realm is PvP, and the restriction may be a realm rule. **In a party
   (eighth report): a party member's max health is secret too** -- `UnitHealthMax(party1)` secret in
   and out of combat, while the player's own max is plain. So for party members the recorder has
   the **deficit** (WOUND adds, HEAL subtracts, floored at 0, zeroed out of combat), not a fraction;
   percentages and the measured danger line need a max from somewhere else (still to ask:
   `ShouldUnitHealthMaxBeSecret("party1")`; a status bar can still *draw* the secret values).
3. **Are `UNIT_COMBAT` amounts on party units readable in combat**, and does the event fire for
   heals (`action == "HEAL"`) as well as damage, with the target unit? Decides the damage stream. **Half answered 2026-09-28:** out of combat the
   amounts are plain numbers for WOUND and HEAL, on `player`, `target` and another unit (an 8 is
   one Rejuvenation R1 tick) -- fourth report. **In combat on the player, answered 2026-09-28** (seventh report,
   solo): 26 WOUND and 4 HEAL on `player`, 52 WOUND on the target, all plain. The same hit also
   arrives under other tokens (a mirror `other` count for every `player` HEAL), so the recorder
   registers per token (`RegisterUnitEvent`) or keys by GUID. **`party1` in combat answered the same day** (eighth
   report): 5 WOUND and 4 HEAL on `party1`, all plain. Q3 is answered. Open: whether the HEAL
   amount is gross or effective (the meter's is effective: a Healing Touch R2 of 88-112
   counted 31).
4. **What does `C_DamageMeter`'s session carry after a fight?** Per-source HealingDone; is there
   any per-spell or overheal breakdown? Decides the calibration and overheal features. **Partly
   answered:** per-spell rows (`spellID`, `totalAmount`, `amountPerSecond`, `overkillAmount`) out
   of combat; `combatSpellDetails` is **one table**, not a per-target list, and was empty
   (`amount=0`, blank `unitName`) on every spell out of combat -- sixth report. After a party fight
   still to see.
5. **Are party auras (`C_UnitAuras.GetAuraDataByIndex("party1", …)`) secret in combat?** And out
   of combat? Decides how pre-pull HoTs are captured. **Answered 2026-09-28** (eighth report):
   readable out of combat (`party1`'s Mark of the Wild, whole), and in combat reading them raises
   "Auras cannot be accessed when secret while tainted" as on the player. Pre-pull HoTs come from
   the last out-of-combat read.
6. **Which talent API answers on Forever's trees** — `C_SpecializationInfo.GetTalentInfo` or
   `C_Traits`? Decides the talent scan.
7. **Do SavedVariables come back on build 70009?** Decides whether recordings can be kept in the
   beta at all, or need the kit's seed workaround.
8. **Is `GetShapeshiftFormID` / own-cast target (`UNIT_SPELLCAST_SENT`) readable in combat?**
   Decides form tracking and cast attribution. **Target answered 2026-09-28:** `UNIT_SPELLCAST_SENT`'s
   target name readable in combat, 26 of 26 (seventh report). Form in combat still untested (no
   form was held).
9. **Which TOC suffix does Forever's client load?** **Answered 2026-09-27, build 70009:
   `_Mainline`** (`docs/probe/1.60.1_70009.md`: `SPELLTUNER_TOC = Mainline` with the plain,
   `_Forever` and `_Vanilla` copies beside it). `SpellTuner_Mainline.toc` is the Forever TOC;
   `docs/ROADMAP-FOREVER.md` §1.1 follows.
10. **Is there a server-side downrank penalty?** Not a probe of the API but a measurement, added
   2026-09-27 from `REFERENCES-FOREVER.md` §4: the client data carries the full coefficient on
   every rank, and a rule applied by the server (TBC's `(level + 6) / casterLevel` cut on ranks
   learned more than a few levels below yours, or something new) would not show there. Protocol,
   out of combat so nothing is secret: take fall damage, note `GetSpellBonusHealing()`, cast
   **Healing Touch Rank 1** (learned at 1) on yourself, read the landed heal from the `UNIT_HEALTH`
   delta or the `UNIT_COMBAT` amount (Q3), and compare with the tooltip's base plus
   `0.429 × healing`. Repeat with **Rank 4** (learned at 20) and the highest rank known, at level
   ≥ 20, and again after a level-up. Equal within the crit spread → no server rule; a shortfall
   that grows with the gap between the rank's level and yours → a rule, to be fitted. Decides
   whether `Engine/RankMath.lua`'s downrank penalty ports, is dropped, or is replaced. Done in M2
   (T12), needs Q3 answered first.

## 7. Decisions that are the author's

- ~~Repository~~ decided: in place, tagged `manademon-final`; a `tbc` branch only if a fix cannot live in shared code.
- Whether to run the two-party debate + judge on the two contested designs before phase 3: the
  recorder without a combat log (§2.3), and the module boundaries (§3.1).
- Name and version line: `SpellTuner` continues, version resets to `1.0.0` at the first Forever
  release, or keeps counting from 0.15.
